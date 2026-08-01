import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/social.dart';
import '../services/chat_service.dart';
import '../services/social_service.dart';
import '../theme/app_colors.dart';
import '../widgets/skeleton.dart';
import 'channel_chat_screen.dart';
import 'plus_subscription_screen.dart';

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

/// A private one-to-one thread.
///
/// Deliberately not a [ChatChannel]: a channel is a room with a name everyone
/// shares, and this is a person whose name depends on who is looking. What the
/// two do share is the channel slug in [channelId] — every message endpoint and
/// the WebSocket take it, so the thread opens in the same screen as `#general`.
class DirectConversation {
  final int id;
  final String channelId;
  final int otherUserId;
  final String displayName;
  final String? avatarUrl;

  /// True when *either* side has blocked the other. The server does not say
  /// which, and the effect here is the same either way: the composer closes.
  final bool isBlocked;

  final int unreadCount;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final bool lastMessageIsVoice;
  final bool lastMessageIsImage;
  final bool lastMessageIsDeleted;
  final DateTime? createdAt;

  const DirectConversation({
    required this.id,
    required this.channelId,
    required this.otherUserId,
    required this.displayName,
    this.avatarUrl,
    this.isBlocked = false,
    this.unreadCount = 0,
    this.lastMessage,
    this.lastMessageAt,
    this.lastMessageIsVoice = false,
    this.lastMessageIsImage = false,
    this.lastMessageIsDeleted = false,
    this.createdAt,
  });

  factory DirectConversation.fromJson(Map<String, dynamic> json) {
    final other = json['other_user'] as Map<String, dynamic>? ?? const {};
    final lastMsg = json['last_message'] as Map<String, dynamic>?;
    return DirectConversation(
      id: (json['id'] as num?)?.toInt() ?? 0,
      channelId: json['channel_id']?.toString() ?? '',
      otherUserId: (other['user_id'] as num?)?.toInt() ?? 0,
      displayName: other['display_name']?.toString() ?? 'Linka user',
      avatarUrl: ChatService.absoluteUrl(other['profile_image'] as String?),
      isBlocked: json['is_blocked'] as bool? ?? false,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      lastMessage: lastMsg?['text'] as String?,
      lastMessageAt: ChatChannel._parseDate(lastMsg?['sent_at'] as String?),
      lastMessageIsVoice: lastMsg?['is_voice'] as bool? ?? false,
      lastMessageIsImage: lastMsg?['is_image'] as bool? ?? false,
      lastMessageIsDeleted: lastMsg?['is_deleted'] as bool? ?? false,
      createdAt: ChatChannel._parseDate(json['created_at'] as String?),
    );
  }

  /// The inert channel the thread's messages hang off. A conversation has no
  /// channel row of its own to show — no emoji, no tile colour, no type — so
  /// these are placeholders; [DirectThread] is what the screen actually reads.
  ChatChannel get asChannel => ChatChannel(
        id: channelId,
        name: displayName,
        emoji: '💬',
        tileColor: const Color(0xFF5B7FD4),
        type: ChannelType.text,
        unreadCount: unreadCount,
      );

  DirectThread get asThread => DirectThread(
        otherUserId: otherUserId,
        displayName: displayName,
        isBlocked: isBlocked,
      );
}

/// What the chat screen needs to know to render a thread as a conversation
/// rather than a channel.
class DirectThread {
  final int otherUserId;
  final String displayName;
  final bool isBlocked;

  const DirectThread({
    required this.otherUserId,
    required this.displayName,
    required this.isBlocked,
  });
}

