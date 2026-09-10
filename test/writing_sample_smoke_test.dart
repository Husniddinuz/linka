import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/screens/writing_sample_screen.dart';
import 'package:linka/screens/writing_samples_list_screen.dart';
import 'package:linka/screens/writing_test_screen.dart';
import 'package:linka/theme/app_colors.dart';
import 'package:linka/widgets/sample_list_widgets.dart';
import 'package:linka/widgets/writing_report.dart';

/// The sample viewer reads its colours from the [AppColors] theme extension,
/// the same way the app wires them up in `main.dart`.
MaterialApp _app(Widget child, {bool dark = false}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      extensions: [dark ? AppColors.dark : AppColors.light],
    ),
    home: child,
  );
}

/// Shaped like a real row from `/writing-samples/` — the task statement lives
/// in `title`, the rubric in `prompt_html`, and both the essay and the
/// commentary arrive with the markdown their author typed.
const _sample = <String, dynamic>{
  'id': 31,
  'task_number': 1,
  'title': 'The charts below show the average time UK workers spent travelling to work in 2009.',
  'prompt_html': 'Summarise the information by selecting and reporting the main features.\n'
      'Write at least 150 words.',
  'image_url': 'https://example.test/chart.jpg',
  'tutor_name': 'Azizbek Mirzakarimov',
  'tutor_image_url': '',
  'band_score': '8.5',
  'sample_essay_html': 'The pie chart illustrates the distribution of UK workers.\n\n'
      'Overall, **most workers travelled for under half an hour**, while the car dominated.',
  'examiner_comment': '**Estimated Band Score: 8.5**\n\n'
      'The **Task Achievement** is strong: the report selects the right features.',
  'annotations': <Map<String, dynamic>>[
    {'highlighted_text': 'The pie chart illustrates', 'note': 'A clean overview opener.'},
    {'highlighted_text': 'nowhere in this essay', 'note': 'Unplaceable phrase must not crash the viewer.'},
  ],
};

/// Pumps [child] on a phone-width but very tall surface.
///
/// The sample is one long scroll, and a [ListView] does not build what is off
/// screen — on the default 800x600 test window everything below the task card
/// simply would not exist to be found.
Future<void> _pumpTall(WidgetTester tester, Widget child, {bool dark = false}) async {
  tester.view.physicalSize = const Size(1200, 7200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(child, dark: dark));
  await tester.pumpAndSettle();
}

