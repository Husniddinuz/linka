import 'dart:convert';

import 'api_service.dart';
import 'user_service.dart';

/// Participant metadata — the source of truth for role/team in the new
/// LiveKit-driven flow. Carried both in the `/join/` response and on every
/// LiveKit participant (as a JSON string).
class DebateMeta {
  final String? fullName;
  final String? avatar;
  final String role; // "speaker" | "viewer"
  final String? team; // "A" | "B" | null

  const DebateMeta({
    this.fullName,
    this.avatar,
    required this.role,
    this.team,
  });

  factory DebateMeta.fromJson(Map<String, dynamic> j) {
    final av = j['avatar']?.toString();
    final tm = j['team']?.toString();
    return DebateMeta(
      fullName: (j['full_name']?.toString().isNotEmpty ?? false)
          ? j['full_name'].toString()
          : null,
      avatar: (av != null && av.isNotEmpty && av != 'null') ? av : null,
      role: (j['role'] ?? 'viewer').toString(),
      team: (tm != null && tm.isNotEmpty && tm != 'null') ? tm : null,
    );
  }

  /// Parses a LiveKit participant metadata string. Tolerates null / empty /
  /// malformed JSON (returns null so callers can fall back to other data).
  static DebateMeta? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) return DebateMeta.fromJson(decoded);
    } catch (_) {}
    return null;
  }
}

/// One member from `GET /live/debate/state/` → `members[]`.
class DebateMember {
  final int userId;
  final String name;
  final String? avatar;
  final String role; // "speaker" | "viewer"
  final String? team; // "A" | "B" | null

  const DebateMember({
    required this.userId,
    required this.name,
    this.avatar,
    required this.role,
    this.team,
  });

  factory DebateMember.fromJson(Map<String, dynamic> j) {
    final id = int.tryParse('${j['identity'] ?? ''}') ?? 0;
    final name =
        (j['full_name'] ?? j['name'] ?? '').toString().trim();
    final av = j['avatar']?.toString();
    final tm = j['team']?.toString();
    return DebateMember(
      userId: id,
      name: name.isEmpty ? 'User $id' : name,
      avatar: (av != null && av.isNotEmpty && av != 'null') ? av : null,
      role: (j['role'] ?? 'viewer').toString(),
      team: (tm != null && tm.isNotEmpty && tm != 'null') ? tm : null,
    );
  }
}

/// Result of `GET /live/debate/state/` — room snapshot used to seed the
/// roster before the LiveKit connection settles.
class DebateState {
  final String room;
  final int capacity;
  final List<DebateMember> members;
  final int countA;
  final int countB;

  const DebateState({
    required this.room,
    required this.capacity,
    required this.members,
    required this.countA,
    required this.countB,
  });

  factory DebateState.fromJson(Map<String, dynamic> j) {
    final m = j['members'];
    final counts = j['counts'];
    return DebateState(
      room: (j['room'] ?? 'main').toString(),
      capacity: (j['capacity'] as num?)?.toInt() ?? 0,
      members: m is List
          ? m
              .whereType<Map<String, dynamic>>()
              .map(DebateMember.fromJson)
              .toList()
          : const [],
      countA: counts is Map ? ((counts['A'] as num?)?.toInt() ?? 0) : 0,
      countB: counts is Map ? ((counts['B'] as num?)?.toInt() ?? 0) : 0,
    );
  }
}

/// Result of `POST /live/debate/join/` — LiveKit credentials plus the
/// caller's current role/team and admin flag.
class DebateJoinResult {
  final String url;
  final String token;
  final String identity;
  final String room;
  final bool isAdmin;
  final String? team;
  final String role; // "speaker" | "viewer"
  final DebateMeta? metadata;

  const DebateJoinResult({
    required this.url,
    required this.token,
    required this.identity,
    required this.room,
    required this.isAdmin,
    this.team,
    required this.role,
    this.metadata,
  });

  int get userId => int.tryParse(identity) ?? 0;
  bool get canPublish => role == 'speaker';
  bool get hasCredentials => url.isNotEmpty && token.isNotEmpty;

  factory DebateJoinResult.fromJson(Map<String, dynamic> j) {
    DebateMeta? meta;
    final rawMeta = j['metadata'];
    if (rawMeta is String) {
      meta = DebateMeta.tryParse(rawMeta);
    } else if (rawMeta is Map<String, dynamic>) {
      meta = DebateMeta.fromJson(rawMeta);
    }
    final tm = j['team']?.toString();
    return DebateJoinResult(
      url: (j['url'] ?? '').toString(),
      token: (j['token'] ?? '').toString(),
      identity: (j['identity'] ?? '').toString(),
      room: (j['room'] ?? 'main').toString(),
      isAdmin: j['isAdmin'] as bool? ?? false,
      team: (tm != null && tm.isNotEmpty && tm != 'null') ? tm : null,
      role: (j['role'] ?? 'viewer').toString(),
      metadata: meta,
    );
  }
}

