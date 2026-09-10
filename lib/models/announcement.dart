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

  /// Set on app release notes: the version they describe. Empty otherwise.
  final String minAppVersion;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.target,
    required this.imageUrl,
    required this.audience,
    required this.courseId,
    this.minAppVersion = '',
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
      minAppVersion: json['min_app_version']?.toString().trim() ?? '',
    );
  }

  /// True for the card a new course made for itself.
  bool get isCourse => courseId != null;

  /// A "what's new in this version" card rather than a single feature.
  bool get isReleaseNotes => minAppVersion.isNotEmpty;

  /// The button leads nowhere past the popup (release notes usually point
  /// at `/`), so a second "Maybe later" button would be noise.
  bool get dismissOnly {
    final t = target.trim();
    return t.isEmpty || t == '/';
  }

  static final _bullet = RegExp(r'^[-•*]\s+');

  /// [body] line by line, with `- ` lines flagged as checklist items. Staff
  /// write release notes that way; plain prose has no bullets at all.
  List<({bool bullet, String text})> get bodyLines => [
        for (final raw in body.split('\n'))
          if (raw.trim().isNotEmpty)
            _bullet.hasMatch(raw.trim())
                ? (bullet: true, text: raw.trim().replaceFirst(_bullet, ''))
                : (bullet: false, text: raw.trim()),
      ];

  bool get hasChecklist => bodyLines.any((l) => l.bullet);
}