void main() {
  test('inline markdown is turned into spans rather than left as asterisks', () {
    final spans = wInlineBoldSpans('a **bold** b').cast<TextSpan>();
    expect(spans.map((s) => s.text).join(), 'a bold b');
    expect(spans.where((s) => s.style?.fontWeight == FontWeight.w700).single.text, 'bold');

    // An unclosed marker is prose, not markup — leaving it alone beats eating
    // the rest of the paragraph.
    final unclosed = wInlineBoldSpans('rated 5**').cast<TextSpan>();
    expect(unclosed.map((s) => s.text).join(), 'rated 5**');
  });

  testWidgets('the sample renders the task, the model answer and the commentary', (tester) async {
    await _pumpTall(tester, const WritingSampleScreen(sample: _sample));

    expect(find.text('Task 1 sample'), findsOneWidget);
    expect(find.text('Azizbek Mirzakarimov'), findsOneWidget);
    expect(find.text('8.5'), findsOneWidget);
    expect(find.text('Model answer'), findsOneWidget);
    expect(find.text('Why this scores well'), findsOneWidget);

    // The task is drawn by the shared report card, so the sample inherits its
    // Task/min-words tags and its question-first layout.
    expect(find.byType(WTaskCard), findsOneWidget);
    expect(find.text('Task 1'), findsOneWidget);
    expect(find.text('Minimum 150 words'), findsOneWidget);

    // Markdown reaches the screen as weight, not punctuation.
    expect(find.textContaining('most workers travelled for under half an hour'), findsOneWidget);
    expect(find.textContaining('Estimated Band Score: 8.5'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
  });

  testWidgets('tapping a highlight opens the tutor note', (tester) async {
    await _pumpTall(tester, const WritingSampleScreen(sample: _sample));

    expect(find.text('Tap a highlighted phrase to read why it works.'), findsOneWidget);

    // Only the phrase that is actually in the essay is marked; the second
    // annotation quotes text that is not, and is skipped silently.
    final essayFinder = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('The pie chart illustrates'),
    );
    expect(essayFinder, findsOneWidget);

    final richText = tester.widget<RichText>(essayFinder);
    final marked = <TextSpan>[];
    richText.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null) marked.add(span);
      return true;
    });
    expect(marked.length, 1);
    expect(marked.single.text, 'The pie chart illustrates');
  });

  testWidgets('the chart opens full screen from inside a sample', (tester) async {
    await _pumpTall(tester, const WritingSampleScreen(sample: _sample));

    await tester.tap(find.text('Tap the chart to enlarge'));
    await tester.pumpAndSettle();

    expect(find.byType(WChartViewer), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('try-it-yourself opens the editor bound to the sample', (tester) async {
    await _pumpTall(tester, const WritingSampleScreen(sample: _sample));

    await tester.tap(find.text('Try this question yourself'));
    await tester.pumpAndSettle();

    final editor = tester.widget<WritingTestScreen>(find.byType(WritingTestScreen));
    // The submission routes through the sample, not through a prompt id the
    // client made up: a sample's task has no published prompt of its own.
    expect(editor.sampleId, 31);
    expect(editor.prompt['title'], _sample['title']);
    expect(editor.prompt['image_url'], _sample['image_url']);
    // A sample carries no floor of its own, so the editor follows the exam.
    expect(editor.prompt['min_words'], 150);
    expect(find.text('Writing Task 1'), findsOneWidget);
  });

  testWidgets('a task 2 sample answers to the 250-word floor', (tester) async {
    final task2 = Map<String, dynamic>.from(_sample)
      ..['task_number'] = 2
      ..['image_url'] = null;

    await _pumpTall(tester, WritingSampleScreen(sample: task2));

    expect(find.text('Task 2 sample'), findsOneWidget);
    expect(find.text('Minimum 250 words'), findsOneWidget);
    // No chart, no invitation to enlarge one.
    expect(find.text('Tap the chart to enlarge'), findsNothing);
  });

  testWidgets('a sample without notes still reads as a model answer', (tester) async {
    final bare = Map<String, dynamic>.from(_sample)
      ..['annotations'] = const <Map<String, dynamic>>[]
      ..['examiner_comment'] = '';

    await _pumpTall(tester, WritingSampleScreen(sample: bare));

    expect(find.text('The answer Azizbek Mirzakarimov wrote to this task.'), findsOneWidget);
    expect(find.text('Why this scores well'), findsNothing);
    expect(find.text('Try this question yourself'), findsOneWidget);
  });

  testWidgets('the topic list keeps Task 2 one tap away behind a long Task 1', (tester) async {
    // The reason the tabs exist: a tutor with a full Task 1 set used to bury
    // Task 2 below a screen or two of charts, and a student who did not scroll
    // concluded it had never been published.
    final samples = <Map<String, dynamic>>[
      for (var i = 0; i < 12; i++)
        {..._sample, 'id': 100 + i, 'task_number': 1, 'title': 'Chart topic $i'},
      {..._sample, 'id': 200, 'task_number': 2, 'title': 'Some people think exams are unfair.'},
    ];

    await tester.pumpWidget(_app(
      WritingSampleTutorTopicsScreen(
        tutorId: 21,
        tutorName: 'Azizbek Mirzakarimov',
        tutorImageUrl: null,
        samples: Future.value(samples),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Chart topic 0'), findsOneWidget);
    expect(find.text('Some people think exams are unfair.'), findsNothing);

    await tester.tap(find.text('Task 2'));
    await tester.pumpAndSettle();

    expect(find.text('Some people think exams are unfair.'), findsOneWidget);
    expect(find.text('Chart topic 0'), findsNothing);
  });

  testWidgets('leaving the topic list before it loads unmounts cleanly', (tester) async {
    // The list fires both its samples fetch and its Plus check in initState,
    // and a widget test has no network for either; what matters is that the
    // screen tears down mid-flight without either completing onto a dead State.
    await tester.pumpWidget(_app(
      const WritingSampleTutorTopicsScreen(
        tutorId: 21,
        tutorName: 'Azizbek Mirzakarimov',
        tutorImageUrl: null,
      ),
    ));
    await tester.pump();
    expect(find.text('Azizbek Mirzakarimov'), findsOneWidget);

    await tester.pumpWidget(_app(const SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the library opens on a row per tutor, not a grid of faces', (tester) async {
    // The grid this replaced was indistinguishable from the Tutors directory,
    // and from the Speaking library it sits next to. Rows, a header that says
    // what the page is, and a per-tutor count make it read as an index.
    await tester.pumpWidget(_app(
      WritingSamplesListScreen(
        tutors: Future.value(const [
          {
            'tutor_id': 21,
            'tutor_name': 'Azizbek Mirzakarimov',
            'tutor_image_url': null,
            'tutor_writing_score': 8.0,
            'sample_count': 4,
          },
          {
            'tutor_id': null,
            'tutor_name': 'Malika Yusupova',
            'tutor_image_url': null,
            'tutor_writing_score': null,
            'sample_count': 1,
          },
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Read real high-band essays'), findsOneWidget);
    expect(find.textContaining('5 model answers from 2 tutors'), findsOneWidget);
    expect(find.text('4 topics'), findsOneWidget);
    // Singular, so a tutor with one essay does not read as "1 topics".
    expect(find.text('1 topic'), findsOneWidget);
    // The tutor's own credential, not any one essay's band.
    expect(find.text('IELTS WRITING 8.0'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('a tutor with no photo still gets a tile rather than a hole', (tester) async {
    // Most Writing samples carry no tutor image at all, which is what made the
    // old grid render as a wall of blank cards.
    await tester.pumpWidget(_app(
      WritingSamplesListScreen(
        tutors: Future.value(const [
          {
            'tutor_id': 21,
            'tutor_name': 'Azizbek Mirzakarimov',
            'tutor_image_url': null,
            'tutor_writing_score': 8.0,
            'sample_count': 4,
          },
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SampleArtworkFallback), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('searching narrows the index to one tutor', (tester) async {
    await tester.pumpWidget(_app(
      WritingSamplesListScreen(
        tutors: Future.value(const [
          {
            'tutor_id': 21,
            'tutor_name': 'Azizbek Mirzakarimov',
            'tutor_image_url': null,
            'tutor_writing_score': 8.0,
            'sample_count': 4,
          },
          {
            'tutor_id': 22,
            'tutor_name': 'Malika Yusupova',
            'tutor_image_url': null,
            'tutor_writing_score': 7.5,
            'sample_count': 1,
          },
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'malika');
    await tester.pumpAndSettle();

    expect(find.text('Malika Yusupova'), findsOneWidget);
    expect(find.text('Azizbek Mirzakarimov'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nobody');
    await tester.pumpAndSettle();
    expect(find.text('No tutors match that search.'), findsOneWidget);
  });

  testWidgets('a locked topic shows the paywall instead of the band', (tester) async {
    // A locked sample arrives with its content stripped, so the row has no
    // band or chart to lead with — and must not imply the essay is readable.
    final samples = <Map<String, dynamic>>[
      for (var i = 0; i < 5; i++)
        {
          ..._sample,
          'id': 300 + i,
          'task_number': 2,
          'title': 'Essay $i',
          'image_url': null,
          if (i == 4) 'locked': true,
          if (i == 4) 'band_score': null,
          if (i == 4) 'annotations': const <Map<String, dynamic>>[],
        },
    ];

    // Five rows do not fit the default test window, and the locked one is
    // last — the point of the test.
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(
      WritingSampleTutorTopicsScreen(
        tutorId: null,
        tutorName: 'Malika Yusupova',
        tutorImageUrl: null,
        tutorWritingScore: '7.5',
        samples: Future.value(samples),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Task 2'));
    await tester.pumpAndSettle();

    expect(find.text('LINKA PLUS'), findsOneWidget);
    expect(find.text('IELTS WRITING 7.5'), findsOneWidget);
    expect(find.textContaining('5 model answers'), findsOneWidget);
  });

  testWidgets('the sample takes its ink from the dark theme', (tester) async {
    await _pumpTall(tester, const WritingSampleScreen(sample: _sample), dark: true);

    expect(find.text('Model answer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
