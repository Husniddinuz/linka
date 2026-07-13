// Typed models for the IELTS Reading/Listening mock-test API
// (`/mock-tests/...`), mirroring the Django models in
// `apps.mock_tests.models` field-for-field.

/// A `{value, label}` entry from a `Question.options`/`QuestionGroup.shared_options` list.
class QuestionOption {
  const QuestionOption({required this.value, required this.label});

  final String value;
  final String label;

  factory QuestionOption.fromJson(Map<String, dynamic> json) => QuestionOption(
    value: json['value']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
  );

  static List<QuestionOption> listFromJson(List? raw) =>
      (raw ?? const []).map((e) => QuestionOption.fromJson(e as Map<String, dynamic>)).toList();
}

class Question {
  const Question({
    required this.id,
    required this.number,
    this.numberEnd,
    required this.inputCount,
    required this.promptText,
    required this.options,
  });

  final int id;
  final int number;
  final int? numberEnd;
  final int inputCount;
  final String promptText;
  final List<QuestionOption> options;

  /// This question's own options, falling back to the group's shared legend
  /// (matching/true-false/MCQ groups usually only store options once, on the
  /// group, since every question in the group shares the same choices).
  List<QuestionOption> effectiveOptions(QuestionGroup group) =>
      options.isNotEmpty ? options : group.sharedOptions;

  /// "14" or, for a multi-select range, "37–40".
  String get label => numberEnd != null ? '$number–$numberEnd' : '$number';

  factory Question.fromJson(Map<String, dynamic> json) => Question(
    id: json['id'] as int,
    number: (json['number'] as num).toInt(),
    numberEnd: (json['number_end'] as num?)?.toInt(),
    inputCount: (json['input_count'] as num?)?.toInt() ?? 1,
    promptText: json['prompt_text']?.toString() ?? '',
    options: QuestionOption.listFromJson(json['options'] as List?),
  );

  static List<Question> listFromJson(List? raw) =>
      (raw ?? const []).map((e) => Question.fromJson(e as Map<String, dynamic>)).toList();
}

class QuestionGroup {
  const QuestionGroup({
    required this.id,
    required this.order,
    required this.type,
    required this.questionStart,
    required this.questionEnd,
    required this.instructionHtml,
    required this.sharedOptions,
    required this.imageUrl,
    required this.questions,
  });

  final int id;
  final int order;

  /// 'text' | 'single_choice' | 'true_false_ng' | 'multi_select' (or any
  /// future type — treat as an open string, not a closed enum, so the client
  /// doesn't need a release to tolerate a new backend value).
  final String type;
  final int questionStart;
  final int questionEnd;
  final String instructionHtml;
  final List<QuestionOption> sharedOptions;
  final String imageUrl;
  final List<Question> questions;

  factory QuestionGroup.fromJson(Map<String, dynamic> json) => QuestionGroup(
    id: json['id'] as int,
    order: (json['order'] as num?)?.toInt() ?? 0,
    type: json['type']?.toString() ?? 'text',
    questionStart: (json['question_start'] as num?)?.toInt() ?? 0,
    questionEnd: (json['question_end'] as num?)?.toInt() ?? 0,
    instructionHtml: json['instruction_html']?.toString() ?? '',
    sharedOptions: QuestionOption.listFromJson(json['shared_options'] as List?),
    imageUrl: json['image_url']?.toString() ?? '',
    questions: Question.listFromJson(json['questions'] as List?),
  );

  static List<QuestionGroup> listFromJson(List? raw) =>
      (raw ?? const []).map((e) => QuestionGroup.fromJson(e as Map<String, dynamic>)).toList();
}

class TestSection {
  const TestSection({
    required this.id,
    required this.order,
    required this.title,
    required this.bodyHtml,
    required this.instructions,
    required this.questionGroups,
  });

  final int id;
  final int order;
  final String title;
  final String bodyHtml;
  final String instructions;
  final List<QuestionGroup> questionGroups;

  factory TestSection.fromJson(Map<String, dynamic> json) => TestSection(
    id: json['id'] as int,
    order: (json['order'] as num?)?.toInt() ?? 0,
    title: json['title']?.toString() ?? '',
    bodyHtml: json['body_html']?.toString() ?? '',
    instructions: json['instructions']?.toString() ?? '',
    questionGroups: QuestionGroup.listFromJson(json['question_groups'] as List?),
  );

  static List<TestSection> listFromJson(List? raw) =>
      (raw ?? const []).map((e) => TestSection.fromJson(e as Map<String, dynamic>)).toList();
}

class MockTest {
  const MockTest({
    required this.id,
    required this.testType,
    required this.number,
    required this.title,
    required this.durationSeconds,
    required this.audioUrl,
    required this.totalQuestions,
    required this.sortOrder,
    required this.sections,
  });

