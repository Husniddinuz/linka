import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:zego_express_engine/zego_express_engine.dart';
import '../services/api_constants.dart';
import '../services/api_service.dart';
import '../services/debate_service.dart';
import '../services/token_service.dart';
import '../widgets/cached_avatar.dart';

// ─── Screen ────────────────────────────────────────────────────────────────────

class DebateScreen extends StatefulWidget {
  final int sessionId;
  final String title;
  final String status;
  final String? topic;

  const DebateScreen({
    super.key,
    required this.sessionId,
    required this.title,
    required this.status,
    this.topic,
  });

  @override
  State<DebateScreen> createState() => _DebateScreenState();
}

class _DebateScreenState extends State<DebateScreen> {
  DebateJoinData? _joinData;
  List<DebateParticipant> _participants = [];
  String? _topic;
  bool _loading = true;
  String? _error;

  // Speaking
  bool _isMySpeaking = false;
  bool _micLoading = false;
  Set<int> _speakingUserIds = {};

  // Viewer count + chat
  int _viewerCount = 0;
  final List<_ChatMessage> _messages = [];
  final _chatController = TextEditingController();
  final _scrollController = ScrollController();
  bool _chatVisible = false;
  bool _sendingMessage = false;
  final Set<String> _pendingOutbound = {};

  // WebSocket
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSub;

  // Polling for speaking state
  Timer? _pollTimer;

  // ZEGO (RTC mode)
  bool _zegoInitialized = false;

  // CDN audio stream
  VideoPlayerController? _audioController;

  @override
  void initState() {
    super.initState();
    _topic = widget.topic;
    _join();
  }

  // ─── Join + setup ─────────────────────────────────────────────────────────

