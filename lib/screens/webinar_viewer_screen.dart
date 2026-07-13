import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/api_constants.dart';
import '../services/api_service.dart';
import '../services/token_service.dart';
import '../theme/app_colors.dart';
import '../widgets/cached_avatar.dart';
import 'tutor_profile_screen.dart';

// ─── Model ─────────────────────────────────────────────────────────────────────

class WebinarData {
  final int id;
  final String title;
  final String tutorName;
  final String? tutorImage;
  final int? tutorId;
  final DateTime? scheduledAt;
  final DateTime? endAt;
  final String status; // "scheduled" | "live" | "ended"
  final String? muxPlaybackId;
  final int viewerCount;
  final bool joinEnabled;
  final String? vodUrl;

  const WebinarData({
    required this.id,
    required this.title,
    required this.tutorName,
    this.tutorImage,
    this.tutorId,
    this.scheduledAt,
    this.endAt,
    required this.status,
    this.muxPlaybackId,
    this.viewerCount = 0,
    this.joinEnabled = false,
    this.vodUrl,
  });

  factory WebinarData.fromJson(Map<String, dynamic> j) {
    final tutorMap = j['tutor'] as Map<String, dynamic>?;
    final rawStart = (j['start_at'] ?? j['scheduled_at'] ?? j['starts_at'] ?? '').toString();
    final rawEnd = (j['end_at'] ?? '').toString();
    final tutorName = tutorMap?['display_name']?.toString() ??
        [j['tutor_first_name'] ?? '', j['tutor_last_name'] ?? '']
            .where((s) => (s as String).isNotEmpty)
            .join(' ');
    // tutor_profile_id / profile_id take priority over the generic 'id' field
    // because 'id' inside a nested tutor map may be the user ID, not the profile ID.
    final tutorProfileId =
        tutorMap?['tutor_profile_id'] as int? ??
        tutorMap?['profile_id'] as int? ??
        j['tutor_profile_id'] as int? ??
        j['tutor_id'] as int? ??
        tutorMap?['id'] as int?;
    return WebinarData(
      id: j['id'] as int? ?? 0,
      title: (j['title'] ?? '').toString(),
      tutorName: tutorName,
      tutorImage: tutorMap?['image']?.toString() ?? j['tutor_profile_image'] as String?,
      tutorId: tutorProfileId,
      scheduledAt: DateTime.tryParse(rawStart)?.toLocal(),
      endAt: DateTime.tryParse(rawEnd)?.toLocal(),
      status: (j['status'] ?? 'scheduled').toString(),
      muxPlaybackId: j['mux_playback_id']?.toString(),
      viewerCount: (j['viewer_count'] ?? j['viewers_count'] ?? 0) as int,
      joinEnabled: j['join_enabled'] as bool? ?? j['is_live'] as bool? ?? false,
      vodUrl: j['vod_url']?.toString() ?? j['recording_url']?.toString(),
    );
  }

  bool get isLive => status == 'live';
  bool get isScheduled => status == 'scheduled';
  bool get hasVod => (vodUrl?.isNotEmpty ?? false) && status == 'ended';
  String? get muxPlaybackUrl => (muxPlaybackId?.isNotEmpty ?? false)
      ? 'https://stream.mux.com/$muxPlaybackId.m3u8'
      : null;
}

// ─── Chat message model ────────────────────────────────────────────────────────

class _ChatMessage {
  final String sender;
  final String text;
  final bool isOwn;
  final String? avatarUrl;

