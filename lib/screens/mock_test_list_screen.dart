import 'package:flutter/material.dart';
import '../models/mock_test.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'mock_test_taking_screen.dart';
import 'plus_subscription_screen.dart';

/// How many distinct mock tests (Reading + Listening combined) a non-Plus
/// user can take for free. Tests they have already attempted stay open for
/// retakes; starting a new test beyond this prompts for Linka Plus.
const int _freeSolvedTestsLimit = 2;

/// Full list of Reading or Listening mock tests for [testType]. Every test
/// is always visible; non-Plus users who have already taken
/// [_freeSolvedTestsLimit] tests see a lock on the remaining ones and get a
/// "Get Plus" prompt when opening them.
class MockTestListScreen extends StatefulWidget {
  const MockTestListScreen({super.key, required this.testType});
  final String testType; // 'reading' | 'listening'

  @override
  State<MockTestListScreen> createState() => _MockTestListScreenState();
}

class _MockTestListScreenState extends State<MockTestListScreen> {
  late Future<List<MockTest>> _future = MockTestService.fetchTests(widget.testType);
  bool _isLocked = false;
  Set<int> _solvedTestIds = {};

  @override
  void initState() {
    super.initState();
    _loadAccessState();
  }

  Future<void> _loadAccessState() async {
    final locked = await mtCheckContentLocked();
    if (!mounted) return;
    if (!locked) {
      setState(() => _isLocked = false);
      return;
    }
    // Tests the user already attempted stay open (retakes are free) — only
    // *new* tests beyond the free window require Plus. Counted across both
    // Reading and Listening, hence no testType filter.
    var solved = <int>{};
    try {
      final attempts = await MockTestService.fetchAttempts();
      solved = attempts.map((a) => a.testId).toSet();
    } catch (_) {
      // Fail open like mtCheckContentLocked: a history fetch hiccup should
      // never lock someone out, at worst it re-grants the free window.
    }
    if (!mounted) return;
    setState(() {
      _isLocked = locked;
      _solvedTestIds = solved;
    });
  }

  Future<void> _openTest(MockTest test) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MockTestTakingScreen(testId: test.id, testType: widget.testType),
      ),
    );
    // The attempt they may have just submitted counts toward the free
    // window — refresh so newly-gated tests lock without a screen reload.
    if (mounted && _isLocked) _loadAccessState();
  }

  void _showPlusPrompt() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspace_premium_rounded, color: MockTestColors.yellow, size: 40),
            const SizedBox(height: 12),
            const Text(
              'You\'ve used your $_freeSolvedTestsLimit free tests',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: MockTestColors.navy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Get Linka Plus to unlock all Reading and Listening mock tests.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.4, color: MockTestColors.grey),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlusSubscriptionScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: MockTestColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Get Plus',
                  style: TextStyle(fontFamily: 'SF Pro', fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isListening = widget.testType == 'listening';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: isListening ? 'Listening' : 'Reading'),
      body: FutureBuilder<List<MockTest>>(
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
          final tests = snapshot.data ?? const [];
          if (tests.isEmpty) {
            return const Center(
              child: Text(
                'No tests available yet',
                style: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.greyLight, fontSize: 15),
              ),
            );
          }

          final freeWindowUsed = _isLocked && _solvedTestIds.length >= _freeSolvedTestsLimit;

          return RefreshIndicator(
            color: MockTestColors.navy,
            onRefresh: () async {
              setState(() {
                _future = MockTestService.fetchTests(widget.testType);
              });
              await Future.wait([_future, _loadAccessState()]);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                for (final test in tests) ...[
                  Builder(builder: (context) {
                    final locked = freeWindowUsed && !_solvedTestIds.contains(test.id);
                    return _TestCard(
                      test: test,
                      testType: widget.testType,
                      locked: locked,
                      onTap: locked ? _showPlusPrompt : () => _openTest(test),
                    );
                  }),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({required this.test, required this.testType, required this.locked, required this.onTap});
  final MockTest test;
  final String testType;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final minutes = test.durationSeconds ~/ 60;
    final icon = testType == 'listening' ? Icons.headphones_rounded : Icons.menu_book_rounded;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: mtSoftCard(),
        child: Row(
          children: [
            MtAvatar(icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    test.title,
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
                    '${test.totalQuestions} questions · $minutes min',
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
    );
  }
}
