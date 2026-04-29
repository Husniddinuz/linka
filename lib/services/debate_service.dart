import 'api_service.dart';

class DebateParticipant {
  final int userId;
  final String firstName;
  final String lastName;
  final String? profileImage;
  final String role;
  final String? team;
  final bool isSpeaking;
  final bool canSpeak;

  const DebateParticipant({
    required this.userId,
    required this.firstName,
    required this.lastName,
    this.profileImage,
    required this.role,
    this.team,
    required this.isSpeaking,
    required this.canSpeak,
  });

  factory DebateParticipant.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>? ?? {};
    return DebateParticipant(
      userId: j['user_id'] as int? ?? user['id'] as int? ?? 0,
      firstName: user['first_name'] as String? ?? '',
      lastName: user['last_name'] as String? ?? '',
      profileImage: user['profile_image'] as String?,
      role: j['role'] as String? ?? 'viewer',
      team: j['team'] as String?,
      isSpeaking: j['is_speaking'] as bool? ?? false,
      canSpeak: j['can_speak'] as bool? ?? false,
    );
  }

  String get displayName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? 'User' : name;
  }
}

class DebateJoinData {
  final int sessionId;
  final String title;
  final String status;
  final String roomId;
  final String role;
  final String? team;
  final bool canSpeak;
  final List<DebateParticipant> participants;
  final String mode; // "rtc" | "cdn"
  final int? zegoAppId;
  final String? zegoToken;
  final String? zegoUserId;
  final String? playbackUrl;

  const DebateJoinData({
    required this.sessionId,
    required this.title,
    required this.status,
    required this.roomId,
    required this.role,
    this.team,
    required this.canSpeak,
    required this.participants,
    required this.mode,
    this.zegoAppId,
    this.zegoToken,
    this.zegoUserId,
    this.playbackUrl,
  });

  factory DebateJoinData.fromJson(Map<String, dynamic> j) {
    final rawParticipants = j['participants'] as List<dynamic>? ?? [];
    return DebateJoinData(
      sessionId: j['session_id'] as int? ?? j['id'] as int? ?? 0,
      title: j['title'] as String? ?? 'Debate',
      status: j['status'] as String? ?? 'live',
      roomId: j['room_id'] as String? ?? '',
      role: j['role'] as String? ?? 'viewer',
      team: j['team'] as String?,
      canSpeak: j['can_speak'] as bool? ?? false,
      participants: rawParticipants
          .map((e) => DebateParticipant.fromJson(e as Map<String, dynamic>))
          .toList(),
      mode: j['mode'] as String? ?? 'cdn',
      zegoAppId: j['zego_app_id'] as int?,
      zegoToken: j['zego_token'] as String?,
      zegoUserId: j['zego_user_id']?.toString(),
      playbackUrl: j['playback_url'] as String?,
    );
  }
}

class DebateService {
  static Future<Map<String, dynamic>> fetchToday() =>
      ApiService.get('/live/debate/today/');

  static Future<DebateJoinData> join(int sessionId) async {
    final data = await ApiService.post('/live/debate/$sessionId/join/', {});
    return DebateJoinData.fromJson(data);
  }

  static Future<List<DebateParticipant>> fetchParticipants(
      int sessionId) async {
    final data =
        await ApiService.get('/live/debate/$sessionId/participants/');
    final raw = data['participants'] as List<dynamic>? ?? [];
    return raw
        .map((e) => DebateParticipant.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> setSpeaking(int sessionId, bool speaking) async {
    await ApiService.post(
      '/live/debate/$sessionId/speaking/',
      {'speaking': speaking},
    );
  }
}
