import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/course_reel.dart';
import '../theme/app_colors.dart';

/// The two per-lesson markers used across Course Reels:
/// yellow = video watched, green = required practice completed.
class ReelProgressMarkers extends StatelessWidget {
  const ReelProgressMarkers({
    super.key,
    required this.progress,
    required this.practiceRequired,
    this.size = 20,
    this.onDark = false,
  });

  final ReelLessonProgress progress;
  final bool practiceRequired;
  final double size;

  /// Draws the "not yet" state for a dark backdrop (the reels feed).
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final off = onDark ? Colors.white.withValues(alpha: 0.28) : c.border;
    final offIcon = onDark
        ? Colors.white.withValues(alpha: 0.7)
        : c.textTertiary;
    final practiceDone = practiceRequired
        ? progress.practiceCompleted
        : progress.watched;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(
          size: size,
          on: progress.watched,
          onColor: c.accentYellow,
          offColor: off,
          offIconColor: offIcon,
          icon: Symbols.play_arrow_rounded,
          tooltip: progress.watched ? 'Video watched' : 'Video not watched yet',
        ),
        SizedBox(width: size * 0.3),
        _Dot(
          size: size,
          on: practiceDone,
          onColor: c.success,
          offColor: off,
          offIconColor: offIcon,
          icon: Symbols.check_rounded,
          tooltip: practiceDone
              ? 'Practice completed'
              : 'Practice not done yet',
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.size,
    required this.on,
    required this.onColor,
    required this.offColor,
    required this.offIconColor,
    required this.icon,
    required this.tooltip,
  });

  final double size;
  final bool on;
  final Color onColor;
  final Color offColor;
  final Color offIconColor;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? onColor : Colors.transparent,
          border: on ? null : Border.all(color: offColor, width: 1.5),
        ),
        child: Icon(
          icon,
          size: size * 0.66,
          weight: 700,
          color: on ? Colors.white : offIconColor,
        ),
      ),
    );
  }
}
