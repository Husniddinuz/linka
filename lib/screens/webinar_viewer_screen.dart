import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/api_constants.dart';
import '../services/token_service.dart';
import '../widgets/cached_avatar.dart';

// ─── Model ─────────────────────────────────────────────────────────────────────

class WebinarData {
  final int id;
  final String title;
  final String tutorName;
  final String? tutorImage;
  final DateTime? scheduledAt;
  final String status; // "live" | "upcoming" | "ended"
  final String? playbackUrl;
  final int viewerCount;

  const WebinarData({
    required this.id,
    required this.title,
    required this.tutorName,
    this.tutorImage,
    this.scheduledAt,
    required this.status,
    this.playbackUrl,
    this.viewerCount = 0,
  });

  factory WebinarData.fromJson(Map<String, dynamic> j) {
    final rawAt = (j['scheduled_at'] ?? j['starts_at'] ?? '').toString();
    return WebinarData(
      id: j['id'] as int? ?? 0,
      title: (j['title'] ?? '').toString(),
      tutorName: [
        j['tutor_first_name'] ?? '',
        j['tutor_last_name'] ?? '',
      ].where((s) => (s as String).isNotEmpty).join(' '),
      tutorImage: j['tutor_profile_image'] as String?,
      scheduledAt: DateTime.tryParse(rawAt)?.toLocal(),
      status: (j['status'] ?? 'upcoming').toString(),
      playbackUrl: (j['playback_url'] ?? j['stream_url'] ?? '') as String?,
      viewerCount: (j['viewer_count'] ?? j['viewers_count'] ?? 0) as int,
    );
  }

  bool get isLive => status == 'live';
}

// ─── Chat message model ────────────────────────────────────────────────────────

class _ChatMessage {
  final String sender;
  final String text;
  final bool isOwn;

  const _ChatMessage({
    required this.sender,
    required this.text,
    required this.isOwn,
  });
}

// ─── Screen ────────────────────────────────────────────────────────────────────

class WebinarViewerScreen extends StatefulWidget {
  final WebinarData webinar;

  const WebinarViewerScreen({super.key, required this.webinar});

  @override
  State<WebinarViewerScreen> createState() => _WebinarViewerScreenState();
}

class _WebinarViewerScreenState extends State<WebinarViewerScreen> {
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoError = false;

  WebSocketChannel? _chatWs;
  StreamSubscription? _chatSub;
  final List<_ChatMessage> _messages = [];
  final _chatController = TextEditingController();
  final _scrollController = ScrollController();
  bool _chatExpanded = true;
  bool _sendingMessage = false;

  int _viewerCount = 0;

  @override
  void initState() {
    super.initState();
    _viewerCount = widget.webinar.viewerCount;
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (widget.webinar.isLive && widget.webinar.playbackUrl != null && widget.webinar.playbackUrl!.isNotEmpty) {
      _initVideo(widget.webinar.playbackUrl!);
    }
    _connectChat();
  }

