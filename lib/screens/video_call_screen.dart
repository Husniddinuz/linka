import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/call_kit_service.dart';
import '../services/call_service.dart';

/// A one-to-one video call with the other person in a private thread.
///
/// The media is peer-to-peer WebRTC; the only server in the path is the Node
/// signaling relay that carries the offer, the answer and the ICE candidates
/// between the two phones. Whoever is already in the room when the other
/// arrives makes the offer — normally the caller, who joins the moment the
/// call is placed and waits there while the other phone rings.
///
/// For an outgoing call the screen owns the ringing phase too: it counts
/// down the ring window, polls the server so a decline shows up as one
/// rather than as silence, and cancels the call if nobody answers. For an
/// incoming call the accept has already happened on the native screen by the
/// time this is pushed, so it goes straight to connecting.
class VideoCallScreen extends StatefulWidget {
  final CallSession session;

  /// True when this phone answered; false when it placed the call.
  final bool incoming;

  const VideoCallScreen({
    super.key,
    required this.session,
    required this.incoming,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

enum _Phase { ringing, connecting, connected, ended }

class _VideoCallScreenState extends State<VideoCallScreen>
    with WidgetsBindingObserver {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  RTCPeerConnection? _pc;
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  StreamSubscription<String>? _nativeEndSub;

  _Phase _phase = _Phase.ringing;
  String _endReason = '';
  bool _micOn = true;
  bool _cameraOn = true;
  bool _remoteCameraOn = true;
  bool _frontCamera = true;
  bool _offerInFlight = false;
  bool _remoteDescSet = false;
  bool _leaving = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  Timer? _ringTimer;
  Timer? _pollTimer;
  Timer? _clockTimer;
  int _ringSecondsLeft = 45;
  int _elapsedSeconds = 0;

  CallInfo get _call => widget.session.call;
  CallPerson get _other => _call.other;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _phase = widget.incoming ? _Phase.connecting : _Phase.ringing;
    _ringSecondsLeft = _call.ringSeconds;
    CallKitService.activeCallUuid = _call.roomId;
    _nativeEndSub = CallKitService.endedFromNative.stream.listen((uuid) {
      if (uuid == _call.roomId) _hangUp(reason: 'Call ended', tellNative: false);
    });
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nativeEndSub?.cancel();
    _ringTimer?.cancel();
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    if (CallKitService.activeCallUuid == _call.roomId) {
      CallKitService.activeCallUuid = null;
    }
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  // ─── Setup ─────────────────────────────────────────────────────────────────

  Future<void> _start() async {
    WakelockPlus.enable();
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    if (!await _ensurePermissions()) {
      await _hangUp(reason: 'Camera and microphone are required');
      return;
    }
    await _startLocalMedia();
    if (!mounted || _leaving) return;

    final signaling = widget.session.signaling;
    if (signaling == null) {
      await _hangUp(reason: 'This call is no longer available');
      return;
    }
    await _createPeerConnection(signaling.iceServers);
    await _connectSignaling(signaling);

    if (!widget.incoming) {
      CallKitService.showOutgoing(_call);
      _ringTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _ringSecondsLeft -= 1);
        if (_ringSecondsLeft <= 0) {
          _hangUp(reason: 'No answer');
        }
      });
      // A decline reaches the caller only through the API: the other phone
      // never joins the room, so the relay has nothing to say about it.
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    }
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    return (statuses[Permission.camera]?.isGranted ?? false) &&
        (statuses[Permission.microphone]?.isGranted ?? false);
  }

  // The loudspeaker as the *default* route, not a one-shot override: iOS
  // falls back to the earpiece whenever the audio unit restarts otherwise.
  Future<void> _configureAudioRoute() async {
    try {
      await Helper.setAppleAudioConfiguration(
        AppleAudioConfiguration(
          appleAudioCategory: AppleAudioCategory.playAndRecord,
          appleAudioCategoryOptions: {
            AppleAudioCategoryOption.defaultToSpeaker,
            AppleAudioCategoryOption.allowBluetooth,
          },
          appleAudioMode: AppleAudioMode.videoChat,
        ),
      );
      await Helper.setAndroidAudioConfiguration(
        AndroidAudioConfiguration.communication,
      );
    } catch (_) {}
  }

  Future<void> _routeToSpeaker() async {
    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (_) {}
  }

