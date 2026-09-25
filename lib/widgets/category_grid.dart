import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/course_reel.dart';
import '../screens/student_progress_screen.dart';
import '../services/course_reels_service.dart';
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
class CategoryGrid extends StatefulWidget {
  const CategoryGrid({super.key, required this.onOpenCourse});

  /// A course path opens inside the Home tab, which owns that state.
  final ValueChanged<ReelCourse> onOpenCourse;

  @override
  State<CategoryGrid> createState() => CategoryGridState();
}

class CategoryGridState extends State<CategoryGrid> {
  List<ReelCourse> _courses = const [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Re-reads the course list; the home screen calls it on pull-to-refresh.
  Future<void> refresh() async {
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

  @override
  Widget build(BuildContext context) {
    final progress = _specs[HomeCategory.progress]!;
    final tiles = <Widget>[
      _CategoryTile(
        spec: progress,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StudentProgressScreen()),
        ),
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
