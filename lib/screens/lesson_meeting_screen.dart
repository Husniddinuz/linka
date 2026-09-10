import 'dart:async';
import 'dart:convert';
import 'package:daily_flutter/daily_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_colors.dart';

class LessonMeetingScreen extends StatefulWidget {
  final String roomUrl;
  final String token;
  final String tutorName;
  final String localName;

  const LessonMeetingScreen({
    super.key,
    required this.roomUrl,
    this.token = '',
    this.tutorName = 'Tutor',
    this.localName = 'You',
  });

  @override
  State<LessonMeetingScreen> createState() => _LessonMeetingScreenState();
}

class _LessonMeetingScreenState extends State<LessonMeetingScreen> {
  CallClient? _client;
  StreamSubscription? _eventSub;
  bool _permsReady = false;
  bool _joined = false;
  bool _cameraOn = true;
  bool _micOn = true;
  ParticipantId? _remoteId;
  final VideoViewController _localCtrl = VideoViewController();
  final VideoViewController _remoteCtrl = VideoViewController();
  final ValueNotifier<List<_ChatEntry>> _messages = ValueNotifier([]);
  final ValueNotifier<int> _unread = ValueNotifier(0);
  bool _remoteCamera = false;
  bool _remoteMic = true;
  bool _chromeVisible = true;
  Timer? _chromeHideTimer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    final ok = (statuses[Permission.camera]?.isGranted ?? false) &&
        (statuses[Permission.microphone]?.isGranted ?? false);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera and microphone are required')),
      );
      Navigator.of(context).pop();
      return;
    }
    setState(() => _permsReady = true);

    try {
      final client = await CallClient.create();
      _client = client;
      final uri = Uri.parse(widget.roomUrl);
      final firstName = uri.queryParameters['linka_first_name'] ?? '';
      final lastName = uri.queryParameters['linka_last_name'] ?? '';
      final displayName = [firstName, lastName]
          .where((s) => s.isNotEmpty)
          .join(' ');
      client.setUsername(displayName.isNotEmpty ? displayName : widget.localName);
      client.setInputsEnabled(camera: true, microphone: true);
      client.updateSubscriptionProfiles(
        forProfiles: {
          SubscriptionProfile.base: const MediaSubscriptionSettingsUpdate.set(
            camera: VideoSubscriptionSettingsUpdate.set(
              subscriptionState: SubscriptionStateUpdate.subscribed,
            ),
            screenVideo: VideoSubscriptionSettingsUpdate.set(
              subscriptionState: SubscriptionStateUpdate.subscribed,
            ),
          ),
        },
      );
      _eventSub = client.events.listen(_onEvent);
      await client.join(
        url: Uri.parse(widget.roomUrl),
        token: widget.token.isEmpty ? null : widget.token,
      );
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join: $e')),
        );
      }
    }
  }

  void _onEvent(Event event) {
    if (!mounted) return;
    event.whenOrNull<void>(
      callStateUpdated: (data) {
        final state = data.state;
        if (state == CallState.joined) {
          setState(() => _joined = true);
          _refreshLocalTrack();
          _refreshRemote();
        } else if (state == CallState.left) {
          if (_leaving) return;
          _leaving = true;
          if (mounted) Navigator.of(context).pop();
        }
      },
      inputsUpdated: (inputs) {
        setState(() {
          _cameraOn = inputs.camera.isEnabled;
          _micOn = inputs.microphone.isEnabled;
        });
        _refreshLocalTrack();
      },
      participantJoined: (p) {
        if (!p.info.isLocal) {
          setState(() => _remoteId = p.id);
          _refreshRemote();
        }
      },
      participantUpdated: (p) {
        if (p.info.isLocal) {
          _refreshLocalTrack();
        } else {
          if (_remoteId == null) setState(() => _remoteId = p.id);
          _refreshRemote();
        }
      },
      participantLeft: (p) {
        if (_remoteId == p.id) {
          setState(() => _remoteId = null);
          _remoteCtrl.setTrack(null);
        }
      },
      appMessageReceived: (data, from) {
        String? text;
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map) {
            text = (decoded['message'] ?? decoded['text'])?.toString();
          } else if (decoded is String) {
            text = decoded;
          }
        } catch (_) {
          text = data;
        }
        if (text == null || text.isEmpty) return;
        final name = _nameFor(from);
        _messages.value = [..._messages.value, _ChatEntry(name, text, false)];
        _unread.value = _unread.value + 1;
      },
      error: (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      },
    );
  }

  String _nameFor(ParticipantId id) {
    final client = _client;
    if (client == null) return 'Tutor';
    final p = client.participants.all[id];
    final name = p?.info.username;
    return (name == null || name.isEmpty) ? widget.tutorName : name;
  }

  void _refreshLocalTrack() {
    final client = _client;
    if (client == null) return;
    final track = client.inputs.camera.isEnabled
        ? client.participants.local.media?.camera.track
        : null;
    _localCtrl.setTrack(track);
  }

  void _refreshRemote() {
    final client = _client;
    final id = _remoteId;
    if (client == null || id == null) return;
    final p = client.participants.remote[id];
    final media = p?.media;
    final screenTrack = media?.screenVideo.track;
    final camTrack = media?.camera.track;
    _remoteCtrl.setTrack(screenTrack ?? camTrack);
    setState(() {
      _remoteCamera = screenTrack != null || !(p?.isCameraMuted ?? true);
      _remoteMic = !(p?.isMicrophoneMuted ?? true);
    });
  }

  Future<void> _toggleCamera() async {
    final client = _client;
    if (client == null) return;
    await client.setInputsEnabled(camera: !_cameraOn, microphone: _micOn);
  }

  Future<void> _toggleMic() async {
    final client = _client;
    if (client == null) return;
    await client.setInputsEnabled(camera: _cameraOn, microphone: !_micOn);
  }

  Future<void> _sendChat(String text) async {
    final client = _client;
    if (client == null || !_joined || text.trim().isEmpty) return;
    final payload = jsonEncode({'message': text.trim()});
    try {
      final remotes = client.participants.remote;
      if (remotes.isEmpty) {
        await client.sendAppMessage(payload, null);
      } else {
        for (final id in remotes.keys) {
          await client.sendAppMessage(payload, id);
        }
      }
      _messages.value = [
        ..._messages.value,
        _ChatEntry(widget.localName, text.trim(), true),
      ];
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  void _openChat() {
    _unread.value = 0;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ChatSheet(
        messagesListenable: _messages,
        onSend: _sendChat,
      ),
    );
  }

  Future<void> _confirmExit() async {
    if (_leaving) return;
    final leave = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _LeaveSheet(),
    );
    if (!mounted) return;
    if (leave == true) {
      await _leave();
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      await _client?.leave();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void deactivate() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.deactivate();
  }

  @override
  void dispose() {
    _chromeHideTimer?.cancel();
    _eventSub?.cancel();
    _client?.dispose();
    _localCtrl.dispose();
    _remoteCtrl.dispose();
    _messages.dispose();
    _unread.dispose();
    super.dispose();
  }

  void _toggleChrome() {
    _chromeHideTimer?.cancel();
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) {
      _chromeHideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _chromeVisible = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_permsReady) {
      return const Scaffold(
        backgroundColor: Color(0xFF13152A),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: const Color(0xFF13152A),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: const Color(0xFF13152A),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmExit();
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF13152A),
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleChrome,
                  child: _remoteArea(),
                ),
              ),
              if (_joined && _cameraOn)
                _FloatingSelfView(
                  controller: _localCtrl,
                  name: widget.localName,
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_chromeVisible,
                  child: AnimatedOpacity(
                    opacity: _chromeVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: ColoredBox(
                      color: const Color(0xFF13152A),
                      child: SafeArea(
                        bottom: false,
                        child: _MeetingHeader(
                          title: widget.tutorName,
                          live: _joined,
                          onClose: _confirmExit,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_chromeVisible,
                  child: AnimatedOpacity(
                    opacity: _chromeVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: _BottomControls(
                      micOn: _micOn,
                      cameraOn: _cameraOn,
                      unreadListenable: _unread,
                      onToggleMic: _toggleMic,
                      onToggleCamera: _toggleCamera,
                      onChat: _openChat,
                      onLeave: _confirmExit,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _remoteArea() {
    if (_remoteId == null) {
      return _WaitingView(tutorName: widget.tutorName);
    }
    if (!_remoteCamera) {
      return _CameraOffView(name: widget.tutorName, micOn: _remoteMic);
    }
    return Container(
      color: Colors.black,
      child: VideoView(controller: _remoteCtrl, fit: VideoViewFit.contain),
    );
  }
}

class _ChatEntry {
  final String name;
  final String text;
  final bool mine;
  _ChatEntry(this.name, this.text, this.mine);
}

class _MeetingHeader extends StatelessWidget {
  final String title;
  final bool live;
  final VoidCallback onClose;

  const _MeetingHeader({
    required this.title,
    required this.live,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF13152A),
      child: Row(
        children: [
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Symbols.close_rounded, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'In a lesson with',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 11,
                    color: Color(0xFFAAAAAA),
                  ),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (live ? const Color(0xFF27AE60) : Colors.grey)
                  .withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.circle_rounded,
                  color: live ? const Color(0xFF27AE60) : Colors.grey,
                  size: 8,
                ),
                const SizedBox(width: 6),
                Text(
                  live ? 'Live' : 'Connecting',
                  style: TextStyle(
                    color: live ? const Color(0xFF27AE60) : Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _FloatingSelfView extends StatefulWidget {
  final VideoViewController controller;
  final String name;

  const _FloatingSelfView({
    required this.controller,
    required this.name,
  });

  @override
  State<_FloatingSelfView> createState() => _FloatingSelfViewState();
}

class _FloatingSelfViewState extends State<_FloatingSelfView> {
  Offset _offset = const Offset(16, 16);
  static const _size = Size(110, 150);

  @override
  Widget build(BuildContext context) {
    final bounds = MediaQuery.of(context).size;
    return Positioned(
      left: _offset.dx.clamp(8.0, bounds.width - _size.width - 8),
      top: _offset.dy.clamp(8.0, 420.0),
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() => _offset = _offset + d.delta);
        },
        child: Container(
          width: _size.width,
          height: _size.height,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
            color: const Color(0xFF1E2040),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Transform.scale(
            scaleX: -1,
            child: VideoView(
              controller: widget.controller,
              fit: VideoViewFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

class _WaitingView extends StatelessWidget {
  final String tutorName;
  const _WaitingView({required this.tutorName});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF13152A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Waiting for $tutorName…',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraOffView extends StatelessWidget {
  final String name;
  final bool micOn;
  const _CameraOffView({required this.name, required this.micOn});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF13152A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1E2040),
                border: Border.all(color: Colors.white24, width: 2),
              ),
              child: const Icon(Symbols.person_rounded, size: 56, color: Colors.white70),
            ),
            const SizedBox(height: 14),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  micOn ? Symbols.mic_rounded : Symbols.mic_off_rounded,
                  size: 14,
                  color: micOn ? Colors.white54 : const Color(0xFFE53935),
                ),
                const SizedBox(width: 4),
                Text(
                  'Camera off',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
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

class _BottomControls extends StatelessWidget {
  final bool micOn;
  final bool cameraOn;
  final ValueListenable<int> unreadListenable;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onChat;
  final VoidCallback onLeave;

  const _BottomControls({
    required this.micOn,
    required this.cameraOn,
    required this.unreadListenable,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onChat,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF13152A),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 14,
      ),
      child: Row(
        children: [
          _CircleButton(
            icon: micOn ? Symbols.mic_rounded : Symbols.mic_off_rounded,
            active: micOn,
            onTap: onToggleMic,
          ),
          const SizedBox(width: 12),
          _CircleButton(
            icon: cameraOn ? Symbols.videocam_rounded : Symbols.videocam_off_rounded,
            active: cameraOn,
            onTap: onToggleCamera,
          ),
          const SizedBox(width: 12),
          ValueListenableBuilder<int>(
            valueListenable: unreadListenable,
            builder: (_, count, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  _CircleButton(
                    icon: Symbols.chat_bubble_rounded,
                    active: true,
                    onTap: onChat,
                  ),
                  if (count > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(minWidth: 18),
                        child: Text(
                          '$count',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const Spacer(),
          GestureDetector(
            onTap: onLeave,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935),
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.center,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.call_end_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Leave',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _CircleButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? Colors.white.withValues(alpha: 0.14)
              : const Color(0xFFE53935).withValues(alpha: 0.85),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _ChatSheet extends StatefulWidget {
  final ValueListenable<List<_ChatEntry>> messagesListenable;
  final Future<void> Function(String) onSend;

  const _ChatSheet({
    required this.messagesListenable,
    required this.onSend,
  });

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = _text.text;
    if (t.trim().isEmpty) return;
    _text.clear();
    await widget.onSend(t);
    if (_scroll.hasClients) {
      await _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: FractionallySizedBox(
        heightFactor: 0.75,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Chat',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: ValueListenableBuilder<List<_ChatEntry>>(
                valueListenable: widget.messagesListenable,
                builder: (_, msgs, _) {
                  if (msgs.isEmpty) {
                    return Center(
                      child: Text(
                        'No messages yet',
                        style: TextStyle(color: context.colors.textTertiary),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) => _ChatBubble(entry: msgs[i]),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText: 'Message…',
                          filled: true,
                          fillColor: context.colors.surfaceAlt,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _submit,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: context.colors.brand,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Symbols.send_rounded, color: Colors.white, size: 20),
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
  final _ChatEntry entry;
  const _ChatBubble({required this.entry});

  @override
  Widget build(BuildContext context) {
    final mine = entry.mine;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: mine
                    ? context.colors.brand
                    : context.colors.surfaceAlt,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(mine ? 14 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!mine)
                    Text(
                      entry.name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  if (!mine) const SizedBox(height: 2),
                  Text(
                    entry.text,
                    style: TextStyle(
                      color: mine ? Colors.white : context.colors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaveSheet extends StatelessWidget {
  const _LeaveSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Leave the lesson?',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You can rejoin while the lesson is still active.',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.pop(context, true),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: context.colors.error,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'Leave',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.pop(context, false),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: context.colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'Stay',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
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
