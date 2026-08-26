import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/screens/writing_progress_screen.dart';
import 'package:linka/screens/writing_prompts_list_screen.dart';
import 'package:linka/screens/writing_result_screen.dart';
import 'package:linka/theme/app_colors.dart';
import 'package:linka/widgets/writing_grading_progress.dart';
import 'package:linka/widgets/writing_report.dart';

/// Every report surface reads its colours from the [AppColors] theme
/// extension, the same way the app wires them up in `main.dart`.
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
  const essay = 'Many people beleive that education is important.\n\nFirstly, it help '
      'the economy. Moreover, it help society. Moreover, it help families.';

  final errors = <Map<String, dynamic>>[
    {
      'quote': 'beleive',
      'correction': 'believe',
      'category': 'spelling',
      'grammar_topic': null,
      'explanation': 'Spelling: i before e except after c.',
      'severity': 'high',
    },
    {
      'quote': 'it help the economy',
      'correction': 'it helps the economy',
      'category': 'grammar',
      'grammar_topic': 'subject_verb_agreement',
      'explanation': 'Third person singular takes -s.',
      'severity': 'medium',
    },
    {
      'quote': 'nowhere in the essay',
      'correction': 'x',
      'category': 'grammar',
      'grammar_topic': 'articles',
      'explanation': 'Unplaceable quote must not crash the highlighter.',
      'severity': 'low',
    },
  ];

  test('highlighter places findable quotes and skips the rest', () {
    final segments = wHighlightEssay(essay, errors);
    final marked = segments.where((s) => s.errorIndex != null).toList();
    expect(marked.length, 2);
    expect(marked.map((s) => s.errorIndex).toSet(), {0, 1});
    expect(segments.map((s) => s.text).join(), essay);
  });

  test('labels fall back rather than throwing on unknown keys', () {
    expect(wTopicLabel('articles'), 'Articles (a / an / the)');
    expect(wTopicLabel('future_perfect_continuous'), 'Future Perfect Continuous');
    expect(wHabitSentence('overused_linkers', 'Moreover', 3), 'You used the linker “Moreover” 3 times.');
    expect(wHabitSentence('thin_paragraphing', '', 1), 'The whole answer sits in 1 paragraph.');
    expect(wFormatBand('7'), '7.0');
    expect(wFormatBand(null), '—');
    expect(wFormatDelta(0.5), '+0.5');
    expect(wFormatDelta(-0.5), '-0.5');
  });

  testWidgets('report sections render from a full analysis payload', (tester) async {
    await tester.pumpWidget(_app(
      Scaffold(
        body: ListView(
          children: [
            WNextSteps(steps: const [
              {'title': 'Fix subject–verb agreement', 'detail': 'Check every verb after a singular noun.', 'criterion': 'grammar_accuracy'},
            ]),
            WHabitsSection(
              counted: const [
                {'code': 'overused_linkers', 'detail': 'Moreover', 'count': 3, 'evidence': ['Moreover', 'Moreover', 'Moreover']},
              ],
              observed: const [
                {'title': 'You never concede a counter-argument', 'detail': 'Every paragraph agrees.', 'cost': 'Caps Task Achievement at 6.'},
              ],
            ),
            WGrammarTopics(topics: const [
              {'topic': 'subject_verb_agreement', 'error_count': 3, 'why': 'It breaks accuracy.', 'practice': 'Rewrite ten sentences.'},
            ]),
            WAnnotatedEssay(essayText: essay, errors: errors, wordCount: 24),
            for (var i = 0; i < errors.length; i++) WCorrectionCard(error: errors[i], index: i),
            WVocabularyUpgrades(upgrades: const [
              {'original': 'important', 'suggestion': 'pivotal', 'note': 'Stronger and less common.'},
            ]),
            WStatsStrip(stats: const {
              'word_count': 24,
              'sentence_count': 4,
              'paragraph_count': 2,
              'avg_sentence_length': 6.0,
              'unique_words': 19,
              'lexical_diversity': 0.79,
            }),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('You used the linker “Moreover” 3 times.'), findsOneWidget);
    expect(find.text('Subject–verb agreement'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Distinct words'), 300);
    expect(find.text('Distinct words'), findsOneWidget);

    // Tapping a marked span opens that correction in a sheet.
    await tester.tap(find.byType(RichText).first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the grading panel narrates the stages while marking runs', (tester) async {
    await tester.pumpWidget(_app(
      const Scaffold(body: SingleChildScrollView(child: WritingGradingProgress())),
    ));
    await tester.pump();

    expect(find.text('Marking your essay'), findsOneWidget);
    expect(find.text('Reading your essay'), findsOneWidget);
    expect(find.textContaining('30–60 seconds'), findsOneWidget);

    // The clock is wall-clock driven, so a pumped frame advances the stages.
    await tester.pump(const Duration(seconds: 40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the graded report renders end to end from an attempt', (tester) async {
    // The share card is laid out offscreen at a fixed 320pt for SF Pro; the
    // test font's square glyphs are far wider and overflow it. That is a
    // property of the test font, not of the report this test is about.
    // A tall surface so the whole report builds at once: a ListView only
    // builds what is near the viewport, and this test is about every section
    // being there.
    tester.view.physicalSize = const Size(1400, 14000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final onError = FlutterError.onError!;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) return;
      onError(details);
    };
    addTearDown(() => FlutterError.onError = onError);

    final attempt = <String, dynamic>{
      'id': 12,
      'status': 'graded',
      'essay_text': essay,
      'word_count': 24,
      'submitted_at': '2026-08-01T10:00:00Z',
      'overall_band': '6.5',
      'task_achievement': '6.0',
      'coherence_cohesion': '6.5',
      'lexical_resource': '7.0',
      'grammar_accuracy': '6.0',
      'feedback': 'A solid answer held back by verb agreement.',
      'error_message': '',
      'prompt': {'id': 3, 'task_number': 2, 'title': 'Education and the economy', 'min_words': 250, 'image_url': null},
      'analysis': {
        'version': 1,
        'summary': 'Clear position, but agreement errors repeat throughout.',
        'criteria': {
          'task_achievement': {
            'band': 6.0,
            'verdict': 'Both parts covered.',
            'strengths': ['Clear position'],
            'improvements': ['Develop the second body paragraph'],
          },
          'coherence_cohesion': {'band': 6.5, 'verdict': 'Logical order.', 'strengths': [], 'improvements': []},
          'lexical_resource': {'band': 7.0, 'verdict': 'Good range.', 'strengths': ['Precise word choice'], 'improvements': []},
          'grammar_accuracy': {'band': 6.0, 'verdict': 'Agreement slips.', 'strengths': [], 'improvements': ['Check singular subjects']},
        },
        'errors': errors,
        'habits': [
          {'title': 'You never concede a counter-argument', 'detail': 'Every paragraph agrees.', 'cost': 'Caps Task Achievement at 6.'},
        ],
        'grammar_topics': [
          {'topic': 'subject_verb_agreement', 'error_count': 3, 'why': 'It breaks accuracy.', 'practice': 'Rewrite ten sentences.'},
        ],
        'vocabulary_upgrades': [
          {'original': 'important', 'suggestion': 'pivotal', 'note': 'Stronger and less common.'},
        ],
        'next_steps': [
          {'title': 'Fix subject–verb agreement', 'detail': 'Check every verb after a singular noun.', 'criterion': 'grammar_accuracy'},
        ],
        'stats': {
          'word_count': 24,
          'sentence_count': 4,
          'paragraph_count': 2,
          'avg_sentence_length': 6.0,
          'unique_words': 19,
          'lexical_diversity': 0.79,
          'habits': [
            {'code': 'overused_linkers', 'detail': 'Moreover', 'count': 3, 'evidence': ['Moreover', 'Moreover']},
          ],
        },
      },
    };

    await tester.pumpWidget(_app(WritingResultScreen(attempt: attempt)));
    // Fixed pumps rather than pumpAndSettle: the staggered reveals and the
    // band ring are still animating, and the profile fetch never resolves in a
    // test.
    await tester.pump(const Duration(seconds: 2));

    // Every section the diagnostic feeds.
    for (final heading in const [
      'AI Coach',
      'What to Work On Next',
      'Score Breakdown',
      'Patterns In This Essay',
      'Grammar To Revise',
      'Your Essay',
      'Corrections',
      'Stronger Word Choices',
      'Essay Statistics',
    ]) {
      expect(find.text(heading), findsWidgets, reason: 'missing section: $heading');
    }

    // The diagnostic's own content, not just its headings.
    expect(find.text('Fix subject–verb agreement'), findsOneWidget);
    expect(find.text('You used the linker “Moreover” 3 times.'), findsOneWidget);
    expect(find.textContaining('2 corrections are marked'), findsOneWidget);
    expect(find.text('pivotal'), findsOneWidget);

    // The grader's own verdict replaces the generic band descriptor, and the
    // server's counted stats replace the locally derived ones.
    expect(find.text('Agreement slips.'), findsOneWidget);
    expect(find.text('Distinct words'), findsOneWidget);
  });

  testWidgets('the progress view reads a full insights payload', (tester) async {
    tester.view.physicalSize = const Size(1400, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const insights = <String, dynamic>{
      'attempts_graded': 5,
      'attempts_analysed': 5,
      'has_history': true,
      'band_average': 6.3,
      'band_best': 7.0,
      'band_latest': 6.5,
      'band_change': 0.5,
      'band_history': [
        {'attempt_id': 1, 'submitted_at': '2026-06-01T10:00:00Z', 'task_number': 2, 'title': 'City transport', 'overall_band': 6.0, 'word_count': 262},
        {'attempt_id': 2, 'submitted_at': '2026-07-01T10:00:00Z', 'task_number': 1, 'title': 'Coffee exports chart', 'overall_band': 6.5, 'word_count': 171},
        {'attempt_id': 3, 'submitted_at': '2026-08-01T10:00:00Z', 'task_number': 2, 'title': 'Education and the economy', 'overall_band': 7.0, 'word_count': 288},
      ],
      'criteria': [
        {'key': 'task_achievement', 'average': 6.5, 'latest': 6.5, 'best': 7.0, 'change': 0.5, 'is_weakest': false},
        {'key': 'coherence_cohesion', 'average': 6.5, 'latest': 6.5, 'best': 7.0, 'change': null, 'is_weakest': false},
        {'key': 'lexical_resource', 'average': 6.5, 'latest': 7.0, 'best': 7.0, 'change': 0.5, 'is_weakest': false},
        {'key': 'grammar_accuracy', 'average': 5.5, 'latest': 6.0, 'best': 6.0, 'change': -0.5, 'is_weakest': true},
      ],
      'recurring_topics': [
        {
          'topic': 'articles',
          'error_count': 9,
          'attempt_count': 4,
          'attempts_analysed': 5,
          'share_of_attempts': 0.8,
          'is_persistent': true,
          'last_seen_at': '2026-08-01T10:00:00Z',
          'why': 'Article slips are the most visible accuracy error.',
          'practice': 'Rewrite a paragraph adding every missing article.',
        },
        {
          'topic': 'modals',
          'error_count': 1,
          'attempt_count': 1,
          'attempts_analysed': 5,
          'share_of_attempts': 0.2,
          'is_persistent': false,
          'last_seen_at': null,
          'why': 'One-off.',
          'practice': '',
        },
      ],
      'recurring_categories': [
        {'category': 'grammar', 'error_count': 12, 'attempt_count': 5},
      ],
      'persistent_habits': [
        {'code': 'overused_linkers', 'attempt_count': 4, 'attempts_analysed': 5, 'share_of_attempts': 0.8, 'latest_count': 3, 'examples': ['Moreover', 'Furthermore']},
      ],
      'focus': [
        {'kind': 'criterion', 'key': 'grammar_accuracy', 'value': 5.5, 'practice': 'Proofread for agreement before submitting.'},
        {'kind': 'grammar_topic', 'key': 'articles', 'value': 4},
        {'kind': 'habit', 'key': 'overused_linkers', 'value': 4},
      ],
    };

    await tester.pumpWidget(_app(const Scaffold(body: WritingInsightsView(insights: insights))));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Up +0.5 bands on your recent essays.'), findsOneWidget);
    expect(find.text('Grammatical range & accuracy is your weakest criterion, averaging 5.5.'), findsOneWidget);
    expect(find.text('Articles (a / an / the) has cost you marks in 4 essays.'), findsOneWidget);
    expect(find.text('You lean on the same linking words — in 4 essays.'), findsOneWidget);
    // Only the persistent topic is listed; a one-off is a bad day, not a gap.
    expect(find.text('Modal verbs'), findsNothing);
    expect(find.text('Weakest'), findsOneWidget);
    expect(find.text('Education and the economy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the task card shows the question, not just the instruction', (tester) async {
    const prompt = <String, dynamic>{
      'id': 20,
      'task_number': 2,
      'title': 'Some people believe that people who commit crimes should be sent to prison. '
          'However, others argue that there are better alternatives for minor crimes. '
          'Discuss both views and give your own opinion.',
      'prompt_html': 'Give reasons for your answer and include any relevant examples from your own '
          'knowledge or experience.\nWrite at least 250 words.',
      'image_url': null,
      'min_words': 250,
    };

    await tester.pumpWidget(_app(const Scaffold(body: WTaskCard(prompt: prompt))));
    await tester.pump();

    // The question is the title field; the instruction is prompt_html. Both
    // have to be on screen — the instruction alone says nothing to write about.
    expect(find.textContaining('people who commit crimes should be sent to prison'), findsOneWidget);
    expect(find.textContaining('Write at least 250 words'), findsOneWidget);
    expect(find.text('Task 2'), findsOneWidget);
    expect(find.text('Minimum 250 words'), findsOneWidget);
  });

  test('prompt markup is stripped into paragraphs', () {
    expect(
      wPromptParagraphs('<p>First block.</p><p>Second <b>block</b>.<br>Same block.</p>'),
      ['First block.', 'Second block.\nSame block.'],
    );
    // What the API actually stores today: plain text with a hard newline.
    expect(
      wPromptParagraphs('Summarise the information.\nWrite at least 150 words.'),
      ['Summarise the information.\nWrite at least 150 words.'],
    );
    expect(wPromptParagraphs(null), isEmpty);
  });

  testWidgets('the report takes its ink from the dark theme, not the light navy', (tester) async {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(
      dark: true,
      Scaffold(
        backgroundColor: AppColors.dark.background,
        body: ListView(
          children: [
            WNextSteps(steps: const [
              {'title': 'Fix subject–verb agreement', 'detail': 'Check every verb.', 'criterion': 'grammar_accuracy'},
            ]),
            WAnnotatedEssay(essayText: essay, errors: errors, wordCount: 24),
            WStatsStrip(stats: const {
              'word_count': 24,
              'sentence_count': 4,
              'paragraph_count': 2,
              'avg_sentence_length': 6.0,
              'unique_words': 19,
              'lexical_diversity': 0.79,
            }),
          ],
        ),
      ),
    ));
    await tester.pump();

    // Body copy must be the dark palette's near-white, never the light theme's
    // navy — that pairing is the bug this guards.
    final step = tester.widget<Text>(find.text('Fix subject–verb agreement'));
    expect(step.style?.color, AppColors.dark.textPrimary);

    final stat = tester.widget<Text>(find.text('Distinct words'));
    expect(stat.style?.color, AppColors.dark.textSecondary);

    // Cards sit on the dark surface, not on white.
    final card = tester.widget<Container>(
      find.ancestor(of: find.text('Distinct words'), matching: find.byType(Container)).first,
    );
    expect((card.decoration as BoxDecoration).color, AppColors.dark.surface);

    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving the prompt list before it loads unmounts cleanly', (tester) async {
    await tester.pumpWidget(_app(dark: true, const WritingPromptsListScreen()));
    await tester.pump(const Duration(seconds: 1));

    // Still on the spinner — the tabs have never been built. Unmounting here
    // used to construct the TabController from inside dispose().
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('the prompt list leads with the question and switches tasks', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final prompts = Future.value(const [
      {
        'id': 19,
        'task_number': 1,
        'title': 'The charts below show the results of a survey conducted by a university library.',
        'prompt_html': 'Summarise the information.\nWrite at least 150 words.',
        'image_url': null,
        'min_words': 150,
      },
      {
        'id': 20,
        'task_number': 2,
        'title': 'Some people believe that people who commit crimes should be sent to prison.',
        'prompt_html': 'Give reasons for your answer.\nWrite at least 250 words.',
        'image_url': null,
        'min_words': 250,
      },
    ]);

    await tester.pumpWidget(_app(WritingPromptsListScreen(prompts: prompts)));
    await tester.pumpAndSettle();

    // The card carries the question itself, not a truncated label.
    expect(find.textContaining('survey conducted by a university library'), findsOneWidget);
    // Each tab counts what is behind it.
    expect(find.text('Charts & data'), findsOneWidget);
    expect(find.text('Essays'), findsOneWidget);

    await tester.tap(find.text('Task 2'));
    await tester.pumpAndSettle();
    expect(find.textContaining('should be sent to prison'), findsOneWidget);

    // Search filters within the selected task.
    await tester.enterText(find.byType(TextField), 'library');
    await tester.pumpAndSettle();
    expect(find.text('No task matches that search.'), findsOneWidget);

    await tester.tap(find.text('Task 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('survey conducted by a university library'), findsOneWidget);
  });

  testWidgets('the chart opens full screen with the question kept in view', (tester) async {
    const prompt = <String, dynamic>{
      'id': 19,
      'task_number': 1,
      'title': 'The charts below show the results of a survey conducted by a university library.',
      'prompt_html': 'Summarise the information.\nWrite at least 150 words.',
      'image_url': 'https://example.test/chart.jpg',
      'min_words': 150,
    };

    await tester.pumpWidget(_app(const Scaffold(body: SingleChildScrollView(child: WTaskCard(prompt: prompt)))));
    await tester.pump();

    // A chart at card size is unreadable — the affordance has to be explicit.
    expect(find.text('Tap the chart to enlarge'), findsOneWidget);

    await tester.tap(find.text('Tap the chart to enlarge'));
    await tester.pumpAndSettle();

    expect(find.byType(WChartViewer), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    // The question stays on screen: zooming into a series is useless if you
    // have lost track of what you were asked to describe.
    expect(find.textContaining('survey conducted by a university library'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(WChartViewer), findsNothing);
  });
}
