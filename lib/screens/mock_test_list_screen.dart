import 'package:flutter/material.dart';
import '../models/mock_test.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'mock_test_taking_screen.dart';

const int _freeTestLimit = 3;

/// Full list of Reading or Listening mock tests for [testType]. Non-Plus
/// users see the first [_freeTestLimit] tests normally; the rest are shown
/// blurred with an upgrade prompt.
class MockTestListScreen extends StatefulWidget {
  const MockTestListScreen({super.key, required this.testType});
  final String testType; // 'reading' | 'listening'

  @override
  State<MockTestListScreen> createState() => _MockTestListScreenState();
}

class _MockTestListScreenState extends State<MockTestListScreen> {
  late Future<List<MockTest>> _future = MockTestService.fetchTests(widget.testType);
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

          final locked = _isLocked && tests.length > _freeTestLimit;
          final visible = locked ? tests.sublist(0, _freeTestLimit) : tests;
          final hidden = locked ? tests.sublist(_freeTestLimit) : const <MockTest>[];

          return RefreshIndicator(
            color: MockTestColors.navy,
            onRefresh: () async {
              setState(() {
                _future = MockTestService.fetchTests(widget.testType);
              });
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                for (final test in visible) ...[
                  _TestCard(test: test, testType: widget.testType, locked: false),
                  const SizedBox(height: 10),
                ],
                if (locked)
                  MtLockedSection(
                    hiddenCount: hidden.length,
                    itemLabel: 'tests',
                    lockedCards: [
                      for (final test in hidden) ...[
                        _TestCard(test: test, testType: widget.testType, locked: true),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({required this.test, required this.testType, required this.locked});
  final MockTest test;
  final String testType;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final minutes = test.durationSeconds ~/ 60;
    final icon = testType == 'listening' ? Icons.headphones_rounded : Icons.menu_book_rounded;
    return GestureDetector(
      onTap: locked
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MockTestTakingScreen(testId: test.id, testType: testType),
                ),
              ),
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
