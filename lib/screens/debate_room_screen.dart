import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/api_constants.dart';
import '../services/api_service.dart';
import '../services/debate_service.dart';
import '../widgets/cached_avatar.dart';

// ─── Chat message model ────────────────────────────────────────────────────────

class _ChatMessage {
  final String sender;
  final String text;
  final bool isOwn;
  final String? avatarUrl;
  final String? team; // "A" | "B" | null — colors the sender name
  // Nullable so a hot reload that adds this field to already-created
  // messages can't crash the chat; readers fall back to "now".
  final DateTime? time;

  _ChatMessage({
    required this.sender,
    required this.text,
    required this.isOwn,
    this.avatarUrl,
    this.team,
  }) : time = DateTime.now();
}

// ─── Roster entry ──────────────────────────────────────────────────────────────

class _RosterEntry {
  final int userId;
  String name;
  String? avatarUrl;
  String role; // "speaker" | "viewer"
  String? team; // "A" | "B" | null

  _RosterEntry({
    required this.userId,
    required this.name,
    this.avatarUrl,
    required this.role,
    this.team,
  });

  bool get isSpeaker => role == 'speaker';
  bool get isViewer => role != 'speaker';
}

// ─── Screen ────────────────────────────────────────────────────────────────────

class DebateRoomScreen extends StatefulWidget {
  final String title;

  const DebateRoomScreen({
    super.key,
    this.title = 'Daily Debate',
  });

  @override
  State<DebateRoomScreen> createState() => _DebateRoomScreenState();
}

class _DebateRoomScreenState extends State<DebateRoomScreen> {
  // Join state
  DebateJoinResult? _join;
  bool _joining = true;
  String? _joinError;
  int _myUserId = 0;
  int _capacity = 10;

  // Today's motion, from GET /live/debate/today/. Falls back to
  // widget.title until (and if) the request resolves.
  String? _topic;

  // Local role/team — tracked so a metadata update that changes *our* role
  // can trigger a re-join for fresh LiveKit publish permissions.
  String _myRole = 'viewer';
  String? _myTeam;

  // Live roster (speakers + viewers), keyed by user id. Derived entirely
  // from LiveKit participants + their metadata (the source of truth).
  final Map<int, _RosterEntry> _roster = {};
  // Set while the admin sheet is open; lets async roster/metadata updates
  // repaint the sheet's own StatefulBuilder.
  void Function()? _adminSheetRefresh;
  // Target user ids with an admin role/team request in flight. Each
  // /role/ or /team/ call costs ~1.5s server-side, so the row shows a
  // spinner and ignores further taps until it resolves.
  final Set<int> _busyUserIds = {};

  // LiveKit
  Room? _room;
  EventsListener<RoomEvent>? _roomListener;
  bool _rtcConnected = false;
  bool _micOn = false;
  bool _togglingMic = false;
  // User ids currently speaking (derived from LiveKit active speakers).
  Set<int> _speakingUserIds = {};

  // Chat (LiveKit data channel, topic "chat")
  final List<_ChatMessage> _messages = [];
  final _chatController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sendingMessage = false;

  // "Which team is speaking" + how long. Recomputed from active speakers /
  // roster; the ticker just repaints the elapsed clock once a second.
  String? _speakingTeamKey; // "A" | "B" | "BOTH" | null
  DateTime? _speakingSince;
  Timer? _speakTicker;

