import 'api_service.dart';

/// Reading/Listening/Writing IELTS mock tests: fetching test content,
/// submitting attempts (auto-graded for Reading/Listening, AI-graded for
/// Writing), and reading back attempt history.
class MockTestService {
  static Future<List<Map<String, dynamic>>> fetchTests(String testType) async {
    final data = await ApiService.getList('/mock-tests/?type=$testType');
    return data.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> fetchTestDetail(int testId) {
    return ApiService.get('/mock-tests/$testId/');
  }

  /// [answers] maps question id -> submitted value (`String` for text/single
  /// choice, `List<String>` for multi-select).
  static Future<Map<String, dynamic>> submitTest(
    int testId,
    Map<String, dynamic> answers,
  ) {
    return ApiService.post('/mock-tests/$testId/submit/', {'answers': answers});
  }

  static Future<List<Map<String, dynamic>>> fetchAttempts({String? testType}) async {
    final qs = testType != null ? '?type=$testType' : '';
    final data = await ApiService.getList('/mock-tests/attempts/$qs');
    return data.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> fetchAttemptDetail(int attemptId) {
    return ApiService.get('/mock-tests/attempts/$attemptId/');
  }

  static Future<List<Map<String, dynamic>>> fetchWritingPrompts({int? taskNumber}) async {
    final qs = taskNumber != null ? '?task=$taskNumber' : '';
    final data = await ApiService.getList('/writing-prompts/$qs');
    return data.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> submitWriting(int promptId, String essayText) {
    return ApiService.post('/writing-prompts/$promptId/submit/', {'essay_text': essayText});
  }

  static Future<List<Map<String, dynamic>>> fetchWritingAttempts() async {
    final data = await ApiService.getList('/writing-attempts/');
    return data.cast<Map<String, dynamic>>();
  }

  /// {is_plus, limit, used_today, remaining} — `limit`/`remaining` are null
  /// for Plus users (unlimited).
  static Future<Map<String, dynamic>> fetchWritingQuota() {
    return ApiService.get('/writing-attempts/quota/');
  }

  static Future<List<Map<String, dynamic>>> fetchSpeakingSamples({int? part}) async {
    final qs = part != null ? '?part=$part' : '';
    final data = await ApiService.getList('/speaking-samples/$qs');
    return data.cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> fetchWritingSamples({int? taskNumber}) async {
    final qs = taskNumber != null ? '?task=$taskNumber' : '';
    final data = await ApiService.getList('/writing-samples/$qs');
    return data.cast<Map<String, dynamic>>();
  }
}
