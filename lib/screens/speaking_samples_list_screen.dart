import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'speaking_sample_screen.dart';

/// Grid of tutors with real Speaking sample answers for students to study —
/// read-only reference content, no submission/grading. Each card opens the
/// tutor's Part 1/2/3 samples with audio + live transcript.
class SpeakingSamplesListScreen extends StatefulWidget {
  const SpeakingSamplesListScreen({super.key});

  @override
  State<SpeakingSamplesListScreen> createState() => _SpeakingSamplesListScreenState();
}

class _SpeakingSamplesListScreenState extends State<SpeakingSamplesListScreen> {
  final Future<List<Map<String, dynamic>>> _future = MockTestService.fetchSpeakingSamples();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: 'Speaking Samples'),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: MockTestColors.yellow));
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey, fontSize: 14),
                ),
              ),
            );
          }
          final tutors = snapshot.data ?? const [];
          if (tutors.isEmpty) {
            return const Center(
              child: Text(
                'No speaking samples yet',
                style: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey, fontSize: 14),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: tutors.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.72,
            ),
            itemBuilder: (context, i) => _TutorCard(tutor: tutors[i]),
          );
        },
      ),
    );
  }
}

/// Full-bleed photo card: name/part count and band score are overlaid on
/// the photo itself (gradient scrim + corner badge) rather than stacked
/// below it, so the card reads like a tutor/coach profile, not a product tile.
class _TutorCard extends StatelessWidget {
  const _TutorCard({required this.tutor});
  final Map<String, dynamic> tutor;

  @override
  Widget build(BuildContext context) {
    final name = tutor['tutor_name']?.toString() ?? '';
    final imageUrl = tutor['tutor_image_url'] as String?;
    // The tutor's own IELTS Speaking score (their credential) — distinct
    // from this specific sample's band_score.
    final speakingScore = tutor['tutor_speaking_score']?.toString();
    final parts = (tutor['parts'] as List?) ?? const [];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SpeakingSampleTutorScreen(tutor: tutor)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const _TutorImageFallback(),
              )
            else
              const _TutorImageFallback(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.45, 1],
                  colors: [Colors.transparent, Color(0xCC0B0C1A)],
                ),
              ),
            ),
            if (speakingScore != null)
              Positioned(
                top: 10,
                right: 10,
                child: MtPill(
                  background: MockTestColors.yellow,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Text(
                    'IELTS $speakingScore',
                    style: const TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: MockTestColors.navy,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mic_rounded, color: Colors.white70, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        '${parts.length} sample parts',
                        style: const TextStyle(fontFamily: 'SF Pro', fontSize: 11.5, color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorImageFallback extends StatelessWidget {
  const _TutorImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MockTestColors.chipBg,
      alignment: Alignment.center,
      child: const Icon(Icons.person_rounded, color: MockTestColors.greyLight, size: 40),
    );
  }
}
