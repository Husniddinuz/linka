import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/api_constants.dart';
import '../services/api_service.dart';
import '../services/token_service.dart';

// ─── Gender filter enum ─────────────────────────────────────────────────────

enum GenderFilter { all, female, male }

// ─── Screen ─────────────────────────────────────────────────────────────────

class SpeakingTrainingScreen extends StatefulWidget {
  const SpeakingTrainingScreen({super.key});

  @override
  State<SpeakingTrainingScreen> createState() => _SpeakingTrainingScreenState();
}

class _SpeakingTrainingScreenState extends State<SpeakingTrainingScreen> {
  // ── UI state ──
  bool _isCameraOn = true;
  bool _isConnected = false;
  bool _isStopping = false;
  GenderFilter _genderFilter = GenderFilter.all;

  String _localName = '';
  String? _remoteName;
  final String? _remoteGender = null;
  bool _remoteCameraOn = true;

  // ── Media ──
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  MediaStream? _localStream;

  // ── Matchmaking WS (existing waiting-room) ──
  WebSocketChannel? _matchWs;
  StreamSubscription? _matchSub;

  // ── Signaling WS (Node relay) ──
  WebSocketChannel? _sigWs;
  StreamSubscription? _sigSub;

  // ── WebRTC ──
  RTCPeerConnection? _pc;
  bool _isCaller = false;
  int? _sessionId;
  List<Map<String, dynamic>> _iceServers = const [
    {'urls': 'stun:stun.l.google.com:19302'},
  ];
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _remoteDescSet = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    dev.log('INIT → starting');

    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    try {
      final result = await ApiService.get('/student/profile/');
      final data = result['data'] as Map<String, dynamic>?;
      final first = data?['first_name'] as String? ?? '';
      final last = data?['last_name'] as String? ?? '';
      _localName = '$first $last'.trim();
    } catch (e) {
      dev.log('INIT → profile failed: $e');
    }
    if (!mounted) return;
    setState(() {});

    await _startLocalMedia();
    if (!mounted) return;