  Future<void> _join() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await DebateService.join(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _joinData = data;
        _participants = data.participants;
        _speakingUserIds = data.participants
            .where((p) => p.isSpeaking)
            .map((p) => p.userId)
            .toSet();
        _loading = false;
      });

      if (data.mode == 'rtc') {
        _initZego(data);
      } else if (data.playbackUrl != null && data.playbackUrl!.isNotEmpty) {
        _initAudio(data.playbackUrl!);
      }

      _connectWs();
      _startPolling();
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _initZego(DebateJoinData data) async {
    if (data.zegoAppId == null || data.zegoToken == null || data.zegoUserId == null) return;
    try {
      await ZegoExpressEngine.createEngineWithProfile(
        ZegoEngineProfile(data.zegoAppId!, ZegoScenario.HighQualityChatroom),
      );
      final config = ZegoRoomConfig.defaultConfig();
      config.token = data.zegoToken!;
      config.isUserStatusNotify = true;
      await ZegoExpressEngine.instance.loginRoom(
        data.roomId,
        ZegoUser(data.zegoUserId!, 'u${data.zegoUserId}'),
        config: config,
      );
      if (data.canSpeak) {
        await ZegoExpressEngine.instance.muteMicrophone(true); // start muted
        await ZegoExpressEngine.instance.startPublishingStream(data.zegoUserId!);
      }
      _zegoInitialized = true;
    } catch (_) {
      // Continue without ZEGO audio if init fails
    }
  }

  Future<void> _initAudio(String url) async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      if (!mounted) { controller.dispose(); return; }
      setState(() => _audioController = controller);
      controller.setVolume(1);
      controller.play();
    } catch (_) {}
  }

  Future<void> _connectWs() async {
    final token = await TokenService.getAccessToken();
    if (token == null || !mounted) return;
    final apiUri = Uri.parse(apiBaseUrl);
    final scheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
    final url = '$scheme://${apiUri.host}/ws/live/session/${widget.sessionId}/?token=$token';
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(url));
      await _wsChannel!.ready;
      _wsSub = _wsChannel!.stream.listen(
        _onWsMessage,
        onError: (_) {},
        onDone: () {},
        cancelOnError: false,
      );
    } catch (_) {}
  }

  void _onWsMessage(dynamic raw) {
    try {
      final data = json.decode(raw as String) as Map<String, dynamic>;
      final type = data['type'] as String? ?? '';

      if (type == 'chat_message') {
        final msgObj = data['message'] as Map<String, dynamic>?;
        if (msgObj == null) return;
        final text = msgObj['text'] as String? ?? '';
        if (text.isEmpty) return;
        if (_pendingOutbound.remove(text)) return;
        final user = msgObj['user'] as Map<String, dynamic>?;
        final sender = user?['display_name'] as String? ?? 'User';
        final imgRaw = user?['image'] as String? ?? '';
        final apiUri = Uri.parse(apiBaseUrl);
        final avatarUrl = imgRaw.isEmpty
            ? null
            : imgRaw.startsWith('http')
                ? imgRaw
                : '${apiUri.scheme}://${apiUri.host}$imgRaw';
        if (!mounted) return;
        setState(() => _messages.add(_ChatMessage(
          sender: sender, text: text, avatarUrl: avatarUrl,
        )));
        _scrollToBottom();
      } else if (type == 'viewer_count') {
        final count = data['count'] as int?;
        if (count != null && mounted) setState(() => _viewerCount = count);
      }
    } catch (_) {}
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollParticipants());
  }

  Future<void> _pollParticipants() async {
    if (!mounted) return;
    try {
      final list = await DebateService.fetchParticipants(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _participants = list;
        _speakingUserIds = list
            .where((p) => p.isSpeaking)
            .map((p) => p.userId)
            .toSet();
      });
    } catch (_) {}
  }

  // ─── Mic toggle ───────────────────────────────────────────────────────────

  Future<void> _toggleMic() async {
    if (_joinData?.canSpeak != true || _micLoading) return;
    setState(() => _micLoading = true);
    final newSpeaking = !_isMySpeaking;
    try {
      await DebateService.setSpeaking(widget.sessionId, newSpeaking);
      if (_zegoInitialized) {
        await ZegoExpressEngine.instance.muteMicrophone(!newSpeaking);
      }
      if (mounted) setState(() => _isMySpeaking = newSpeaking);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _micLoading = false);
    }
  }

  // ─── Chat ─────────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _sendingMessage || _wsChannel == null) return;
    _chatController.clear();
    FocusScope.of(context).unfocus();
    _pendingOutbound.add(text);
    setState(() {
      _sendingMessage = true;
      _messages.add(_ChatMessage(sender: 'You', text: text, isOwn: true));
    });
    _scrollToBottom();
    try {
      _wsChannel!.sink.add(json.encode({'type': 'chat_message', 'text': text}));
    } catch (_) {
      _pendingOutbound.remove(text);
    } finally {
      if (mounted) setState(() => _sendingMessage = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _wsSub?.cancel();
    _wsChannel?.sink.close();
    _chatController.dispose();
    _scrollController.dispose();
    _audioController?.dispose();
    if (_zegoInitialized) {
      ZegoExpressEngine.instance.stopPublishingStream();
      ZegoExpressEngine.instance.logoutRoom();
      ZegoExpressEngine.destroyEngine();
    }
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1E35),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFF5C542), strokeWidth: 2,
                ),
              )
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFAAAAAA), size: 48),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _join,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5C542),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text('Try again', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF272942))),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Text('Go back', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _TopBar(
          title: widget.title,
          status: _joinData!.status,
          viewerCount: _viewerCount,
          onClose: () => Navigator.of(context).pop(),
        ),
        if (_topic != null && _topic!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              '"$_topic"',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: const Color(0xFFF5C542).withValues(alpha: 0.85),
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
        Expanded(
          child: _ParticipantGrid(
            participants: _participants,
            speakingUserIds: _speakingUserIds,
          ),
        ),
        _BottomBar(
          canSpeak: _joinData!.canSpeak,
          isSpeaking: _isMySpeaking,
          micLoading: _micLoading,
          chatVisible: _chatVisible,
          onMicTap: _toggleMic,
          onChatTap: () => setState(() => _chatVisible = !_chatVisible),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          height: _chatVisible ? 260.0 : 0.0,
          child: _ChatPanel(
            messages: _messages,
            controller: _chatController,
            scrollController: _scrollController,
            sending: _sendingMessage,
            onSend: _sendMessage,
          ),
        ),
      ],
    );
  }
}

