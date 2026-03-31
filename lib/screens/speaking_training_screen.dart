import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:daily_flutter/daily_flutter.dart';
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
  CallClient? _callClient;
  bool _isCameraOn = true;
  bool _isConnected = false;
  bool _isStopping = false;
  bool _hasJoined = false;
  GenderFilter _genderFilter = GenderFilter.all;

  // Local user info
  String _localName = '';

  // Remote participant info
  String? _remoteName;
  String? _remoteGender;
  bool _remoteCameraOn = true;

  // Video controllers
  final _localVideoController = VideoViewController();
  final _remoteVideoController = VideoViewController();

  StreamSubscription<Event>? _eventSubscription;

  // WebSocket matchmaking
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  int? _sessionId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    dev.log('INIT → starting');

    // Load user's own name
    try {
      final result = await ApiService.get('/student/profile/');
      final data = result['data'] as Map<String, dynamic>?;
      final first = data?['first_name'] as String? ?? '';
      final last = data?['last_name'] as String? ?? '';
      _localName = '$first $last'.trim();
      dev.log('INIT → profile: $_localName');
    } catch (e) {
      dev.log('INIT → profile failed: $e');
    }

    if (!mounted) return;
    setState(() {});

    // Create Daily client for local camera preview
    await _createCallClient();
    if (!mounted) return;

    // Start local camera preview (without joining a room)
    if (_callClient != null) {
      dev.log('INIT → enabling local camera preview');
      try {
        await _callClient!.updateInputs(
          inputs: InputSettingsUpdate.set(
            camera: CameraInputSettingsUpdate.set(
              isEnabled: BoolUpdate.set(true),
            ),
            microphone: MicrophoneInputSettingsUpdate.set(
              isEnabled: BoolUpdate.set(false),
            ),
          ),
        );
        final local = _callClient!.participants.local;
        _localVideoController.setTrack(local.media?.camera.track);
        dev.log('INIT → local camera preview active');
      } catch (e) {
        dev.log('INIT → camera preview failed: $e');
      }
    }

    // Connect to waiting room for matchmaking
    _connectWaitingRoom();
    dev.log('INIT → done');
  }

  Future<void> _createCallClient() async {
    if (_callClient != null) return;
    dev.log('DAILY → creating CallClient...');
    try {
      final client = await CallClient.create();
      if (!mounted || _isStopping) {
        client.dispose();
        return;
      }
      _callClient = client;
      _eventSubscription = client.events.listen(_handleEvent);
      dev.log('DAILY → CallClient ready');
    } catch (e) {
      dev.log('DAILY → CallClient.create() FAILED: $e');
    }
  }

  // ─── WebSocket waiting room ───────────────────────────────────────────────

  Future<void> _connectWaitingRoom() async {
    dev.log('══════════════════════════════════════');
    dev.log('WS → _connectWaitingRoom() called');

    // Clean up previous connection
    if (_wsChannel != null) {
      dev.log('WS → closing previous connection');
    }
    await _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _wsChannel = null;

    setState(() {
      _isConnected = false;
      _remoteName = null;
      _remoteGender = null;
      _sessionId = null;
    });
    _remoteVideoController.setTrack(null);

    final token = await TokenService.getAccessToken();
    if (token == null) {
      dev.log('WS → ERROR: no access token available');
      return;
    }
    if (!mounted) {
      dev.log('WS → widget not mounted, aborting');
      return;
    }

    // Derive WS URL from API base URL
    final apiUri = Uri.parse(apiBaseUrl);
    final wsScheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
    final wsUrl = '$wsScheme://${apiUri.host}/ws/waiting-room/?token=$token';

    dev.log('WS → connecting to $wsUrl');

    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      dev.log('WS → waiting for ready...');
      await _wsChannel!.ready;
      dev.log('WS → connected successfully, listening for messages');

      _wsSubscription = _wsChannel!.stream.listen(
        _handleWsMessage,
        onError: (error) {
          dev.log('WS → stream error: $error');
          if (mounted) _showWsError('Connection error. Please try again.');
        },
        onDone: () {
          dev.log('WS → stream done — closeCode: ${_wsChannel?.closeCode}, closeReason: ${_wsChannel?.closeReason}');
          if (mounted && _wsChannel?.closeCode == 4001) {
            _showWsError('Authentication failed. Please re-login.');
          }
        },
      );
    } catch (e) {
      dev.log('WS → connect failed: $e');
      if (mounted) _showWsError('Could not connect to server.');
    }
    dev.log('══════════════════════════════════════');
  }

  void _handleWsMessage(dynamic raw) {
    dev.log('══════════════════════════════════════');
    dev.log('WS ← raw message: $raw');
    final data = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = data['type'] as String?;
    dev.log('WS ← parsed type: $type');
    dev.log('WS ← full data: $data');

    switch (type) {
      case 'match_found':
        final roomUrl = data['room_url'] as String;
        final dailyToken = data['token'] as String;
        final partnerName = data['partner_name'] as String?;
        final sessionId = data['session_id'] as int?;

        dev.log('WS ← match_found:');
        dev.log('WS ←   session_id: $sessionId');
        dev.log('WS ←   room_url: $roomUrl');
        dev.log('WS ←   partner_name: $partnerName');
        dev.log('WS ←   token length: ${dailyToken.length}');

        setState(() {
          _sessionId = sessionId;
          _remoteName = partnerName ?? 'Partner';
        });

        // Create Daily client on first match, then join
        _createCallClient().then((_) {
          if (!mounted || _isStopping) return;
          dev.log('WS → joining Daily room...');
          _joinRoom(roomUrl, token: dailyToken);
        });
        break;

      case 'error':
        final detail = data['detail'] as String? ?? 'Matchmaking failed';
        final status = data['status'];
        dev.log('WS ← error: detail=$detail, status=$status');
        if (mounted) _showWsError('Matchmaking error. Please try again.');
        break;

      default:
        dev.log('WS ← unknown message type: $type');
    }
    dev.log('══════════════════════════════════════');
  }

  void _showWsError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  // ─── Daily.co events ──────────────────────────────────────────────────────

  void _handleEvent(Event event) {
    if (!mounted || _isStopping) return;
    event.whenOrNull(
      participantJoined: (participant) {
        dev.log('DAILY → participantJoined: isLocal=${participant.info.isLocal}, username=${participant.info.username}');
        if (!participant.info.isLocal) {
          setState(() {
            _isConnected = true;
            _remoteName ??= participant.info.username ?? 'Partner';
          });
          _remoteVideoController.setTrack(participant.media?.camera.track);
          dev.log('DAILY → remote participant connected: $_remoteName');
        }
      },
      participantUpdated: (participant) {
        dev.log('DAILY → participantUpdated: isLocal=${participant.info.isLocal}, cameraMuted=${participant.isCameraMuted}');
        if (!participant.info.isLocal) {
          setState(() {
            _remoteCameraOn = !participant.isCameraMuted;
          });
          _remoteVideoController.setTrack(participant.media?.camera.track);
        } else {
          _localVideoController.setTrack(participant.media?.camera.track);
        }
      },
      participantLeft: (participant) {
        dev.log('DAILY → participantLeft: isLocal=${participant.info.isLocal}, username=${participant.info.username}');
        if (!participant.info.isLocal && !_isStopping) {
          dev.log('DAILY → partner left, returning to waiting room');
          _callClient?.leave();
          _connectWaitingRoom();
        }
      },
      callStateUpdated: (stateData) {
        stateData.whenOrNull(
          joined: (_) {
            dev.log('DAILY → callState: joined');
            final local = _callClient?.participants.local;
            _localVideoController.setTrack(local?.media?.camera.track);
          },
          left: () {
            dev.log('DAILY → callState: left');
            _localVideoController.setTrack(null);
            _remoteVideoController.setTrack(null);
          },
        );
      },
    );
  }

  Future<void> _joinRoom(String url, {String? token}) async {
    if (_callClient == null) {
      dev.log('DAILY → _joinRoom: callClient is null, aborting');
      return;
    }
    dev.log('DAILY → joining room: $url (token length: ${token?.length ?? 0})');
    try {
      final joinData = await _callClient!.join(url: Uri.parse(url), token: token);
      _hasJoined = true;
      dev.log('DAILY → join succeeded: $joinData');
    } catch (e, st) {
      dev.log('DAILY → join FAILED: $e');
      dev.log('DAILY → stacktrace: $st');
      if (mounted) _showWsError('Failed to join call. Retrying...');
      _connectWaitingRoom();
    }
  }

  Future<void> _toggleCamera() async {
    if (_callClient == null) return;
    final newState = !_isCameraOn;
    setState(() => _isCameraOn = newState);
    await _callClient!.updateInputs(
      inputs: InputSettingsUpdate.set(
        camera: CameraInputSettingsUpdate.set(
          isEnabled: BoolUpdate.set(newState),
        ),
      ),
    );
  }

  void _onStop() {
    dev.log('ACTION → _onStop (hasJoined=$_hasJoined)');
    _isStopping = true;
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _wsSubscription?.cancel();
    _wsSubscription = null;
    try { _wsChannel?.sink.close(); } catch (_) {}
    _wsChannel = null;
    // Pop immediately
    Navigator.of(context).pop();
    // Cleanup Daily in background
    final client = _callClient;
    final joined = _hasJoined;
    _callClient = null;
    if (client != null) {
      Future(() {
        if (joined) { try { client.leave(); } catch (_) {} }
        Future.delayed(const Duration(milliseconds: 500), () {
          try { client.dispose(); } catch (_) {}
        });
      });
    }
  }

  Future<void> _onNext() async {
    final sessionId = _sessionId;
    dev.log('ACTION → _onNext: session_id=$sessionId');
    _callClient?.leave();

    if (sessionId != null) {
      dev.log('ACTION → calling POST /skip/ with session_id=$sessionId');
      try {
        final result = await ApiService.post('/skip/', {'session_id': sessionId});
        dev.log('ACTION → skip response: $result');
      } catch (e) {
        dev.log('ACTION → skip API error: $e');
      }
    } else {
      dev.log('ACTION → no session_id, skipping skip API call');
    }

    dev.log('ACTION → reconnecting to waiting room');
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
    dev.log('ACTION → _submitReport: reason=$reason, session_id=$sessionId');
    if (sessionId == null) {
      dev.log('ACTION → no session_id, aborting report');
      return;
    }

    _callClient?.leave();

    dev.log('ACTION → calling POST /report/ with session_id=$sessionId, reason=$reason');
    try {
      final result = await ApiService.post('/report/', {
        'session_id': sessionId,
        'reason': reason,
      });
      dev.log('ACTION → report response: $result');
    } catch (e) {
      dev.log('ACTION → report API error: $e');
    }

    dev.log('ACTION → reconnecting to waiting room');
    _connectWaitingRoom();
  }

  @override
  void dispose() {
    dev.log('DISPOSE → start (hasJoined=$_hasJoined)');
    _isStopping = true;
    _eventSubscription?.cancel();
    _wsSubscription?.cancel();
    try { _wsChannel?.sink.close(); } catch (_) {}
    try { _localVideoController.dispose(); } catch (_) {}
    try { _remoteVideoController.dispose(); } catch (_) {}
    final client = _callClient;
    final joined = _hasJoined;
    _callClient = null;
    if (client != null) {
      Future(() {
        if (joined) { try { client.leave(); } catch (_) {} }
        Future.delayed(const Duration(milliseconds: 500), () {
          try { client.dispose(); } catch (_) {}
          dev.log('DISPOSE → Daily client disposed');
        });
      });
    }
    dev.log('DISPOSE → done');
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
          // ── Status bar background ──
          Container(
            color: Colors.white,
            height: MediaQuery.of(context).padding.top,
          ),
          // ── Top video area (remote or searching) ──
          Expanded(
            child: _isConnected
                ? _remoteCameraOn
                    ? _RemoteVideoArea(
                        controller: _remoteVideoController,
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

          // ── Linka bar ──
          const _LinkaBanner(),

          // ── Bottom video area (local) ──
          Expanded(
            child: _isCameraOn
                ? _LocalVideoArea(controller: _localVideoController)
                : _LocalPreviewView(
                    name: _localName.isNotEmpty ? _localName : 'You',
                    isCameraOn: _isCameraOn,
                  ),
          ),

          // ── Bottom controls ──
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
          // Animated static noise
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
          // Loader on top
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
    // Use a simple pseudo-random based on seed
    int rng = seed;
    const step = 6.0;
    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        rng = ((rng * 1103515245 + 12345) & 0x7fffffff);
        final grey = (rng % 40); // dark greys 0-39
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
  final VideoViewController controller;
  final String name;
  final String? gender;
  final VoidCallback onReport;

  const _RemoteVideoArea({
    required this.controller,
    required this.name,
    this.gender,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        VideoView(controller: controller, fit: VideoViewFit.cover),

        // Name + gender badge (top-left)
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

        // Report button (top-right)
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
          // Report button (top-right)
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
  final VideoViewController controller;

  const _LocalVideoArea({required this.controller});

  @override
  Widget build(BuildContext context) {
    return VideoView(controller: controller, fit: VideoViewFit.cover);
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
            // Umbrella icon
            SvgPicture.asset(
              'assets/images/branding/meeting-umbrella.svg',
              width: 140,
            ),
            // Avatar placeholder
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
          // Camera toggle
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

          // Gender filter
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

          // Stop button
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

          // Next button
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
