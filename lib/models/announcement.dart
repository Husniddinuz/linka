/// One "what's new" card from `GET /announcements/`.
///
/// Shown once per account as a popup on the home screen; tapping the button
/// opens [target], which is an in-product path (`/courses/12`, `/ai-coach`)
/// or a full URL. See `AnnouncementTarget` for how a path becomes a screen.
class Announcement {
  final int id;
  final String title;
  final String body;
  final String ctaLabel;
  final String target;
  final String? imageUrl;
  final String audience;
  final int? courseId;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.target,
    required this.imageUrl,
    required this.audience,
    required this.courseId,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    final image = json['image_url']?.toString();
    final cta = json['cta_label']?.toString().trim();
    return Announcement(
      id: json['id'] is int ? json['id'] as int : int.parse('${json['id']}'),
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      ctaLabel: (cta == null || cta.isEmpty) ? 'Check it out' : cta,
      target: json['target']?.toString() ?? '/',
      imageUrl: (image == null || image.isEmpty) ? null : image,
      audience: json['audience']?.toString() ?? 'students',
      courseId: json['course'] is int ? json['course'] as int : null,
    );
  }

  /// True for the card a new course made for itself.
  bool get isCourse => courseId != null;
}
