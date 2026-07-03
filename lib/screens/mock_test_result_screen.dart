import 'package:flutter/material.dart';

class MockTestResultScreen extends StatelessWidget {
  const MockTestResultScreen({super.key, required this.attempt});

  final Map<String, dynamic> attempt;

  @override
  Widget build(BuildContext context) {
    final rawScore = (attempt['raw_score'] as num?)?.toInt() ?? 0;
    final maxScore = (attempt['max_score'] as num?)?.toInt() ?? 0;
    final band = attempt['band_score']?.toString() ?? '-';
    final details = ((attempt['result_detail'] as List?) ?? const []).cast<Map<String, dynamic>>();

    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Text('Band $band', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('$rawScore / $maxScore correct', style: const TextStyle(fontSize: 16, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Review', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...details.map((d) {
            final correct = d['is_correct'] == true;
            final number = d['number'];
            final endNumber = d['number_end'];
            final label = endNumber != null ? '$number–$endNumber' : '$number';
            final submitted = _formatAnswer(d['submitted']);
            final correctAnswer = _formatAnswer(d['correct_answer']);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: correct ? Colors.green.shade100 : Colors.red.shade100,
                  child: Icon(
                    correct ? Icons.check : Icons.close,
                    color: correct ? Colors.green.shade800 : Colors.red.shade800,
                    size: 20,
                  ),
                ),
                title: Text('Question $label'),
                subtitle: Text(
                  correct ? 'Your answer: $submitted' : 'Your answer: $submitted\nCorrect: $correctAnswer',
                ),
                isThreeLine: !correct,
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatAnswer(dynamic value) {
    if (value == null || value == '') return '(no answer)';
    if (value is List) return value.isEmpty ? '(no answer)' : value.join(', ');
    return value.toString();
  }
}
