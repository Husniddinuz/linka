import 'dart:io';

import '../models/course.dart';
import 'api_service.dart';

/// Tutor-created, paid live-cohort Courses.
///
/// Student-facing: browse the catalogue, open a course, enroll (wallet payment
/// handled server-side, mirroring paid bookings). Tutor-facing: create/edit/
/// cancel own courses, view the roster, post announcements.
class CourseService {
  // ─── Student-facing ────────────────────────────────────────────────────────

  static Future<List<Course>> fetchCourses() async {
    final data = await ApiService.getList('/courses/');
    return Course.listFromJson(data);
  }

  static Future<Course> fetchCourse(int id) async {
    final data = await ApiService.get('/courses/$id/');
    final map = (data['data'] as Map<String, dynamic>?) ?? data;
    return Course.fromJson(map);
  }

  /// Enroll (and pay from wallet). Throws [InsufficientBalanceException] when
  /// the wallet is short, so the caller can route to top-up; other failures
  /// surface as the usual [ApiException].
  ///
  /// Returns the slug of the course's chat channel — paying is what admits the
  /// student to it, so the UI can offer to open the chat straight away.
  static Future<String?> enroll(int courseId) async {
    try {
      final res = await ApiService.post('/courses/$courseId/enroll/', {});
      final payload = (res['data'] as Map<String, dynamic>?) ?? res;
      final slug = payload['chat_channel_slug']?.toString() ?? '';
      return slug.isEmpty ? null : slug;
    } on ApiException catch (e) {
      if (e.message.toLowerCase().contains('insufficient')) {
        throw InsufficientBalanceException(e.message);
      }
      rethrow;
    }
  }

  static Future<List<CourseAnnouncement>> fetchAnnouncements(int courseId) async {
    final data = await ApiService.getList('/courses/$courseId/announcements/');
    return CourseAnnouncement.listFromJson(data);
  }

  /// Get a Daily.co room URL + token for the live session. Throws
  /// [SessionNotLiveException] when the session isn't currently in its window
  /// (so the caller can show "starts at …" instead of a raw error).
  static Future<CourseJoinInfo> joinSession(int courseId) async {
    try {
      final res = await ApiService.post('/courses/$courseId/join/', {});
      final payload = (res['data'] as Map<String, dynamic>?) ?? res;
      final roomUrl = (payload['joinUrl'] ??
              payload['join_url'] ??
              payload['room_url'] ??
              '')
          .toString();
      final token = (payload['token'] ?? '').toString();
      return CourseJoinInfo(roomUrl: roomUrl, token: token);
    } on ApiException catch (e) {
      // The join endpoint returns 400 with session_active:false outside the window.
      final msg = e.message.toLowerCase();
      if (msg.contains("isn't live") || msg.contains('not live') ||
          msg.contains('session')) {
        throw SessionNotLiveException(e.message);
      }
      rethrow;
    }
  }

  /// Search active tutors by name for the co-tutor picker.
  static Future<List<TutorSearchResult>> searchTutors(String query) async {
    final q = Uri.encodeQueryComponent(query);
    final data = await ApiService.getList('/tutors/?search=$q');
    return TutorSearchResult.listFromJson(data);
  }

  // ─── Tutor self-service ────────────────────────────────────────────────────

  static Future<List<Course>> fetchMyCourses() async {
    final data = await ApiService.getList('/tutor/courses/my/');
    return Course.listFromJson(data);
  }

  static Future<Course> createCourse({
    required String title,
    required String description,
    required String category,
    required double priceUzs,
    required int maxStudents,
    required DateTime startDate,
    required DateTime endDate,
    required String startTime, // "HH:MM"
    required String endTime, // "HH:MM"
    required String scheduleDetails,
    int? coTutorId,
    File? banner,
  }) async {
    final fields = <String, String>{
      'title': title,
      'description': description,
      'category': category,
      'price_uzs': priceUzs.toStringAsFixed(2),
      'max_students': '$maxStudents',
      'start_date': _fmtDate(startDate),
      'end_date': _fmtDate(endDate),
      'start_time': startTime,
      'end_time': endTime,
      'schedule_details': scheduleDetails,
      if (coTutorId != null) 'co_tutor_id': '$coTutorId',
    };
    final data = await ApiService.postMultipart(
      '/tutor/courses/',
      files: banner != null ? {'banner': banner} : const {},
      fields: fields,
    );
    return Course.fromJson(data);
  }

  /// Partial edit of text fields (banner is set at create time). The backend
  /// rejects locked fields (price/dates) once anyone has enrolled.
  static Future<void> updateCourse(int courseId, Map<String, dynamic> fields) {
    return ApiService.patch('/tutor/courses/$courseId/', fields);
  }

  static Future<void> cancelCourse(int courseId) {
    return ApiService.post('/tutor/courses/$courseId/cancel/', {});
  }

  static Future<List<CourseEnrollmentRow>> fetchEnrollments(int courseId) async {
    final data = await ApiService.getList('/tutor/courses/$courseId/enrollments/');
    return CourseEnrollmentRow.listFromJson(data);
  }

  static Future<CourseAnnouncement> postAnnouncement(int courseId, String text) async {
    final data =
        await ApiService.post('/courses/$courseId/announcements/', {'text': text});
    return CourseAnnouncement.fromJson(data);
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Thrown by [CourseService.enroll] when the student's wallet can't cover the
/// price — the UI routes the student to top-up instead of showing a raw error.
class InsufficientBalanceException implements Exception {
  final String message;
  const InsufficientBalanceException(this.message);
  @override
  String toString() => message;
}

/// Thrown by [CourseService.joinSession] when the session isn't in its live
/// window — the UI shows the schedule instead of an error.
class SessionNotLiveException implements Exception {
  final String message;
  const SessionNotLiveException(this.message);
  @override
  String toString() => message;
}

/// Daily.co room URL + token returned by [CourseService.joinSession].
class CourseJoinInfo {
  final String roomUrl;
  final String token;
  const CourseJoinInfo({required this.roomUrl, required this.token});
}
