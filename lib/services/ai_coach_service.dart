import '../models/ai_coach.dart';
import 'api_constants.dart';
import 'api_service.dart';

/// The AI coach: a conversation partner that answers out loud, scores how the
/// student said it, and remembers what they keep getting wrong.
///
/// Its endpoints sit at `/ai/` on the API host rather than under `/api/v1/`,
/// so every path here is absolute — [ApiService] passes a full URL through
/// untouched, which keeps the shared token refresh and network handling.
class AiCoachService {
  /// Derived from [apiBaseUrl] rather than written out again, so moving the
  /// API to another host moves the coach with it.
  static final String _base =
      '${apiBaseUrl.replaceFirst(RegExp(r'/api/v\d+/?$'), '')}/ai';

  /// The five characters. Their names and taglines come back in Russian; the
  /// app names the known ones itself and falls back to these.
  static Future<List<CoachPersona>> fetchPersonas() async {
    final data = await ApiService.getList('$_base/personas/');
    return data
        .whereType<Map<String, dynamic>>()
        .map(CoachPersona.fromJson)
        .toList();
  }

  /// Models the server has a key for. An empty list means `/ai/` cannot work
  /// at all — every `session` call would answer 503 — which is worth knowing
  /// before drawing a start button.
  static Future<List<String>> fetchModels() async {
    final data = await ApiService.getList('$_base/models/');
    return data
        .whereType<Map<String, dynamic>>()
        .map((model) => model['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  /// Opens a conversation. With [greet] left on the reply carries the coach's
  /// spoken hello, which is one round trip instead of a session call followed
  /// by an empty turn.
  ///
  /// No model is sent: the server picks from the keys it actually holds, and
  /// naming one here would mean naming it from a list that could be a deploy
  /// stale.
  static Future<CoachSession> startSession({
    required String persona,
    required String level,
    String goal = '',
    bool greet = true,
  }) async {
    final data = await ApiService.post('$_base/session/', {
      'persona': persona,
      'level': level,
      'goal': goal,
      'greet': greet,
    });
    return CoachSession.fromJson(data);
  }

  /// Closing is optional — an abandoned conversation simply goes cold — but a
  /// closed one cannot be reopened, which is what stops a stale screen from
  /// talking into yesterday's session.
  static Future<void> endSession(int sessionId) async {
    await ApiService.post('$_base/session/$sessionId/end/', const {});
  }

  /// One typed turn — the way in when speaking aloud is not an option.
  ///
  /// Spoken turns do not come through here: they stream over the socket in
  /// [CoachSocket] as they are said. The `POST /ai/turn/{id}/` upload endpoint
  /// still exists server-side and is the fallback if streaming ever has to go.
  /// `pronunciation` always comes back null here: there is no audio to score.
  static Future<CoachTurn> sendTextTurn({
    required int sessionId,
    required String text,
  }) async {
    final data =
        await ApiService.post('$_base/turn/$sessionId/text/', {'text': text});
    return CoachTurn.fromJson(data);
  }

  /// What the coach has noticed across every conversation.
  static Future<CoachStats> fetchStats() async {
    final data = await ApiService.get('$_base/stats/');
    return CoachStats.fromJson(data);
  }
}
