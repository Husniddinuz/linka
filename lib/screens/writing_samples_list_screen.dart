import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'writing_sample_screen.dart';

const int _freeSamplesPerTask = 2;

/// Real Writing sample essays (Task 1 & 2) for students to study — read-only
/// reference content, no submission/grading. Non-Plus users see the first
/// [_freeSamplesPerTask] samples of each task normally; the rest are shown
/// blurred with an upgrade prompt.
class WritingSamplesListScreen extends StatefulWidget {
  const WritingSamplesListScreen({super.key});

  @override
  State<WritingSamplesListScreen> createState() => _WritingSamplesListScreenState();
}

class _WritingSamplesListScreenState extends State<WritingSamplesListScreen> {
  final Future<List<Map<String, dynamic>>> _future = MockTestService.fetchWritingSamples();
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
      appBar: mtAppBar(context, title: 'Writing Samples'),
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
          final task1 = samples.where((s) => s['task_number'] == 1).toList();
          final task2 = samples.where((s) => s['task_number'] == 2).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const _TaskSectionLabel(text: 'TASK 1'),
              const SizedBox(height: 10),
              ..._buildTaskSamples(task1),
              const SizedBox(height: 22),
              const _TaskSectionLabel(text: 'TASK 2'),
              const SizedBox(height: 10),
              ..._buildTaskSamples(task2),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildTaskSamples(List<Map<String, dynamic>> taskSamples) {
    final locked = _isLocked && taskSamples.length > _freeSamplesPerTask;
    final visible = locked ? taskSamples.sublist(0, _freeSamplesPerTask) : taskSamples;
    final hidden = locked ? taskSamples.sublist(_freeSamplesPerTask) : const <Map<String, dynamic>>[];
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

class _TaskSectionLabel extends StatelessWidget {
  const _TaskSectionLabel({required this.text});
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
                  MaterialPageRoute(builder: (_) => WritingSampleScreen(sample: sample)),
                ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: mtSoftCard(),
          child: Row(
            children: [
              const MtAvatar(icon: Icons.auto_stories_rounded),
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
                      band != null ? 'Band $band' : 'Sample essay',
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
