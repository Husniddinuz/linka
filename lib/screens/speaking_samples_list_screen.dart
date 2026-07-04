import 'package:flutter/material.dart';
import '../data/speaking_sample_tutors_mock.dart';
import '../widgets/mock_test_styles.dart';
import 'speaking_sample_screen.dart';

/// Grid of tutors with real Speaking sample answers for students to study —
/// read-only reference content, no submission/grading. Each card opens the
/// tutor's Part 1/2/3 samples with audio + live transcript.
class SpeakingSamplesListScreen extends StatelessWidget {
  const SpeakingSamplesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tutors = mockSpeakingSampleTutors;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: 'Speaking Samples'),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: tutors.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.72,
        ),
        itemBuilder: (context, i) => _TutorCard(tutor: tutors[i]),
      ),
    );
  }
}

/// Full-bleed photo card: name/part count and band score are overlaid on
/// the photo itself (gradient scrim + corner badge) rather than stacked
/// below it, so the card reads like a tutor/coach profile, not a product tile.
class _TutorCard extends StatelessWidget {
  const _TutorCard({required this.tutor});
  final SpeakingSampleTutor tutor;

  @override
  Widget build(BuildContext context) {
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
            Image.asset(tutor.imageAsset, fit: BoxFit.cover),
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
            Positioned(
              top: 10,
              right: 10,
              child: MtPill(
                background: MockTestColors.yellow,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(
                  'IELTS ${tutor.bandScore}',
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
                    tutor.name,
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
                        '${tutor.parts.length} sample parts',
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