  Future<void> _startLocalMedia() async {
    try {
      await _configureAudioRoute();
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
      await _routeToSpeaker();
      if (mounted) setState(() {});
    } catch (_) {
      await _hangUp(reason: 'Camera or microphone unavailable');
    }
  }

  Future<void> _createPeerConnection(List<Map<String, dynamic>> iceServers) async {
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _send({
        'type': 'ice',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    pc.onTrack = (event) {
      if (event.streams.isEmpty) return;
      _remoteRenderer.srcObject = event.streams.first;
      _routeToSpeaker();
      if (mounted) setState(() => _remoteCameraOn = true);
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _routeToSpeaker();
        _send({'type': 'camera', 'enabled': _cameraOn});
        _onConnected();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _hangUp(reason: 'Connection lost');
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

  void _onConnected() {
    if (!mounted || _phase == _Phase.connected || _phase == _Phase.ended) return;
    _ringTimer?.cancel();
    _pollTimer?.cancel();
    setState(() => _phase = _Phase.connected);
    CallKitService.markConnected(_call.roomId);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds += 1);
    });
  }

  // ─── Signaling ─────────────────────────────────────────────────────────────

  Future<void> _connectSignaling(CallSignaling signaling) async {
    try {
      _ws = WebSocketChannel.connect(Uri.parse(signaling.url));
      await _ws!.ready;
      _wsSub = _ws!.stream.listen(
        _onSignal,
        onDone: () {
          if (!_leaving && _phase != _Phase.ended) {
            _hangUp(reason: 'Connection lost');
          }
        },
        onError: (_) => _hangUp(reason: 'Connection lost'),
      );
      _send({'type': 'auth', 'token': signaling.token});
    } catch (_) {
      await _hangUp(reason: 'Could not reach the call server');
    }
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _ws?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  Future<void> _onSignal(dynamic raw) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'joined':
        // Someone already here means we are second: their offer is coming.
        final peers = msg['peers'];
        if (peers is List && peers.isNotEmpty && mounted && _phase == _Phase.ringing) {
          setState(() => _phase = _Phase.connecting);
        }
      case 'peer-joined':
      case 'peer_joined':
        if (mounted && _phase == _Phase.ringing) {
          _ringTimer?.cancel();
          _pollTimer?.cancel();
          setState(() => _phase = _Phase.connecting);
        }
        if (_pc != null && !_offerInFlight) await _makeOffer();
      case 'offer':
        await _handleOffer(msg);
      case 'answer':
        await _handleAnswer(msg);
      case 'ice':
      case 'candidate':
        await _handleIce(msg);
      case 'camera':
        final enabled = msg['enabled'] as bool? ?? true;
        if (mounted) setState(() => _remoteCameraOn = enabled);
      case 'peer-left':
        // The other side hung up. Tell the server too — whichever phone
        // reports first ends it, the second report is a no-op.
        await _hangUp(reason: 'Call ended');
      case 'error':
        final detail = msg['detail']?.toString() ?? '';
        if (detail == 'room_full') await _hangUp(reason: 'This call was answered elsewhere');
        if (detail == 'jwt_expired' || detail == 'auth_failed') {
          await _hangUp(reason: 'Could not join the call');
        }
    }
  }

  Future<void> _makeOffer() async {
    final pc = _pc;
    if (pc == null || _offerInFlight) return;
    _offerInFlight = true;
    try {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _send({'type': 'offer', 'sdp': offer.sdp, 'sdpType': offer.type});
    } catch (_) {
      _offerInFlight = false;
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> msg) async {
    final pc = _pc;
    final sdp = msg['sdp'] as String?;
    if (pc == null || sdp == null) return;
    final type = (msg['sdpType'] ?? msg['sdp_type'] ?? 'offer') as String;
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      _remoteDescSet = true;
      await _flushCandidates();
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _send({'type': 'answer', 'sdp': answer.sdp, 'sdpType': answer.type});
    } catch (_) {}
  }

