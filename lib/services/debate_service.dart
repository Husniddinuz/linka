import 'api_service.dart';

class DebateService {
  static Future<Map<String, dynamic>> getToday() {
    return ApiService.get('/live/debate/today/');
  }

  static Future<Map<String, dynamic>> join(int sessionId) {
    return ApiService.post('/live/debate/$sessionId/join/', {});
  }

  static Future<List<dynamic>> getParticipants(int sessionId) async {
    final data = await ApiService.get('/live/debate/$sessionId/participants/');
    return data['participants'] as List<dynamic>? ?? [];
  }

  static Future<List<dynamic>> getChatHistory(int sessionId,
      {int limit = 50}) async {
    try {
      final data = await ApiService.get('/live/$sessionId/chat/?limit=$limit');
      return (data['results'] ??
              data['messages'] ??
              data['data'] ??
              []) as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> sendChat(
      int sessionId, String text) {
    return ApiService.post('/live/$sessionId/chat/', {'text': text});
  }

  static Future<void> reportSpeaking(int sessionId, bool speaking) async {
    await ApiService.post(
        '/live/debate/$sessionId/speaking/', {'speaking': speaking});
  }

  static Future<Map<String, dynamic>> getAdminRoster(int sessionId) {
    return ApiService.get('/live/debate/$sessionId/admin/roster/');
  }

  static Future<Map<String, dynamic>> promote(
      int sessionId, int userId, String team) {
    return ApiService.post(
        '/live/debate/$sessionId/admin/promote/', {'user_id': userId, 'team': team});
  }

  static Future<Map<String, dynamic>> demote(int sessionId, int userId) {
    return ApiService.post(
        '/live/debate/$sessionId/admin/demote/', {'user_id': userId});
  }
}
