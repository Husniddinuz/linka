import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/api_constants.dart';
import '../services/api_service.dart';
import '../services/debate_service.dart';
import '../services/token_service.dart';

// ─── Models ────────────────────────────────────────────────────────────────────

class _Part {
  final int userId;
  final String firstName;
  final String lastName;
  final String? profileImage;
  String role; // 'speaker' | 'viewer' | 'moderator'
  String? team; // 'A' | 'B' | null
  bool isSpeaking;

  _Part({
    required this.userId,
    required this.firstName,
    required this.lastName,
    this.profileImage,
    required this.role,
    this.team,
    this.isSpeaking = false,
  });

  String get displayName {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? 'User' : n;
  }

  factory _Part.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>? ?? {};
    return _Part(
      userId: (j['user_id'] ?? user['id'] ?? 0) as int,
      firstName: (user['first_name'] ?? '').toString(),
      lastName: (user['last_name'] ?? '').toString(),
      profileImage: user['profile_image']?.toString(),
      role: (j['role'] ?? 'viewer').toString(),
      team: j['team']?.toString(),
      isSpeaking: j['is_speaking'] as bool? ?? false,
    );
  }
}

class _ChatMsg {
  final int? id;
  final String sender;
  final String text;
  final bool isOwn;

  const _ChatMsg({
    this.id,
    required this.sender,
    required this.text,
    this.isOwn = false,
  });
}

// ─── Screen ────────────────────────────────────────────────────────────────────

class DebateRoomScreen extends StatefulWidget {
  final int sessionId;
  final String title;
  final String? topic;

  const DebateRoomScreen({
    super.key,
    required this.sessionId,
    required this.title,
    this.topic,
  });

  @override
  State<DebateRoomScreen> createState() => _DebateRoomScreenState();
}

class _DebateRoomScreenState extends State<DebateRoomScreen> {
  // ── Join state ──────────────────────────────────────────────────────────────
  bool _loading = true;
  String? _errorMsg;
  String _mode = 'chat_only'; // 'rtc' | 'cdn' | 'chat_only'
  String? _myTeam;

  // ── WebView (mode=rtc) ───────────────────────────────────────────────────────
  WebViewController? _webCtrl;

  // ── Participants ────────────────────────────────────────────────────────────
  final Map<int, _Part> _parts = {};
  int _viewerCount = 0;

  // ── Chat ────────────────────────────────────────────────────────────────────
  final List<_ChatMsg> _msgs = [];
  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _canSend = true;
  Timer? _cooldownTimer;

  // ── WebSocket ───────────────────────────────────────────────────────────────
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  Timer? _wsReconTimer;

  // ── Reconciliation ──────────────────────────────────────────────────────────
  Timer? _partsTimer;

