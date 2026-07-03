import 'package:flutter/material.dart';

class WritingResultScreen extends StatelessWidget {
  const WritingResultScreen({super.key, required this.attempt});

  final Map<String, dynamic> attempt;

  @override
  Widget build(BuildContext context) {
    final status = attempt['status']?.toString() ?? 'pending';
    final failed = status == 'failed';

    return Scaffold(
      appBar: AppBar(title: const Text('Writing result')),
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
            const Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 12),
            const Text('Grading is unavailable right now', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              attempt['error_message']?.toString() ?? 'Please try again later.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
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
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Text('Band $overall', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 20),
        _CriteriaRow(label: 'Task Achievement', value: attempt['task_achievement']),
        _CriteriaRow(label: 'Coherence & Cohesion', value: attempt['coherence_cohesion']),
        _CriteriaRow(label: 'Lexical Resource', value: attempt['lexical_resource']),
        _CriteriaRow(label: 'Grammatical Range & Accuracy', value: attempt['grammar_accuracy']),
        const SizedBox(height: 20),
        const Text('Feedback', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        Text(
          attempt['feedback']?.toString() ?? '',
          style: const TextStyle(fontSize: 14.5, height: 1.5),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14.5)),
          Text(value?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
