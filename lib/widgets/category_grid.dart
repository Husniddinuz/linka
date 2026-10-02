import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/course_reel.dart';
import '../models/student_progress.dart';
import '../screens/student_progress_screen.dart';
import '../services/app_feature_service.dart';
import '../services/course_reels_service.dart';
import '../services/student_progress_service.dart';
import '../theme/app_colors.dart';
import '../utils/course_icons.dart';

/// The subjects the home screen offers, in the order the grid shows them.
/// [progress] isn't a subject — it's the student's own stats, pinned first.
enum HomeCategory {
  progress,
  ielts,
  sat,
  biologiya,
  onaTili,
  matematika,
  tarix,
  fizika,
}

class _CategorySpec {
  final String label;
  final IconData icon;
  const _CategorySpec(this.label, this.icon);
}

const _specs = <HomeCategory, _CategorySpec>{
  HomeCategory.progress:
      _CategorySpec('Your progress', Symbols.trending_up_rounded),
  HomeCategory.ielts:
      _CategorySpec('IELTS', Symbols.language_rounded),
  HomeCategory.sat:
      _CategorySpec('SAT', Symbols.school_rounded),
  HomeCategory.biologiya:
      _CategorySpec('Biologiya', Symbols.genetics_rounded),
  HomeCategory.onaTili:
      _CategorySpec('Ona tili', Symbols.menu_book_rounded),
  HomeCategory.matematika:
      _CategorySpec('Matematika', Symbols.calculate_rounded),
  HomeCategory.tarix:
      _CategorySpec('Tarix', Symbols.history_edu_rounded),
  HomeCategory.fizika:
      _CategorySpec('Fizika', Symbols.bolt_rounded),
};

/// Rows of four: "Your progress" first, then the courses an admin has set
/// up with sections (their own title and icon), then the subjects that are
/// still coming soon. Replaces the old stats strip — the stats now live
/// behind the first tile.
///
/// The `course_reels_home` flag hides every tile but "Your progress"; a lone
/// quarter-width tile looks broken, so it becomes a full-width card with the
/// latest band per skill instead.
class CategoryGrid extends StatefulWidget {
  const CategoryGrid({super.key, required this.onOpenCourse});

  /// A course path opens inside the Home tab, which owns that state.
  final ValueChanged<ReelCourse> onOpenCourse;

  @override
  State<CategoryGrid> createState() => CategoryGridState();
}

class CategoryGridState extends State<CategoryGrid> {
  /// Remote flag key for the course + subject tiles.
  static const coursesFlag = 'course_reels_home';

  List<ReelCourse> _courses = const [];
  Future<StudentProgress>? _progress;

  bool get _showCourses => AppFeatureService.isEnabled(coursesFlag);

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Re-reads the course list; the home screen calls it on pull-to-refresh.
  Future<void> refresh() async {
    // Only the card reads the stats, so they're fetched only while it shows.
    if (!_showCourses) {
      setState(() => _progress = StudentProgressService.fetch());
    }
    try {
      final courses = await CourseReelsService.fetchSectionedCourses();
      if (mounted) setState(() => _courses = courses);
    } catch (_) {
      // Keep whatever is showing; the placeholders still render.
    }
  }

  void _comingSoon(String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label — coming soon')));
  }

  void _openProgress() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const StudentProgressScreen()),
  );

  @override
  Widget build(BuildContext context) {
    if (!_showCourses) {
      // The flag can flip mid-session (the home screen rebuilds on it).
      _progress ??= StudentProgressService.fetch();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: FutureBuilder<StudentProgress>(
          future: _progress,
          builder: (context, snapshot) => _ProgressCard(
            progress: snapshot.data,
            loading: snapshot.connectionState != ConnectionState.done,
            onTap: _openProgress,
          ),
        ),
      );
    }

    final progress = _specs[HomeCategory.progress]!;
    final tiles = <Widget>[
      _CategoryTile(
        spec: progress,
        onTap: _openProgress,
      ),
      for (final course in _courses)
        _CategoryTile(
          spec: _CategorySpec(course.title, courseIcon(course.icon)),
          onTap: () => widget.onOpenCourse(course),
        ),
      // Subjects without a course yet. The IELTS placeholder steps aside
      // once any real course is up.
      for (final category in HomeCategory.values.skip(1))
        if (category != HomeCategory.ielts || _courses.isEmpty)
          _CategoryTile(
            spec: _specs[category]!,
            onTap: () => _comingSoon(_specs[category]!.label),
          ),
    ];

    Widget row(List<Widget> items) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: i < items.length ? items[i] : const SizedBox()),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        children: [
          for (var start = 0; start < tiles.length; start += 4) ...[
            if (start > 0) const SizedBox(height: 16),
            row(tiles.sublist(start, (start + 4).clamp(0, tiles.length))),
          ],
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final _CategorySpec spec;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.spec,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                spec.icon,
                size: 36,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              spec.label,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Your progress" on its own: what the tile opens, with the latest band of
/// each skill so the card earns its width.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.progress,
    required this.loading,
    required this.onTap,
  });

  /// Null while loading or when every source failed.
  final StudentProgress? progress;
  final bool loading;
  final VoidCallback onTap;

  String get _subtitle {
    final p = progress;
    if (p == null) {
      return loading ? 'Loading your bands…' : 'Your bands, tests and lessons';
    }
    if (!p.hasAny) return 'Take a mock test to see your bands here';
    final tests = p.listening.attempts +
        p.reading.attempts +
        p.writing.attempts +
        p.speaking.attempts;
    return [
      '$tests ${tests == 1 ? 'test' : 'tests'}',
      if (p.lessons.count > 0) '${p.lessons.hoursLabel} h with tutors',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final p = progress;
    final skills = <(String, IconData, SkillProgress?)>[
      ('Listening', Symbols.headphones_rounded, p?.listening),
      ('Reading', Symbols.auto_stories_rounded, p?.reading),
      ('Writing', Symbols.edit_note_rounded, p?.writing),
      ('Speaking', Symbols.mic_rounded, p?.speaking),
    ];
    return Material(
      color: colors.surfaceAlt,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.brand,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Symbols.trending_up_rounded,
                      size: 24,
                      color: colors.onBrand,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your progress',
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 12.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Symbols.chevron_right_rounded,
                    color: colors.textTertiary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 0; i < skills.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _SkillStat(
                        label: skills[i].$1,
                        icon: skills[i].$2,
                        band: skills[i].$3?.latest,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillStat extends StatelessWidget {
  const _SkillStat({required this.label, required this.icon, this.band});

  final String label;
  final IconData icon;
  final double? band;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: colors.textSecondary),
          const SizedBox(height: 4),
          Text(
            band?.toStringAsFixed(1) ?? '–',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: band != null ? colors.textPrimary : colors.textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
