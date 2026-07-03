import 'package:flutter/material.dart';
import '../widgets/mock_test_styles.dart';

/// Read-only view of a real Writing sample essay: prompt, sample essay text,
/// achieved band score, and examiner commentary. No submission or grading.
class WritingSampleScreen extends StatelessWidget {
  const WritingSampleScreen({super.key, required this.sample});

  final Map<String, dynamic> sample;

  @override
  Widget build(BuildContext context) {
    final imageUrl = sample['image_url'] as String?;
    final band = sample['band_score']?.toString();
    final examinerComment = sample['examiner_comment']?.toString() ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: sample['title']?.toString() ?? 'Writing sample'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: mtSoftCard(color: MockTestColors.chipBg, radius: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl != null && imageUrl.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      color: Colors.white,
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2, color: MockTestColors.yellow),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'Could not load chart image',
                              style: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.greyLight, fontSize: 12.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  sample['prompt_html']?.toString() ?? '',
                  style: const TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 14,
                    height: 1.5,
                    color: MockTestColors.navy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (band != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(color: MockTestColors.navy, borderRadius: BorderRadius.circular(20)),
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
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          const Text(
            'Sample essay',
            style: TextStyle(fontFamily: 'SF Pro', fontWeight: FontWeight.w700, fontSize: 15, color: MockTestColors.navy),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: mtSoftCard(radius: 14),
            child: Text(
              sample['sample_essay_html']?.toString() ?? '',
              style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14, height: 1.5, color: MockTestColors.navy),
            ),
          ),
          if (examinerComment.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Why this scores well',
              style: TextStyle(fontFamily: 'SF Pro', fontWeight: FontWeight.w700, fontSize: 15, color: MockTestColors.navy),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: mtSoftCard(color: MockTestColors.chipBg, radius: 14),
              child: Text(
                examinerComment,
                style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14, height: 1.5, color: MockTestColors.navy),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
