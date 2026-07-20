import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'plus_subscription_screen.dart';
import 'speaking_sample_screen.dart';

/// How many of a tutor's topics a non-Plus user can open for free; the rest
/// stay visible but locked and route to the Plus subscription screen.
const int _freeSamples = 3;

/// Grid of tutors with real Speaking sample answers for students to study —
/// read-only reference content, no submission/grading. Tapping a tutor
/// drills into their submitted topics (see [SpeakingSampleTutorTopicsScreen]);
/// tapping a topic opens that sample's Part 1/2/3 audio + live transcript.
class SpeakingSamplesListScreen extends StatefulWidget {
  const SpeakingSamplesListScreen({super.key});

  @override
  State<SpeakingSamplesListScreen> createState() => _SpeakingSamplesListScreenState();
}

class _SpeakingSamplesListScreenState extends State<SpeakingSamplesListScreen> {
  final Future<List<Map<String, dynamic>>> _future = MockTestService.fetchSpeakingSampleTutors();

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
            itemBuilder: (context, i) {
              final tutor = tutors[i];
              final tutorId = (tutor['tutor_id'] as num?)?.toInt();
              final tutorName = tutor['tutor_name']?.toString() ?? '';
              final tutorImageUrl = tutor['tutor_image_url'] as String?;
              final tutorSpeakingScore = tutor['tutor_speaking_score']?.toString();
              final sampleCount = (tutor['sample_count'] as num?)?.toInt() ?? 0;

              return _TutorCard(
                name: tutorName,
                imageUrl: tutorImageUrl,
                scoreLabel: tutorSpeakingScore != null ? 'IELTS $tutorSpeakingScore' : null,
                subtitle: '$sampleCount topic${sampleCount == 1 ? '' : 's'}',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SpeakingSampleTutorTopicsScreen(
                      tutorId: tutorId,
                      tutorName: tutorName,
                      tutorImageUrl: tutorImageUrl,
                      tutorSpeakingScore: tutorSpeakingScore,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One tutor's submitted Speaking topics — a simple list of that tutor's
/// samples, one row per submitted topic. Tapping a topic opens the existing
/// Part 1/2/3 audio/transcript viewer, unchanged.
class SpeakingSampleTutorTopicsScreen extends StatefulWidget {
  const SpeakingSampleTutorTopicsScreen({
    super.key,
    required this.tutorId,
    required this.tutorName,
    required this.tutorImageUrl,
    required this.tutorSpeakingScore,
  });

  final int? tutorId;
  final String tutorName;
  final String? tutorImageUrl;
  final String? tutorSpeakingScore;

  @override
  State<SpeakingSampleTutorTopicsScreen> createState() => _SpeakingSampleTutorTopicsScreenState();
}

class _SpeakingSampleTutorTopicsScreenState extends State<SpeakingSampleTutorTopicsScreen> {
  late final Future<List<Map<String, dynamic>>> _future;
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    _future = MockTestService.fetchSpeakingSamples(
      tutorId: widget.tutorId,
      tutorName: widget.tutorId == null ? widget.tutorName : null,
    );
    _checkPlusStatus();
  }

  Future<void> _checkPlusStatus() async {
    final locked = await mtCheckContentLocked();
    if (!mounted) return;
    setState(() => _isLocked = locked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: widget.tutorName),
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
          final samples = snapshot.data ?? const [];
          if (samples.isEmpty) {
            return const Center(
              child: Text(
                'No speaking samples yet',
                style: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey, fontSize: 14),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: samples.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            // The backend is the source of truth ('locked' items arrive with
            // their parts stripped); the index check is a fallback for
            // backends that predate server-side gating.
            itemBuilder: (context, i) => _TopicRow(
              sample: samples[i],
              locked: samples[i]['locked'] == true || (_isLocked && i >= _freeSamples),
            ),
          );
        },
      ),
    );
  }
}

/// Full-bleed photo card: name/subtitle and score badge are overlaid on
/// the photo itself (gradient scrim + corner badge) rather than stacked
/// below it, so the card reads like a tutor/coach profile, not a product
/// tile. Used for the top-level tutor grid — [scoreLabel], when present, is
/// the tutor's own IELTS Speaking credential, not any single sample's score.
class _TutorCard extends StatelessWidget {
  const _TutorCard({
    required this.name,
    required this.imageUrl,
    required this.scoreLabel,
    required this.subtitle,
    required this.onTap,
  });

  final String name;
  final String? imageUrl;
  final String? scoreLabel;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null && imageUrl!.isNotEmpty)
              Image.network(
                imageUrl!,
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
            if (scoreLabel != null)
              Positioned(
                top: 10,
                right: 10,
                child: MtPill(
                  background: MockTestColors.yellow,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Text(
                    scoreLabel!,
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
                        subtitle,
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

/// Simple list row, one level down from [_TutorCard]: a single submitted
/// topic (sample) for the tutor selected on the previous screen — no tutor
/// photo, since the tutor is already chosen. The score badge here is that
/// specific sample's own `band_score` — distinct from the tutor's overall
/// `tutor_speaking_score` shown at the tutor-list level. When [locked], the
/// row dims, shows a lock instead of a chevron, and tapping it opens the
/// Plus subscription screen instead of the sample.
class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.sample, required this.locked});
  final Map<String, dynamic> sample;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final id = sample['id']?.toString() ?? '';
    final title = sample['topic_title']?.toString() ?? 'Sample #$id';
    final band = sample['band_score']?.toString();
    final parts = (sample['parts'] as List?) ?? const [];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              locked ? const PlusSubscriptionScreen() : SpeakingSampleTutorScreen(tutor: sample),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: mtSoftCard(),
        child: Opacity(
          opacity: locked ? 0.55 : 1,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: MockTestColors.chipBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.mic_rounded, color: MockTestColors.navy, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: MockTestColors.navy,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      locked
                          ? 'Linka Plus'
                          : '${parts.length} part${parts.length == 1 ? '' : 's'} recorded',
                      style: const TextStyle(fontFamily: 'SF Pro', fontSize: 12, color: MockTestColors.grey),
                    ),
                  ],
                ),
              ),
              if (band != null) ...[
                const SizedBox(width: 8),
                MtPill(
                  background: MockTestColors.yellow,
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  child: Text(
                    'Band $band',
                    style: const TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: MockTestColors.navy,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                locked ? Icons.lock_rounded : Icons.chevron_right_rounded,
                color: MockTestColors.greyLight,
                size: locked ? 18 : 22,
              ),
            ],
          ),
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
