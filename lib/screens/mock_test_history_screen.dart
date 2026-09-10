import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../models/mock_test.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'mock_test_result_screen.dart';
import 'writing_result_screen.dart';
import '../theme/app_colors.dart';

class MockTestHistoryScreen extends StatefulWidget {
  const MockTestHistoryScreen({super.key});

  @override
  State<MockTestHistoryScreen> createState() => _MockTestHistoryScreenState();
}

class _MockTestHistoryScreenState extends State<MockTestHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);
  final Future<List<MockTestAttempt>> _testAttempts = MockTestService.fetchAttempts();
  final Future<List<Map<String, dynamic>>> _writingAttempts = MockTestService.fetchWritingAttempts();

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: mtAppBar(
        context,
        title: 'History',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 8),
            child: TabBar(
              controller: _tabController,
              labelColor: context.colors.textPrimary,
              unselectedLabelColor: context.colors.textTertiary,
              indicatorColor: context.colors.textPrimary,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, fontWeight: FontWeight.w600),
              tabs: const [Tab(text: 'Reading / Listening'), Tab(text: 'Writing')],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          FutureBuilder<List<MockTestAttempt>>(
            future: _testAttempts,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Center(child: CircularProgressIndicator(color: context.colors.accentYellow));
              }
              final attempts = snapshot.data ?? const [];
              if (attempts.isEmpty) return const _EmptyHistory();
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: attempts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final a = attempts[i];
                  final icon = a.testType == 'listening' ? Symbols.headphones_rounded : Symbols.menu_book_rounded;
                  return _HistoryRow(
                    icon: icon,
                    title: a.testTitle,
                    subtitle: '${a.rawScore}/${a.maxScore} correct',
                    band: a.bandScore ?? '-',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => MockTestResultScreen(attempt: a)),
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
                return Center(child: CircularProgressIndicator(color: context.colors.accentYellow));
              }
              final attempts = snapshot.data ?? const [];
              if (attempts.isEmpty) return const _EmptyHistory();
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: attempts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final a = attempts[i];
                  final prompt = (a['prompt'] as Map?) ?? const {};
                  return _HistoryRow(
                    icon: Symbols.edit_note_rounded,
                    title: prompt['title']?.toString() ?? '',
                    subtitle: '${a['word_count']} words · ${a['status']}',
                    band: a['overall_band'] != null ? '${a['overall_band']}' : '-',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => WritingResultScreen(attempt: a)),
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

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.band,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String band;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: mtSoftCard(context),
        child: Row(
          children: [
            MtAvatar(icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, color: context.colors.textSecondary),
                  ),
                ],
              ),
            ),
            MtPill(
              child: Text(
                'Band $band',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No attempts yet',
        style: TextStyle(fontFamily: 'SF Pro', color: context.colors.textTertiary, fontSize: 15),
      ),
    );
  }
}