  Future<void> _handleAnswer(Map<String, dynamic> msg) async {
    final pc = _pc;
    final sdp = msg['sdp'] as String?;
    if (pc == null || sdp == null) return;
    final type = (msg['sdpType'] ?? msg['sdp_type'] ?? 'answer') as String;
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      _remoteDescSet = true;
      await _flushCandidates();
    } catch (_) {}
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
      _pendingCandidates.add(candidate);
      return;
    }
    try {
      await pc.addCandidate(candidate);
    } catch (_) {}
  }

  Future<void> _flushCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    for (final c in _pendingCandidates) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
    _pendingCandidates.clear();
  }

  // ─── Ringing (outgoing) ────────────────────────────────────────────────────

  Future<void> _poll() async {
    if (_phase != _Phase.ringing || _leaving) return;
    try {
      final fresh = await CallService.fetch(_call.id);
      if (!mounted || _phase != _Phase.ringing) return;
      switch (fresh.call.status) {
        case 'declined':
          await _hangUp(reason: 'Declined', tellServer: false);
        case 'missed':
        case 'cancelled':
          await _hangUp(reason: 'No answer', tellServer: false);
        case 'ended':
          await _hangUp(reason: 'Call ended', tellServer: false);
      }
    } catch (_) {}
  }

  // ─── Controls ──────────────────────────────────────────────────────────────

  void _toggleMic() {
    final stream = _localStream;
    if (stream == null) return;
    setState(() => _micOn = !_micOn);
    for (final track in stream.getAudioTracks()) {
      track.enabled = _micOn;
    }
  }

  void _toggleCamera() {
    final stream = _localStream;
    if (stream == null) return;
    setState(() => _cameraOn = !_cameraOn);
    for (final track in stream.getVideoTracks()) {
      track.enabled = _cameraOn;
    }
    // A disabled track still flows as black frames, so the other phone is
    // told explicitly and shows the avatar instead of a dark rectangle.
    _send({'type': 'camera', 'enabled': _cameraOn});
  }

  Future<void> _switchCamera() async {
    final stream = _localStream;
    if (stream == null) return;
    final tracks = stream.getVideoTracks();
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
      setState(() => _frontCamera = !_frontCamera);
    } catch (_) {}
  }

  /// Ends the call from this side, for any reason, exactly once.
  ///
  /// [tellServer] is false when the server already knows (it told us the
  /// call was declined); [tellNative] is false when the native UI is what
  /// ended it and asking it to end again would be a no-op at best.
  Future<void> _hangUp({
    required String reason,
    bool tellServer = true,
    bool tellNative = true,
  }) async {
    if (_leaving) return;
    _leaving = true;
    _ringTimer?.cancel();
    _pollTimer?.cancel();
    _clockTimer?.cancel();

    if (mounted) {
      setState(() {
        _phase = _Phase.ended;
        _endReason = reason;
      });
    }
    if (tellServer) {
      // Fire and forget: the screen must close even if the network is gone.
      CallService.end(_call.id);
    }
    if (tellNative) CallKitService.endNative(_call.roomId);

    await _wsSub?.cancel();
    _wsSub = null;
    try {
      _ws?.sink.add(jsonEncode({'type': 'leave'}));
    } catch (_) {}
    try {
      _ws?.sink.close();
    } catch (_) {}
    _ws = null;

    final pc = _pc;
    _pc = null;
    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _remoteRenderer.srcObject = null;
    final stream = _localStream;
    _localStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await stream.dispose();
      } catch (_) {}
    }
    _localRenderer.srcObject = null;

    // Leave the reason on screen for a beat, then go.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.of(context).pop();
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  String get _statusLine {
    switch (_phase) {
      case _Phase.ringing:
        if (!widget.session.calleeReachable) {
          return 'Their phone is off — they will see a missed call';
        }
        return 'Ringing…';
      case _Phase.connecting:
        return 'Connecting…';
      case _Phase.connected:
        return _clock(_elapsedSeconds);
      case _Phase.ended:
        return _endReason;
    }
  }

  static String _clock(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(m >= 60 ? 2 : 1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final showRemote = _phase == _Phase.connected && _remoteCameraOn;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hangUp(reason: 'Call ended');
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: const Color(0xFF0E1020),
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Stage: the other person once connected; ourselves while
              // waiting, as a phone does.
              if (showRemote)
                RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else if (_phase == _Phase.connected)
                _AvatarStage(person: _other, dim: true)
              else if (_cameraOn && _localStream != null)
                RTCVideoView(
                  _localRenderer,
                  mirror: _frontCamera,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else
                const ColoredBox(color: Color(0xFF13152A)),

              if (_phase != _Phase.connected)
                Container(color: Colors.black.withValues(alpha: 0.45)),

              // Who and what.
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: _phase == _Phase.connected
                      ? _ConnectedHeader(name: _other.displayName, status: _statusLine)
                      : _WaitingHeader(person: _other, status: _statusLine),
                ),
              ),

              // Self view once the other person is on screen.
              if (_phase == _Phase.connected && _localStream != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 84,
                  right: 16,
                  child: _SelfView(
                    renderer: _localRenderer,
                    mirror: _frontCamera,
                    cameraOn: _cameraOn,
                  ),
                ),

              Align(
                alignment: Alignment.bottomCenter,
                child: _Controls(
                  micOn: _micOn,
                  cameraOn: _cameraOn,
                  enabled: _phase != _Phase.ended,
                  onMic: _toggleMic,
                  onCamera: _toggleCamera,
                  onFlip: _switchCamera,
                  onEnd: () => _hangUp(reason: 'Call ended'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Pieces ───────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final CallPerson person;
  final double size;
  const _Avatar({required this.person, required this.size});

  @override
  Widget build(BuildContext context) {
    final image = person.profileImage;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF252844),
        border: Border.all(color: Colors.white24, width: 2),
      ),
      child: ClipOval(
        child: image != null
            ? Image.network(
                image,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Center(
        child: Text(
          person.displayName.isNotEmpty
              ? person.displayName.trim()[0].toUpperCase()
              : '?',
          style: TextStyle(
            color: Colors.white70,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _AvatarStage extends StatelessWidget {
  final CallPerson person;
  final bool dim;
  const _AvatarStage({required this.person, this.dim = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF13152A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Avatar(person: person, size: 120),
            const SizedBox(height: 14),
            const Text(
              'Camera is off',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitingHeader extends StatelessWidget {
  final CallPerson person;
  final String status;
  const _WaitingHeader({required this.person, required this.status});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 48),
        _Avatar(person: person, size: 110),
        const SizedBox(height: 18),
        Text(
          person.displayName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'SF Pro',
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          status,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'SF Pro',
            color: Colors.white70,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _ConnectedHeader extends StatelessWidget {
  final String name;
  final String status;
  const _ConnectedHeader({required this.name, required this.status});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontFamily: 'SF Pro',
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              status,
              style: const TextStyle(
                fontFamily: 'SF Pro',
                color: Colors.white70,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelfView extends StatelessWidget {
  final RTCVideoRenderer renderer;
  final bool mirror;
  final bool cameraOn;
  const _SelfView({
    required this.renderer,
    required this.mirror,
    required this.cameraOn,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 104,
        height: 148,
        color: const Color(0xFF1C1F3A),
        child: cameraOn
            ? RTCVideoView(
                renderer,
                mirror: mirror,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : const Icon(Symbols.videocam_off_rounded, color: Colors.white38),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final bool micOn;
  final bool cameraOn;
  final bool enabled;
  final VoidCallback onMic;
  final VoidCallback onCamera;
  final VoidCallback onFlip;
  final VoidCallback onEnd;

  const _Controls({
    required this.micOn,
    required this.cameraOn,
    required this.enabled,
    required this.onMic,
    required this.onCamera,
    required this.onFlip,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, bottom + 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(
            icon: micOn ? Symbols.mic_rounded : Symbols.mic_off_rounded,
            active: micOn,
            onTap: enabled ? onMic : null,
          ),
          _RoundButton(
            icon: cameraOn ? Symbols.videocam_rounded : Symbols.videocam_off_rounded,
            active: cameraOn,
            onTap: enabled ? onCamera : null,
          ),
          _RoundButton(
            icon: Symbols.cameraswitch_rounded,
            active: true,
            onTap: enabled && cameraOn ? onFlip : null,
          ),
          _RoundButton(
            icon: Symbols.call_end_rounded,
            active: true,
            color: const Color(0xFFE53935),
            size: 64,
            onTap: enabled ? onEnd : null,
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color? color;
  final double size;
  final VoidCallback? onTap;

  const _RoundButton({
    required this.icon,
    required this.active,
    this.color,
    this.size = 56,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ??
        (active ? Colors.white.withValues(alpha: 0.18) : Colors.white);
    final fg = color != null
        ? Colors.white
        : (active ? Colors.white : const Color(0xFF13152A));
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
          child: Icon(icon, color: fg, size: size * 0.46),
        ),
      ),
    );
  }
}