  final int id;
  final String testType; // 'reading' | 'listening'
  final int number;
  final String title;
  final int durationSeconds;
  final String audioUrl; // '' for reading
  final int totalQuestions;
  final int sortOrder;

  /// Populated on the detail endpoint; empty on the list endpoint.
  final List<TestSection> sections;

  bool get isListening => testType == 'listening';

  factory MockTest.fromJson(Map<String, dynamic> json) => MockTest(
    id: json['id'] as int,
    testType: json['test_type']?.toString() ?? 'reading',
    number: (json['number'] as num?)?.toInt() ?? 0,
    title: json['title']?.toString() ?? '',
    durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 3600,
    audioUrl: json['audio_url']?.toString() ?? '',
    totalQuestions: (json['total_questions'] as num?)?.toInt() ?? 40,
    // Absent from the detail endpoint's response (list-only field) — default
    // to 0 since ordering doesn't matter once a specific test is loaded.
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    sections: TestSection.listFromJson(json['sections'] as List?),
  );

  static List<MockTest> listFromJson(List raw) =>
      raw.map((e) => MockTest.fromJson(e as Map<String, dynamic>)).toList();
}

/// One row of `TestAttempt.result_detail` — mirrors grading.py's
/// `grade_attempt()` per-question breakdown.
class QuestionResult {
  const QuestionResult({
    required this.questionId,
    required this.number,
    this.numberEnd,
    required this.submitted,
    required this.correctAnswer,
    required this.isCorrect,
    required this.pointsEarned,
    required this.pointsAvailable,
  });

  final int questionId;
  final int number;
  final int? numberEnd;

  /// `String`/`List<String>`/null — shape depends on the question type, same
  /// as the answers map sent on submit.
  final dynamic submitted;
  final dynamic correctAnswer;
  final bool isCorrect;
  final int pointsEarned;
  final int pointsAvailable;

  String get label => numberEnd != null ? '$number–$numberEnd' : '$number';

  factory QuestionResult.fromJson(Map<String, dynamic> json) => QuestionResult(
    questionId: json['question_id'] as int,
    number: (json['number'] as num?)?.toInt() ?? 0,
    numberEnd: (json['number_end'] as num?)?.toInt(),
    submitted: json['submitted'],
    correctAnswer: json['correct_answer'],
    isCorrect: json['is_correct'] == true,
    pointsEarned: (json['points_earned'] as num?)?.toInt() ?? 0,
    pointsAvailable: (json['points_available'] as num?)?.toInt() ?? 0,
  );

  static List<QuestionResult> listFromJson(List? raw) =>
      (raw ?? const []).map((e) => QuestionResult.fromJson(e as Map<String, dynamic>)).toList();
}

class MockTestAttempt {
  const MockTestAttempt({
    required this.id,
    required this.testId,
    required this.testTitle,
    required this.testType,
    required this.status,
    required this.startedAt,
    this.submittedAt,
    required this.answers,
    this.rawScore,
    this.maxScore,
    this.bandScore,
    required this.resultDetail,
  });

  final int id;
  final int testId;
  final String testTitle;
  final String testType; // 'reading' | 'listening'
  final String status; // 'in_progress' | 'submitted'
  final String startedAt;
  final String? submittedAt;

  /// question id -> submitted value(s) — inherently polymorphic per question
  /// type, same shape as what's sent on submit; not worth a stronger type.
  final Map<String, dynamic> answers;
  final int? rawScore;
  final int? maxScore;

  /// DRF DecimalField serializes as a string, e.g. "6.5".
  final String? bandScore;
  final List<QuestionResult> resultDetail;

  factory MockTestAttempt.fromJson(Map<String, dynamic> json) {
    final test = (json['test'] as Map?)?.cast<String, dynamic>() ?? const {};
    return MockTestAttempt(
      id: json['id'] as int,
      testId: (test['id'] as num?)?.toInt() ?? 0,
      testTitle: test['title']?.toString() ?? '',
      testType: test['test_type']?.toString() ?? 'reading',
      status: json['status']?.toString() ?? 'in_progress',
      startedAt: json['started_at']?.toString() ?? '',
      submittedAt: json['submitted_at']?.toString(),
      answers: (json['answers'] as Map?)?.cast<String, dynamic>() ?? const {},
      rawScore: (json['raw_score'] as num?)?.toInt(),
      maxScore: (json['max_score'] as num?)?.toInt(),
      bandScore: json['band_score']?.toString(),
      resultDetail: QuestionResult.listFromJson(json['result_detail'] as List?),
    );
  }

  static List<MockTestAttempt> listFromJson(List raw) =>
      raw.map((e) => MockTestAttempt.fromJson(e as Map<String, dynamic>)).toList();
}
