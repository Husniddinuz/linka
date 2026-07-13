import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/chat_service.dart';
import '../theme/app_colors.dart';
import 'channel_chat_screen.dart';

// ─── Models ────────────────────────────────────────────────────────────────────

enum ChannelType { text, voiceOnly, announcement }

class ChatChannel {
  final String id;
  final String name;
  final String emoji;
  final Color tileColor;
  final ChannelType type;
  final int unreadCount;
  final String? lastSenderName;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final bool lastMessageIsVoice;
  final bool lastMessageIsImage;
  final bool lastMessageIsDeleted;
  final bool studentCanPost;

  const ChatChannel({
    required this.id,
    required this.name,
    required this.emoji,
    required this.tileColor,
    required this.type,
    this.unreadCount = 0,
    this.lastSenderName,
    this.lastMessage,
    this.lastMessageAt,
    this.lastMessageIsVoice = false,
    this.lastMessageIsImage = false,
    this.lastMessageIsDeleted = false,
    this.studentCanPost = true,
  });

  factory ChatChannel.fromJson(Map<String, dynamic> json) {
    final lastMsg = json['last_message'] as Map<String, dynamic>?;
    return ChatChannel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '💬',
      tileColor: _parseColor(json['tile_color']?.toString() ?? ''),
      type: _parseType(json['type']?.toString() ?? ''),
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      lastSenderName: lastMsg?['sender_name'] as String?,
      lastMessage: lastMsg?['text'] as String?,
      lastMessageAt: _parseDate(lastMsg?['sent_at'] as String?),
      lastMessageIsVoice: lastMsg?['is_voice'] as bool? ?? false,
      lastMessageIsImage: lastMsg?['is_image'] as bool? ?? false,
      lastMessageIsDeleted: lastMsg?['is_deleted'] as bool? ?? false,
      studentCanPost: json['student_can_post'] as bool? ?? true,
    );
  }

  static Color _parseColor(String hex) {
    try {
      final cleaned = hex.trim().replaceAll('#', '');
      if (cleaned.isEmpty) return const Color(0xFF5B7FD4);
      return Color(int.parse('FF$cleaned', radix: 16));
    } catch (_) {
      return const Color(0xFF5B7FD4);
    }
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  static ChannelType _parseType(String type) {
    final normalized = type.toLowerCase().replaceAll('_', '').replaceAll('-', '');
    switch (normalized) {
      case 'voiceonly':
      case 'voice':
        return ChannelType.voiceOnly;
      case 'announcement':
      case 'announcements':
        return ChannelType.announcement;
      default:
        return ChannelType.text;
    }
  }
}

// ─── Screen ────────────────────────────────────────────────────────────────────

class ChatsScreen extends StatefulWidget {
  final bool isActive;
  const ChatsScreen({super.key, this.isActive = true});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with WidgetsBindingObserver {
  List<ChatChannel> _channels = [];
  bool _loading = true;
  String? _error;
  bool _disposed = false;

  int _onlineCount = 0;
  WebSocketChannel? _presenceWs;
  StreamSubscription? _presenceSub;
  Timer? _presenceReconnectTimer;

  // channel_id → first name of the user currently typing
  final Map<String, String> _channelTyping = {};
  final Map<String, Timer> _channelTypingTimers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChannels();
    if (widget.isActive) _connectPresence();
  }

  @override
  void didUpdateWidget(ChatsScreen old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _connectPresence();
      _loadChannels();
    } else if (!widget.isActive && old.isActive) {
      _disconnectPresence();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _disconnectPresence();
    } else if (state == AppLifecycleState.resumed && widget.isActive) {
      _connectPresence();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _disconnectPresence();
    super.dispose();
  }

  void _disconnectPresence() {
    _presenceReconnectTimer?.cancel();
    _presenceReconnectTimer = null;
    _presenceSub?.cancel();
    _presenceSub = null;
    _presenceWs?.sink.close();
    _presenceWs = null;
    for (final t in _channelTypingTimers.values) {
      t.cancel();
    }
    _channelTypingTimers.clear();
    if (mounted && !_disposed) {
      setState(() {
        _onlineCount = 0;
        _channelTyping.clear();
      });
    }
  }

