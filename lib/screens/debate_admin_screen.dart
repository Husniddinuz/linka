import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/api_constants.dart';
import '../services/api_service.dart';
import '../services/debate_service.dart';
import '../services/token_service.dart';

// ─── Model ─────────────────────────────────────────────────────────────────────

class _AdminPart {
  final int userId;
  final String firstName;
  final String lastName;
  final String? profileImage;
  String role; // 'speaker' | 'viewer' | 'moderator'
  String? team; // 'A' | 'B' | null
  bool isSpeaking;
  bool isOnline;

  _AdminPart({
    required this.userId,
    required this.firstName,
    required this.lastName,
    this.profileImage,
    required this.role,
    this.team,
    this.isSpeaking = false,
    this.isOnline = false,
  });

  String get displayName {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? 'User #$userId' : n;
  }

  factory _AdminPart.fromJson(Map<String, dynamic> j,
      {Set<int> connectedIds = const {}}) {
    final user = j['user'] as Map<String, dynamic>? ?? {};
    final uid = (j['user_id'] ?? user['id'] ?? 0) as int;
    return _AdminPart(
      userId: uid,
      firstName: (user['first_name'] ?? '').toString(),
      lastName: (user['last_name'] ?? '').toString(),
      profileImage: user['profile_image']?.toString(),
      role: (j['role'] ?? 'viewer').toString(),
      team: j['team']?.toString(),
      isSpeaking: j['is_speaking'] as bool? ?? false,
      isOnline: connectedIds.contains(uid),
    );
  }
}

// ─── Screen ────────────────────────────────────────────────────────────────────

class DebateAdminScreen extends StatefulWidget {
  final int sessionId;
  final String title;
  final String? topic;

  const DebateAdminScreen({
    super.key,
    required this.sessionId,
    required this.title,
    this.topic,
  });

  @override
  State<DebateAdminScreen> createState() => _DebateAdminScreenState();
}