/// Opens the private thread with [userId], or says why it cannot be opened.
///
/// The single entry point for every place a conversation can start — a public
/// profile, a message author in a channel, a follower row, the compose search —
/// so the Plus prompt and the refusal read the same wherever the tap came from.
///
/// Only *starting* a thread costs Plus. Reopening one already in existence does
/// not, so this is also the right call for a lapsed subscriber returning to a
/// conversation they began while subscribed.
Future<void> openDirectConversation(
  BuildContext context, {
  required int userId,
}) async {
  try {
    final raw = await ChatService.startConversation(userId: userId);
    if (!context.mounted) return;
    final conversation = DirectConversation.fromJson(raw);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelChatScreen(
          channel: conversation.asChannel,
          direct: conversation.asThread,
        ),
      ),
    );
  } on ConversationRefused catch (e) {
    if (!context.mounted) return;
    // The only refusal worth a detour. Every other one — a tutor, a hidden
    // account, someone who has blocked you — is a dead end the server
    // deliberately does not distinguish, so it gets a plain message.
    if (e.needsPlus) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PlusSubscriptionScreen()),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.message)),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
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
  List<DirectConversation> _conversations = [];
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
      // Both lists in one pass so a pull-to-refresh does not settle twice.
      // The conversation list is allowed to fail on its own — a tutor account
      // has no private threads and the endpoint refuses it, which must not
      // take the community channels down with it.
      final results = await Future.wait([
        ChatService.fetchChannels(),
        ChatService.fetchConversations().catchError(
          (_) => <Map<String, dynamic>>[],
        ),
      ]);
      if (mounted) {
        setState(() {
          _channels = results[0].map(ChatChannel.fromJson).toList();
          _conversations =
              results[1].map(DirectConversation.fromJson).toList();
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
      return const _ChannelListSkeleton();
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
      child: ListView(
        // Always scrollable, or a short list on a tall screen has nothing to
        // pull against and the refresh gesture is unreachable.
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < _channels.length; i++)
            _ChannelTile(
              channel: _channels[i],
              showDivider: i < _channels.length - 1,
              onReturn: _loadChannels,
              typingText: _channelTyping[_channels[i].id],
            ),
          if (_conversations.isNotEmpty) ...[
            _SectionHeader(title: 'Private messages'),
            for (var i = 0; i < _conversations.length; i++)
              _ConversationTile(
                conversation: _conversations[i],
                showDivider: i < _conversations.length - 1,
                onReturn: _loadChannels,
              ),
          ],
          const SizedBox(height: 24),
        ],
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
          const Spacer(),
          // The one place to start a thread with someone you have not spoken
          // to — the other entry points all begin from a person already on
          // screen (a profile, a message author, a follower row).
          IconButton(
            onPressed: () async {
              final userId = await showModalBottomSheet<int>(
                context: context,
                isScrollControlled: true,
                backgroundColor: context.colors.surface,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (_) => const _ComposeSheet(),
              );
              if (!mounted) return;
              if (userId != null) {
                await openDirectConversation(context, userId: userId);
              }
              if (mounted) _loadChannels(silent: true);
            },
            tooltip: 'New message',
            icon: Icon(
              Icons.edit_square,
              size: 22,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Compose: find someone to write to ─────────────────────────────────────────

class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet();

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _controller = TextEditingController();
  List<SocialUserCard> _results = const [];
  bool _searching = false;
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final term = _controller.text.trim();
    if (term.length < 2 || _searching) return;
    setState(() => _searching = true);
    try {
      final found = await SocialService.search(term);
      if (!mounted) return;
      setState(() {
        // Tutors come back from this search because it is shared with the
        // follow graph, where they belong. Private threads are
        // student-to-student, so offering one here would only be refused.
        _results = found.where((person) => !person.isTutor).toList();
      });
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
          _searched = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New message',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Only Linka Plus members can start a new conversation. '
            'Anyone can reply to one.',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 12,
              color: context.colors.textTertiary,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search by name',
              hintStyle: TextStyle(color: context.colors.textTertiary),
              filled: true,
              fillColor: context.colors.surfaceAlt,
              suffixIcon: IconButton(
                icon: _searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
                color: context.colors.textSecondary,
                onPressed: _run,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_searched && _results.isEmpty && !_searching)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Nobody found by that name.',
                style: TextStyle(color: context.colors.textSecondary),
              ),
            ),
          if (_results.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (context, index) =>
                    Divider(height: 1, color: context.colors.border),
                itemBuilder: (_, i) {
                  final person = _results[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _Avatar(
                      url: ChatService.absoluteUrl(person.profileImage),
                      name: person.displayName,
                      size: 40,
                    ),
                    title: Text(
                      person.displayName,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    subtitle: person.subtitle == null
                        ? null
                        : Text(
                            person.subtitle!,
                            style:
                                TextStyle(color: context.colors.textSecondary),
                          ),
                    trailing: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 20,
                      color: context.colors.accentBlue,
                    ),
                    // Hands the chosen id back rather than opening the thread
                    // itself: this context dies with the sheet, and the push
                    // and any error snackbar have to outlive it.
                    onTap: () => Navigator.pop(context, person.userId),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Loading skeleton ─────────────────────────────────────────────────────────

class _ChannelListSkeleton extends StatelessWidget {
  const _ChannelListSkeleton();

  // Varied preview-line widths so the placeholder rows don't look identical.
  static const _previewFactors = [0.62, 0.48, 0.70, 0.40, 0.56, 0.66, 0.44, 0.60];

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width;
    return IgnorePointer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < _previewFactors.length; i++)
            _tile(
              context,
              previewWidth: maxWidth * _previewFactors[i],
              showDivider: i < _previewFactors.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required double previewWidth,
    required bool showDivider,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Skeleton(width: 54, height: 54, borderRadius: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Skeleton(width: 150, height: 15, borderRadius: 4),
                    const SizedBox(height: 8),
                    Skeleton(width: previewWidth, height: 13, borderRadius: 4),
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

  String _timeLabel(DateTime dt) => _chatTimeLabel(dt);
}

/// Time today, "Yesterday", the weekday within the last week, then a numeric
/// date. Shared by the channel and conversation rows so the two lists on the
/// same screen cannot climb different ladders.
String _chatTimeLabel(DateTime dt) {
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

// ─── Private conversations ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: 'SF Pro',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final DirectConversation conversation;
  final bool showDivider;
  final VoidCallback? onReturn;
  const _ConversationTile({
    required this.conversation,
    this.showDivider = true,
    this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        // Straight to the thread: it already exists, so there is nothing to
        // ask the server and no Plus check to fail.
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChannelChatScreen(
              channel: conversation.asChannel,
              direct: conversation.asThread,
            ),
          ),
        );
        onReturn?.call();
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _Avatar(
                  url: conversation.avatarUrl,
                  name: conversation.displayName,
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
                                Flexible(
                                  child: Text(
                                    conversation.displayName,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'SF Pro',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: context.colors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (conversation.isBlocked) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.block_rounded,
                                    size: 14,
                                    color: context.colors.textTertiary,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (conversation.lastMessageAt != null)
                            Text(
                              _chatTimeLabel(conversation.lastMessageAt!),
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 12,
                                color: conversation.unreadCount > 0
                                    ? context.colors.accentBlue
                                    : context.colors.textTertiary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _preview(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 14,
                                fontStyle: conversation.lastMessageIsDeleted
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                color: context.colors.textSecondary,
                              ),
                            ),
                          ),
                          if (conversation.unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            _UnreadBadge(count: conversation.unreadCount),
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

  String _preview() {
    if (conversation.lastMessageIsDeleted) return 'Message deleted';
    if (conversation.lastMessageIsVoice) return '🎧 Voice message';
    if (conversation.lastMessageIsImage) return '🖼 Image';
    final text = conversation.lastMessage;
    if (text == null || text.isEmpty) return 'No messages yet';
    return text;
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  const _Avatar({required this.url, required this.name, this.size = 54});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt,
        shape: BoxShape.circle,
      ),
      child: url == null
          ? Center(
              child: Text(
                initials,
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: size * 0.34,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textSecondary,
                ),
              ),
            )
          : Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: size * 0.34,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) {
      final first = parts.first;
      return (first.length >= 2 ? first.substring(0, 2) : first).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
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
