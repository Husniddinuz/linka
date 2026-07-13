import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Reusable display of a booking's lesson goals (and the optional free-text
/// student note). Rendered inside the shared [LessonCard] so both the student
/// (confirming what they requested) and the tutor (seeing what to prepare) get
/// the same view.
class LessonGoals extends StatelessWidget {
  /// Human-readable goal labels (e.g. "Speaking practice", "Grammar").
  final List<String> goals;

  /// Optional free-text note the student left when booking.
  final String? note;

  const LessonGoals({super.key, required this.goals, this.note});

  bool get _hasNote => note != null && note!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (goals.isEmpty && !_hasNote) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (goals.isNotEmpty) ...[
            const _SectionLabel('Goals'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final g in goals) _GoalChip(g)],
            ),
          ],
          if (goals.isNotEmpty && _hasNote) const SizedBox(height: 10),
          if (_hasNote) ...[
            const _SectionLabel('Note'),
            const SizedBox(height: 4),
            Text(
              note!.trim(),
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.colors.textPrimary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'SF Pro',
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: context.colors.textTertiary,
        letterSpacing: 0.5,
        height: 1.0,
      ),
    );
  }
}

class _GoalChip extends StatelessWidget {
  final String label;
  const _GoalChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'SF Pro',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.colors.textPrimary,
          height: 1.0,
        ),
      ),
    );
  }
}
