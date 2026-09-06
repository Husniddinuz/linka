import 'package:flutter/material.dart';
import '../screens/plus_subscription_screen.dart';
import '../services/mock_test_service.dart';
import '../theme/app_colors.dart';
import 'mock_test_styles.dart';

/// How many distinct mock tests (Reading + Listening combined) a non-Plus
/// user can take for free. Tests they have already attempted stay open for
/// retakes; starting a new test beyond this prompts for Linka Plus.
const int mtFreeSolvedTestsLimit = 2;

/// Ids of the Reading/Listening tests the current user may still open, or
/// null when every test is open (Plus member, exempt QA account, or the free
/// window not yet spent). Counted across both skills, like the list screens.
///
/// Fails open like [mtCheckContentLocked]: a history fetch hiccup should
/// never lock someone out.
Future<Set<int>?> mtOpenableMockTestIds() async {
  final locked = await mtCheckContentLocked();
  if (!locked) return null;
  Set<int> solved;
  try {
    final attempts = await MockTestService.fetchAttempts();
    solved = attempts.map((a) => a.testId).toSet();
  } catch (_) {
    return null;
  }
  return solved.length >= mtFreeSolvedTestsLimit ? solved : null;
}

/// The "you've used your free tests" sheet with a Get Plus button.
void mtShowPlusPrompt(BuildContext context) {
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
            'You\'ve used your $mtFreeSolvedTestsLimit free tests',
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
