import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../theme/app_colors.dart';
import '../widgets/lesson_card.dart';
import '../widgets/lesson_goals.dart';

/// Full-screen detail view for a single booking/lesson.
///
/// Reuses [LessonCard] for the participant summary and the join/copy/cancel/
/// rate actions (so behaviour stays identical to the list), and shows the full
/// goals and student note — which don't fit on the compact card — below it.
class LessonDetailScreen extends StatelessWidget {
  final Lesson lesson;
  final bool showStartButton;
  final bool showCopyLink;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onRated;

  const LessonDetailScreen({
    super.key,
    required this.lesson,
    this.showStartButton = false,
    this.showCopyLink = false,
    this.onStart,
    this.onCancel,
    this.onRated,
  });

  static const _months = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdays = [
    '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
    'Saturday', 'Sunday',
  ];

  String get _formattedDate {
    final d = lesson.startAt;
    if (d == null) return '—';
    return '${_weekdays[d.weekday]}, ${d.day} ${_months[d.month]} ${d.year}';
  }

  ({String label, Color color}) _statusBadge(BuildContext context) {
    switch (lesson.status) {
      case 'finished':
        return (label: 'Completed', color: context.colors.success);
      case 'cancelled':
        return (label: 'Cancelled', color: context.colors.error);
      case 'confirmed':
        return (label: 'Confirmed', color: context.colors.accentBlue);
      case 'pending':
        // Pending is a one-off amber status accent with no direct token
        // match — left as a literal.
        return (label: 'Pending', color: const Color(0xFFE67E22));
      default:
        final s = lesson.status;
        return (
          label: s.isEmpty
              ? 'Scheduled'
              : '${s[0].toUpperCase()}${s.substring(1)}',
          color: context.colors.textSecondary,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasGoals = lesson.lessonGoals.isNotEmpty ||
        (lesson.studentNote?.trim().isNotEmpty ?? false);
    final status = _statusBadge(context);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Symbols.chevron_left_rounded, color: context.colors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Lesson details',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Participant summary + actions (reused from the list).
            LessonCard(
              lesson: lesson,
              opensDetail: false,
              showStartButton: showStartButton,
              showCopyLink: showCopyLink,
              onStart: onStart,
              // Cancelling or rating refreshes the underlying list, so return
              // there afterwards instead of leaving a stale detail open.
              onCancel: onCancel == null
                  ? null
                  : () {
                      onCancel!();
                      Navigator.of(context).pop();
                    },
              onRated: onRated == null
                  ? null
                  : () {
                      onRated!();
                      Navigator.of(context).pop();
                    },
            ),
            const SizedBox(height: 16),

            // Schedule / status
            _Section(
              title: 'Schedule',
              child: Column(
                children: [
                  _InfoRow(label: 'Date', value: _formattedDate),
                  const _RowDivider(),
                  _InfoRow(
                    label: 'Time',
                    value: lesson.timeRange.isEmpty ? '—' : lesson.timeRange,
                  ),
                  if (lesson.duration.isNotEmpty) ...[
                    const _RowDivider(),
                    _InfoRow(label: 'Duration', value: lesson.duration),
                  ],
                  const _RowDivider(),
                  _InfoRow(
                    label: 'Status',
                    valueWidget: Text(
                      status.label,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: status.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Goals + note
            _Section(
              title: 'What to focus on',
              child: hasGoals
                  ? LessonGoals(
                      goals: lesson.lessonGoals,
                      note: lesson.studentNote,
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'No goals were specified for this lesson.',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 13,
                          color: context.colors.textTertiary,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.colors.textTertiary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? valueWidget;
  const _InfoRow({required this.label, this.value, this.valueWidget});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 13,
              color: context.colors.textSecondary,
            ),
          ),
          const Spacer(),
          valueWidget ??
              Text(
                value ?? '—',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textPrimary,
                ),
              ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Divider(height: 1, color: context.colors.border),
    );
  }
}