// ─── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final String status;
  final int viewerCount;
  final VoidCallback onClose;

  const _TopBar({
    required this.title,
    required this.status,
    required this.viewerCount,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final (String badgeLabel, Color badgeColor) = switch (status) {
      'live' => ('LIVE', const Color(0xFFE53935)),
      'ended' => ('ENDED', const Color(0xFF6C6C6C)),
      _ => ('UPCOMING', const Color(0xFFF5C542)),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: badgeColor,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'DEBATE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF5C542),
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              Icon(Icons.remove_red_eye_outlined, size: 13, color: Colors.white.withValues(alpha: 0.4)),
              const SizedBox(width: 4),
              Text(
                '$viewerCount',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Participant grid ──────────────────────────────────────────────────────────

class _ParticipantGrid extends StatelessWidget {
  final List<DebateParticipant> participants;
  final Set<int> speakingUserIds;

  const _ParticipantGrid({
    required this.participants,
    required this.speakingUserIds,
  });

  @override
  Widget build(BuildContext context) {
    final teamA = participants.where((p) => p.team == 'A').toList();
    final teamB = participants.where((p) => p.team == 'B').toList();
    final hasTeams = teamA.isNotEmpty || teamB.isNotEmpty;

    // Participants without team assignment
    final unassigned = hasTeams
        ? <DebateParticipant>[]
        : participants;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: hasTeams
            ? [
                _TeamRow(label: 'TEAM A', members: teamA, slots: 5, speakingUserIds: speakingUserIds),
                const SizedBox(height: 40),
                _TeamRow(label: 'TEAM B', members: teamB, slots: 5, speakingUserIds: speakingUserIds),
              ]
            : [
                _TeamRow(label: '', members: unassigned.take(5).toList(), slots: 5, speakingUserIds: speakingUserIds),
                const SizedBox(height: 40),
                _TeamRow(label: '', members: unassigned.skip(5).take(5).toList(), slots: 5, speakingUserIds: speakingUserIds),
              ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  final String label;
  final List<DebateParticipant> members;
  final int slots;
  final Set<int> speakingUserIds;

  const _TeamRow({
    required this.label,
    required this.members,
    required this.slots,
    required this.speakingUserIds,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14, left: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.35),
                letterSpacing: 1.2,
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(slots, (i) {
            final p = i < members.length ? members[i] : null;
            return _ParticipantSlot(
              participant: p,
              isSpeaking: p != null && speakingUserIds.contains(p.userId),
            );
          }),
        ),
      ],
    );
  }
}

class _ParticipantSlot extends StatelessWidget {
  final DebateParticipant? participant;
  final bool isSpeaking;

  const _ParticipantSlot({this.participant, this.isSpeaking = false});

  @override
  Widget build(BuildContext context) {
    if (participant == null) {
      return SizedBox(
        width: 58,
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.person_outline_rounded,
                color: Colors.white.withValues(alpha: 0.15),
                size: 22,
              ),
            ),
            const SizedBox(height: 7),
            Container(
              width: 32,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: 58,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSpeaking
                    ? const Color(0xFF27AE60)
                    : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: isSpeaking
                  ? [
                      BoxShadow(
                        color: const Color(0xFF27AE60).withValues(alpha: 0.45),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(2.5),
              child: CachedAvatar(
                imageUrl: participant!.profileImage,
                size: 49,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            participant!.firstName.isNotEmpty
                ? participant!.firstName
                : participant!.displayName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom bar ────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final bool canSpeak;
  final bool isSpeaking;
  final bool micLoading;
  final bool chatVisible;
  final VoidCallback onMicTap;
  final VoidCallback onChatTap;

  const _BottomBar({
    required this.canSpeak,
    required this.isSpeaking,
    required this.micLoading,
    required this.chatVisible,
    required this.onMicTap,
    required this.onChatTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          if (canSpeak) ...[
            GestureDetector(
              onTap: onMicTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSpeaking
                      ? const Color(0xFF27AE60)
                      : Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: micLoading
                    ? const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2,
                          ),
                        ),
                      )
                    : Icon(
                        isSpeaking
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: GestureDetector(
              onTap: onChatTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: chatVisible
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(22),
                  border: chatVisible
                      ? Border.all(color: const Color(0xFFF5C542).withValues(alpha: 0.4))
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: chatVisible
                          ? const Color(0xFFF5C542)
                          : Colors.white.withValues(alpha: 0.4),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Chat',
                      style: TextStyle(
                        color: chatVisible
                            ? Colors.white.withValues(alpha: 0.9)
                            : Colors.white.withValues(alpha: 0.4),
                        fontSize: 14,
                        fontWeight: chatVisible ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chat panel ────────────────────────────────────────────────────────────────

class _ChatPanel extends StatelessWidget {
  final List<_ChatMessage> messages;
  final TextEditingController controller;
  final ScrollController scrollController;
  final bool sending;
  final VoidCallback onSend;

  const _ChatPanel({
    required this.messages,
    required this.controller,
    required this.scrollController,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161828),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _ChatBubble(message: messages[i]),
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: controller,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onSend,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF5C542),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: Color(0xFF272942),
                      size: 17,
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

// ─── Chat message model + bubble ───────────────────────────────────────────────

class _ChatMessage {
  final String sender;
  final String text;
  final bool isOwn;
  final String? avatarUrl;

  const _ChatMessage({
    required this.sender,
    required this.text,
    this.isOwn = false,
    this.avatarUrl,
  });
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.isOwn) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.68,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5C542),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(
                  message.text,
                  style: const TextStyle(
                    color: Color(0xFF272942),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CachedAvatar(imageUrl: message.avatarUrl, size: 28),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.sender,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 3),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.68,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.09),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Text(
                      message.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.35,
                      ),
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