  Future<void> _connectPresence() async {
    if (_presenceWs != null) return;
    try {
      final ws = await ChatService.connectPresenceWebSocket();
      await ws.ready;
      if (!mounted || !widget.isActive) {
        ws.sink.close();
        return;
      }
      _presenceWs = ws;
      _presenceSub = ws.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            if (json['type'] == 'online_count' && mounted) {
              setState(() => _onlineCount = (json['count'] as num).toInt());
            } else if (json['type'] == 'channel_updated' && mounted) {
              _loadChannels(silent: true);
            } else if (json['type'] == 'channel_typing' && mounted) {
              final channelId = json['channel_id'] as String?;
              final userId = (json['user_id'] as num?)?.toInt();
              final userName = json['user_name'] as String?;
              final isTyping = json['is_typing'] as bool? ?? false;
              if (channelId != null && userId != null) {
                _channelTypingTimers[channelId]?.cancel();
                if (isTyping && userName != null) {
                  final firstName = userName.split(' ').first;
                  setState(() => _channelTyping[channelId] = firstName);
                  _channelTypingTimers[channelId] = Timer(const Duration(seconds: 6), () {
                    if (mounted) {
                      setState(() => _channelTyping.remove(channelId));
                    }
                  });
                } else {
                  setState(() => _channelTyping.remove(channelId));
                }
              }
            } else if (json['type'] == 'ping') {
              _presenceWs?.sink.add('{"type":"pong"}');
            }
          } catch (_) {}
        },
        onError: (_) => _schedulePresenceReconnect(),
        onDone: _schedulePresenceReconnect,
        cancelOnError: false,
      );
    } catch (_) {
      _schedulePresenceReconnect();
    }
  }

  void _schedulePresenceReconnect() {
    _presenceSub?.cancel();
    _presenceSub = null;
    _presenceWs = null;
    if (mounted) setState(() => _onlineCount = 0);
    _presenceReconnectTimer?.cancel();
    _presenceReconnectTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && widget.isActive) _connectPresence();
    });
  }

  Future<void> _loadChannels({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final raw = await ChatService.fetchChannels();
      if (mounted) {
        setState(() {
          _channels = raw.map(ChatChannel.fromJson).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.accentBlue),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _loadChannels,
                child: Text(
                  'Retry',
                  style: TextStyle(color: context.colors.accentBlue),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadChannels,
      color: context.colors.accentBlue,
      child: ListView.builder(
        itemCount: _channels.length,
        itemBuilder: (_, i) => _ChannelTile(
          channel: _channels[i],
          showDivider: i < _channels.length - 1,
          onReturn: _loadChannels,
          typingText: _channelTyping[_channels[i].id],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: context.colors.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Chats',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          if (_onlineCount > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.colors.successBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: context.colors.success.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: context.colors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$_onlineCount online',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.colors.success,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Channel tile (Telegram style) ────────────────────────────────────────────

class _ChannelTile extends StatelessWidget {
  final ChatChannel channel;
  final bool showDivider;
  final VoidCallback? onReturn;
  final String? typingText;
  const _ChannelTile({required this.channel, this.showDivider = true, this.onReturn, this.typingText});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChannelChatScreen(channel: channel),
          ),
        );
        onReturn?.call();
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: channel.tileColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      channel.emoji,
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  '# ${channel.name}',
                                  style: TextStyle(
                                    fontFamily: 'SF Pro',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: context.colors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (channel.type == ChannelType.voiceOnly) ...[
                                  const SizedBox(width: 6),
                                  _VoiceBadge(),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (channel.lastMessageAt != null)
                            Text(
                              _timeLabel(channel.lastMessageAt!),
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 12,
                                color: channel.unreadCount > 0
                                    ? context.colors.accentBlue
                                    : context.colors.textTertiary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(child: _buildPreview(context)),
                          if (channel.unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            _UnreadBadge(count: channel.unreadCount),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showDivider)
            Padding(
              padding: const EdgeInsets.only(left: 82),
              child: Divider(height: 1, color: context.colors.border),
            ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    if (typingText != null) {
      return Text(
        '$typingText is typing...',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'SF Pro',
          fontSize: 14,
          color: context.colors.accentBlue,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final senderName = channel.lastSenderName;
    final message = channel.lastMessage;

    if (senderName == null && message == null) {
      return Text(
        'No messages yet',
        style: TextStyle(
          fontFamily: 'SF Pro',
          fontSize: 14,
          color: context.colors.textTertiary,
        ),
      );
    }

    if (channel.lastMessageIsDeleted) {
      return RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 14,
            color: context.colors.textTertiary,
          ),
          children: [
            if (senderName != null)
              TextSpan(
                text: '$senderName: ',
                style: TextStyle(color: context.colors.textSecondary),
              ),
            TextSpan(
              text: 'Message deleted',
              style: TextStyle(fontStyle: FontStyle.italic, color: context.colors.textTertiary),
            ),
          ],
        ),
      );
    }

    if (channel.lastMessageIsImage) {
      return Row(
        children: [
          if (senderName != null)
            Flexible(
              child: Text(
                '$senderName: ',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 14,
                  color: context.colors.textTertiary,
                ),
              ),
            ),
          Icon(Icons.image_outlined, size: 14, color: context.colors.textTertiary),
          const SizedBox(width: 3),
          Text(
            'Image',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 14,
              color: context.colors.textTertiary,
            ),
          ),
        ],
      );
    }

    if (channel.lastMessageIsVoice) {
      return Row(
        children: [
          Flexible(
            child: Text(
              '$senderName: ',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 14,
                color: context.colors.textTertiary,
              ),
            ),
          ),
          Icon(Icons.headphones_rounded, size: 14, color: context.colors.textTertiary),
          const SizedBox(width: 3),
          Text(
            'Voice message',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 14,
              color: context.colors.textTertiary,
            ),
          ),
        ],
      );
    }

    // API may not set is_image on channel list; detect by null text
    if (message == null) {
      return Row(
        children: [
          if (senderName != null)
            Flexible(
              child: Text(
                '$senderName: ',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 14,
                  color: context.colors.textTertiary,
                ),
              ),
            ),
          Icon(Icons.image_outlined, size: 14, color: context.colors.textTertiary),
          const SizedBox(width: 3),
          Text(
            'Image',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 14,
              color: context.colors.textTertiary,
            ),
          ),
        ],
      );
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'SF Pro',
          fontSize: 14,
          color: context.colors.textTertiary,
          height: 1.3,
        ),
        children: [
          TextSpan(
            text: '$senderName: ',
            style: TextStyle(color: context.colors.textSecondary),
          ),
          TextSpan(text: message),
        ],
      ),
    );
  }

  String _timeLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(d).inDays;

    if (diff == 0) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (diff == 1) return 'Yesterday';
    if (diff <= 6) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}';
  }
}

// ─── Voice badge ───────────────────────────────────────────────────────────────

class _VoiceBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: context.colors.success.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        'Voice',
        style: TextStyle(
          fontFamily: 'SF Pro',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: context.colors.success,
        ),
      ),
    );
  }
}

// ─── Unread badge ──────────────────────────────────────────────────────────────

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.accentBlue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'SF Pro',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
