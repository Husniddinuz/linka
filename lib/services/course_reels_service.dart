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

  /// One page of comments, newest first, plus the total count.
  static Future<(List<ReelComment>, int)> fetchComments(
    int lessonId, {
    int offset = 0,
    int limit = 30,
  }) async {
    final data = await ApiService.get(
      '/course-reels/lessons/$lessonId/comments/?limit=$limit&offset=$offset',
    );
    final items = (data['results'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReelComment.fromJson)
        .toList();
    return (items, (data['count'] as num?)?.toInt() ?? items.length);
  }

  static Future<ReelComment> postComment(int lessonId, String text) async =>
      ReelComment.fromJson(
        await ApiService.post('/course-reels/lessons/$lessonId/comments/', {
          'text': text,
        }),
      );

  static Future<void> deleteComment(int commentId) =>
      ApiService.delete('/course-reels/comments/$commentId/');

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
