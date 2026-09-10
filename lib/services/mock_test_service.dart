import 'dart:io';

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

  /// Answers the task a published Writing sample answers, and grades it.
  ///
  /// Returns the same graded attempt shape as [submitWriting] — the server
  /// mirrors the sample's task into a hidden prompt, so the answer lands in
  /// `/writing-attempts/` and spends the same free quota. A sample the student
  /// cannot open is one they cannot answer: this 403s on the same Plus window
  /// as reading it does.
  static Future<Map<String, dynamic>> submitWritingSampleAnswer(int sampleId, String essayText) {
    return ApiService.post('/writing-samples/$sampleId/submit/', {'essay_text': essayText});
  }

  static Future<List<Map<String, dynamic>>> fetchWritingAttempts() async {
    final data = await ApiService.getList('/writing-attempts/');
    return data.cast<Map<String, dynamic>>();
  }

  /// One attempt in full, including `analysis` — the diagnostic review the
  /// list endpoint deliberately omits (a full review runs to several KB, and a
  /// student with thirty essays would otherwise download all thirty of them to
  /// draw a list of titles and bands).
  static Future<Map<String, dynamic>> fetchWritingAttempt(int attemptId) {
    return ApiService.get('/writing-attempts/$attemptId/');
  }

  /// What the student keeps getting wrong, counted across every graded essay:
  /// band trend, per-criterion averages, recurring grammar topics, persistent
  /// habits and a short focus list. Pure aggregation over stored reviews — no
  /// second AI call — so it is free to open and stable between reloads.
  static Future<Map<String, dynamic>> fetchWritingInsights() {
    return ApiService.get('/writing-attempts/insights/');
  }

  /// {is_plus, limit, used, remaining} — `limit`/`remaining` are null
  /// for Plus users (unlimited). The limit is a total free window, not a
  /// daily allowance.
  static Future<Map<String, dynamic>> fetchWritingQuota() {
    return ApiService.get('/writing-attempts/quota/');
  }

  /// Speaking sample answers, each covering Part 1/2/3 (some tutors may only
  /// have 2 of the 3 parts). Optionally scoped to a single tutor via
  /// [tutorId] (preferred) or [tutorName] (for admin-authored samples with no
  /// real tutor account, where `tutor_id` is null), or to a single curated
  /// topic via [topicId] — every tutor's take on the same question.
  static Future<List<Map<String, dynamic>>> fetchSpeakingSamples({
    int? tutorId,
    String? tutorName,
    int? topicId,
  }) async {
    final params = <String>[];
    if (tutorId != null) params.add('tutor_id=$tutorId');
    if (tutorName != null) params.add('tutor_name=${Uri.encodeQueryComponent(tutorName)}');
    if (topicId != null) params.add('topic_id=$topicId');
    final qs = params.isNotEmpty ? '?${params.join('&')}' : '';
    final data = await ApiService.getList('/speaking-samples/$qs');
    return data.cast<Map<String, dynamic>>();
  }

  /// The whole curated Speaking topic bank — every topic with its Part 1/2/3
  /// questions and `sample_count`, the number of tutors who recorded an answer
  /// to it.
  ///
  /// This is the question library behind the samples, and unlike the samples it
  /// is not Plus-gated: what Plus buys is a tutor's recording, not the
  /// examiner's question. Answering one still spends the AI marking quota (see
  /// [fetchSpeakingAnswerQuota]), which is the budget that costs money.
  static Future<List<Map<String, dynamic>>> fetchSpeakingTopics() async {
    final data = await ApiService.getList('/speaking-topics/');
    return data.cast<Map<String, dynamic>>();
  }

  /// Tutors with at least one published Speaking sample, sorted alphabetically
  /// by name. `tutor_id` is null for admin-authored samples with no real
  /// tutor account (grouped by name in that case).
  static Future<List<Map<String, dynamic>>> fetchSpeakingSampleTutors() async {
    final data = await ApiService.getList('/speaking-samples/tutors/');
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

  // ─── Speaking answers (AI marking) ────────────────────────────────────────

  /// The free window on AI-marked *spoken* answers — `{is_plus, limit, used,
  /// remaining}`, with `limit`/`remaining` null for Plus.
  ///
  /// A lifetime allowance, not a daily one, and not to be confused with the
  /// free live-practice minutes in `/video/speaking/quota/`: two unrelated
  /// budgets, and a student can be out of one with the other untouched.
  static Future<Map<String, dynamic>> fetchSpeakingAnswerQuota() {
    return ApiService.get('/speaking-attempts/quota/');
  }

  /// Sends the student's own recording of a sample part's question for AI
  /// marking, and returns the created attempt — `pending`, because
  /// transcription and marking run on the server after the upload lands.
  /// Poll [fetchSpeakingAttempt] until `status` reads `graded` or `failed`.
  ///
  /// [durationSeconds] is the client's own stopwatch reading: the server
  /// cannot probe every container, so until transcription reports an
  /// authoritative length this is the only duration the attempt has.
  static Future<Map<String, dynamic>> submitSpeakingAnswer({
    required int partId,
    required File audio,
    required int durationSeconds,
  }) {
    return ApiService.postMultipart(
      '/speaking-sample-parts/$partId/submit/',
      files: {'audio_file': audio},
      fields: {'duration_seconds': '$durationSeconds'},
    );
  }

  /// The same as [submitSpeakingAnswer], for a question picked straight out of
  /// the topic bank rather than from under a tutor's recording.
  ///
  /// [partId] is a *topic* part id — the ids in a topic's `parts` and the ids
  /// in a sample's `parts` come from different tables and are not
  /// interchangeable, which is why this is a separate call rather than a flag.
  static Future<Map<String, dynamic>> submitSpeakingTopicAnswer({
    required int partId,
    required File audio,
    required int durationSeconds,
  }) {
    return ApiService.postMultipart(
      '/speaking-topic-parts/$partId/submit/',
      files: {'audio_file': audio},
      fields: {'duration_seconds': '$durationSeconds'},
    );
  }

  /// One spoken attempt in full, including `analysis`, `transcript` and the
  /// per-word timings the corrections seek against — all three of which the
  /// list endpoint omits. This is also the poll target while marking runs.
  static Future<Map<String, dynamic>> fetchSpeakingAttempt(int attemptId) {
    return ApiService.get('/speaking-attempts/$attemptId/');
  }

  /// Every answer this student has sent for marking, newest first.
  ///
  /// Unsettled attempts are included deliberately: marking outlives the screen
  /// that started it, and a student who backed out mid-marking is exactly who
  /// comes looking for this list.
  static Future<List<Map<String, dynamic>>> fetchSpeakingAttempts() async {
    final data = await ApiService.getList('/speaking-attempts/');
    return data.cast<Map<String, dynamic>>();
  }
}
