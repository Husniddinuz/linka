import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import 'mock_test_history_screen.dart';
import 'mock_test_taking_screen.dart';
import 'writing_test_screen.dart';

class MockTestsHomeScreen extends StatefulWidget {
  const MockTestsHomeScreen({super.key});

  @override
  State<MockTestsHomeScreen> createState() => _MockTestsHomeScreenState();
}

class _MockTestsHomeScreenState extends State<MockTestsHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mock Tests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MockTestHistoryScreen()),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Reading'), Tab(text: 'Listening'), Tab(text: 'Writing')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _TestList(testType: 'reading'),
          _TestList(testType: 'listening'),
          _WritingPromptList(),
        ],
      ),
    );
  }
}

class _TestList extends StatefulWidget {
  const _TestList({required this.testType});
  final String testType;

  @override
  State<_TestList> createState() => _TestListState();
}

class _TestListState extends State<_TestList> with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> _future = MockTestService.fetchTests(widget.testType);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Failed to load: ${snapshot.error}'));
        }
        final tests = snapshot.data ?? const [];
        if (tests.isEmpty) {
          return const Center(child: Text('No tests available yet'));
        }
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _future = MockTestService.fetchTests(widget.testType));
            await _future;
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tests.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final test = tests[i];
              final minutes = ((test['duration_seconds'] as num?)?.toInt() ?? 0) ~/ 60;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text('${test['number'] ?? i + 1}'),
                  ),
                  title: Text(test['title']?.toString() ?? 'Test ${i + 1}'),
                  subtitle: Text('${test['total_questions'] ?? 40} questions · $minutes min'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MockTestTakingScreen(
                        testId: test['id'] as int,
                        testType: widget.testType,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _WritingPromptList extends StatefulWidget {
  const _WritingPromptList();

  @override
  State<_WritingPromptList> createState() => _WritingPromptListState();
}

class _WritingPromptListState extends State<_WritingPromptList> with AutomaticKeepAliveClientMixin {
  final Future<List<Map<String, dynamic>>> _future = MockTestService.fetchWritingPrompts();

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Failed to load: ${snapshot.error}'));
        }
        final prompts = snapshot.data ?? const [];
        final task1 = prompts.where((p) => p['task_number'] == 1).toList();
        final task2 = prompts.where((p) => p['task_number'] == 2).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Task 1', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 8),
            ...task1.map((p) => _PromptCard(prompt: p)),
            const SizedBox(height: 20),
            const Text('Task 2', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 8),
            ...task2.map((p) => _PromptCard(prompt: p)),
          ],
        );
      },
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.prompt});
  final Map<String, dynamic> prompt;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(prompt['title']?.toString() ?? ''),
        subtitle: Text('Minimum ${prompt['min_words'] ?? 150} words'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WritingTestScreen(prompt: prompt)),
        ),
      ),
    );
  }
}
