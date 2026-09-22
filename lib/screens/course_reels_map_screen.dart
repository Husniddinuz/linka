import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/course_reel.dart';
import '../theme/app_colors.dart';
import '../widgets/reel_progress_markers.dart';
import 'reel_practice_screen.dart';

/// Duolingo-style winding path through a course's lessons.
///
/// Each stop shows the lesson's two markers — yellow once the video is
/// watched, green once its practice is done. Tapping a stop offers "Watch"
/// (pops with the lesson index so the feed jumps there) and "Practice".
class CourseReelsMapScreen extends StatefulWidget {
  const CourseReelsMapScreen({
    super.key,
    required this.course,
    required this.lessons,
    required this.currentIndex,
  });

  final ReelCourse course;

  /// Shared with the feed: practice done here shows up there too.
  final List<ReelLesson> lessons;
  final int currentIndex;

  @override
  State<CourseReelsMapScreen> createState() => _CourseReelsMapScreenState();
}

class _CourseReelsMapScreenState extends State<CourseReelsMapScreen>
    with SingleTickerProviderStateMixin {
  static const double _nodeSize = 76;
  static const double _rowHeight = 150;
  static const double _topPad = 40;

  final ScrollController _scroll = ScrollController();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _topPad + widget.currentIndex * _rowHeight - 160;
      _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Horizontal offset of stop [i] from the centre line, as a share of the
  /// available swing: 0, ½, 1, ½, 0, −½, −1, −½, …
  static double _swing(int i) => math.sin(i * math.pi / 4);

  Offset _center(int i, double width) {
    final amplitude = math.min(width * 0.26, 110.0);
    return Offset(
      width / 2 + _swing(i) * amplitude,
      _topPad + _nodeSize / 2 + i * _rowHeight,
    );
  }

  Future<void> _openLesson(int i) async {
    final lesson = widget.lessons[i];
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => _LessonSheet(lesson: lesson, number: i + 1),
    );
    if (!mounted || action == null) return;
    if (action == 'watch') {
      Navigator.pop(context, i);
    } else if (action == 'practice') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => ReelPracticeScreen(lesson: lesson)),
      );
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lessons = widget.lessons;
    final watched = lessons.where((l) => l.progress.watched).length;
    final completed = lessons.where((l) => l.progress.completed).length;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Symbols.arrow_back_rounded, color: c.textPrimary),
        ),
        title: Text(
          widget.course.title,
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ),
      body: Column(
        children: [
          _Summary(
            watched: watched,
            completed: completed,
            total: lessons.length,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = _topPad + lessons.length * _rowHeight + 140;
                final centers = [
                  for (var i = 0; i < lessons.length; i++) _center(i, width),
                ];
                return SingleChildScrollView(
                  controller: _scroll,
                  child: SizedBox(
                    height: height,
                    width: width,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _PathPainter(
                              centers: centers,
                              completed: [
                                for (final l in lessons) l.progress.completed,
                              ],
                              done: c.success,
                              todo: c.border,
                            ),
                          ),
                        ),
                        for (var i = 0; i < lessons.length; i++)
                          Positioned(
                            left: centers[i].dx - 70,
                            // The disc sits in a (size + 24) box that leaves room for the pulse ring.
                            top: centers[i].dy - (_nodeSize + 24) / 2,
                            width: 140,
                            child: _Stop(
                              lesson: lessons[i],
                              number: i + 1,
                              current: i == widget.currentIndex,
                              pulse: _pulse,
                              size: _nodeSize,
                              onTap: () => _openLesson(i),
                            ),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: _topPad + lessons.length * _rowHeight - 10,
                          child: Icon(
                            Symbols.emoji_events_rounded,
                            size: 56,
                            fill:
                                completed == lessons.length &&
                                    lessons.isNotEmpty
                                ? 1
                                : 0,
                            color:
                                completed == lessons.length &&
                                    lessons.isNotEmpty
                                ? c.accentYellow
                                : c.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.watched,
    required this.completed,
    required this.total,
  });

  final int watched;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: c.border),
                  FractionallySizedBox(
                    widthFactor: total == 0 ? 0 : watched / total,
                    child: Container(color: c.accentYellow),
                  ),
                  FractionallySizedBox(
                    widthFactor: total == 0 ? 0 : completed / total,
                    child: Container(color: c.success),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Legend(color: c.accentYellow, label: 'Watched $watched/$total'),
              const SizedBox(width: 16),
              _Legend(color: c.success, label: 'Practised $completed/$total'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({
    required this.lesson,
    required this.number,
    required this.current,
    required this.pulse,
    required this.size,
    required this.onTap,
  });

  final ReelLesson lesson;
  final int number;
  final bool current;
  final Animation<double> pulse;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = lesson.progress;
    final Color fill;
    final Widget face;
    if (p.completed) {
      fill = c.success;
      face = const Icon(
        Symbols.check_rounded,
        size: 38,
        weight: 700,
        color: Colors.white,
      );
    } else if (p.watched) {
      fill = c.accentYellow;
      face = const Icon(
        Symbols.edit_note_rounded,
        size: 36,
        color: Colors.white,
      );
    } else if (current) {
      fill = c.brand;
      face = const Icon(
        Symbols.play_arrow_rounded,
        fill: 1,
        size: 40,
        color: Colors.white,
      );
    } else {
      fill = c.surfaceAlt;
      face = Text(
        '$number',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: c.textTertiary,
        ),
      );
    }

    final disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        boxShadow: [
          // The "3D" lip under each stop.
          BoxShadow(
            color: Color.lerp(fill, Colors.black, 0.25)!,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: face,
    );

    return Semantics(
      button: true,
      label:
          'Lesson $number, ${lesson.title}. '
          '${p.watched ? 'Watched' : 'Not watched'}. '
          '${p.completed ? 'Completed' : 'Not completed'}.',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size + 24,
              height: size + 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (current)
                    AnimatedBuilder(
                      animation: pulse,
                      builder: (context, _) => Container(
                        width: size + 24 * pulse.value,
                        height: size + 24 * pulse.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: fill.withValues(
                              alpha: (1 - pulse.value) * 0.6,
                            ),
                            width: 4,
                          ),
                        ),
                      ),
                    ),
                  disc,
                ],
              ),
            ),
            ReelProgressMarkers(
              progress: p,
              practiceRequired: lesson.practiceRequired,
              size: 16,
            ),
            const SizedBox(height: 4),
            Text(
              lesson.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                color: current ? c.textPrimary : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathPainter extends CustomPainter {
  _PathPainter({
    required this.centers,
    required this.completed,
    required this.done,
    required this.todo,
  });

  final List<Offset> centers;
  final List<bool> completed;
  final Color done;
  final Color todo;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i + 1 < centers.length; i++) {
      final a = centers[i];
      final b = centers[i + 1];
      final mid = (b.dy - a.dy) / 2;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx, a.dy + mid, b.dx, b.dy - mid, b.dx, b.dy);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 14
        ..color = completed[i] ? done.withValues(alpha: 0.55) : todo;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) =>
      old.centers != centers ||
      old.completed.toString() != completed.toString() ||
      old.done != done;
}

class _LessonSheet extends StatelessWidget {
  const _LessonSheet({required this.lesson, required this.number});

  final ReelLesson lesson;
  final int number;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = lesson.progress;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LESSON $number',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
                color: c.textTertiary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              lesson.title,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ReelProgressMarkers(
                  progress: p,
                  practiceRequired: lesson.practiceRequired,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p.completed
                        ? 'Completed'
                        : p.watched
                        ? 'Watched — practice left'
                        : 'Not started',
                    style: TextStyle(color: c.textSecondary, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, 'watch'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      foregroundColor: c.textPrimary,
                      side: BorderSide(color: c.border, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Symbols.play_arrow_rounded),
                    label: Text(
                      p.watched ? 'Watch again' : 'Watch',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                if (lesson.hasPractice) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, 'practice'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: c.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Symbols.edit_note_rounded),
                      label: const Text(
                        'Practice',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