  // ── HLS ─────────────────────────────────────────────────────────────────────
  VideoPlayerController? _vc;
  bool _vcReady = false;
  bool _vcError = false;
  String? _playbackUrl;
  int _hlsRetries = 0;
  Timer? _hlsRetryTimer;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _join();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _cooldownTimer?.cancel();
    _wsReconTimer?.cancel();
    _partsTimer?.cancel();
    _hlsRetryTimer?.cancel();
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    _teardown();
    super.dispose();
  }

  // ─── Join ────────────────────────────────────────────────────────────────────

  Future<void> _join() async {
    if (mounted) setState(() { _loading = true; _errorMsg = null; });
    try {
      final data = await DebateService.join(widget.sessionId);
      if (!mounted) return;

      final mode = data['mode'] as String? ?? 'chat_only';
      final team = data['team']?.toString();

      final rawParts = data['participants'] as List<dynamic>? ?? [];
      final partsMap = <int, _Part>{};
      for (final p in rawParts) {
        final part = _Part.fromJson(p as Map<String, dynamic>);
        partsMap[part.userId] = part;
      }

      setState(() {
        _mode = mode;
        _myTeam = team;
        _parts
          ..clear()
          ..addAll(partsMap);
        _loading = false;
      });

      _loadChatHistory();
      _connectWs();
      _startPartsTimer();

      if (mode == 'rtc') {
        final url = data['web_rtc_url'] as String?;
        if (url != null && url.isNotEmpty) {
          _initWebView(url);
        } else {
          setState(() => _mode = 'chat_only');
        }
      } else if (mode == 'cdn') {
        final url = data['playback_url'] as String?;
        if (url != null && url.isNotEmpty) {
          _playbackUrl = url;
          _hlsRetries = 0;
          _initHls(url);
        } else {
          setState(() => _mode = 'chat_only');
        }
      }
      // chat_only: no media to init
    } on ApiException catch (e) {
      if (!mounted) return;
      final msg = switch (e.statusCode) {
        410 => 'This debate has already ended.',
        403 => 'You don\'t have permission to join this debate.',
        503 => 'The live stream isn\'t ready yet. Please try again in a moment.',
        _ => e.message,
      };
      setState(() { _loading = false; _errorMsg = msg; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _errorMsg = 'Failed to join debate. Please try again.'; });
    }
  }

  // ─── HLS ─────────────────────────────────────────────────────────────────────

  Future<void> _initHls(String url) async {
    _hlsRetryTimer?.cancel();
    try {
      await _vc?.dispose();
      final vc = VideoPlayerController.networkUrl(Uri.parse(url));
      await vc.initialize();
      if (!mounted) { vc.dispose(); return; }
      setState(() {
        _vc = vc;
        _vcReady = true;
        _vcError = false;
      });
      vc.play();
      vc.setLooping(false);
    } catch (_) {
      if (!mounted) return;
      if (_hlsRetries < 5) {
        const delays = [2, 4, 8, 15, 20];
        final delay = delays[_hlsRetries.clamp(0, delays.length - 1)];
        _hlsRetries++;
        _hlsRetryTimer = Timer(Duration(seconds: delay), () => _initHls(url));
      } else {
        setState(() => _vcError = true);
      }
    }
  }

  // ─── WebView (mode=rtc) ──────────────────────────────────────────────────────

  void _initWebView(String url) {
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));
    if (!mounted) return;
    setState(() => _webCtrl = ctrl);
  }

  // ─── WebSocket ───────────────────────────────────────────────────────────────

  Future<void> _connectWs() async {
    await _wsSub?.cancel();
    try { _ws?.sink.close(); } catch (_) {}

    final token = await TokenService.getAccessToken();
    if (token == null || !mounted) return;

    final apiUri = Uri.parse(apiBaseUrl);
    final scheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
    final url =
        '$scheme://${apiUri.host}/ws/live/session/${widget.sessionId}/?token=$token';

    try {
      _ws = WebSocketChannel.connect(Uri.parse(url));
      await _ws!.ready;
      if (!mounted) return;
      _wsSub = _ws!.stream.listen(
        _onWsMsg,
        onError: (_) => _scheduleWsRecon(),
        onDone: _scheduleWsRecon,
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleWsRecon();
    }
  }

  void _scheduleWsRecon() {
    _wsReconTimer?.cancel();
    _wsReconTimer =
        Timer(const Duration(seconds: 5), () { if (mounted) _connectWs(); });
  }

  void _onWsMsg(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (data['type'] as String?) {
        case 'chat_message':
          _handleChatMsg(data['message'] as Map<String, dynamic>? ?? {});
        case 'viewer_count':
          final count = data['count'] as int?;
          if (count != null && mounted) setState(() => _viewerCount = count);
        case 'speaking_changed':
          final uid = data['user_id'] as int?;
          final speaking = data['speaking'] as bool?;
          if (uid != null && speaking != null && mounted) {
            setState(() {
              if (_parts.containsKey(uid)) {
                _parts[uid]!.isSpeaking = speaking;
              } else {
                _fetchParticipants();
              }
            });
          }
        case 'role_changed':
          final uid = data['user_id'] as int?;
          final role = data['role'] as String?;
          final team = data['team']?.toString();
          if (uid != null && role != null && mounted) {
            setState(() {
              if (_parts.containsKey(uid)) {
                _parts[uid]!.role = role;
                _parts[uid]!.team = team;
                if (role != 'speaker') _parts[uid]!.isSpeaking = false;
              } else {
                _fetchParticipants();
              }
            });
          }
        case 'chat_rate_limited':
          _showSnack('Please wait before sending another message');
      }
    } catch (_) {}
  }

  void _handleChatMsg(Map<String, dynamic> msg) {
    final text = (msg['text'] ?? '').toString();
    if (text.isEmpty) return;
    final user = msg['user'] as Map<String, dynamic>? ?? {};
    final sender = (user['display_name'] ?? 'User').toString();
    if (!mounted) return;
    setState(() {
      _msgs.add(_ChatMsg(id: msg['id'] as int?, sender: sender, text: text));
    });
    _scrollToBottom();
  }

  // ─── Chat ────────────────────────────────────────────────────────────────────

  Future<void> _loadChatHistory() async {
    final items = await DebateService.getChatHistory(widget.sessionId);
    if (!mounted || items.isEmpty) return;
    final loaded = <_ChatMsg>[];
    for (final item in items) {
      final msg = item as Map<String, dynamic>;
      final text = (msg['text'] ?? '').toString();
      if (text.isEmpty) continue;
      final user = msg['user'] as Map<String, dynamic>? ?? {};
      final sender = (user['display_name'] ?? 'User').toString();
      loaded.add(_ChatMsg(id: msg['id'] as int?, sender: sender, text: text));
    }
    if (!mounted) return;
    setState(() => _msgs.insertAll(0, loaded));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _sendMessage() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty || !_canSend) return;
    _chatCtrl.clear();
    setState(() {
      _canSend = false;
      _msgs.add(_ChatMsg(sender: 'You', text: text, isOwn: true));
    });
    _scrollToBottom();

    try {
      await DebateService.sendChat(widget.sessionId, text);
      _startCooldown(10);
    } on ApiException catch (e) {
      if (e.statusCode == 429) {
        _startCooldown(10);
        _showSnack('Please wait before sending another message');
      } else {
        if (mounted) setState(() => _canSend = true);
      }
    } catch (_) {
      if (mounted) setState(() => _canSend = true);
    }
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) setState(() => _canSend = true);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─── Participants ─────────────────────────────────────────────────────────────

  void _startPartsTimer() {
    _partsTimer?.cancel();
    _partsTimer = Timer.periodic(const Duration(seconds: 20),
        (_) { if (mounted) _fetchParticipants(); });
  }

  Future<void> _fetchParticipants() async {
    try {
      final list = await DebateService.getParticipants(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _parts.clear();
        for (final p in list) {
          final part = _Part.fromJson(p as Map<String, dynamic>);
          _parts[part.userId] = part;
        }
      });
    } catch (_) {}
  }

  // ─── Teardown ────────────────────────────────────────────────────────────────

  Future<void> _teardown() async {
    await _wsSub?.cancel();
    try { _ws?.sink.close(); } catch (_) {}
    _webCtrl = null;
    final vc = _vc;
    _vc = null;
    vc?.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: const Color(0xFF0D0F1F),
        body: SafeArea(
          child: _loading
              ? const _LoadingBody()
              : _errorMsg != null
                  ? _ErrorBody(
                      message: _errorMsg!,
                      onBack: () => Navigator.pop(context),
                      onRetry: _join,
                    )
                  : _buildActive(),
        ),
      ),
    );
  }

  Widget _buildActive() {
    return Column(
      children: [
        _TopBar(
          title: widget.title,
          topic: widget.topic,
          viewerCount: _viewerCount,
          myTeam: _myTeam,
          onLeave: () => Navigator.pop(context),
        ),
        Expanded(
          child: Column(
            children: [
              _buildMediaArea(),
              Expanded(child: _buildSpeakerStrip()),
            ],
          ),
        ),
        _buildChatSection(),
      ],
    );
  }

  Widget _buildMediaArea() {
    if (_mode == 'rtc') {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: _webCtrl != null
            ? WebViewWidget(controller: _webCtrl!)
            : _buildVideoConnecting(),
      );
    }
    if (_mode == 'cdn') {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: _vcReady && _vc != null
            ? VideoPlayer(_vc!)
            : _vcError
                ? _buildVideoError()
                : _buildVideoConnecting(),
      );
    }
    // chat_only or unknown mode
    return _buildChatOnlyBanner();
  }

  Widget _buildChatOnlyBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F3A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2D4A)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFF5C542), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Live audio/video isn\'t available in this version yet — follow the debate via chat.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoConnecting() {
    return Container(
      color: const Color(0xFF0D0F1F),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                color: Color(0xFFF5C542), strokeWidth: 2),
          ),
          const SizedBox(height: 12),
          Text(
            _hlsRetries > 0
                ? 'Connecting… (attempt ${_hlsRetries + 1})'
                : 'Connecting to live stream…',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          if (_hlsRetries >= 2)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Stream may still be starting up',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoError() {
    return Container(
      color: const Color(0xFF0D0F1F),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.signal_wifi_off_rounded,
              color: Colors.white38, size: 32),
          const SizedBox(height: 10),
          const Text('Stream unavailable',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _playbackUrl != null
                ? () {
                    setState(() {
                      _vcReady = false;
                      _vcError = false;
                      _hlsRetries = 0;
                    });
                    _initHls(_playbackUrl!);
                  }
                : null,
            child: const Text('Retry',
                style: TextStyle(color: Color(0xFFF5C542))),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeakerStrip() {
    final speakers =
        _parts.values.where((p) => p.role == 'speaker').toList();
    if (speakers.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            'SPEAKERS',
            style: TextStyle(
              color: Color(0xFFF5C542),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: speakers.length,
            itemBuilder: (_, i) => _SpeakerChip(part: speakers[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildChatSection() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF131524),
        border: Border(top: BorderSide(color: Color(0xFF2A2D4A), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: _msgs.isEmpty
                ? const SizedBox.shrink()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) => _ChatBubble(msg: _msgs[i]),
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              12, 6, 12,
              MediaQuery.of(context).padding.bottom + 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2141),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF2A2D4A)),
                    ),
                    child: TextField(
                      controller: _chatCtrl,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Say something…',
                        hintStyle:
                            TextStyle(color: Colors.white38, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _canSend ? _sendMessage : null,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _canSend
                          ? const Color(0xFFF5C542)
                          : const Color(0xFF2A2D4A),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.send_rounded,
                      color: _canSend
                          ? const Color(0xFF272942)
                          : Colors.white30,
                      size: 16,
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

// ─── Private widgets ───────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final String? topic;
  final int viewerCount;
  final String? myTeam;
  final VoidCallback onLeave;

  const _TopBar({
    required this.title,
    this.topic,
    required this.viewerCount,
    this.myTeam,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1F3A),
        border:
            Border(bottom: BorderSide(color: Color(0xFF2A2D4A), width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onLeave,
            child:
                const Icon(Icons.close, color: Colors.white70, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (topic != null && topic!.isNotEmpty)
                  Text(
                    topic!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (myTeam != null) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: myTeam == 'A'
                    ? const Color(0xFF3A6BC7)
                    : const Color(0xFFC7523A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Team $myTeam',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (viewerCount > 0) ...[
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.remove_red_eye_outlined,
                    color: Colors.white38, size: 13),
                const SizedBox(width: 3),
                Text(
                  viewerCount.toString(),
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                color: Color(0xFFF5C542), strokeWidth: 2),
          ),
          SizedBox(height: 12),
          Text('Joining debate…',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onBack;
  final VoidCallback onRetry;

  const _ErrorBody(
      {required this.message,
      required this.onBack,
      required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: onBack,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFF272942),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Go Back',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onRetry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5C542),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Try Again',
                        style: TextStyle(
                            color: Color(0xFF272942),
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeakerChip extends StatelessWidget {
  final _Part part;
  const _SpeakerChip({required this.part});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(right: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F3A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: part.isSpeaking
              ? const Color(0xFFF5C542)
              : const Color(0xFF2A2D4A),
          width: part.isSpeaking ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (part.team != null) ...[
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: part.team == 'A'
                    ? const Color(0xFF3A6BC7)
                    : const Color(0xFFC7523A),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  part.team!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            part.displayName,
            style: TextStyle(
              color: part.isSpeaking
                  ? const Color(0xFFF5C542)
                  : Colors.white70,
              fontSize: 12,
              fontWeight: part.isSpeaking
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
          if (part.isSpeaking) ...[
            const SizedBox(width: 5),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFFF5C542),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _ChatMsg msg;
  const _ChatBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '${msg.sender}  ',
              style: TextStyle(
                color: msg.isOwn
                    ? const Color(0xFFF5C542)
                    : const Color(0xFF8890D0),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: msg.text,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
