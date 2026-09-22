// Typed models for Course Reels (`/course-reels/...`): admin-authored,
// self-paced video courses watched as a vertical feed.
//
// Not to be confused with [Course] (`lib/models/course.dart`), which is a
// tutor-run paid live cohort. Mirrors the Django `apps.course_reels`
// serializers field-for-field.

int _asInt(dynamic v, [int fallback = 0]) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? fallback);

double _asDouble(dynamic v, [double fallback = 0]) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? fallback;

String? _nonEmpty(dynamic v) {
  final s = v?.toString() ?? '';
  return s.isEmpty ? null : s;
}

List<String> _asStrings(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : const [];

class ReelLanguage {
  const ReelLanguage({required this.language, required this.courseCount});

  final String language;
  final int courseCount;

  factory ReelLanguage.fromJson(Map<String, dynamic> json) => ReelLanguage(
    language: json['language']?.toString() ?? '',
    courseCount: _asInt(json['course_count']),
  );
}

/// The student's standing in one lesson — drives the two map markers:
/// yellow once [watched], green once [completed].
class ReelLessonProgress {
  const ReelLessonProgress({
    required this.positionSeconds,
    required this.durationSeconds,
    required this.watched,
    required this.practiceCompleted,
    required this.completed,
  });

  static const empty = ReelLessonProgress(
    positionSeconds: 0,
    durationSeconds: 0,
    watched: false,
    practiceCompleted: false,
    completed: false,
  );

  final double positionSeconds;
  final double durationSeconds;
  final bool watched;
  final bool practiceCompleted;

  /// Watched, and the required practice is done (or the lesson has none).
  final bool completed;

  /// The same progress once the video has been seen — what the feed shows
  /// straight away, before the server confirms.
  ReelLessonProgress markWatched({required bool practiceRequired}) =>
      ReelLessonProgress(
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds,
        watched: true,
        practiceCompleted: practiceCompleted,
        completed: practiceCompleted || !practiceRequired,
      );

  factory ReelLessonProgress.fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    return ReelLessonProgress(
      positionSeconds: _asDouble(json['position_seconds']),
      durationSeconds: _asDouble(json['duration_seconds']),
      watched: json['watched'] as bool? ?? false,
      practiceCompleted: json['practice_completed'] as bool? ?? false,
      completed: json['completed'] as bool? ?? false,
    );
  }
}

class ReelLesson {
  ReelLesson({
    required this.id,
    required this.courseId,
    required this.courseTitle,
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.videoUrlExpiresAt,
    required this.posterUrl,
    required this.durationSeconds,
    required this.likeCount,
    required this.commentCount,
    required this.exerciseCount,
    required this.liked,
    required this.saved,
    required this.practiceRequired,
    required this.progress,
  });

  final int id;
  final int courseId;
  final String courseTitle;
  final String title;
  final String description;
  final String? posterUrl;
  final int durationSeconds;
  final int exerciseCount;
  final bool practiceRequired;

  /// Uploaded videos are served through signed links that stop working at
  /// [videoUrlExpiresAt]; the feed swaps in fresh ones (CDN links never expire).
  String? videoUrl;
  DateTime? videoUrlExpiresAt;

  /// True when [videoUrl] is dead or about to be — fetch a new one first.
  bool get videoUrlExpiring {
    final at = videoUrlExpiresAt;
    return at != null &&
        DateTime.now().isAfter(at.subtract(const Duration(minutes: 2)));
  }

  // Mutable: the feed flips these optimistically and after server replies.
  int likeCount;
  int commentCount;
  bool liked;
  bool saved;
  ReelLessonProgress progress;

  bool get hasPractice => exerciseCount > 0;

  factory ReelLesson.fromJson(Map<String, dynamic> json) => ReelLesson(
    id: _asInt(json['id']),
    courseId: _asInt(json['course_id']),
    courseTitle: json['course_title']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    videoUrl: _nonEmpty(json['video_url']),
    videoUrlExpiresAt: json['video_url_expires_at'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (json['video_url_expires_at'] as num).toInt() * 1000,
          )
        : null,
    posterUrl: _nonEmpty(json['poster_url']),
    durationSeconds: _asInt(json['duration_seconds']),
    likeCount: _asInt(json['like_count']),
    commentCount: _asInt(json['comment_count']),
    exerciseCount: _asInt(json['exercise_count']),
    liked: json['liked'] as bool? ?? false,
    saved: json['saved'] as bool? ?? false,
    practiceRequired: json['practice_required'] as bool? ?? false,
    progress: ReelLessonProgress.fromJson(
      json['progress'] as Map<String, dynamic>?,
    ),
  );

