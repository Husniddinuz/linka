import '../models/course_reel.dart';
import 'api_service.dart';

/// REST client for Course Reels (`/course-reels/...`). Stateless — screens
/// hold the data. Playback position goes through [CourseReelsResumeService],
/// which batches it before calling [saveProgress].
class CourseReelsService {
  CourseReelsService._();

  static Future<List<ReelLanguage>> fetchLanguages() async {
    final raw = await ApiService.getList('/course-reels/languages/');
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ReelLanguage.fromJson)
        .toList();
  }

  static Future<List<ReelCourse>> fetchCourses({String? language}) async {
    final query = (language == null || language.isEmpty)
        ? ''
        : '?language=${Uri.encodeQueryComponent(language)}';
    return ReelCourse.listFromJson(
      await ApiService.getList('/course-reels/courses/$query'),
    );
  }

  /// Courses split into sections — the home screen's subject tiles. Listed
  /// even before their first lesson is uploaded.
  static Future<List<ReelCourse>> fetchSectionedCourses() async =>
      ReelCourse.listFromJson(
        await ApiService.getList('/course-reels/courses/?with_sections=1'),
      );

  /// Pays one period of the Course Reels subscription from the wallet; a
  /// running one is extended. Throws [ReelInsufficientBalance] (nothing
  /// charged) when the balance is short.
  static Future<ReelSubscription> subscribe() async {
    try {
      return ReelSubscription.fromJson(
        await ApiService.post('/course-reels/subscription/', const {}),
      );
    } on ApiException catch (e) {
      if (e.errorCode == 'insufficient_balance') {
        int uzs(String key) =>
            double.tryParse('${e.data?[key] ?? ''}')?.ceil() ?? 0;
        throw ReelInsufficientBalance(
          priceUzs: uzs('required_uzs'),
          balanceUzs: uzs('balance_uzs'),
          shortfallUzs: uzs('shortfall_uzs'),
        );
      }
      rethrow;
    }
  }

  /// The course with every lesson — the feed and the progress map both read it.
  static Future<ReelCourse> fetchCourse(int id) async =>
      ReelCourse.fromJson(await ApiService.get('/course-reels/courses/$id/'));

  /// Makes [id] the student's current course (what the home card resumes).
  static Future<void> startCourse(int id) =>
      ApiService.post('/course-reels/courses/$id/start/', const {});

  static Future<ReelResume> fetchResume() async =>
      ReelResume.fromJson(await ApiService.get('/course-reels/resume/'));

  static Future<ReelLessonProgress> saveProgress(
    int lessonId, {
    required double positionSeconds,
    required double durationSeconds,
    bool completed = false,
  }) async {
    final data =
        await ApiService.post('/course-reels/lessons/$lessonId/progress/', {
          'position_seconds': positionSeconds,
          'duration_seconds': durationSeconds,
          'completed': completed,
        });
    return ReelLessonProgress.fromJson(data);
  }

  /// Returns (liked, likeCount) as the server now has them.
  static Future<(bool, int)> setLiked(int lessonId, bool liked) async {
    final path = '/course-reels/lessons/$lessonId/like/';
    final data = liked
        ? await ApiService.post(path, const {})
        : await ApiService.delete(path);
    return (
      data['liked'] as bool? ?? liked,
      (data['like_count'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<bool> setSaved(int lessonId, bool saved) async {
    final path = '/course-reels/lessons/$lessonId/save/';
    final data = saved
        ? await ApiService.post(path, const {})
        : await ApiService.delete(path);
    return data['saved'] as bool? ?? saved;
  }

  static Future<List<ReelLesson>> fetchSaved() async =>
      ReelLesson.listFromJson(await ApiService.getList('/course-reels/saved/'));

  /// One page of top-level comments, newest first, plus how many there are.
  static Future<(List<ReelComment>, int)> fetchComments(
    int lessonId, {
    int offset = 0,
    int limit = 30,
  }) => _commentPage(
    '/course-reels/lessons/$lessonId/comments/?limit=$limit&offset=$offset',
  );

  /// One page of replies to [commentId], oldest first, plus how many there are.
  static Future<(List<ReelComment>, int)> fetchReplies(
    int commentId, {
    int offset = 0,
    int limit = 30,
  }) => _commentPage(
    '/course-reels/comments/$commentId/replies/?limit=$limit&offset=$offset',
  );

  static Future<(List<ReelComment>, int)> _commentPage(String path) async {
    final data = await ApiService.get(path);
    final items = (data['results'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReelComment.fromJson)
        .toList();
    return (items, (data['count'] as num?)?.toInt() ?? items.length);
  }

  /// Posts a comment, or a reply when [parentId] is set. The server moves a
  /// reply to a reply onto its root.
  static Future<ReelComment> postComment(
    int lessonId,
    String text, {
    int? parentId,
  }) async => ReelComment.fromJson(
    await ApiService.post('/course-reels/lessons/$lessonId/comments/', {
      'text': text,
      'parent': ?parentId,
    }),
  );

  static Future<ReelComment> editComment(int commentId, String text) async =>
      ReelComment.fromJson(
        await ApiService.patch('/course-reels/comments/$commentId/', {
          'text': text,
        }),
      );

  static Future<void> deleteComment(int commentId) =>
      ApiService.delete('/course-reels/comments/$commentId/');

  /// Returns (liked, likeCount) as the server now has them.
  static Future<(bool, int)> setCommentLiked(int commentId, bool liked) async {
    final path = '/course-reels/comments/$commentId/like/';
    final data = liked
        ? await ApiService.post(path, const {})
        : await ApiService.delete(path);
    return (
      data['liked'] as bool? ?? liked,
      (data['like_count'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<ReelPractice> fetchPractice(int lessonId) async =>
      ReelPractice.fromJson(
        await ApiService.get('/course-reels/lessons/$lessonId/practice/'),
      );

  /// [answer]: tiles in order (sentence building), one string per gap
  /// (fill gaps) or the sentence (write a sentence).
  static Future<ReelAnswerResult> submitAnswer(
    int exerciseId,
    Object answer,
  ) async => ReelAnswerResult.fromJson(
    await ApiService.post('/course-reels/exercises/$exerciseId/submit/', {
      'answer': answer,
    }),
  );
}

/// The wallet can't cover a section; [shortfallUzs] is what a top-up needs
/// to add before [CourseReelsService.subscribe] goes through.
class ReelInsufficientBalance implements Exception {
  const ReelInsufficientBalance({
    required this.priceUzs,
    required this.balanceUzs,
    required this.shortfallUzs,
  });

  final int priceUzs;
  final int balanceUzs;
  final int shortfallUzs;

  @override
  String toString() => 'Insufficient wallet balance';
}
