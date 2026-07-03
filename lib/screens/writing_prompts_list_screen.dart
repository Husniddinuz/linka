import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'writing_test_screen.dart';

const int _freePromptsPerTask = 2;

/// Writing Task 1 & 2 prompts. Non-Plus users see the first
/// [_freePromptsPerTask] prompts of each task normally; the rest are shown
/// blurred with an upgrade prompt.
class WritingPromptsListScreen extends StatefulWidget {
  const WritingPromptsListScreen({super.key});

  @override
  State<WritingPromptsListScreen> createState() => _WritingPromptsListScreenState();
}

class _WritingPromptsListScreenState extends State<WritingPromptsListScreen> {
  final Future<List<Map<String, dynamic>>> _future = MockTestService.fetchWritingPrompts();
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
      appBar: mtAppBar(context, title: 'Writing'),
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
          final prompts = snapshot.data ?? const [];
          final task1 = prompts.where((p) => p['task_number'] == 1).toList();
          final task2 = prompts.where((p) => p['task_number'] == 2).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const _TaskSectionLabel(text: 'TASK 1'),
              const SizedBox(height: 10),
              ..._buildTaskPrompts(task1),
              const SizedBox(height: 22),
              const _TaskSectionLabel(text: 'TASK 2'),
              const SizedBox(height: 10),
              ..._buildTaskPrompts(task2),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildTaskPrompts(List<Map<String, dynamic>> taskPrompts) {
    final locked = _isLocked && taskPrompts.length > _freePromptsPerTask;
    final visible = locked ? taskPrompts.sublist(0, _freePromptsPerTask) : taskPrompts;
    final hidden = locked ? taskPrompts.sublist(_freePromptsPerTask) : const <Map<String, dynamic>>[];
    return [
      for (final p in visible) _PromptCard(prompt: p, locked: false),
      if (locked)
        MtLockedSection(
          hiddenCount: hidden.length,
          itemLabel: 'prompts',
          lockedCards: [for (final p in hidden) _PromptCard(prompt: p, locked: true)],
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

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.prompt, required this.locked});
  final Map<String, dynamic> prompt;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: locked
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => WritingTestScreen(prompt: prompt)),
                ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: mtSoftCard(),
          child: Row(
            children: [
              const MtAvatar(icon: Icons.edit_note_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prompt['title']?.toString() ?? '',
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
                      'Minimum ${prompt['min_words'] ?? 150} words',
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
