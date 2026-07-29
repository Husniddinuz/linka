import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/course.dart';
import '../theme/app_colors.dart';
import 'cached_avatar.dart';

/// Full-width card for a live-cohort [Course]: a banner (uploaded image or a
/// gradient placeholder) carrying the price + status badge, over the title,
/// tutor byline, and a meta row (date range + seats). Used in the courses list
/// and the tutor's "My Courses" list.
class CourseCard extends StatelessWidget {
  final Course course;
  final Color accent;
  final VoidCallback onTap;

  /// Manage affordance for the tutor's own list (shows a subtle chevron and,
  /// for cancelled courses, a muted overlay).
  final bool tutorView;

  const CourseCard({
    super.key,
    required this.course,
    required this.accent,
    required this.onTap,
    this.tutorView = false,
  });

  static const _palette = [
    Color(0xFF4776E6),
    Color(0xFF11998E),
    Color(0xFFEB3349),
    Color(0xFFF7971E),
    Color(0xFF8E54E9),
    Color(0xFF1D976C),
  ];

  static Color accentFor(int index) => _palette[index.abs() % _palette.length];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: course.isCancelled ? 0.6 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 8,
                child: _Banner(course: course, accent: accent),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        CachedAvatar(
                          imageUrl: course.tutorImageUrl,
                          size: 22,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            course.tutorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        if (tutorView)
                          Icon(Icons.chevron_right,
                              size: 20, color: colors.textTertiary),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MetaChip(
                          icon: Symbols.calendar_month_rounded,
                          label: _dateLabel,
                          colors: colors,
                        ),
                        const SizedBox(width: 8),
                        _MetaChip(
                          icon: Symbols.group_rounded,
                          label: _seatsLabel,
                          colors: colors,
                          emphasize: course.isFull && !course.isEnrolled,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _seatsLabel {
    if (course.isFull) return 'Sold out';
    return '${course.seatsLeft} of ${course.maxStudents} left';
  }

  /// "1 month · 15 Aug – 15 Sep · 16:00" — the length leads, since that is what
  /// a student comparing courses is really weighing.
  String get _dateLabel {
    return [
      if (course.durationLabel.isNotEmpty) course.durationLabel,
      if (course.dateRangeLabel.isNotEmpty) course.dateRangeLabel,
      if (course.startTime != null) course.startTime!,
    ].join(' · ');
  }
}

class _Banner extends StatelessWidget {
  final Course course;
  final Color accent;
  const _Banner({required this.course, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        _placeholder(),
        if (course.bannerUrl != null)
          Image.network(
            course.bannerUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        // Price pill (top-left)
        Positioned(
          top: 10,
          left: 10,
          child: _Pill(
            text: course.priceLabel,
            bg: Colors.black.withValues(alpha: 0.42),
            fg: Colors.white,
          ),
        ),
        // Status badge (top-right)
        if (_statusBadge != null)
          Positioned(top: 10, right: 10, child: _statusBadge!),
      ],
    );
  }

  Widget? get _statusBadge {
    if (course.isCancelled) {
      return const _Pill(text: 'Cancelled', bg: Color(0xCC4A4A4A), fg: Colors.white);
    }
    if (course.sessionActiveNow) {
      return const _Pill(text: '● LIVE', bg: Color(0xE6E23A3A), fg: Colors.white);
    }
    if (course.isEnrolled) {
      return const _Pill(text: 'Enrolled', bg: Color(0xE627AE60), fg: Colors.white);
    }
    if (course.isFull) {
      return const _Pill(text: 'Sold out', bg: Color(0xE6E74C3C), fg: Colors.white);
    }
    if (course.hasStarted) {
      return const _Pill(text: 'Started', bg: Color(0xCC4A4A4A), fg: Colors.white);
    }
    return null;
  }

  Widget _placeholder() {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent, Color.lerp(accent, Colors.black, 0.30)!],
            ),
          ),
        ),
        Positioned(
          top: -30,
          right: -20,
          child: _circle(120, Colors.white.withValues(alpha: 0.10)),
        ),
        Center(
          child: Icon(
            Symbols.school_rounded,
            size: 40,
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ),
      ],
    );
  }

  Widget _circle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

class _Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Pill({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppColors colors;
  final bool emphasize;
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.colors,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final color = emphasize ? colors.error : colors.textSecondary;
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
