import 'package:flutter/material.dart';
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

  ({String label, Color color}) get _statusBadge {
    switch (lesson.status) {
      case 'finished':
        return (label: 'Completed', color: const Color(0xFF27AE60));
      case 'cancelled':
        return (label: 'Cancelled', color: const Color(0xFFE74C3C));
      case 'confirmed':
        return (label: 'Confirmed', color: const Color(0xFF2B85DB));
      case 'pending':
        return (label: 'Pending', color: const Color(0xFFE67E22));
      default:
        final s = lesson.status;
        return (
          label: s.isEmpty
              ? 'Scheduled'
              : '${s[0].toUpperCase()}${s.substring(1)}',
          color: const Color(0xFF6C6C6C),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasGoals = lesson.lessonGoals.isNotEmpty ||
        (lesson.studentNote?.trim().isNotEmpty ?? false);
    final status = _statusBadge;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF272942), size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Lesson details',
          style: TextStyle(
            color: Color(0xFF272942),
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
                  : const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'No goals were specified for this lesson.',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 13,
                          color: Color(0xFFAAAAAA),
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
          style: const TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFFAAAAAA),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F6F6),
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
            style: const TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 13,
              color: Color(0xFF999999),
            ),
          ),
          const Spacer(),
          valueWidget ??
              Text(
                value ?? '—',
                style: const TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF272942),
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
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: Divider(height: 1, color: Color(0xFFEAEAEA)),
    );
  }
}
