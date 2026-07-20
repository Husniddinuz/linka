// Typed models for tutor-created, paid live-cohort Courses (`/courses/...`).
//
// A [Course] is a seat-limited class that runs over a fixed date window. It is
// NOT self-paced content — delivery happens through the enrolled-only "room"
// (the tutor's [sharedLink] + [announcements]). Mirrors the Django
// `apps.courses` serializers field-for-field.

int _asInt(dynamic v, [int fallback = 0]) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? fallback);

double _asDouble(dynamic v, [double fallback = 0]) => v is num
    ? v.toDouble()
    : double.tryParse('${v ?? ''}') ?? fallback;

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

const _monthAbbr = [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class Course {
  const Course({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.bannerUrl,
    required this.priceUzs,
    required this.maxStudents,
    required this.seatsLeft,
    required this.enrolledCount,
    required this.isFull,
    required this.enrollmentOpen,
    required this.startDate,
    required this.endDate,
    required this.scheduleDetails,
    required this.tutorId,
    required this.tutorName,
    required this.tutorImageUrl,
    required this.isEnrolled,
    required this.isOwner,
    required this.isCancelled,
    required this.sharedLink,
    required this.announcements,
  });

  final int id;
  final String title;
  final String description;
  final String category;
  final String? bannerUrl;
  final double priceUzs;
  final int maxStudents;
  final int seatsLeft;
  final int enrolledCount;
  final bool isFull;
  final bool enrollmentOpen;
  final DateTime? startDate;
  final DateTime? endDate;
  final String scheduleDetails;
  final int tutorId;
  final String tutorName;
  final String? tutorImageUrl;
  final bool isEnrolled;
  final bool isOwner;
  final bool isCancelled;

  /// Detail-only: the meeting/group link, empty unless enrolled or owner.
  final String sharedLink;

  /// Detail-only: the course room feed (empty unless enrolled or owner).
  final List<CourseAnnouncement> announcements;

  bool get isFree => priceUzs <= 0;
  bool get hasStarted =>
      startDate != null && DateTime.now().isAfter(_endOfDay(startDate!));
  bool get hasEnded =>
      endDate != null && DateTime.now().isAfter(_endOfDay(endDate!));

  /// "Free" or a space-grouped amount, e.g. "50 000 so'm".
  String get priceLabel {
    if (isFree) return 'Free';
    final whole = priceUzs.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write(' ');
      buf.write(whole[i]);
    }
    return "$buf so'm";
  }

  /// "15–20 Jun", "28 Jun – 3 Jul", or spanning years "28 Dec 2026 – 3 Jan 2027".
  String get dateRangeLabel {
    final s = startDate, e = endDate;
    if (s == null && e == null) return '';
    if (s == null) return _fmtDay(e!);
    if (e == null) return _fmtDay(s);
    if (s.year != e.year) {
      return '${_fmtDay(s)} ${s.year} – ${_fmtDay(e)} ${e.year}';
    }
    if (s.month == e.month) {
      return '${s.day}–${e.day} ${_monthAbbr[s.month]}';
    }
    return '${_fmtDay(s)} – ${_fmtDay(e)}';
  }

  static String _fmtDay(DateTime d) => '${d.day} ${_monthAbbr[d.month]}';
  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: _asInt(json['id']),
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        bannerUrl: (json['banner_url']?.toString().isEmpty ?? true)
            ? null
            : json['banner_url'].toString(),
        priceUzs: _asDouble(json['price_uzs']),
        maxStudents: _asInt(json['max_students']),
        seatsLeft: _asInt(json['seats_left']),
        enrolledCount: _asInt(json['enrolled_count']),
        isFull: json['is_full'] as bool? ?? false,
        enrollmentOpen: json['enrollment_open'] as bool? ?? false,
        startDate: _asDate(json['start_date']),
        endDate: _asDate(json['end_date']),
        scheduleDetails: json['schedule_details']?.toString() ?? '',
        tutorId: _asInt(json['tutor_id']),
        tutorName: json['tutor_name']?.toString() ?? '',
        tutorImageUrl: (json['tutor_image_url']?.toString().isEmpty ?? true)
            ? null
            : json['tutor_image_url'].toString(),
        isEnrolled: json['is_enrolled'] as bool? ?? false,
        isOwner: json['is_owner'] as bool? ?? false,
        isCancelled: json['is_cancelled'] as bool? ?? false,
        sharedLink: json['shared_link']?.toString() ?? '',
        announcements:
            CourseAnnouncement.listFromJson(json['announcements'] as List?),
      );

  static List<Course> listFromJson(List raw) =>
      raw.map((e) => Course.fromJson(e as Map<String, dynamic>)).toList();
}

class CourseAnnouncement {
  const CourseAnnouncement({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  final int id;
  final String text;
  final DateTime? createdAt;

  factory CourseAnnouncement.fromJson(Map<String, dynamic> json) =>
      CourseAnnouncement(
        id: _asInt(json['id']),
        text: json['text']?.toString() ?? '',
        createdAt: _asDate(json['created_at']),
      );

  static List<CourseAnnouncement> listFromJson(List? raw) => (raw ?? const [])
      .map((e) => CourseAnnouncement.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// One roster row from `/tutor/courses/{id}/enrollments/`.
class CourseEnrollmentRow {
  const CourseEnrollmentRow({
    required this.id,
    required this.studentName,
    required this.studentImageUrl,
    required this.status,
    required this.amountPaidUzs,
    required this.createdAt,
  });

  final int id;
  final String studentName;
  final String? studentImageUrl;
  final String status; // 'paid' | 'refunded'
  final double amountPaidUzs;
  final DateTime? createdAt;

  factory CourseEnrollmentRow.fromJson(Map<String, dynamic> json) =>
      CourseEnrollmentRow(
        id: _asInt(json['id']),
        studentName: json['student_name']?.toString() ?? '',
        studentImageUrl:
            (json['student_image_url']?.toString().isEmpty ?? true)
                ? null
                : json['student_image_url'].toString(),
        status: json['status']?.toString() ?? 'paid',
        amountPaidUzs: _asDouble(json['amount_paid_uzs']),
        createdAt: _asDate(json['created_at']),
      );

  static List<CourseEnrollmentRow> listFromJson(List raw) => raw
      .map((e) => CourseEnrollmentRow.fromJson(e as Map<String, dynamic>))
      .toList();
}