  static List<ReelLesson> listFromJson(List? raw) => (raw ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(ReelLesson.fromJson)
      .toList();
}

class ReelCourse {
  const ReelCourse({
    required this.id,
    required this.title,
    required this.description,
    required this.language,
    required this.level,
    required this.coverUrl,
    required this.lessonsCount,
    required this.watchedCount,
    required this.completedCount,
    required this.lastLessonId,
    required this.started,
    this.lessons = const [],
  });

  final int id;
  final String title;
  final String description;
  final String language;
  final String level;
  final String? coverUrl;
  final int lessonsCount;
  final int watchedCount;
  final int completedCount;
  final int? lastLessonId;
  final bool started;

  /// Only filled by the detail endpoint.
  final List<ReelLesson> lessons;

  double get completedFraction =>
      lessonsCount == 0 ? 0 : (completedCount / lessonsCount).clamp(0.0, 1.0);

  factory ReelCourse.fromJson(Map<String, dynamic> json) => ReelCourse(
    id: _asInt(json['id']),
    title: json['title']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    language: json['language']?.toString() ?? '',
    level: json['level']?.toString() ?? '',
    coverUrl: _nonEmpty(json['cover_url']),
    lessonsCount: _asInt(json['lessons_count']),
    watchedCount: _asInt(json['watched_count']),
    completedCount: _asInt(json['completed_count']),
    lastLessonId: json['last_lesson_id'] == null
        ? null
        : _asInt(json['last_lesson_id']),
    started: json['started'] as bool? ?? false,
    lessons: ReelLesson.listFromJson(json['lessons'] as List?),
  );

  static List<ReelCourse> listFromJson(List? raw) => (raw ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(ReelCourse.fromJson)
      .toList();
}

/// Where the student left off, according to the server.
class ReelResume {
  const ReelResume({
    required this.course,
    required this.lesson,
    required this.positionSeconds,
  });

  final ReelCourse? course;
  final ReelLesson? lesson;
  final double positionSeconds;

  factory ReelResume.fromJson(Map<String, dynamic> json) => ReelResume(
    course: json['course'] is Map<String, dynamic>
        ? ReelCourse.fromJson(json['course'] as Map<String, dynamic>)
        : null,
    lesson: json['lesson'] is Map<String, dynamic>
        ? ReelLesson.fromJson(json['lesson'] as Map<String, dynamic>)
        : null,
    positionSeconds: _asDouble(json['position_seconds']),
  );
}

enum ReelExerciseType { sentenceBuilding, fillGaps, writeSentence, unknown }

ReelExerciseType _exerciseType(String? raw) => switch (raw) {
  'sentence_building' => ReelExerciseType.sentenceBuilding,
  'fill_gaps' => ReelExerciseType.fillGaps,
  'write_sentence' => ReelExerciseType.writeSentence,
  _ => ReelExerciseType.unknown,
};

/// One piece of a fill-in-the-gaps text: plain [text], or a gap at [gapIndex].
class ReelGapSegment {
  const ReelGapSegment.text(this.text) : gapIndex = null;
  const ReelGapSegment.gap(int this.gapIndex) : text = '';

  final String text;
  final int? gapIndex;

  bool get isGap => gapIndex != null;

  factory ReelGapSegment.fromJson(Map<String, dynamic> json) =>
      json['type'] == 'gap'
      ? ReelGapSegment.gap(_asInt(json['index']))
      : ReelGapSegment.text(json['value']?.toString() ?? '');
}

class ReelExercise {
  ReelExercise({
    required this.id,
    required this.type,
    required this.instruction,
    required this.hint,
    required this.isRequired,
    required this.tiles,
    required this.segments,
    required this.gapCount,
    required this.prompt,
    required this.requiredWords,
    required this.minWords,
    required this.solved,
    required this.attempts,
    required this.expected,
    required this.sampleAnswer,
  });