/// Result of `GET /live/debate/today/` — the motion/topic for today's
/// debate. Field names are tolerated loosely so a backend rename
/// (`topic` / `title` / `motion` / `question`) doesn't break the UI.
class DailyDebate {
  final String topic;
  final String? description;
  final String? date;
  final bool hasSession;

  /// Live-session id (the `id` in `/live/debate/today/`). This is the key the
  /// chat WebSocket is mounted under (`/ws/live/session/{sessionId}/`) — the
  /// LiveKit room name ("main") is NOT a valid WS key.
  final int? sessionId;

  const DailyDebate({
    required this.topic,
    this.description,
    this.date,
    this.hasSession = false,
    this.sessionId,
  });

  factory DailyDebate.fromJson(Map<String, dynamic> j) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = j[k]?.toString().trim();
        if (v != null && v.isNotEmpty && v != 'null') return v;
      }
      return '';
    }

    final desc = pick(['description', 'details', 'context']);
    final dt = pick(['date', 'day']);
    final hs = j['has_session'];
    final rawId = j['id'] ?? j['session_id'] ?? j['session'];
    return DailyDebate(
      topic: pick(['topic', 'title', 'motion', 'question']),
      description: desc.isEmpty ? null : desc,
      date: dt.isEmpty ? null : dt,
      hasSession: hs is bool ? hs : (hs?.toString().toLowerCase() == 'true'),
      sessionId: rawId == null ? null : int.tryParse('$rawId'),
    );
  }
}

/// Thin wrapper over the new debate REST control-plane. RTC audio runs over
/// the LiveKit connection; chat runs over the backend room WebSocket
/// (`/ws/live/session/{room}/`) in the debate room screen.
class DebateService {
  /// The authenticated user's id, needed for `/join/` and admin calls.
  static Future<int> currentUserId() async {
    final cached = UserService.current?.id;
    if (cached != null && cached > 0) return cached;
    final me = await UserService.fetchMe();
    return me.id;
  }

  /// `GET /live/debate/today/` — the motion/topic for today's debate.
  static Future<DailyDebate> today() async {
    final data = await ApiService.get('/live/debate/today/');
    return DailyDebate.fromJson(data);
  }

  /// `GET /live/debate/state/` — members + per-team counts.
  static Future<DebateState> getState() async {
    final data = await ApiService.get('/live/debate/state/');
    return DebateState.fromJson(data);
  }

  /// `POST /live/debate/join/` — mints a LiveKit token for [userId].
  static Future<DebateJoinResult> join(int userId) async {
    final body = {'userId': userId};
    final data = await ApiService.post('/live/debate/join/', body);
    return DebateJoinResult.fromJson(data);
  }

  /// `POST /live/debate/role/` — admin promote (`speaker`, auto team) or
  /// demote (`viewer`, clears team). 409 if both teams are full.
  static Future<void> setRole({
    required int adminId,
    required int targetId,
    required String role,
  }) async {
    final body = {'adminId': adminId, 'targetId': targetId, 'role': role};
    await ApiService.post('/live/debate/role/', body);
  }

  /// `POST /live/debate/team/` — admin moves an existing speaker between
  /// teams. 400 if target is still a viewer, 409 if the target team is full.
  static Future<void> setTeam({
    required int adminId,
    required int targetId,
    required String team,
  }) async {
    final body = {'adminId': adminId, 'targetId': targetId, 'team': team};
    await ApiService.post('/live/debate/team/', body);
  }

  /// Demotes the caller back to `viewer` when they leave the room, freeing
  /// their speaker slot/team server-side (otherwise the assignment persists
  /// and they keep occupying a slot in the background until rejoin).
  ///
  /// Reuses `POST /live/debate/role/` as a self-demote (adminId == targetId)
  /// — no dedicated leave endpoint exists. Best-effort: swallows errors
  /// (incl. a possible 403 if the backend enforces admin-only role changes)
  /// since it runs on screen teardown.
  static Future<void> leave(int userId) async {
    if (userId <= 0) return;
    try {
      await setRole(adminId: userId, targetId: userId, role: 'viewer');
    } catch (_) {
      // Best-effort self-demote on teardown; ignore failures.
    }
  }
}
