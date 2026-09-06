import 'package:flutter/material.dart';
import '../models/mock_test.dart';
import '../services/mock_test_service.dart';
import '../services/random_test_picker.dart';
import '../widgets/mock_test_access.dart';
import '../widgets/mock_test_styles.dart';
import '../widgets/random_test_card.dart';
import 'mock_test_taking_screen.dart';
import '../theme/app_colors.dart';

/// Full list of Reading or Listening mock tests for [testType]. Every test
/// is always visible; non-Plus users who have already taken
/// [mtFreeSolvedTestsLimit] tests see a lock on the remaining ones and get a
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
  final _picker = RandomTestPicker();

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

  void _showPlusPrompt() => mtShowPlusPrompt(context);

  /// Opens one of the tests the student can actually start. Once the free
  /// window is spent that is only their retakes; with none of those left the
  /// tap lands on the Plus prompt, same as tapping a locked row.
  void _openRandomTest(List<MockTest> tests, bool freeWindowUsed) {
    final open = freeWindowUsed ? tests.where((t) => _solvedTestIds.contains(t.id)).toList() : tests;
    if (open.isEmpty) {
      _showPlusPrompt();
      return;
    }
    _openTest(_picker.pick(open));
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

          final freeWindowUsed = _isLocked && _solvedTestIds.length >= mtFreeSolvedTestsLimit;

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
                RandomTestCard(
                  subtitle: 'Any of the ${tests.length} ${isListening ? 'Listening' : 'Reading'} tests',
                  onTap: () => _openRandomTest(tests, freeWindowUsed),
                ),
                const SizedBox(height: 10),
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
