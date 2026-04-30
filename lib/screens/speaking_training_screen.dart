import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/api_constants.dart';
import '../services/api_service.dart';
import '../services/plus_service.dart';
import '../services/token_service.dart';
import '../services/user_service.dart';
import '../widgets/free_minutes_dialog.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

String _resolveImageUrl(String path) {
  if (path.startsWith('http')) return path;
  final uri = Uri.parse(apiBaseUrl);
  return '${uri.scheme}://${uri.host}$path';
}

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
  int? _secondsLeft;
  int? _sessionSecondsLeft; // persists across matches so the budget doesn't reset on Next
  Timer? _countdownTimer;
  bool _isPlus = false;

  String _localName = '';
  String? _remoteName;
  String? _remoteGender;
  String? _remoteProfileImage;
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
  bool _offerInFlight = false;
  // Reentrancy guard: _connectWaitingRoom is triggered from multiple paths
  // (Next button, peer-left, pc state change). Without this, concurrent calls
  // race on _matchWs and throw "Stream has already been listened to".
  bool _reconnecting = false;
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
    WakelockPlus.enable();

    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    try {
      final result = await ApiService.get('/student/profile/');
      final data = result['data'] as Map<String, dynamic>?;
      final first = data?['first_name'] as String? ?? '';
      final last = data?['last_name'] as String? ?? '';
      _localName = '$first $last'.trim();
    } catch (e) {
    }
    if (UserService.isExemptFromPlus) {
      _isPlus = true;
    } else {
      try {
        final status = await PlusService.getMyStatus();
        _isPlus = status.isActive;
      } catch (e) {
      }
    }
    if (!mounted) return;
    setState(() {});

    await _startLocalMedia();
    if (!mounted) return;

    _connectWaitingRoom();
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    final camOk = statuses[Permission.camera]?.isGranted ?? false;
    final micOk = statuses[Permission.microphone]?.isGranted ?? false;
    if (!camOk || !micOk) {
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
      await Helper.setSpeakerphoneOn(true);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _showError('Camera/microphone unavailable.');
    }
  }

  // ─── Matchmaking (waiting-room WS) ──────────────────────────────────────

  Future<void> _connectWaitingRoom() async {
    if (_reconnecting) {
      return;
    }
    _reconnecting = true;
    try {
      await _teardownSession();

      if (!mounted) return;
      setState(() {
        _isConnected = false;
        _remoteName = null;
        _remoteGender = null;
        _remoteProfileImage = null;
        _remoteCameraOn = true;
        _sessionId = null;
        _secondsLeft = null;
      });

      final token = await TokenService.getAccessToken();
      if (token == null) {
        return;
      }
      if (!mounted) return;

      final apiUri = Uri.parse(apiBaseUrl);
      final wsScheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
      final partnerGender = switch (_genderFilter) {
        GenderFilter.female => 'Female',
        GenderFilter.male => 'Male',
        GenderFilter.all => 'Any',
      };
      final url =
          '$wsScheme://${apiUri.host}/ws/waiting-room/?token=$token&partner_gender=$partnerGender';

      final ws = WebSocketChannel.connect(Uri.parse(url));
      _matchWs = ws;
      await ws.ready;
      _matchSub = ws.stream.listen(
        _handleMatchMessage,
        onError: (e) {
          if (mounted) _showError('Connection error. Please try again.');
        },
        onDone: () {
          if (mounted && ws.closeCode == 4001) {
            _showError('Authentication failed. Please re-login.');
          }
        },
      );
    } catch (e) {
      if (mounted) _showError('Could not connect to server.');
    } finally {
      _reconnecting = false;
    }
  }

  void _startCountdown(int serverSeconds) {
    _countdownTimer?.cancel();
    if (!mounted) return;
    // Use whichever is smaller: remaining session budget or new token TTL.
    // This prevents the timer from resetting to the full server value on each
    // new match when the user still has unused time from the previous call.
    final prior = _sessionSecondsLeft;
    final effective = (prior != null && prior > 0 && prior < serverSeconds)
        ? prior
        : serverSeconds;
    setState(() {
      _secondsLeft = effective;
      _sessionSecondsLeft = effective;
    });
    if (effective <= 0) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        final s = _secondsLeft;
        if (s == null || s <= 0) {
          t.cancel();
          _secondsLeft = 0;
          _sessionSecondsLeft = 0;
        } else {
          _secondsLeft = s - 1;
          _sessionSecondsLeft = s - 1;
        }
      });
    });
  }

  Future<void> _handleMatchMessage(dynamic raw) async {
    final data = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = data['type'] as String?;

    switch (type) {
      case 'match_found':
        final roomId = (data['room_id'] ?? data['webrtc_room'] ?? data['webrtc_room_id'] ?? data['room'])?.toString();
        final partner = data['partner_name'] as String?;
        final partnerGender = data['partner_gender'] as String?;
        final partnerProfileImage = data['partner_profile_image'] as String?;
        final sessionId = data['session_id'] as int?;
        final inlineSignalingUrl = data['signaling_url'] as String?;
        final inlineSignalingToken = data['signaling_token'] as String?;
        final inlineIce = data['ice_servers'];
        if (roomId == null) {
          _showError('Invalid match payload.');
          return;
        }
        setState(() {
          _remoteName = partner ?? 'Partner';
          _remoteGender = partnerGender;
          _remoteProfileImage = partnerProfileImage;
          _sessionId = sessionId;
          _offerInFlight = false;
        });
        if (inlineSignalingUrl != null && inlineSignalingToken != null) {
          if (inlineIce is List) {
            _iceServers = inlineIce
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }

          // Always hit REST to get limit even when inline credentials are present.
          try {
            final sigRes = await ApiService.post('/video/signaling/', {'room_id': roomId});
            final limit = sigRes['limit'] as int?;
            dev.log('PLUS → [inline REST] limit=$limit isPlus=$_isPlus');
            if (!_isPlus && limit != null && limit <= 0) {
              dev.log('PLUS → [inline REST] firing popup (limit exhausted)');
              if (mounted) {
                await showFreeMinutesDialog(context, dismissible: false);
                if (mounted) Navigator.of(context).pop();
              }
              return;
            }
            if (!_isPlus && limit != null && limit > 0) _startCountdown(limit);
          } catch (e) {
          }
          dev.log('SIGNALING URL → $inlineSignalingUrl');
          dev.log('SIGNALING TOKEN → $inlineSignalingToken');
          await _createPeerConnection();
          await _connectSignalingWs(inlineSignalingUrl, inlineSignalingToken);
        } else {
          _startSignaling(roomId);
        }
        break;

      case 'error':
        final detail = data['detail'] as String? ?? 'Matchmaking failed';
        if (mounted) _showError('Matchmaking error. Please try again.');
        break;

      default:
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

      final limit = res['limit'] as int?;
      dev.log('PLUS → [_startSignaling REST] limit=$limit isPlus=$_isPlus');
      if (!_isPlus && limit != null && limit <= 0) {
        dev.log('PLUS → [_startSignaling REST] firing popup (limit exhausted)');
        if (mounted) {
          await showFreeMinutesDialog(context, dismissible: false);
          if (mounted) Navigator.of(context).pop();
        }
        return;
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
      for (var i = 0; i < _iceServers.length; i++) {
        final srv = _iceServers[i];
        final urls = srv['urls'] ?? srv['url'];
        final hasCred = srv['username'] != null || srv['credential'] != null;
      }

      if (!_isPlus && limit != null && limit > 0) _startCountdown(limit);

      dev.log('SIGNALING URL → $signalingUrl');
      dev.log('SIGNALING TOKEN → $signalingToken');
      await _createPeerConnection();
      await _connectSignalingWs(signalingUrl, signalingToken);
    } catch (e) {
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
      // Candidate types: host (local), srflx (STUN reflexive), relay (TURN),
      // prflx (peer reflexive). Seeing only `host` means STUN is not reachable.
      final candStr = candidate.candidate!;
      final typ = RegExp(r'typ (\w+)').firstMatch(candStr)?.group(1) ?? '?';
      _sendSig({
        'type': 'ice',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    pc.onIceGatheringState = (state) {
    };

    pc.onIceConnectionState = (state) {
    };

    pc.onTrack = (event) {
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
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (!_isStopping && !_reconnecting && mounted) {
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
      _sigSub = _sigWs!.stream.listen(
        _handleSigMessage,
      );
      _sendSig({'type': 'auth', 'token': token});
    } catch (e) {
      if (mounted) _showError('Signaling connection failed.');
    }
  }

  void _sendSig(Map<String, dynamic> msg) {
    try {
      _sigWs?.sink.add(jsonEncode(msg));
    } catch (e) {
    }
  }

  Future<void> _handleSigMessage(dynamic raw) async {
    dev.log('WS ← SERVER RAW: $raw');
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (e) {
      return;
    }
    final type = msg['type'] as String?;

    switch (type) {
      case 'auth_ok':
        break;

      case 'joined':
        // Server confirms we're in the room. If it includes a non-empty peers
        // list, someone was here before us — we are the answerer and should
        // wait for their offer. Otherwise, we wait for peer-joined.
        final peersOnJoin = msg['peers'];
        final peerProfiles = msg['peer_profiles'];
        if (peersOnJoin is List && peersOnJoin.isNotEmpty) {
        } else {
        }
        if (peerProfiles is List && peerProfiles.isNotEmpty) {
          final profile = peerProfiles.first as Map<String, dynamic>?;
          if (profile != null && mounted) {
            final firstName = profile['first_name'] as String? ?? '';
            final lastName = profile['last_name'] as String? ?? '';
            final name = '$firstName $lastName'.trim();
            setState(() {
              if (name.isNotEmpty) _remoteName = name;
              _remoteGender = profile['gender'] as String?;
              _remoteProfileImage = profile['profile_image'] as String?;
            });
          }
        }
        break;

      case 'peers':
        // Explicit list of existing peers — we joined second, wait for offer.
        final peerList = msg['peers'];
        break;

      case 'peer-joined':
      case 'peer_joined':
        // Another peer arrived after us — we drive the offer.
        final peerFirstName = msg['first_name'] as String? ?? '';
        final peerLastName = msg['last_name'] as String? ?? '';
        final peerName = '$peerFirstName $peerLastName'.trim();
        if (mounted) {
          setState(() {
            if (peerName.isNotEmpty) _remoteName = peerName;
            _remoteGender = msg['gender'] as String?;
            _remoteProfileImage = msg['profile_image'] as String?;
          });
        }
        if (_pc != null && !_offerInFlight) {
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
        if (!_isStopping && mounted) _connectWaitingRoom();
        break;

      case 'limit finished':
        if (!_isStopping && mounted && !_isPlus) {
          _isStopping = true;
          _sessionSecondsLeft = null;
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
          if (mounted) {
            dev.log('PLUS → [limit finished WS] firing popup');
            await showFreeMinutesDialog(context);
            if (mounted) Navigator.of(context).pop();
          }
        }
        break;

      case 'error':
        break;
    }
  }

  Future<void> _makeOffer() async {
    final pc = _pc;
    if (pc == null || _offerInFlight) return;
    _offerInFlight = true;
    try {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _sendSig({'type': 'offer', 'sdp': offer.sdp, 'sdpType': offer.type});
    } catch (e) {
      _offerInFlight = false;
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
    } catch (e) {
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
    } catch (e) {
    }
  }

  Future<void> _handleIce(Map<String, dynamic> msg) async {
    final pc = _pc;
    if (pc == null) return;
    final c = (msg['candidate'] ?? msg) as Map?;
    if (c == null) return;
    final candStr = c['candidate'] as String?;
    final typ = candStr == null
        ? '?'
        : RegExp(r'typ (\w+)').firstMatch(candStr)?.group(1) ?? '?';
    final candidate = RTCIceCandidate(
      candStr,
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
    }
  }

  Future<void> _flushPendingCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    for (final c in _pendingRemoteCandidates) {
      try {
        await pc.addCandidate(c);
      } catch (e) {
      }
    }
    _pendingRemoteCandidates.clear();
  }

  Future<void> _teardownSession() async {
    await _sigSub?.cancel();
    _sigSub = null;
    try { _sigWs?.sink.add(jsonEncode({'type': 'leave'})); } catch (_) {}
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
    _countdownTimer?.cancel();
    _countdownTimer = null;
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
    _isStopping = true;
    _sessionSecondsLeft = null;
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
    if (sessionId != null) {
      try {
        await ApiService.post('/skip/', {'session_id': sessionId});
      } catch (e) {
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
          Navigator.pop(context);
          if (g == _genderFilter) return;
          setState(() => _genderFilter = g);
          _connectWaitingRoom();
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
    }
    _connectWaitingRoom();
  }

  @override
  void dispose() {
    _isStopping = true;
    _countdownTimer?.cancel();
    WakelockPlus.disable();
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
                        profileImage: _remoteProfileImage,
                        onReport: _showReportDialog,
                      )
                    : _RemoteCameraOffView(
                        name: _remoteName ?? 'Partner',
                        gender: _remoteGender,
                        profileImage: _remoteProfileImage,
                        onReport: _showReportDialog,
                      )
                : const _SearchingView(),
          ),

          _LinkaBanner(secondsLeft: _secondsLeft),

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
  final String? profileImage;
  final VoidCallback onReport;

  const _RemoteVideoArea({
    required this.renderer,
    required this.name,
    this.gender,
    this.profileImage,
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
                child: ClipOval(
                  child: profileImage != null
                      ? Image.network(
                          _resolveImageUrl(profileImage!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.person, size: 20, color: Colors.white),
                        )
                      : const Icon(Icons.person, size: 20, color: Colors.white),
                ),
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
  final String? profileImage;
  final VoidCallback onReport;

  const _RemoteCameraOffView({
    required this.name,
    this.gender,
    this.profileImage,
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
                  child: ClipOval(
                    child: profileImage != null
                        ? Image.network(
                            _resolveImageUrl(profileImage!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                Icon(Icons.person, size: 50, color: Colors.grey.shade300),
                          )
                        : Icon(Icons.person, size: 50, color: Colors.grey.shade300),
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
  final int? secondsLeft;
  const _LinkaBanner({this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: const Color(0xFF272942),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SvgPicture.asset(
            'assets/images/branding/white-logo.svg',
            height: 26,
          ),
          if (secondsLeft != null)
            Positioned(
              right: 16,
              child: _CountdownBadge(seconds: secondsLeft!),
            ),
        ],
      ),
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  final int seconds;
  const _CountdownBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    final label = '$mins:${secs.toString().padLeft(2, '0')}';
    final color = seconds > 60
        ? const Color(0xFF27AE60)
        : seconds > 30
            ? const Color(0xFFF5C542)
            : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
