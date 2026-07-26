import 'package:flutter/material.dart';
import '../models/mock_test.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'mock_test_taking_screen.dart';
import 'plus_subscription_screen.dart';
import '../theme/app_colors.dart';

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
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_rounded, color: context.colors.accentYellow, size: 40),
            const SizedBox(height: 12),
            Text(
              'You\'ve used your $_freeSolvedTestsLimit free tests',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Get Linka Plus to unlock all Reading and Listening mock tests.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.4, color: context.colors.textSecondary),
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
                  backgroundColor: context.colors.brand,
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
      backgroundColor: context.colors.background,
      appBar: mtAppBar(context, title: isListening ? 'Listening' : 'Reading'),
      body: FutureBuilder<List<MockTest>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.accentYellow));
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'SF Pro', color: context.colors.textSecondary, fontSize: 14),
                ),
              ),
            );
          }
          final tests = snapshot.data ?? const [];
          if (tests.isEmpty) {
            return Center(
              child: Text(
                'No tests available yet',
                style: TextStyle(fontFamily: 'SF Pro', color: context.colors.textTertiary, fontSize: 15),
              ),
            );
          }

          final freeWindowUsed = _isLocked && _solvedTestIds.length >= _freeSolvedTestsLimit;

          return RefreshIndicator(
            color: context.colors.textPrimary,
            onRefresh: () async {
              setState(() {
                _future = MockTestService.fetchTests(widget.testType);
              });
              await Future.wait([_future, _loadAccessState()]);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                for (final (index, test) in tests.indexed) ...[
                  Builder(builder: (context) {
                    final locked = freeWindowUsed && !_solvedTestIds.contains(test.id);
                    return _TestCard(
                      test: test,
                      // Position in the list, not `test.number` — backend
                      // numbers have gaps from unpublished tests, and a
                      // "Test 25" sitting 23rd in the list reads as a bug.
                      position: index + 1,
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
  const _TestCard({
    required this.test,
    required this.position,
    required this.locked,
    required this.onTap,
  });
  final MockTest test;

  /// 1-based position in the list, shown in the avatar so the tests are
  /// countable at a glance (every title is otherwise identical).
  final int position;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final minutes = test.durationSeconds ~/ 60;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: mtSoftCard(context),
        child: Row(
          children: [
            MtAvatar(text: '$position'),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    test.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${test.totalQuestions} questions · $minutes min',
                    style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, color: context.colors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              locked ? Icons.lock_rounded : Icons.chevron_right_rounded,
              color: context.colors.textTertiary,
              size: locked ? 18 : 24,
            ),
          ],
        ),
      ),
    );
  }
}
