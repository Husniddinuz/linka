import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import 'mock_test_result_screen.dart';
import 'writing_result_screen.dart';

class MockTestHistoryScreen extends StatefulWidget {
  const MockTestHistoryScreen({super.key});

  @override
  State<MockTestHistoryScreen> createState() => _MockTestHistoryScreenState();
}

class _MockTestHistoryScreenState extends State<MockTestHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);
  final Future<List<Map<String, dynamic>>> _testAttempts = MockTestService.fetchAttempts();
  final Future<List<Map<String, dynamic>>> _writingAttempts = MockTestService.fetchWritingAttempts();

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Reading / Listening'), Tab(text: 'Writing')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _testAttempts,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final attempts = snapshot.data ?? const [];
              if (attempts.isEmpty) return const Center(child: Text('No attempts yet'));
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: attempts.length,
                itemBuilder: (context, i) {
                  final a = attempts[i];
                  final test = (a['test'] as Map?) ?? const {};
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(test['title']?.toString() ?? ''),
                      subtitle: Text('${a['raw_score']}/${a['max_score']} · ${a['status']}'),
                      trailing: Text(
                        'Band ${a['band_score'] ?? '-'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => MockTestResultScreen(attempt: a)),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _writingAttempts,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final attempts = snapshot.data ?? const [];
              if (attempts.isEmpty) return const Center(child: Text('No attempts yet'));
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: attempts.length,
                itemBuilder: (context, i) {
                  final a = attempts[i];
                  final prompt = (a['prompt'] as Map?) ?? const {};
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(prompt['title']?.toString() ?? ''),
                      subtitle: Text('${a['word_count']} words · ${a['status']}'),
                      trailing: Text(
                        a['overall_band'] != null ? 'Band ${a['overall_band']}' : '-',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => WritingResultScreen(attempt: a)),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
