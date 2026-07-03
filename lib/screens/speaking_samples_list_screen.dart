import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'speaking_sample_screen.dart';

const int _freeSamplesPerPart = 2;

/// Real Speaking sample answers (Part 1/2/3) for students to study —
/// read-only reference content, no submission/grading. Non-Plus users see
/// the first [_freeSamplesPerPart] samples of each part normally; the rest
/// are shown blurred with an upgrade prompt.
class SpeakingSamplesListScreen extends StatefulWidget {
  const SpeakingSamplesListScreen({super.key});

  @override
  State<SpeakingSamplesListScreen> createState() => _SpeakingSamplesListScreenState();
}

class _SpeakingSamplesListScreenState extends State<SpeakingSamplesListScreen> {
  final Future<List<Map<String, dynamic>>> _future = MockTestService.fetchSpeakingSamples();
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
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
          final samples = snapshot.data ?? const [];
          final part1 = samples.where((s) => s['part'] == 1).toList();
          final part2 = samples.where((s) => s['part'] == 2).toList();
          final part3 = samples.where((s) => s['part'] == 3).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const _PartSectionLabel(text: 'PART 1'),
              const SizedBox(height: 10),
              ..._buildPartSamples(part1),
              const SizedBox(height: 22),
              const _PartSectionLabel(text: 'PART 2'),
              const SizedBox(height: 10),
              ..._buildPartSamples(part2),
              const SizedBox(height: 22),
              const _PartSectionLabel(text: 'PART 3'),
              const SizedBox(height: 10),
              ..._buildPartSamples(part3),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildPartSamples(List<Map<String, dynamic>> partSamples) {
    final locked = _isLocked && partSamples.length > _freeSamplesPerPart;
    final visible = locked ? partSamples.sublist(0, _freeSamplesPerPart) : partSamples;
    final hidden = locked ? partSamples.sublist(_freeSamplesPerPart) : const <Map<String, dynamic>>[];
    return [
      for (final s in visible) _SampleCard(sample: s, locked: false),
      if (locked)
        MtLockedSection(
          hiddenCount: hidden.length,
          itemLabel: 'samples',
          lockedCards: [for (final s in hidden) _SampleCard(sample: s, locked: true)],
        ),
    ];
  }
}

class _PartSectionLabel extends StatelessWidget {
  const _PartSectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'SF Pro',
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: MockTestColors.greyLight,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _SampleCard extends StatelessWidget {
  const _SampleCard({required this.sample, required this.locked});
  final Map<String, dynamic> sample;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final band = sample['band_score']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: locked
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SpeakingSampleScreen(sample: sample)),
                ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: mtSoftCard(),
          child: Row(
            children: [
              const MtAvatar(icon: Icons.record_voice_over_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sample['title']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: MockTestColors.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      band != null ? 'Band $band' : 'Sample answer',
                      style: const TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, color: MockTestColors.grey),
                    ),
                  ],
                ),
              ),
              Icon(
                locked ? Icons.lock_rounded : Icons.chevron_right_rounded,
                color: MockTestColors.greyLight,
                size: locked ? 18 : 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