class _DebateAdminScreenState extends State<DebateAdminScreen> {
  final Map<int, _AdminPart> _parts = {};
  int _viewerCount = 0;
  bool _loading = true;
  String? _errorMsg;
  final Set<int> _busyIds = {}; // ids with pending promote/demote requests

  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  Timer? _wsReconTimer;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchRoster();
    _connectWs();
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 8), (_) { if (mounted) _fetchRoster(); });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _wsReconTimer?.cancel();
    _wsSub?.cancel();
    try { _ws?.sink.close(); } catch (_) {}
    super.dispose();
  }

  // ─── Roster ──────────────────────────────────────────────────────────────────

  Future<void> _fetchRoster() async {
    try {
      final data = await DebateService.getAdminRoster(widget.sessionId);
      if (!mounted) return;
      final connectedRaw = data['connected_user_ids'] as List<dynamic>? ?? [];
      final connected = connectedRaw.map((e) => e as int).toSet();
      final rawParts = data['participants'] as List<dynamic>? ?? [];
      final map = <int, _AdminPart>{};
      for (final p in rawParts) {
        final part = _AdminPart.fromJson(p as Map<String, dynamic>,
            connectedIds: connected);
        map[part.userId] = part;
      }
      setState(() {
        _parts
          ..clear()
          ..addAll(map);
        _viewerCount = data['viewer_count'] as int? ?? _viewerCount;
        _loading = false;
        _errorMsg = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = e.statusCode == 403
            ? 'Staff access required.'
            : e.message;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── WebSocket (speaking_changed) ────────────────────────────────────────────

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
      if (data['type'] == 'speaking_changed') {
        final uid = data['user_id'] as int?;
        final speaking = data['speaking'] as bool?;
        if (uid != null && speaking != null && mounted) {
          setState(() {
            if (_parts.containsKey(uid)) {
              _parts[uid]!.isSpeaking = speaking;
            }
          });
        }
      } else if (data['type'] == 'viewer_count') {
        final count = data['count'] as int?;
        if (count != null && mounted) setState(() => _viewerCount = count);
      }
    } catch (_) {}
  }

  // ─── Promote / Demote ────────────────────────────────────────────────────────

  Future<void> _promote(int userId, String team) async {
    setState(() => _busyIds.add(userId));
    try {
      await DebateService.promote(widget.sessionId, userId, team);
      // Optimistically update
      if (mounted) {
        setState(() {
          if (_parts.containsKey(userId)) {
            _parts[userId]!.role = 'speaker';
            _parts[userId]!.team = team;
          }
          _busyIds.remove(userId);
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busyIds.remove(userId));
        _showSnack(e.message);
      }
    } catch (_) {
      if (mounted) setState(() => _busyIds.remove(userId));
    }
  }

  Future<void> _demote(int userId) async {
    setState(() => _busyIds.add(userId));
    try {
      await DebateService.demote(widget.sessionId, userId);
      if (mounted) {
        setState(() {
          if (_parts.containsKey(userId)) {
            _parts[userId]!.role = 'viewer';
            _parts[userId]!.team = null;
            _parts[userId]!.isSpeaking = false;
          }
          _busyIds.remove(userId);
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busyIds.remove(userId));
        _showSnack(e.message);
      }
    } catch (_) {
      if (mounted) setState(() => _busyIds.remove(userId));
    }
  }

  void _showPromoteSheet(int userId, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1F3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Promote $name to speaker',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Select which team to assign them to.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _TeamButton(
                      label: 'Team A',
                      color: const Color(0xFF3A6BC7),
                      onTap: () {
                        Navigator.pop(context);
                        _promote(userId, 'A');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TeamButton(
                      label: 'Team B',
                      color: const Color(0xFFC7523A),
                      onTap: () {
                        Navigator.pop(context);
                        _promote(userId, 'B');
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
        backgroundColor: const Color(0xFF0D0F1F),
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFF5C542),
                          strokeWidth: 2,
                        ),
                      )
                    : _errorMsg != null
                        ? _buildError()
                        : _buildRoster(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1F3A),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2D4A))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.topic != null && widget.topic!.isNotEmpty)
                  Text(
                    widget.topic!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (_viewerCount > 0) ...[
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.remove_red_eye_outlined,
                    color: Colors.white38, size: 13),
                const SizedBox(width: 3),
                Text(
                  '$_viewerCount',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _fetchRoster,
            child: const Icon(Icons.refresh_rounded,
                color: Colors.white54, size: 20),
          ),
        ],
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
            const Icon(Icons.error_outline_rounded,
                color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text(_errorMsg!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white60, fontSize: 14)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _fetchRoster,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF272942),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Retry',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoster() {
    final teamA = _parts.values
        .where((p) => p.role == 'speaker' && p.team == 'A')
        .toList();
    final teamB = _parts.values
        .where((p) => p.role == 'speaker' && p.team == 'B')
        .toList();
    final viewers =
        _parts.values.where((p) => p.role != 'speaker').toList();

    return RefreshIndicator(
      color: const Color(0xFF272942),
      onRefresh: _fetchRoster,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Speakers ──
          if (teamA.isNotEmpty || teamB.isNotEmpty) ...[
            _SectionHeader(
              label: 'SPEAKERS',
              trailing: '${teamA.length + teamB.length}',
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _TeamColumn(
                    team: 'A',
                    parts: teamA,
                    busyIds: _busyIds,
                    onDemote: _demote,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TeamColumn(
                    team: 'B',
                    parts: teamB,
                    busyIds: _busyIds,
                    onDemote: _demote,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          // ── Viewers ──
          _SectionHeader(
            label: 'VIEWERS',
            trailing: '${viewers.length}',
          ),
          const SizedBox(height: 8),
          if (viewers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('No viewers yet.',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 13)),
            )
          else
            ...viewers.map((p) => _ViewerRow(
                  part: p,
                  busy: _busyIds.contains(p.userId),
                  onPromote: () => _showPromoteSheet(p.userId, p.displayName),
                )),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final String? trailing;
  const _SectionHeader({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFF5C542),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2D4A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              trailing!,
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }
}

class _TeamColumn extends StatelessWidget {
  final String team;
  final List<_AdminPart> parts;
  final Set<int> busyIds;
  final void Function(int userId) onDemote;

  const _TeamColumn({
    required this.team,
    required this.parts,
    required this.busyIds,
    required this.onDemote,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        team == 'A' ? const Color(0xFF3A6BC7) : const Color(0xFFC7523A);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Team $team',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        if (parts.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('—',
                style: TextStyle(
                    color: Colors.white38, fontSize: 12)),
          )
        else
          ...parts.map((p) => _SpeakerRow(
                part: p,
                teamColor: color,
                busy: busyIds.contains(p.userId),
                onDemote: () => onDemote(p.userId),
              )),
      ],
    );
  }
}

class _SpeakerRow extends StatelessWidget {
  final _AdminPart part;
  final Color teamColor;
  final bool busy;
  final VoidCallback onDemote;

  const _SpeakerRow({
    required this.part,
    required this.teamColor,
    required this.busy,
    required this.onDemote,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F3A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: part.isSpeaking ? const Color(0xFFF5C542) : teamColor,
          width: part.isSpeaking ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          if (part.isSpeaking)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: const BoxDecoration(
                color: Color(0xFFF5C542),
                shape: BoxShape.circle,
              ),
            ),
          Expanded(
            child: Text(
              part.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
          ),
          const SizedBox(width: 6),
          busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white38, strokeWidth: 1.5))
              : GestureDetector(
                  onTap: onDemote,
                  child: const Icon(
                    Icons.person_remove_outlined,
                    color: Colors.white38,
                    size: 18,
                  ),
                ),
        ],
      ),
    );
  }
}

class _ViewerRow extends StatelessWidget {
  final _AdminPart part;
  final bool busy;
  final VoidCallback onPromote;

  const _ViewerRow({
    required this.part,
    required this.busy,
    required this.onPromote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F3A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2D4A)),
      ),
      child: Row(
        children: [
          // Online dot
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: part.isOnline
                  ? const Color(0xFF27AE60)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: part.isOnline
                  ? null
                  : Border.all(color: Colors.white24, width: 1),
            ),
          ),
          Expanded(
            child: Text(
              part.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Color(0xFFF5C542), strokeWidth: 1.5))
              : GestureDetector(
                  onTap: onPromote,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5C542).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFF5C542).withValues(alpha: 0.5)),
                    ),
                    child: const Text(
                      '+ Speaker',
                      style: TextStyle(
                        color: Color(0xFFF5C542),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _TeamButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TeamButton(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