  final int id;
  final ReelExerciseType type;
  final String instruction;
  final String hint;
  final bool isRequired;
  final List<String> tiles;
  final List<ReelGapSegment> segments;
  final int gapCount;
  final String prompt;
  final List<String> requiredWords;
  final int minWords;

  bool solved;
  int attempts;
  String? expected;
  String? sampleAnswer;

  /// The line shown above the task when the admin left [instruction] empty.
  String get displayInstruction {
    if (instruction.isNotEmpty) return instruction;
    return switch (type) {
      ReelExerciseType.sentenceBuilding => 'Put the words in the right order',
      ReelExerciseType.fillGaps => 'Fill in the gaps',
      ReelExerciseType.writeSentence => 'Write a complete sentence',
      ReelExerciseType.unknown => 'Practice',
    };
  }

  factory ReelExercise.fromJson(Map<String, dynamic> json) => ReelExercise(
    id: _asInt(json['id']),
    type: _exerciseType(json['type']?.toString()),
    instruction: json['instruction']?.toString() ?? '',
    hint: json['hint']?.toString() ?? '',
    isRequired: json['is_required'] as bool? ?? true,
    tiles: _asStrings(json['tiles']),
    segments: (json['segments'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReelGapSegment.fromJson)
        .toList(),
    gapCount: _asInt(json['gap_count']),
    prompt: json['prompt']?.toString() ?? '',
    requiredWords: _asStrings(json['required_words']),
    minWords: _asInt(json['min_words']),
    solved: json['solved'] as bool? ?? false,
    attempts: _asInt(json['attempts']),
    expected: _nonEmpty(json['expected']),
    sampleAnswer: _nonEmpty(json['sample_answer']),
  );
}

class ReelPractice {
  const ReelPractice({required this.exercises, required this.progress});

  final List<ReelExercise> exercises;
  final ReelLessonProgress progress;

  factory ReelPractice.fromJson(Map<String, dynamic> json) => ReelPractice(
    exercises: (json['exercises'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReelExercise.fromJson)
        .toList(),
    progress: ReelLessonProgress.fromJson(
      json['progress'] as Map<String, dynamic>?,
    ),
  );
}

class ReelAnswerResult {
  const ReelAnswerResult({
    required this.correct,
    required this.feedback,
    required this.gapResults,
    required this.solved,
    required this.attempts,
    required this.expected,
    required this.sampleAnswer,
    required this.lessonProgress,
  });

  final bool correct;
  final String feedback;
  final List<bool>? gapResults;
  final bool solved;
  final int attempts;
  final String? expected;
  final String? sampleAnswer;
  final ReelLessonProgress lessonProgress;

  factory ReelAnswerResult.fromJson(Map<String, dynamic> json) =>
      ReelAnswerResult(
        correct: json['correct'] as bool? ?? false,
        feedback: json['feedback']?.toString() ?? '',
        gapResults: json['gap_results'] is List
            ? (json['gap_results'] as List).map((e) => e == true).toList()
            : null,
        solved: json['solved'] as bool? ?? false,
        attempts: _asInt(json['attempts']),
        expected: _nonEmpty(json['expected']),
        sampleAnswer: _nonEmpty(json['sample_answer']),
        lessonProgress: ReelLessonProgress.fromJson(
          json['lesson_progress'] as Map<String, dynamic>?,
        ),
      );
}

class ReelComment {
  const ReelComment({
    required this.id,
    required this.text,
    required this.authorName,
    required this.authorImage,
    required this.isMine,
    required this.createdAt,
  });

  final int id;
  final String text;
  final String authorName;
  final String? authorImage;
  final bool isMine;
  final DateTime? createdAt;

  factory ReelComment.fromJson(Map<String, dynamic> json) => ReelComment(
    id: _asInt(json['id']),
    text: json['text']?.toString() ?? '',
    authorName: json['author_name']?.toString() ?? '',
    authorImage: _nonEmpty(json['author_image']),
    isMine: json['is_mine'] as bool? ?? false,
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
  );
}
