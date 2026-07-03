import 'package:flutter/material.dart';
import '../widgets/mock_test_styles.dart';

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
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: 'Result'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: MockTestColors.navy,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Text(
                  'BAND SCORE',
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
                  band,
                  style: const TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$rawScore / $maxScore correct',
                  style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Review',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: MockTestColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          ...details.map((d) {
            final correct = d['is_correct'] == true;
            final number = d['number'];
            final endNumber = d['number_end'];
            final label = endNumber != null ? '$number–$endNumber' : '$number';
            final submitted = _formatAnswer(d['submitted']);
            final correctAnswer = _formatAnswer(d['correct_answer']);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: mtSoftCard(
                color: correct ? MockTestColors.greenBg : MockTestColors.redBg,
                radius: 12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: correct ? MockTestColors.green : MockTestColors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Question $label',
                          style: const TextStyle(
                            fontFamily: 'SF Pro',
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: MockTestColors.navy,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Your answer: $submitted',
                          style: const TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, color: MockTestColors.grey),
                        ),
                        if (!correct) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Correct: $correctAnswer',
                            style: const TextStyle(
                              fontFamily: 'SF Pro',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: MockTestColors.green,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
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
