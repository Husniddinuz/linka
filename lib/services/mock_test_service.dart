import '../models/mock_test.dart';
import 'api_service.dart';

/// Reading/Listening/Writing IELTS mock tests: fetching test content,
/// submitting attempts (auto-graded for Reading/Listening, AI-graded for
/// Writing), and reading back attempt history.
class MockTestService {
  static Future<List<MockTest>> fetchTests(String testType) async {
    final data = await ApiService.getList('/mock-tests/?type=$testType');
    return MockTest.listFromJson(data);
  }

  static Future<MockTest> fetchTestDetail(int testId) async {
    final data = await ApiService.get('/mock-tests/$testId/');
    return MockTest.fromJson(data);
  }

  /// [answers] maps question id -> submitted value (`String` for text/single
  /// choice, `List<String>` for multi-select).
  static Future<MockTestAttempt> submitTest(
    int testId,
    Map<String, dynamic> answers,
  ) async {
    final data = await ApiService.post('/mock-tests/$testId/submit/', {'answers': answers});
    return MockTestAttempt.fromJson(data);
  }

  static Future<List<MockTestAttempt>> fetchAttempts({String? testType}) async {
    final qs = testType != null ? '?type=$testType' : '';
    final data = await ApiService.getList('/mock-tests/attempts/$qs');
    return MockTestAttempt.listFromJson(data);
  }

  static Future<MockTestAttempt> fetchAttemptDetail(int attemptId) async {
    final data = await ApiService.get('/mock-tests/attempts/$attemptId/');
    return MockTestAttempt.fromJson(data);
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

  /// Tutors with real Speaking sample answers, each covering Part 1/2/3
  /// (some tutors may only have 2 of the 3 parts).
  static Future<List<Map<String, dynamic>>> fetchSpeakingSamples() async {
    final data = await ApiService.getList('/speaking-samples/');
    return data.cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> fetchWritingSamples({
    int? taskNumber,
    int? tutorId,
    String? tutorName,
  }) async {
    final params = <String>[];
    if (taskNumber != null) params.add('task=$taskNumber');
    if (tutorId != null) params.add('tutor_id=$tutorId');
    if (tutorName != null) params.add('tutor_name=${Uri.encodeQueryComponent(tutorName)}');
    final qs = params.isNotEmpty ? '?${params.join('&')}' : '';
    final data = await ApiService.getList('/writing-samples/$qs');
    return data.cast<Map<String, dynamic>>();
  }

  /// Tutors with at least one published Writing sample, sorted alphabetically
  /// by name. `tutor_id` is null for admin-authored samples with no real
  /// tutor account (grouped by name in that case).
  static Future<List<Map<String, dynamic>>> fetchWritingSampleTutors() async {
    final data = await ApiService.getList('/writing-samples/tutors/');
    return data.cast<Map<String, dynamic>>();
  }
}