  static const _chatTopic = 'chat';

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _loadTodayTopic();
    _joinDebate();
  }

  Future<void> _loadTodayTopic() async {
    try {
      final daily = await DebateService.today();
      if (!mounted || daily.topic.isEmpty) return;
      setState(() => _topic = daily.topic);
    } on ApiException {
      // Topic is non-essential; leave the default in place on failure.
    } catch (_) {
      // Topic is non-essential; leave the default in place on failure.
    }
  }

  /// Disconnects and disposes a LiveKit room, swallowing the
  /// TimeoutException `Room.disconnect()` throws when the socket is already
  /// gone (e.g. on app teardown or a failed/partial connect).
  static Future<void> _closeRoom(
    Room? room,
    EventsListener<RoomEvent>? listener,
  ) async {
    try {
      listener?.dispose();
    } catch (_) {}
    if (room == null) return;
    try {
      await room.disconnect();
    } catch (_) {}
    try {
      await room.dispose();
    } catch (_) {}
  }

  /// Coalesces rapid participant/metadata events into a single roster
  /// rebuild on the next frame. Crucially this defers the rebuild *out* of
  /// the LiveKit event callback, so we never call setState during a build
  /// nor dispose the event listener while it is dispatching.
  bool _rosterRebuildScheduled = false;
  void _scheduleRosterRebuild() {
    if (_rosterRebuildScheduled) return;
    _rosterRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rosterRebuildScheduled = false;
      _rebuildRoster();
    });
  }

  Future<void> _joinDebate() async {
    try {
      final userId = _myUserId > 0
          ? _myUserId
          : await DebateService.currentUserId();

      final join = await DebateService.join(userId);
      if (!mounted) return;

      _myUserId = join.userId;
      _myRole = join.role;
      _myTeam = join.team;
      setState(() {
        _join = join;
        _joining = false;
        _joinError = null;
      });

      _seedRosterFromState();

      if (!join.hasCredentials) {
        setState(() =>
            _joinError = 'Audio is temporarily unavailable. Please retry.');
        return;
      }
      _connectLiveKit(join);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _joinError = e.message;
      });
    }
  }

  /// Best-effort: pull `/state/` so the roster shows everyone already in the
  /// room before LiveKit participant events arrive. Non-fatal on failure.
  Future<void> _seedRosterFromState() async {
    try {
      final state = await DebateService.getState();
      if (!mounted) return;
      setState(() {
        if (state.capacity > 0) _capacity = state.capacity;
        for (final m in state.members) {
          if (m.userId <= 0) continue;
          _roster[m.userId] = _RosterEntry(
            userId: m.userId,
            name: m.name,
            avatarUrl: _resolveUrl(m.avatar),
            role: m.role,
            team: m.team,
          );
        }
      });
      _adminSheetRefresh?.call();
    } on ApiException {
      // Roster seed is best-effort; LiveKit events will populate it.
    }
  }

  // ─── LiveKit ──────────────────────────────────────────────────────────────────

  Future<void> _connectLiveKit(DebateJoinResult join) async {
    if (join.canPublish) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Microphone permission is required to speak.'),
        ));
      }
    }

    try {
      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );
      final listener = room.createListener();
      _wireRoomEvents(listener);

      await room.connect(join.url, join.token);

      if (!mounted) {
        await _closeRoom(room, listener);
        return;
      }

      setState(() {
        _room = room;
        _roomListener = listener;
        _rtcConnected = true;
      });
      _rebuildRoster();

      // Mic always starts OFF; speakers opt in via the mic button.
      await room.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _joinError = 'Could not connect to debate audio.');
    }
  }

  void _wireRoomEvents(EventsListener<RoomEvent> listener) {
    listener
      ..on<ActiveSpeakersChangedEvent>((e) {
        final ids = <int>{};
        for (final p in e.speakers) {
          final id = _userIdFromIdentity(p.identity);
          if (id != null) ids.add(id);
        }
        if (mounted) {
          setState(() => _speakingUserIds = ids);
          _updateSpeakingTimer();
        }
      })
      ..on<RoomDisconnectedEvent>((_) {
        if (mounted) setState(() => _rtcConnected = false);
      })
      ..on<ParticipantConnectedEvent>((_) => _scheduleRosterRebuild())
      ..on<ParticipantDisconnectedEvent>((_) => _scheduleRosterRebuild())
      ..on<ParticipantMetadataUpdatedEvent>(_onMetadataUpdated)
      ..on<ParticipantPermissionsUpdatedEvent>((_) => _scheduleRosterRebuild())
      ..on<DataReceivedEvent>(_onDataReceived);
  }

  /// LiveKit metadata changed for someone (role/team is encoded there — the
  /// source of truth). When it targets *us*, update our role/team locally;
  /// the server has already updated our LiveKit publish permission in place,
  /// so no reconnect is needed — we just react.
  void _onMetadataUpdated(ParticipantMetadataUpdatedEvent e) {
    final id = _userIdFromIdentity(e.participant.identity);
    if (id != null && id == _myUserId) {
      final meta = DebateMeta.tryParse(e.participant.metadata);
      final newRole = meta?.role ?? _myRole;
      final newTeam = meta?.team;
      if (newRole != _myRole || newTeam != _myTeam) {
        _myRole = newRole;
        _myTeam = newTeam;
        if (newRole != 'speaker') _forceMicOff();
      }
    }
    _scheduleRosterRebuild();
  }

  void _onDataReceived(DataReceivedEvent e) {
    if (e.topic != _chatTopic) return;
    try {
      final decoded = json.decode(utf8.decode(e.data));
      if (decoded is! Map) return;
      final text = (decoded['text'] ?? '').toString();
      if (text.isEmpty) return;

      final p = e.participant;
      final senderId = _userIdFromIdentity(p?.identity ?? '');
      if (senderId != null && senderId == _myUserId) return; // own loopback

      final meta = DebateMeta.tryParse(p?.metadata);
      final sender = (meta?.fullName?.isNotEmpty ?? false)
          ? meta!.fullName!
          : (p != null && p.name.isNotEmpty ? p.name : 'Guest');

      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          sender: sender,
          text: text,
          isOwn: false,
          avatarUrl: _resolveUrl(meta?.avatar),
          team: meta?.role == 'speaker' ? meta?.team : null,
        ));
      });
      _scrollToBottom();
    } catch (_) {}
  }

  /// Rebuilds the roster from the live LiveKit participant list. Every
  /// speaker AND viewer is a LiveKit participant in the new flow, so this is
  /// the single source of truth once connected.
  void _rebuildRoster() {
    final room = _room;
    if (room == null) return;
    final next = <int, _RosterEntry>{};

    void absorb(Participant p) {
      final id = _userIdFromIdentity(p.identity);
      if (id == null || id <= 0) return;
      final meta = DebateMeta.tryParse(p.metadata);
      final name = (meta?.fullName?.isNotEmpty ?? false)
          ? meta!.fullName!
          : (p.name.isNotEmpty ? p.name : (_roster[id]?.name ?? 'User $id'));
      next[id] = _RosterEntry(
        userId: id,
        name: name,
        avatarUrl: _resolveUrl(meta?.avatar) ?? _roster[id]?.avatarUrl,
        role: meta?.role ?? 'viewer',
        team: meta?.team,
      );

      // Keep our own role/team in lockstep with the authoritative LiveKit
      // metadata. _myRole/_myTeam are seeded from /join/, but a late
      // leave()/role change can demote us in the room *after* join()
      // returned (e.g. quitting and immediately re-entering: the in-flight
      // self-demote lands between join and connect). Then no metadata-update
      // *event* fires, so _onMetadataUpdated never corrects us, and the mic
      // UI (driven by _myRole) disagrees with the roster/admin panel (driven
      // by metadata) — Team B shows empty and "Promote" appears for us, yet
      // we can still talk. Reconciling here collapses both onto metadata.
      if (id == _myUserId &&
          meta != null &&
          (meta.role != _myRole || meta.team != _myTeam)) {
        _myRole = meta.role;
        _myTeam = meta.team;
        if (_myRole != 'speaker') _forceMicOff();
      }
    }

    final lp = room.localParticipant;
    if (lp != null) absorb(lp);
    for (final rp in room.remoteParticipants.values) {
      absorb(rp);
    }

    // Guarantee self is listed even if metadata hasn't propagated yet.
    if (_myUserId > 0 && !next.containsKey(_myUserId) && _join != null) {
      next[_myUserId] = _RosterEntry(
        userId: _myUserId,
        name: _join!.metadata?.fullName ?? 'You',
        avatarUrl: _resolveUrl(_join!.metadata?.avatar),
        role: _join!.role,
        team: _join!.team,
      );
    }

    if (!mounted) return;
    setState(() {
      _roster
        ..clear()
        ..addAll(next);
    });
    _updateSpeakingTimer();
    _adminSheetRefresh?.call();
  }

  String? _resolveUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    final base = Uri.parse(apiBaseUrl);
    return '${base.scheme}://${base.host}$url';
  }

  /// livekit identity is the bare user id ("20"); tolerate a legacy
  /// `<userId>-<random>` form too.
  int? _userIdFromIdentity(String identity) {
    if (identity.isEmpty) return null;
    final dash = identity.indexOf('-');
    final head = dash > 0 ? identity.substring(0, dash) : identity;
    return int.tryParse(head);
  }

  /// Active users currently connected over the LiveKit websocket
  /// (remote participants + the local participant).
  int get _activeUserCount {
    final room = _room;
    if (room == null) return 0;
    return room.remoteParticipants.length +
        (room.localParticipant != null ? 1 : 0);
  }

  bool get _canPublish => _myRole == 'speaker';
  bool get _isAdmin => _join?.isAdmin ?? false;

  /// Speakers currently talking, resolved through the roster (skips viewers
  /// and unknown ids). Drives the "who is speaking" label.
  List<_RosterEntry> _activeSpeakingEntries() {
    final out = <_RosterEntry>[];
    for (final id in _speakingUserIds) {
      final e = _roster[id];
      if (e != null && e.isSpeaker) out.add(e);
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// Which team is currently speaking, derived from active LiveKit speakers
  /// mapped through the roster: "A", "B", "BOTH", or null when silent.
  String? _currentSpeakingTeam() {
    var a = false, b = false;
    for (final id in _speakingUserIds) {
      final e = _roster[id];
      if (e == null || !e.isSpeaker) continue;
      if (e.team == 'A') a = true;
      if (e.team == 'B') b = true;
    }
    if (a && b) return 'BOTH';
    if (a) return 'A';
    if (b) return 'B';
    return null;
  }

  /// Keeps [_speakingTeamKey]/[_speakingSince] and the 1s repaint ticker in
  /// sync with whoever is speaking. Resets the clock when the team changes.
  void _updateSpeakingTimer() {
    final team = _currentSpeakingTeam();
    if (team != _speakingTeamKey) {
      _speakingTeamKey = team;
      _speakingSince = team == null ? null : DateTime.now();
    }
    if (team != null && _speakTicker == null) {
      _speakTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (team == null && _speakTicker != null) {
      _speakTicker!.cancel();
      _speakTicker = null;
    }
  }

  Future<void> _toggleMic() async {
    if (!_canPublish || _togglingMic) {
      if (!_canPublish) _forceMicOff();
      return;
    }
    final next = !_micOn;
    setState(() => _togglingMic = true);
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(next);
      if (!mounted) return;
      setState(() {
        _micOn = next;
        _togglingMic = false;
      });
    } catch (_) {
      _forceMicOff();
      if (mounted) {
        setState(() => _togglingMic = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not toggle the microphone.'),
        ));
      }
    }
  }

  Future<void> _forceMicOff() async {
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {}
    if (mounted) setState(() => _micOn = false);
  }

  // ─── Chat (LiveKit data channel) ──────────────────────────────────────────────

  void _scrollToBottom() {
    // Two frames: the first lets the new bubble lay out so maxScrollExtent
    // reflects it, the second snaps to the (now correct) bottom in case the
    // animation started before layout settled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController
              .jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    final lp = _room?.localParticipant;
    if (text.isEmpty || _sendingMessage || lp == null) return;

    _chatController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _sendingMessage = true;
      _messages.add(_ChatMessage(
        sender: 'You',
        text: text,
        isOwn: true,
        team: _canPublish ? _myTeam : null,
      ));
    });
    _scrollToBottom();

    try {
      await lp.publishData(
        utf8.encode(json.encode({'text': text})),
        reliable: true,
        topic: _chatTopic,
      );
    } catch (_) {
      // Chat publish is best-effort.
    } finally {
      if (mounted) setState(() => _sendingMessage = false);
    }
  }

  @override
  void dispose() {
    // If we leave as a speaker, drop our speaker slot server-side so the
    // assignment doesn't linger in the background (and reappear on rejoin).
    // Fire-and-forget: ApiService is static so the request outlives this
    // widget; leave() swallows its own errors.
    if (_myRole == 'speaker' && _myUserId > 0) {
      DebateService.leave(_myUserId);
    }
    // Fire-and-forget but fully guarded: _closeRoom swallows the
    // TimeoutException disconnect() can throw, so no unhandled async error.
    final room = _room;
    final listener = _roomListener;
    _room = null;
    _roomListener = null;
    _closeRoom(room, listener);
    _speakTicker?.cancel();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── UI ───────────────────────────────────────────────────────────────────────

  // Arena palette (dark theme).
  static const _bg = Color(0xFF0A0E1A);
  static const _card = Color(0xFF121A2B);
  static const _cTeamA = Color(0xFF3D8BFF); // blue
  static const _cTeamB = Color(0xFFE2533F); // red
  static const _cLive = Color(0xFFE74C3C);
  static const _cOnline = Color(0xFF27AE60);
  static const _cSpeaking = Color(0xFF2ED573);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(),
            if (_joining)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: _cTeamA),
                ),
              )
            else if (_join == null)
              Expanded(child: _buildErrorState())
            else ...[
              _buildHeaderInfo(),
              _buildTeams(),
              _buildSpeakingBar(),
              Expanded(child: _buildChat()),
              if (_isAdmin) _buildBottomBar(),
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.chevron_left_rounded,
                  size: 24, color: Colors.white),
            ),
          ),
          const Expanded(
            child: Text(
              'Debate Room',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 30),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 44, color: Colors.white38),
            const SizedBox(height: 12),
            Text(
              _joinError ?? 'Could not join the debate.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                setState(() {
                  _joining = true;
                  _joinError = null;
                });
                _joinDebate();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                decoration: BoxDecoration(
                  color: _cTeamA,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderInfo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _cLive,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PulseDot(),
                    SizedBox(width: 5),
                    Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.remove_red_eye_outlined,
                        size: 12, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(
                      '$_activeUserCount',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _topic ?? widget.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeams() {
    final speakers = _roster.values.where((p) => p.isSpeaker).toList();
    final teamA = speakers.where((p) => p.team == 'A').toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final teamB = speakers.where((p) => p.team == 'B').toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final perTeam = _capacity > 0 ? (_capacity ~/ 2) : 5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildTeamCard('Team A', _cTeamA, teamA, perTeam),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildTeamCard('Team B', _cTeamB, teamB, perTeam),
              ),
            ],
          ),
          _buildVsBadge(),
        ],
      ),
    );
  }

  Widget _buildTeamCard(
    String title,
    Color color,
    List<_RosterEntry> team,
    int perTeam,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined, size: 15, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: team.isEmpty
                ? Center(
                    child: Text(
                      'No speakers yet',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  )
                : Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _AvatarStack(
                        avatarUrls: team
                            .map((e) => e.avatarUrl)
                            .toList(growable: false),
                        ringColor: color,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 7),
          Text(
            '${team.length}/$perTeam Members',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVsBadge() {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1A2030),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 8,
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'VS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildSpeakingBar() {
    final team = _speakingTeamKey;
    final color = team == 'A'
        ? _cTeamA
        : team == 'B'
            ? _cTeamB
            : team == 'BOTH'
                ? _cSpeaking
                : Colors.white38;
    final speaking = _activeSpeakingEntries();
    final label = speaking.isEmpty
        ? 'No one speaking'
        : speaking.map((e) => '${e.name} (${e.team ?? '?'})').join(', ');

    final since = _speakingSince;
    final secs =
        since == null ? 0 : DateTime.now().difference(since).inSeconds;
    final clock =
        '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.9),
            ),
            child:
                const Icon(Icons.mic_rounded, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: team == null ? Colors.white54 : color,
              ),
            ),
          ),
          if (team != null)
            Text(
              clock,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          if (_canPublish) ...[
            const SizedBox(width: 8),
            _buildMicChip(),
          ],
        ],
      ),
    );
  }

  Widget _buildMicChip() {
    final disabled = _togglingMic || !_rtcConnected;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: disabled ? null : _toggleMic,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _micOn ? _cLive : Colors.white.withValues(alpha: 0.12),
          ),
          child: Icon(
            _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            size: 16,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // ─── Admin panel ──────────────────────────────────────────────────────────────

  Future<void> _adminAction(
    int targetUserId,
    Future<void> Function() call,
    void Function() refresh,
  ) async {
    if (_busyUserIds.contains(targetUserId)) return; // tap-lock
    _busyUserIds.add(targetUserId);
    if (mounted) setState(() {});
    refresh();
    try {
      await call();
      // LiveKit metadata-updated events will reconcile the roster.
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      _busyUserIds.remove(targetUserId);
      if (mounted) setState(() {});
      refresh();
    }
  }

  void _openAdminPanel() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            void refresh() {
              if (ctx.mounted) setSheet(() {});
            }

            _adminSheetRefresh = refresh;
            final entries = _roster.values.toList()
              ..sort((a, b) {
                int rank(_RosterEntry e) => e.isSpeaker ? 0 : 1;
                final r = rank(a).compareTo(rank(b));
                return r != 0 ? r : a.name.compareTo(b.name);
              });
            final speakerCount =
                _roster.values.where((e) => e.isSpeaker).length;
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.92,
              builder: (_, scrollCtl) => Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: Row(
                      children: [
                        const Text(
                          'Manage debate',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF272942),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$speakerCount/$_capacity speakers',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFAAAAAA),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _seedRosterFromState,
                          child: const Icon(Icons.refresh_rounded,
                              size: 20, color: Color(0xFF272942)),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtl,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: entries.length,
                      itemBuilder: (_, i) {
                        final e = entries[i];
                        return _AdminRosterRow(
                          entry: e,
                          isSelf: e.userId == _myUserId,
                          busy: _busyUserIds.contains(e.userId),
                          onPromote: () => _adminAction(
                            e.userId,
                            () => DebateService.setRole(
                              adminId: _myUserId,
                              targetId: e.userId,
                              role: 'speaker',
                            ),
                            refresh,
                          ),
                          onDemote: () => _adminAction(
                            e.userId,
                            () => DebateService.setRole(
                              adminId: _myUserId,
                              targetId: e.userId,
                              role: 'viewer',
                            ),
                            refresh,
                          ),
                          onSetTeam: (team) => _adminAction(
                            e.userId,
                            () => DebateService.setTeam(
                              adminId: _myUserId,
                              targetId: e.userId,
                              team: team,
                            ),
                            refresh,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() => _adminSheetRefresh = null);
  }

  Widget _buildChatHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          const Text(
            'Live Chat',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _rtcConnected ? _cOnline : Colors.white24,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$_activeUserCount online',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChat() {
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    return Column(
      children: [
        _buildChatHeader(),
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Text(
                    'No messages yet.\nBe the first to say hi!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white38,
                      height: 1.5,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _ChatBubble(
                    message: _messages[i],
                    teamAColor: _cTeamA,
                    teamBColor: _cTeamB,
                  ),
                ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: keyboardH),
          child: _buildChatInput(),
        ),
      ],
    );
  }

  Widget _buildChatInput() {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    // When the admin bottom bar is shown it owns the home-indicator inset;
    // otherwise the input must clear it itself.
    final safeBottom = (keyboardOpen || _isAdmin)
        ? 8.0
        : MediaQuery.of(context).viewPadding.bottom + 8.0;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, safeBottom),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: TextField(
                controller: _chatController,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                cursorColor: _cTeamA,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
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
                color: _sendingMessage ? Colors.white24 : _cTeamA,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.arrow_upward_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 6, 12, bottomInset + 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1C2435))),
      ),
      child: GestureDetector(
        onTap: _openAdminPanel,
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.groups_rounded, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Manage',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Helper widgets ────────────────────────────────────────────────────────────

class _AdminRosterRow extends StatelessWidget {
  final _RosterEntry entry;
  final bool isSelf;
  final bool busy;
  final VoidCallback onPromote;
  final VoidCallback onDemote;
  final void Function(String team) onSetTeam;

  const _AdminRosterRow({
    required this.entry,
    required this.isSelf,
    required this.busy,
    required this.onPromote,
    required this.onDemote,
    required this.onSetTeam,
  });

  @override
  Widget build(BuildContext context) {
    final roleColor = entry.isSpeaker
        ? const Color(0xFF27AE60)
        : const Color(0xFFAAAAAA);
    final roleLabel = entry.isSpeaker
        ? 'Speaker ${entry.team ?? ''}'.trim()
        : 'Watcher';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          CachedAvatar(imageUrl: entry.avatarUrl, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSelf ? '${entry.name} (you)' : entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF272942),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  roleLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: roleColor,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFAAAAAA),
                ),
              ),
            )
          else if (entry.isSpeaker) ...[
            _PillButton(
              label: 'A',
              color: const Color(0xFF4A90D9),
              faded: entry.team == 'A',
              onTap: () => onSetTeam('A'),
            ),
            const SizedBox(width: 6),
            _PillButton(
              label: 'B',
              color: const Color(0xFFE7625F),
              faded: entry.team == 'B',
              onTap: () => onSetTeam('B'),
            ),
            const SizedBox(width: 6),
            _PillButton(
              label: 'Demote',
              color: const Color(0xFFE74C3C),
              onTap: onDemote,
            ),
          ] else
            _PillButton(
              label: 'Promote',
              color: const Color(0xFF27AE60),
              onTap: onPromote,
            ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool faded;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.color,
    this.faded = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: faded ? 0.4 : 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  final List<String?> avatarUrls;
  final Color ringColor;

  const _AvatarStack({required this.avatarUrls, required this.ringColor});

  @override
  Widget build(BuildContext context) {
    const size = 24.0;
    if (avatarUrls.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < avatarUrls.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0A0E1A),
                border: Border.all(color: ringColor, width: 2),
              ),
              child: CachedAvatar(imageUrl: avatarUrls[i], size: size),
            ),
          ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  final Color teamAColor;
  final Color teamBColor;

  const _ChatBubble({
    required this.message,
    required this.teamAColor,
    required this.teamBColor,
  });

  @override
  Widget build(BuildContext context) {
    final isOwn = message.isOwn;
    final t = message.time ?? DateTime.now();
    var h = t.hour % 12;
    if (h == 0) h = 12;
    final ts =
        '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
    final nameColor = message.team == 'A'
        ? teamAColor
        : message.team == 'B'
            ? teamBColor
            : Colors.white;
    final name = isOwn
        ? 'You'
        : (message.team != null
            ? '${message.sender} (Team ${message.team})'
            : message.sender);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CachedAvatar(imageUrl: message.avatarUrl, size: 30),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isOwn ? Colors.white : nameColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ts,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF182236),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    message.text,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.white,
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

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_c),
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
      ),
    );
  }
}
