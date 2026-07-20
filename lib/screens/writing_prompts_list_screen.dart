import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'writing_test_screen.dart';

/// Writing Task 1 & 2 prompts. All prompts are open to everyone — the free
/// window is on AI-graded *submissions* (see WritingTestScreen's quota),
/// not on viewing prompts.
class WritingPromptsListScreen extends StatefulWidget {
  const WritingPromptsListScreen({super.key});

  @override
  State<WritingPromptsListScreen> createState() => _WritingPromptsListScreenState();
}

class _WritingPromptsListScreenState extends State<WritingPromptsListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);
  final Future<List<Map<String, dynamic>>> _future = MockTestService.fetchWritingPrompts();

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(
        context,
        title: 'Writing',
        // Task 1 and Task 2 each get their own tab (rather than one long
        // scrolling list) so Task 2 stays a single tap away no matter how
        // many Task 1 prompts there are — burying it below a long Task 1
        // list made students think only Task 1 existed.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 8),
            child: TabBar(
              controller: _tabController,
              labelColor: MockTestColors.navy,
              unselectedLabelColor: MockTestColors.greyLight,
              indicatorColor: MockTestColors.navy,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, fontWeight: FontWeight.w600),
              tabs: const [Tab(text: 'Task 1'), Tab(text: 'Task 2')],
            ),
          ),
        ),
      ),
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
          return TabBarView(
            controller: _tabController,
            children: [
              _PromptList(prompts: task1),
              _PromptList(prompts: task2),
            ],
          );
        },
      ),
    );
  }
}

class _PromptList extends StatelessWidget {
  const _PromptList({required this.prompts});

  final List<Map<String, dynamic>> prompts;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        for (final p in prompts) _PromptCard(prompt: p),
      ],
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.prompt});
  final Map<String, dynamic> prompt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.push(
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
              const Icon(
                Icons.chevron_right_rounded,
                color: MockTestColors.greyLight,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
