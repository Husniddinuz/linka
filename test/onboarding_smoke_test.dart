import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/screens/onboarding_screen.dart';
import 'package:linka/services/prefs_service.dart';
import 'package:linka/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

MaterialApp _app() {
  return MaterialApp(
    theme: ThemeData(extensions: [AppColors.light]),
    home: const OnboardingScreen(),
  );
}

/// A phone-sized surface: the default 800x600 test window is wider and much
/// shorter than any device the intro actually runs on.
void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the intro walks every slide before it lets the user in',
      (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(_app());
    await tester.pump();

    // Slide 1 of 5. Only the last slide offers to finish.
    expect(find.textContaining('Browse verified IELTS tutors'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Start'), findsNothing);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Start'), findsOneWidget);
    // The features a fresh install has never heard of get their own slides:
    // the last one says "Every attempt" in both its copy and its chip.
    expect(find.textContaining('Every attempt'), findsWidgets);
  });

  testWidgets('the mock test and AI coach slides are part of the intro',
      (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Reading, Listening'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.textContaining('AI coach'), findsOneWidget);
  });

  testWidgets('skipping marks the intro seen so it never returns',
      (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(await PrefsService.isOnboardingCompleted(), isFalse);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // Skip counts as seen — otherwise the intro reappears on every launch.
    expect(await PrefsService.isOnboardingCompleted(), isTrue);
  });
}