    _connectWaitingRoom();
    dev.log('INIT → done');
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    final camOk = statuses[Permission.camera]?.isGranted ?? false;
    final micOk = statuses[Permission.microphone]?.isGranted ?? false;
    if (!camOk || !micOk) {
      dev.log('PERM → camera=$camOk, mic=$micOk');
      if (mounted) _showError('Camera and microphone permissions are required.');
      return false;
    }
    return true;
  }

  Future<void> _startLocalMedia() async {
    if (!await _ensurePermissions()) return;
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 640},
          'height': {'ideal': 480},
        },
      });
      _localStream = stream;
      _localRenderer.srcObject = stream;
      if (mounted) setState(() {});
      dev.log('MEDIA → local stream ready');
    } catch (e) {
      dev.log('MEDIA → getUserMedia failed: $e');
      if (mounted) _showError('Camera/microphone unavailable.');
    }
  }

  // ─── Matchmaking (waiting-room WS) ──────────────────────────────────────

  Future<void> _connectWaitingRoom() async {
    dev.log('══════════════════════════════════════');
    dev.log('MATCH → connecting waiting room');
    await _teardownSession();

    setState(() {
      _isConnected = false;
      _remoteName = null;
      _remoteCameraOn = true;
      _sessionId = null;
    });

    final token = await TokenService.getAccessToken();
    if (token == null) {
      dev.log('MATCH → no access token');
      return;
    }
    if (!mounted) return;

    final apiUri = Uri.parse(apiBaseUrl);
    final wsScheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
    final url = '$wsScheme://${apiUri.host}/ws/waiting-room/?token=$token';

    try {
      _matchWs = WebSocketChannel.connect(Uri.parse(url));
      await _matchWs!.ready;
      dev.log('MATCH → connected');
      _matchSub = _matchWs!.stream.listen(
        _handleMatchMessage,
        onError: (e) {
          dev.log('MATCH → error: $e');
          if (mounted) _showError('Connection error. Please try again.');
        },
        onDone: () {
          dev.log('MATCH → closed (code=${_matchWs?.closeCode})');
          if (mounted && _matchWs?.closeCode == 4001) {
            _showError('Authentication failed. Please re-login.');
          }
        },
      );
    } catch (e) {
      dev.log('MATCH → connect failed: $e');
      if (mounted) _showError('Could not connect to server.');
    }
  }

  void _handleMatchMessage(dynamic raw) {
    dev.log('MATCH ← $raw');
    final data = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = data['type'] as String?;

    switch (type) {
      case 'match_found':
        final roomId = (data['room_id'] ?? data['room'])?.toString();
        final isCaller = (data['is_caller'] as bool?) ??
            (data['role']?.toString() == 'caller');
        final partner = data['partner_name'] as String?;
        final sessionId = data['session_id'] as int?;
        if (roomId == null) {
          dev.log('MATCH ← missing room_id in match_found');
          _showError('Invalid match payload.');
          return;
        }
        setState(() {
          _isCaller = isCaller;
          _remoteName = partner ?? 'Partner';
          _sessionId = sessionId;
        });
        _startSignaling(roomId);
        break;

      case 'error':
        final detail = data['detail'] as String? ?? 'Matchmaking failed';
        dev.log('MATCH ← error: $detail');
        if (mounted) _showError('Matchmaking error. Please try again.');
        break;

      default:
        dev.log('MATCH ← unknown type: $type');
    }
  }

  // ─── Signaling + WebRTC ─────────────────────────────────────────────────

  Future<void> _startSignaling(String roomId) async {
    try {
      final res = await ApiService.post('/video/signaling/', {'room_id': roomId});
      final success = res['success'] as bool? ?? false;
      if (!success) {
        throw ApiException(res['message']?.toString() ?? 'Signaling request failed');
      }
      final signalingUrl = res['signaling_url'] as String;
      final signalingToken = res['signaling_token'] as String;
      final ice = res['ice_servers'];
      if (ice is List) {
        _iceServers = ice
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      dev.log('SIG → signaling_url=$signalingUrl, ice=${_iceServers.length} server(s)');

      await _createPeerConnection();
      await _connectSignalingWs(signalingUrl, signalingToken);
    } catch (e) {
      dev.log('SIG → failed: $e');
      if (mounted) _showError('Failed to start call. Retrying...');
      _connectWaitingRoom();
    }
  }

  Future<void> _createPeerConnection() async {
    final config = {
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    };
    final pc = await createPeerConnection(config);

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _sendSig({
        'type': 'ice',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    pc.onTrack = (event) {
      dev.log('PC → onTrack kind=${event.track.kind}, streams=${event.streams.length}');
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams.first;
        if (mounted) {
          setState(() {
            _isConnected = true;
            _remoteCameraOn = true;
          });
        }
      }
    };

    pc.onConnectionState = (state) {
      dev.log('PC → connectionState=$state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (!_isStopping && mounted) {
          dev.log('PC → peer lost, returning to waiting room');
          _connectWaitingRoom();
        }
      }
    };

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
    }

    _pc = pc;
  }

  Future<void> _connectSignalingWs(String url, String token) async {
    try {
      _sigWs = WebSocketChannel.connect(Uri.parse(url));
      await _sigWs!.ready;
      dev.log('SIG WS → connected');
      _sigSub = _sigWs!.stream.listen(
        _handleSigMessage,
        onError: (e) => dev.log('SIG WS → error: $e'),
        onDone: () => dev.log('SIG WS → closed (code=${_sigWs?.closeCode})'),
      );
      _sendSig({'type': 'auth', 'token': token});
    } catch (e) {
      dev.log('SIG WS → connect failed: $e');
      if (mounted) _showError('Signaling connection failed.');
    }
  }

  void _sendSig(Map<String, dynamic> msg) {
    try {
      _sigWs?.sink.add(jsonEncode(msg));
    } catch (e) {
      dev.log('SIG WS → send failed: $e');
    }
  }

  Future<void> _handleSigMessage(dynamic raw) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (e) {
      dev.log('SIG WS ← bad json: $raw');
      return;
    }
    final type = msg['type'] as String?;
    dev.log('SIG WS ← $type');

    switch (type) {
      case 'joined':
      case 'auth_ok':
        // waiting for peer
        break;

      case 'peers':
      case 'peer-joined':
        // If we are the caller, start the offer once peer is present
        if (_isCaller && _pc != null) {
          await _makeOffer();
        }
        break;

      case 'offer':
        await _handleOffer(msg);
        break;

      case 'answer':
        await _handleAnswer(msg);
        break;

      case 'ice':
      case 'candidate':
        await _handleIce(msg);
        break;

      case 'peer-left':
        dev.log('SIG WS ← peer-left, re-matching');
        if (!_isStopping && mounted) _connectWaitingRoom();
        break;

      case 'error':
        dev.log('SIG WS ← error: ${msg['detail']}');
        break;
    }
  }

  Future<void> _makeOffer() async {
    final pc = _pc;
    if (pc == null) return;
    try {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _sendSig({'type': 'offer', 'sdp': offer.sdp, 'sdpType': offer.type});
      dev.log('PC → offer sent');
    } catch (e) {
      dev.log('PC → makeOffer failed: $e');
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> msg) async {
    final pc = _pc;
    if (pc == null) return;
    final sdp = msg['sdp'] as String?;
    final sdpType = (msg['sdpType'] ?? msg['sdp_type'] ?? 'offer') as String;
    if (sdp == null) return;
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, sdpType));
      _remoteDescSet = true;
      await _flushPendingCandidates();
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _sendSig({'type': 'answer', 'sdp': answer.sdp, 'sdpType': answer.type});
      dev.log('PC → answer sent');
    } catch (e) {
      dev.log('PC → handleOffer failed: $e');
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> msg) async {
    final pc = _pc;
    if (pc == null) return;
    final sdp = msg['sdp'] as String?;
    final sdpType = (msg['sdpType'] ?? msg['sdp_type'] ?? 'answer') as String;
    if (sdp == null) return;
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, sdpType));
      _remoteDescSet = true;
      await _flushPendingCandidates();
      dev.log('PC → remote answer set');
    } catch (e) {
      dev.log('PC → handleAnswer failed: $e');
    }
  }

  Future<void> _handleIce(Map<String, dynamic> msg) async {
    final pc = _pc;
    if (pc == null) return;
    final c = (msg['candidate'] ?? msg) as Map?;
    if (c == null) return;
    final candidate = RTCIceCandidate(
      c['candidate'] as String?,
      c['sdpMid'] as String?,
      c['sdpMLineIndex'] as int?,
    );
    if (!_remoteDescSet) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }
    try {
      await pc.addCandidate(candidate);
    } catch (e) {
      dev.log('PC → addCandidate failed: $e');
    }
  }

  Future<void> _flushPendingCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    for (final c in _pendingRemoteCandidates) {
      try {
        await pc.addCandidate(c);
      } catch (e) {
        dev.log('PC → flush candidate failed: $e');
      }
    }
    _pendingRemoteCandidates.clear();
  }

  Future<void> _teardownSession() async {
    await _sigSub?.cancel();
    _sigSub = null;
    try { _sigWs?.sink.close(); } catch (_) {}
    _sigWs = null;

    await _matchSub?.cancel();
    _matchSub = null;
    try { _matchWs?.sink.close(); } catch (_) {}
    _matchWs = null;

    final pc = _pc;
    _pc = null;
    if (pc != null) {
      try { await pc.close(); } catch (_) {}
    }
    _remoteRenderer.srcObject = null;
    _remoteDescSet = false;
    _pendingRemoteCandidates.clear();
  }

  // ─── Controls ───────────────────────────────────────────────────────────

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _toggleCamera() async {
    final stream = _localStream;
    if (stream == null) return;
    final newState = !_isCameraOn;
    setState(() => _isCameraOn = newState);
    for (final track in stream.getVideoTracks()) {
      track.enabled = newState;
    }
  }

  Future<void> _onStop() async {
    if (_isStopping) return;
    dev.log('ACTION → stop');
    _isStopping = true;
    await _teardownSession();
    final stream = _localStream;
    _localStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        try { await track.stop(); } catch (_) {}
      }
      try { await stream.dispose(); } catch (_) {}
    }
    _localRenderer.srcObject = null;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _onNext() async {
    final sessionId = _sessionId;
    dev.log('ACTION → next (session_id=$sessionId)');
    if (sessionId != null) {
      try {
        await ApiService.post('/skip/', {'session_id': sessionId});
      } catch (e) {
        dev.log('ACTION → skip failed: $e');
      }
    }
    _connectWaitingRoom();
  }

  void _showGenderFilter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GenderFilterSheet(
        selected: _genderFilter,
        onSelected: (g) {
          setState(() => _genderFilter = g);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showReportDialog() {
    String selectedReason = 'harassment';
    final reasons = ['harassment', 'spam', 'inappropriate', 'other'];

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Why are you reporting this user?'),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: selectedReason,
                onChanged: (v) => setDialogState(() => selectedReason = v!),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: reasons.map((r) => RadioListTile<String>(
                    title: Text(r[0].toUpperCase() + r.substring(1)),
                    value: r,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )).toList(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _submitReport(selectedReason);
              },
              child: const Text('Report', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport(String reason) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    try {
      await ApiService.post('/report/', {
        'session_id': sessionId,
        'reason': reason,
      });
    } catch (e) {
      dev.log('ACTION → report failed: $e');
    }
    _connectWaitingRoom();
  }

  @override
  void dispose() {
    dev.log('DISPOSE → start');
    _isStopping = true;
    // Run async teardown fire-and-forget so dispose() returns immediately.
    () async {
      await _teardownSession();
      final stream = _localStream;
      _localStream = null;
      if (stream != null) {
        for (final track in stream.getTracks()) {
          try { await track.stop(); } catch (_) {}
        }
        try { await stream.dispose(); } catch (_) {}
      }
      try { await _localRenderer.dispose(); } catch (_) {}
      try { await _remoteRenderer.dispose(); } catch (_) {}
    }();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
      backgroundColor: const Color(0xFF13152A),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            height: MediaQuery.of(context).padding.top,
          ),
          Expanded(
            child: _isConnected
                ? _remoteCameraOn
                    ? _RemoteVideoArea(
                        renderer: _remoteRenderer,
                        name: _remoteName ?? 'Partner',
                        gender: _remoteGender,
                        onReport: _showReportDialog,
                      )
                    : _RemoteCameraOffView(
                        name: _remoteName ?? 'Partner',
                        gender: _remoteGender,
                        onReport: _showReportDialog,
                      )
                : const _SearchingView(),
          ),

          const _LinkaBanner(),

          Expanded(
            child: _isCameraOn
                ? _LocalVideoArea(renderer: _localRenderer)
                : _LocalPreviewView(
                    name: _localName.isNotEmpty ? _localName : 'You',
                    isCameraOn: _isCameraOn,
                  ),
          ),

          _BottomControls(
            isCameraOn: _isCameraOn,
            isConnected: _isConnected,
            onToggleCamera: _toggleCamera,
            onGenderFilter: _showGenderFilter,
            onStop: _onStop,
            onNext: _onNext,
          ),
        ],
      ),
    ),
    );
  }
}

