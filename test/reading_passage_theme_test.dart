import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/screens/mock_test_taking_screen.dart';
import 'package:linka/theme/app_colors.dart';
import 'package:linka/theme/app_theme.dart';

/// Renders nothing; exists only to hand a themed BuildContext to the test.
Future<BuildContext> _contextUnder(WidgetTester tester, ThemeData theme) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  // MaterialApp animates between themes, so a bare pump leaves the tree on
  // the previous palette — settle before reading colors off the context.
  await tester.pumpAndSettle();
  expect(Theme.of(captured).brightness, theme.brightness);
  return captured;
}

void main() {
  group('passage paper', () {
    testWidgets('every tint stays readable under the passage ink', (tester) async {
      // The passage text is AppColors.textPrimary, so a paper that doesn't
      // flip with the theme puts near-white text on a white sheet.
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final context = await _contextUnder(tester, theme);
        final ink = context.colors.textPrimary;
        for (var i = 0; i < kPassageBackgroundOptions.length; i++) {
          final paper = passagePaperColor(context, i);
          expect(
            (paper.computeLuminance() - ink.computeLuminance()).abs(),
            greaterThan(0.5),
            reason: 'option $i has too little contrast under $theme',
          );
        }
      }
    });

    testWidgets('the same option picks a different sheet per theme', (tester) async {
      final light = await _contextUnder(tester, AppTheme.light);
      final lightPapers = [
        for (var i = 0; i < kPassageBackgroundOptions.length; i++)
          passagePaperColor(light, i),
      ];
      final dark = await _contextUnder(tester, AppTheme.dark);
      for (var i = 0; i < kPassageBackgroundOptions.length; i++) {
        expect(passagePaperColor(dark, i), isNot(lightPapers[i]));
      }
      expect(lightPapers.toSet(), hasLength(kPassageBackgroundOptions.length));
    });

    testWidgets('an out-of-range stored index falls back to the plain sheet', (tester) async {
      final context = await _contextUnder(tester, AppTheme.dark);
      expect(passagePaperColor(context, 99), kPassageBackgroundOptions.first.dark);
      expect(passagePaperColor(context, -1), kPassageBackgroundOptions.first.dark);
    });
  });
}