  Future<void> _initVideo(String url) async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _videoController = controller;
        _videoInitialized = true;
      });
      controller.play();
      controller.setLooping(false);
    } catch (e) {
      dev.log('Webinar video init error: $e');
      if (!mounted) return;
      setState(() => _videoError = true);
    }
  }

  Future<void> _connectChat() async {
    final token = await TokenService.getAccessToken();
    if (token == null || !mounted) return;

    final wsBase = apiBaseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://')
        .replaceFirst('/api/v1', '');
    final wsUrl = '$wsBase/ws/webinars/${widget.webinar.id}/chat/?token=$token';

    try {
      _chatWs = WebSocketChannel.connect(Uri.parse(wsUrl));
      _chatSub = _chatWs!.stream.listen(
        _onChatMessage,
        onError: (e) => dev.log('Webinar chat WS error: $e'),
        cancelOnError: false,
      );
    } catch (e) {
      dev.log('Webinar chat connect error: $e');
    }
  }

  void _onChatMessage(dynamic raw) {
    try {
      final data = json.decode(raw as String) as Map<String, dynamic>;
      final type = data['type'] as String? ?? '';

      if (type == 'chat_message' || type == 'message') {
        final sender = (data['sender_name'] ?? data['sender'] ?? 'User').toString();
        final text = (data['message'] ?? data['text'] ?? '').toString();
        if (text.isEmpty) return;
        if (!mounted) return;
        setState(() {
          _messages.add(_ChatMessage(sender: sender, text: text, isOwn: false));
        });
        _scrollToBottom();
      } else if (type == 'viewer_count') {
        final count = data['count'] as int? ?? _viewerCount;
        if (!mounted) return;
        setState(() => _viewerCount = count);
      }
    } catch (e) {
      dev.log('Chat parse error: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _sendingMessage || _chatWs == null) return;

    _chatController.clear();
    setState(() {
      _sendingMessage = true;
      _messages.add(_ChatMessage(sender: 'You', text: text, isOwn: true));
    });
    _scrollToBottom();

    try {
      _chatWs!.sink.add(json.encode({'type': 'chat_message', 'message': text}));
    } catch (e) {
      dev.log('Chat send error: $e');
    } finally {
      if (mounted) setState(() => _sendingMessage = false);
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chatSub?.cancel();
    _chatWs?.sink.close();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildVideoSection(),
            _buildWebinarInfo(),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            _buildChatToggle(),
            if (_chatExpanded) Expanded(child: _buildChat()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.chevron_left_rounded, size: 30, color: Color(0xFF272942)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.webinar.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF272942),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.webinar.isLive) ...[
            const SizedBox(width: 8),
            _LiveBadge(viewerCount: _viewerCount),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoSection() {
    if (!widget.webinar.isLive) {
      return _UpcomingVideoPlaceholder(webinar: widget.webinar);
    }
    if (_videoError) {
      return _VideoErrorPlaceholder(onRetry: () {
        setState(() => _videoError = false);
        if (widget.webinar.playbackUrl != null) _initVideo(widget.webinar.playbackUrl!);
      });
    }
    if (!_videoInitialized || _videoController == null) {
      return const _VideoLoadingPlaceholder();
    }

    return AspectRatio(
      aspectRatio: _videoController!.value.aspectRatio,
      child: VideoPlayer(_videoController!),
    );
  }

  Widget _buildWebinarInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          CachedAvatar(imageUrl: widget.webinar.tutorImage, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.webinar.tutorName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF272942),
                  ),
                ),
                const Text(
                  'Tutor · Webinar host',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFFAAAAAA),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF272942).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.mic_off_rounded, size: 14, color: Color(0xFFAAAAAA)),
                const SizedBox(width: 4),
                Text(
                  'View only',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatToggle() {
    return GestureDetector(
      onTap: () => setState(() => _chatExpanded = !_chatExpanded),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Text(
              'LIVE CHAT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF272942),
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Icon(
              _chatExpanded
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              color: const Color(0xFF272942),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChat() {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Text(
                    'No messages yet.\nBe the first to say hi!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFFAAAAAA),
                      height: 1.5,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _ChatBubble(message: _messages[i]),
                ),
        ),
        _buildChatInput(),
      ],
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F2),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _chatController,
                style: const TextStyle(fontSize: 14, color: Color(0xFF272942)),
                decoration: const InputDecoration(
                  hintText: 'Ask a question...',
                  hintStyle: TextStyle(color: Color(0xFFAAAAAA), fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendingMessage ? null : _sendMessage,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _sendingMessage
                    ? const Color(0xFFCCCCCC)
                    : const Color(0xFF272942),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helper widgets ────────────────────────────────────────────────────────────

class _LiveBadge extends StatelessWidget {
  final int viewerCount;
  const _LiveBadge({required this.viewerCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFE74C3C),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'LIVE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (viewerCount > 0) ...[
          const SizedBox(width: 6),
          Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 13, color: Color(0xFFAAAAAA)),
              const SizedBox(width: 3),
              Text(
                '$viewerCount',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFAAAAAA),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _VideoLoadingPlaceholder extends StatelessWidget {
  const _VideoLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: const Color(0xFF272942),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFFF5C542)),
        ),
      ),
    );
  }
}

class _VideoErrorPlaceholder extends StatelessWidget {
  final VoidCallback onRetry;
  const _VideoErrorPlaceholder({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: const Color(0xFF272942),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.signal_wifi_bad_rounded, color: Color(0xFFF5C542), size: 40),
            const SizedBox(height: 10),
            const Text(
              'Stream unavailable',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5C542),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    color: Color(0xFF272942),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpcomingVideoPlaceholder extends StatelessWidget {
  final WebinarData webinar;
  const _UpcomingVideoPlaceholder({required this.webinar});

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month]}';
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: const Color(0xFF272942),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.live_tv_rounded, color: Color(0xFFF5C542), size: 44),
            const SizedBox(height: 12),
            const Text(
              'Session starts at',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatDate(webinar.scheduledAt)}  ${_formatTime(webinar.scheduledAt)}',
              style: const TextStyle(
                color: Color(0xFFF5C542),
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: message.isOwn
                  ? const Color(0xFFF5C542)
                  : const Color(0xFF272942).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                message.sender.isNotEmpty ? message.sender[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: message.isOwn
                      ? const Color(0xFF272942)
                      : const Color(0xFF272942),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.isOwn ? 'You' : message.sender,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF272942),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: message.isOwn
                        ? const Color(0xFFF5C542).withValues(alpha: 0.15)
                        : const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    message.text,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF272942),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