// ─── Searching view (TV static noise + loader) ─────────────────────────────

class _SearchingView extends StatefulWidget {
  const _SearchingView();

  @override
  State<_SearchingView> createState() => _SearchingViewState();
}

class _SearchingViewState extends State<_SearchingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0A0A),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _StaticNoisePainter(
                  seed: (_controller.value * 1000).toInt(),
                ),
              );
            },
          ),
          const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaticNoisePainter extends CustomPainter {
  final int seed;
  _StaticNoisePainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    int rng = seed;
    const step = 6.0;
    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        rng = ((rng * 1103515245 + 12345) & 0x7fffffff);
        final grey = (rng % 40);
        paint.color = Color.fromARGB(80, grey, grey, grey);
        canvas.drawRect(Rect.fromLTWH(x, y, step, step), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_StaticNoisePainter old) => old.seed != seed;
}

// ─── Remote video area ──────────────────────────────────────────────────────

class _RemoteVideoArea extends StatelessWidget {
  final RTCVideoRenderer renderer;
  final String name;
  final String? gender;
  final VoidCallback onReport;

  const _RemoteVideoArea({
    required this.renderer,
    required this.name,
    this.gender,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RTCVideoView(
          renderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),

        Positioned(
          top: 8,
          left: 12,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.shade300,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.person, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      shadows: [
                        Shadow(blurRadius: 4, color: Colors.black54),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        gender == 'Female' ? Icons.female : Icons.male,
                        size: 14,
                        color: gender == 'Female'
                            ? Colors.pinkAccent
                            : const Color(0xFF6C6CFF),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        gender ?? 'Male',
                        style: TextStyle(
                          color: gender == 'Female'
                              ? Colors.pinkAccent
                              : const Color(0xFF6C6CFF),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        Positioned(
          top: 8,
          right: 12,
          child: GestureDetector(
            onTap: onReport,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Text(
                'Report',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Remote camera off view ─────────────────────────────────────────────────

class _RemoteCameraOffView extends StatelessWidget {
  final String name;
  final String? gender;
  final VoidCallback onReport;

  const _RemoteCameraOffView({
    required this.name,
    this.gender,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF13152A),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'assets/images/branding/meeting-umbrella.svg',
                  width: 140,
                ),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey.shade400,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: Icon(
                    Icons.person,
                    size: 50,
                    color: Colors.grey.shade300,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 12,
            child: GestureDetector(
              onTap: onReport,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Text(
                  'Report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Local video area (in-call) ─────────────────────────────────────────────

class _LocalVideoArea extends StatelessWidget {
  final RTCVideoRenderer renderer;

  const _LocalVideoArea({required this.renderer});

  @override
  Widget build(BuildContext context) {
    return RTCVideoView(
      renderer,
      mirror: true,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}

// ─── Local preview (searching state) ────────────────────────────────────────

class _LocalPreviewView extends StatelessWidget {
  final String name;
  final bool isCameraOn;

  const _LocalPreviewView({
    required this.name,
    required this.isCameraOn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isCameraOn ? const Color(0xFF272942) : const Color(0xFF13152A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/images/branding/meeting-umbrella.svg',
              width: 140,
            ),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade400,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Icon(
                Icons.person,
                size: 50,
                color: Colors.grey.shade300,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Linka banner bar ───────────────────────────────────────────────────────

class _LinkaBanner extends StatelessWidget {
  const _LinkaBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: const Color(0xFF272942),
      child: Center(
        child: SvgPicture.asset(
          'assets/images/branding/white-logo.svg',
          height: 26,
        ),
      ),
    );
  }
}

// ─── Bottom controls ────────────────────────────────────────────────────────

class _BottomControls extends StatelessWidget {
  final bool isCameraOn;
  final bool isConnected;
  final VoidCallback onToggleCamera;
  final VoidCallback onGenderFilter;
  final VoidCallback onStop;
  final VoidCallback onNext;

  const _BottomControls({
    required this.isCameraOn,
    required this.isConnected,
    required this.onToggleCamera,
    required this.onGenderFilter,
    required this.onStop,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggleCamera,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF6F6F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: SvgPicture.asset(
                  isCameraOn
                      ? 'assets/images/buttons/camera-on.svg'
                      : 'assets/images/buttons/camera-off.svg',
                  width: 22,
                  height: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          GestureDetector(
            onTap: onGenderFilter,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF6F6F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/images/buttons/gender-selection.svg',
                  width: 22,
                  height: 22,
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: GestureDetector(
              onTap: onStop,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F6F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Stop',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: GestureDetector(
              onTap: onNext,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF272942),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Next',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.chevron_right, color: Colors.white, size: 20),
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

// ─── Gender filter bottom sheet ─────────────────────────────────────────────

class _GenderFilterSheet extends StatelessWidget {
  final GenderFilter selected;
  final ValueChanged<GenderFilter> onSelected;

  const _GenderFilterSheet({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GenderOption(
              icon: Icons.transgender,
              iconColor: const Color(0xFF6C6CFF),
              label: 'All gender',
              isSelected: selected == GenderFilter.all,
              onTap: () => onSelected(GenderFilter.all),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _GenderOption(
              icon: Icons.female,
              iconColor: Colors.pinkAccent,
              label: 'Female',
              isSelected: selected == GenderFilter.female,
              onTap: () => onSelected(GenderFilter.female),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _GenderOption(
              icon: Icons.male,
              iconColor: const Color(0xFF6C6CFF),
              label: 'Male',
              isSelected: selected == GenderFilter.male,
              onTap: () => onSelected(GenderFilter.male),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenderOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _GenderOption({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 26),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Color(0xFF272942),
        ),
      ),
      trailing: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6C6CFF)
                : const Color(0xFFCCCCCC),
            width: 2,
          ),
        ),
        child: isSelected
            ? Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF6C6CFF),
                  ),
                ),
              )
            : null,
      ),
      onTap: onTap,
    );
  }
}
