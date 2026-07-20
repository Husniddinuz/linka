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
  static Future<void> enroll(int courseId) async {
    try {
      await ApiService.post('/courses/$courseId/enroll/', {});
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
    required String scheduleDetails,
    required String sharedLink,
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
      'schedule_details': scheduleDetails,
      'shared_link': sharedLink,
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