  const _ChatMessage({
    required this.sender,
    required this.text,
    required this.isOwn,
    this.avatarUrl,
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
  bool _wsConnected = false;
  final Set<String> _pendingOutbound = {};

  int _viewerCount = 0;
  String? _resolvedPlaybackUrl;

  @override
  void initState() {
    super.initState();
    _viewerCount = widget.webinar.viewerCount;
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _joinAndLoadVideo();
    _connectChat();
  }

  Future<void> _joinAndLoadVideo() async {
    final webinar = widget.webinar;
    if (webinar.hasVod) {
      _resolvedPlaybackUrl = webinar.vodUrl;
      _initVideo(webinar.vodUrl!, kind: 'VOD');
      return;
    }
    if (!webinar.isLive) return;

    String? url;
    try {
      final data = await ApiService.post('/live/webinar/${webinar.id}/join/', {});
      url = data['mux_playback_url']?.toString();
    } on ApiException catch (e) {
      url = webinar.muxPlaybackUrl;
    }
    if (url == null || url.isEmpty || !mounted) return;
    _resolvedPlaybackUrl = url;
    _initVideo(url, kind: 'live');
  }

  Future<void> _initVideo(String url, {String kind = 'live'}) async {
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
      if (!mounted) return;
      setState(() => _videoError = true);
    }
  }

  Future<void> _connectChat() async {
    if (!widget.webinar.isLive) return;

    final token = await TokenService.getAccessToken();
    if (token == null || !mounted) return;

    final apiUri = Uri.parse(apiBaseUrl);
    final wsScheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
    final wsUrl =
        '$wsScheme://${apiUri.host}/ws/live/session/${widget.webinar.id}/?token=$token';

    try {
      await _chatSub?.cancel();
      await _chatWs?.sink.close();
      _chatWs = WebSocketChannel.connect(Uri.parse(wsUrl));
      await _chatWs!.ready;
      if (!mounted) return;
      setState(() => _wsConnected = true);
      _chatSub = _chatWs!.stream.listen(
        _onChatMessage,
        onError: (e) {
          if (mounted) setState(() => _wsConnected = false);
        },
        onDone: () {
          if (mounted) setState(() { _wsConnected = false; _chatWs = null; });
        },
        cancelOnError: false,
      );
    } catch (e) {
      _chatWs = null;
      if (mounted) setState(() => _wsConnected = false);
    }
  }

  void _onChatMessage(dynamic raw) {
    try {
      final data = json.decode(raw as String) as Map<String, dynamic>;
      final type = (data['type'] as String? ?? '').toLowerCase();

      // Chat — backend sends:
      // {"type":"chat_message","message":{"text":"...","user":{"display_name":"..."}}}
      if (type == 'chat_message') {
        final msgObj = data['message'];
        final String msgText;
        final String msgSender;
        String? avatarUrl;
        if (msgObj is Map<String, dynamic>) {
          msgText = (msgObj['text'] ?? '').toString();
          final userObj = msgObj['user'];
          if (userObj is Map<String, dynamic>) {
            msgSender =
                (userObj['display_name'] ?? userObj['username'] ?? 'User')
                    .toString();
            final rawImg = userObj['image']?.toString() ?? '';
            if (rawImg.isNotEmpty) {
              final base = Uri.parse(apiBaseUrl);
              avatarUrl = rawImg.startsWith('http')
                  ? rawImg
                  : '${base.scheme}://${base.host}$rawImg';
            }
          } else {
            msgSender = 'User';
          }
        } else {
          // fallback for plain-text format
          msgText = (data['text'] ?? data['content'] ?? '').toString();
          msgSender =
              (data['sender_name'] ?? data['sender'] ?? 'User').toString();
        }
        if (msgText.isEmpty) return;
        if (_pendingOutbound.remove(msgText)) return;
        if (!mounted) return;
        setState(() {
          _messages.add(_ChatMessage(
            sender: msgSender,
            text: msgText,
            isOwn: false,
            avatarUrl: avatarUrl,
          ));
        });
        _scrollToBottom();
      }

      // Viewer count — handle all common field/type names
      final rawCount = data['count'] ??
          data['viewer_count'] ??
          data['viewers_count'] ??
          data['viewers'];
      if (type == 'viewer_count' ||
          type == 'viewer_update' ||
          type == 'viewer_joined' ||
          type == 'viewer_left' ||
          rawCount is int) {
        final count = rawCount is int
            ? rawCount
            : (rawCount as num?)?.toInt();
        if (count != null && mounted) setState(() => _viewerCount = count);
      }
    } catch (e) {
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
    FocusScope.of(context).unfocus();
    _pendingOutbound.add(text); // track before WS echo arrives
    setState(() {
      _sendingMessage = true;
      _messages.add(_ChatMessage(sender: 'You', text: text, isOwn: true));
    });
    _scrollToBottom();

    try {
      _chatWs!.sink.add(json.encode({'type': 'chat_message', 'text': text}));
    } catch (e) {
      _pendingOutbound.remove(text); // send failed, no echo will arrive
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
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
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
    final showPlayer = widget.webinar.isLive || widget.webinar.hasVod;
    if (!showPlayer) {
      return _UpcomingVideoPlaceholder(webinar: widget.webinar);
    }
    if (_videoError) {
      return _VideoErrorPlaceholder(onRetry: () {
        setState(() => _videoError = false);
        final url = _resolvedPlaybackUrl;
        if (url != null && url.isNotEmpty) {
          _initVideo(url, kind: widget.webinar.hasVod ? 'VOD' : 'live');
        } else {
          _joinAndLoadVideo();
        }
      });
    }
    if (!_videoInitialized || _videoController == null) {
      return const _VideoLoadingPlaceholder();
    }

    return GestureDetector(
      onTap: () => _openFullscreen(),
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(
              Icons.fullscreen_rounded,
              color: Colors.white,
              size: 28,
              shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFullscreen() async {
    if (_videoController == null) return;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenVideoScreen(controller: _videoController!),
      ),
    );
    if (mounted) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  Widget _buildWebinarInfo() {
    final tutorId = widget.webinar.tutorId;
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
          const SizedBox(width: 8),
          if (tutorId != null)
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TutorProfileScreen(tutorId: tutorId),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5C542),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Book lesson',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF272942),
                  ),
                ),
              ),
            )
          else
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
            const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _wsConnected
                    ? const Color(0xFF27AE60)
                    : const Color(0xFFCCCCCC),
              ),
            ),
            if (!_wsConnected && widget.webinar.isLive) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _connectChat,
                child: const Text(
                  'Reconnect',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2B85DB),
                  ),
                ),
              ),
            ],
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
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    const inputH = 64.0; // top-pad + TextField + bottom-pad when no keyboard
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
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
                    padding: EdgeInsets.fromLTRB(16, 8, 16, inputH + keyboardH),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _ChatBubble(message: _messages[i]),
                  ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: keyboardH,
          child: _buildChatInput(),
        ),
      ],
    );
  }

  Widget _buildChatInput() {
    final safeBottom = MediaQuery.of(context).viewInsets.bottom > 0
        ? 8.0
        : MediaQuery.of(context).viewPadding.bottom + 8.0;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, safeBottom),
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

class _FullscreenVideoScreen extends StatefulWidget {
  final VideoPlayerController controller;
  const _FullscreenVideoScreen({required this.controller});

  @override
  State<_FullscreenVideoScreen> createState() => _FullscreenVideoScreenState();
}

class _FullscreenVideoScreenState extends State<_FullscreenVideoScreen> {
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _controlsVisible = !_controlsVisible),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: widget.controller.value.aspectRatio,
                child: VideoPlayer(widget.controller),
              ),
            ),
            if (_controlsVisible)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.fullscreen_exit_rounded,
                          color: Colors.white,
                          size: 28,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                        ),
                      ),
                    ],
                  ),
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
    final isOwn = message.isOwn;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isOwn) ...[
            CachedAvatar(imageUrl: message.avatarUrl, size: 30),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isOwn)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Text(
                      message.sender,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF272942),
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isOwn
                        ? const Color(0xFF272942)
                        : const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isOwn ? 16 : 4),
                      bottomRight: Radius.circular(isOwn ? 4 : 16),
                    ),
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 13,
                      color: isOwn ? Colors.white : const Color(0xFF272942),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isOwn) const SizedBox(width: 8),
        ],
      ),
    );
  }
}
