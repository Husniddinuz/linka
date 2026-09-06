import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/screens/writing_prompts_list_screen.dart';
import 'package:linka/services/random_test_picker.dart';
import 'package:linka/theme/app_colors.dart';
import 'package:linka/widgets/random_test_card.dart';

MaterialApp _app(Widget child, {bool dark = false}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      extensions: [dark ? AppColors.dark : AppColors.light],
    ),
    home: child,
  );
}

void main() {
  test('pick() only ever returns a candidate', () {
    final picker = RandomTestPicker(random: Random(7));
    final items = ['a', 'b', 'c'];
    final seen = <String>{};
    for (var i = 0; i < 200; i++) {
      seen.add(picker.pick(items));
    }
    expect(seen, {'a', 'b', 'c'});
    expect(picker.pick(['only']), 'only');
  });

  testWidgets('the card spins and ignores taps while busy', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(
      Scaffold(body: RandomTestCard(subtitle: 'Any test', busy: true, onTap: () => taps++)),
    ));
    await tester.pump();

    expect(find.text('Try a random test'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Try a random test'));
    expect(taps, 0);

    await tester.pumpWidget(_app(
      Scaffold(body: RandomTestCard(subtitle: 'Any test', onTap: () => taps++)),
    ));
    await tester.pump();
    await tester.tap(find.text('Try a random test'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the writing list leads with the shuffle row and hides it while searching', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final prompts = Future.value(const [
      {
        'id': 19,
        'task_number': 1,
        'title': 'The charts below show the results of a survey.',
        'prompt_html': 'Summarise the information.',
        'image_url': null,
        'min_words': 150,
      },
      {
        'id': 21,
        'task_number': 1,
        'title': 'The table below shows rainfall by month.',
        'prompt_html': 'Summarise the information.',
        'image_url': null,
        'min_words': 150,
      },
      {
        'id': 20,
        'task_number': 2,
        'title': 'Some people believe that criminals should go to prison.',
        'prompt_html': 'Give reasons for your answer.',
        'image_url': null,
        'min_words': 250,
      },
    ]);

    await tester.pumpWidget(_app(WritingPromptsListScreen(prompts: prompts), dark: true));
    await tester.pumpAndSettle();

    // Sits above the first prompt, and counts only the selected task.
    expect(find.text('Try a random test'), findsOneWidget);
    expect(find.text('Any of the 2 Task 1 prompts'), findsOneWidget);
    final cardTop = tester.getTopLeft(find.byType(RandomTestCard)).dy;
    final firstPromptTop = tester.getTopLeft(find.textContaining('results of a survey')).dy;
    expect(cardTop, lessThan(firstPromptTop));

    await tester.tap(find.text('Task 2'));
    await tester.pumpAndSettle();
    expect(find.text('Any of the 1 Task 2 prompts'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'prison');
    await tester.pumpAndSettle();
    expect(find.text('Try a random test'), findsNothing);
    expect(find.textContaining('should go to prison'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
