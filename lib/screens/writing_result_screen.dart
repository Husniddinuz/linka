import 'package:flutter/material.dart';
import '../widgets/mock_test_styles.dart';

class WritingResultScreen extends StatelessWidget {
  const WritingResultScreen({super.key, required this.attempt});

  final Map<String, dynamic> attempt;

  @override
  Widget build(BuildContext context) {
    final status = attempt['status']?.toString() ?? 'pending';
    final failed = status == 'failed';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: 'Writing result'),
      body: failed ? _FailedView(attempt: attempt) : _GradedView(attempt: attempt),
    );
  }
}

class _FailedView extends StatelessWidget {
  const _FailedView({required this.attempt});
  final Map<String, dynamic> attempt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: MockTestColors.redBg, shape: BoxShape.circle),
              child: const Icon(Icons.error_outline_rounded, size: 32, color: MockTestColors.red),
            ),
            const SizedBox(height: 16),
            const Text(
              'Grading is unavailable right now',
              style: TextStyle(fontFamily: 'SF Pro', fontWeight: FontWeight.w700, color: MockTestColors.navy),
            ),
            const SizedBox(height: 8),
            Text(
              attempt['error_message']?.toString() ?? 'Please try again later.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradedView extends StatelessWidget {
  const _GradedView({required this.attempt});
  final Map<String, dynamic> attempt;

  @override
  Widget build(BuildContext context) {
    final overall = attempt['overall_band']?.toString() ?? '-';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(color: MockTestColors.navy, borderRadius: BorderRadius.circular(20)),
          child: Column(
            children: [
              const Text(
                'OVERALL BAND',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                overall,
                style: const TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: mtSoftCard(radius: 14),
          child: Column(
            children: [
              _CriteriaRow(label: 'Task Achievement', value: attempt['task_achievement']),
              const Divider(height: 1, color: MockTestColors.divider),
              _CriteriaRow(label: 'Coherence & Cohesion', value: attempt['coherence_cohesion']),
              const Divider(height: 1, color: MockTestColors.divider),
              _CriteriaRow(label: 'Lexical Resource', value: attempt['lexical_resource']),
              const Divider(height: 1, color: MockTestColors.divider),
              _CriteriaRow(label: 'Grammatical Range & Accuracy', value: attempt['grammar_accuracy']),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Feedback',
          style: TextStyle(fontFamily: 'SF Pro', fontWeight: FontWeight.w700, fontSize: 15, color: MockTestColors.navy),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: mtSoftCard(color: MockTestColors.chipBg, radius: 14),
          child: Text(
            attempt['feedback']?.toString() ?? '',
            style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14, height: 1.5, color: MockTestColors.navy),
          ),
        ),
      ],
    );
  }
}

class _CriteriaRow extends StatelessWidget {
  const _CriteriaRow({required this.label, required this.value});
  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14, color: MockTestColors.navy),
            ),
          ),
          Text(
            value?.toString() ?? '-',
            style: const TextStyle(fontFamily: 'SF Pro', fontWeight: FontWeight.w700, color: MockTestColors.navy),
          ),
        ],
      ),
    );
  }
}
