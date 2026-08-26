import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/theme/app_colors.dart';
import 'package:linka/widgets/speaking_grading_progress.dart';
import 'package:linka/widgets/speaking_report.dart';

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

/// A graded attempt with every section populated, and one deliberate trap in
/// each: a quote that is not in the timings, and a pronunciation criterion the
/// grader could not mark.
Map<String, dynamic> _attempt() => <String, dynamic>{
      'id': 42,
      'sample_part_id': 7,
      'part': 2,
      'question_text': 'Describe a journey you remember well.',
      'audio_url': 'https://example.test/answer.m4a',
      'duration_seconds': 96,
      'transcript': 'I want to talk about a trip I taked to the mountains last year.',
      'word_timings': [
        {'word': 'I', 'start': 0.2, 'end': 0.3},
        {'word': 'want', 'start': 0.3, 'end': 0.5},
        {'word': 'to', 'start': 0.5, 'end': 0.6},
        {'word': 'talk', 'start': 0.6, 'end': 0.9},
        {'word': 'about', 'start': 0.9, 'end': 1.2},
        {'word': 'a', 'start': 1.2, 'end': 1.3},
        {'word': 'trip', 'start': 1.3, 'end': 1.6},
        {'word': 'I', 'start': 1.6, 'end': 1.7},
        {'word': 'taked', 'start': 1.7, 'end': 2.1},
      ],
      'status': 'graded',
      'submitted_at': '2026-08-20T10:00:00Z',
      'graded_at': '2026-08-20T10:01:10Z',
      'fluency_coherence': '6.0',
      'lexical_resource': '6.5',
      'grammar_range_accuracy': '5.5',
      // Never scored: not markable from a transcript.
      'pronunciation': null,
      'overall_band': '6.0',
      'feedback': 'A clear answer let down by past-tense slips.',
      'error_message': '',
      'analysis': {
        'version': 1,
        'summary': 'You kept going for the full two minutes, which is the hard part.',
        'pronunciation_scored': false,
        'pronunciation_note': 'Pronunciation cannot be marked from a transcript.',
        'criteria': {
          'fluency_coherence': {
            'band': 6.0,
            'verdict': 'You reached the end without stalling.',
            'strengths': ['No long silences'],
            'improvements': ['Cut the “you know” openings'],
          },
          'lexical_resource': {
            'band': 6.5,
            'verdict': 'Good range for the topic.',
            'strengths': ['Precise place words'],
            'improvements': [],
          },
          'grammar_range_accuracy': {
            'band': 5.5,
            'verdict': 'Past tense breaks down under pressure.',
            'strengths': [],
            'improvements': ['Drill irregular past forms'],
          },
        },
        'errors': [
          {
            'quote': 'I taked',
            'correction': 'I took',
            'category': 'grammar',
            'grammar_topic': 'verb_tenses',
            'explanation': '“Take” is irregular: took, taken.',
            'severity': 'high',
          },
          {
            'quote': 'a sentence you never said',
            'correction': 'x',
            'category': 'vocabulary',
            'grammar_topic': null,
            'explanation': 'An unplaceable quote must not crash the report.',
            'severity': 'low',
          },
        ],
        'habits': [
          {
            'title': 'You restate the question before answering',
            'detail': 'Both Part 2 answers opened by repeating the cue card.',
            'cost': 'Twelve seconds of your two minutes, unmarked.',
          },
        ],
        'grammar_topics': [
          {
            'topic': 'verb_tenses',
            'error_count': 3,
            'why': 'It breaks accuracy under pressure.',
            'practice': 'Say ten past-tense sentences out loud daily.',
          },
        ],
        'vocabulary_upgrades': [
          {'original': 'very big', 'suggestion': 'vast', 'note': 'One word, higher band.'},
        ],
        'next_steps': [
          {
            'title': 'Drill irregular past forms',
            'detail': 'Ten a day, spoken aloud.',
            'criterion': 'grammar_range_accuracy',
          },
        ],
        'stats': {
          'word_count': 214,
          'unique_words': 118,
          'lexical_diversity': 0.55,
          'duration_seconds': 96,
          'timings_available': true,
          'speech_rate_wpm': 134,
          'pause_count': 11,
          'long_pause_count': 2,
          'pause_seconds_total': 14.2,
          'longest_pause_seconds': 3.4,
          'longest_pauses': [
            {'after': 'because', 'seconds': 3.4},
          ],
          'pause_ratio': 0.15,
          'words_per_run': 19.5,
          'filler_count': 7,
          'filler_rate_per_100_words': 3.3,
          'fillers': [
            {'phrase': 'you know', 'count': 4},
            {'phrase': 'like', 'count': 3},
          ],
          'discourse_markers': [],
          'repetitions': [],
        },
      },
    };

void main() {
  test('quotes are matched to the recording, and unmatched ones are dropped', () {
    final times = sQuoteTimes(_attempt());

    // "I taked" is verbatim in the timings; playback starts a moment before it.
    expect(times.containsKey('I taked'), isTrue);
    expect(times['I taked'], closeTo(1.2, 0.001));

    // A quote that is not in the timings gets no seek rather than a wrong one.
    expect(times.containsKey('a sentence you never said'), isFalse);
  });

  test('quote matching survives an attempt with no timings at all', () {
    final attempt = _attempt()..['word_timings'] = <Map<String, dynamic>>[];
    expect(sQuoteTimes(attempt), isEmpty);
  });

  test('part caps are the exam’s own, with a sane fallback', () {
    expect(sCapForPart(1), 60);
    expect(sCapForPart(2), 120);
    expect(sCapForPart(3), 150);
    // A part number the server invents must not produce a null cap.
    expect(sCapForPart(9), 120);
  });

  test('band tiers and the clock read the way the report prints them', () {
    expect(sBandTier(9.0), 'Expert user');
    expect(sBandTier(7.0), 'Good user');
    expect(sBandTier(6.0), 'Competent user');
    expect(sBandTier(5.0), 'Modest user');
    expect(sBandTier(4.0), 'Still building');
    expect(sClock(96), '1:36');
    expect(sClock(9), '0:09');
  });

  testWidgets('the full report renders every section from a graded attempt', (tester) async {
    // A tall surface so the whole report builds at once: a ListView only
    // builds what is near the viewport, and this test is about every section
    // being there.
    tester.view.physicalSize = const Size(1400, 14000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final heard = <double>[];
    await tester.pumpWidget(_app(
      Scaffold(
        body: SpeakingReportView(
          attempt: _attempt(),
          onHear: heard.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('6.0'), findsWidgets);
    expect(find.text('What to Practise Next'), findsOneWidget);
    expect(find.text('What We Measured'), findsOneWidget);
    expect(find.text('Criterion by Criterion'), findsOneWidget);
    expect(find.text('Corrections'), findsOneWidget);
    expect(find.text('Habits to Break'), findsOneWidget);
    expect(find.text('Grammar to Revise'), findsOneWidget);
    expect(find.text('Stronger Word Choices'), findsOneWidget);
    expect(find.text('What We Heard'), findsOneWidget);

    // The unscored criterion is stated rather than skipped — a student who
    // knows IELTS has four Speaking criteria would otherwise count three and
    // assume the report is broken.
    expect(find.text('Pronunciation'), findsOneWidget);
    expect(find.text('Not scored'), findsOneWidget);
    expect(find.textContaining('cannot be marked from a transcript'), findsOneWidget);

    // Only the placeable quote gets a play button.
    expect(find.text('Hear it'), findsOneWidget);
    await tester.tap(find.text('Hear it'));
    await tester.pump();
    expect(heard, [closeTo(1.2, 0.001)]);
  });

  testWidgets('the report degrades to the bands when there is no analysis', (tester) async {
    tester.view.physicalSize = const Size(1400, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(
      Scaffold(
        body: SpeakingReportView(
          attempt: const {
            'id': 1,
            'part': 1,
            'status': 'graded',
            'overall_band': '5.5',
            'fluency_coherence': '5.5',
            'lexical_resource': '5.5',
            'grammar_range_accuracy': '5.5',
            'pronunciation': null,
            'feedback': 'Marked before the diagnostic shipped.',
            'transcript': '',
            'word_timings': [],
            'analysis': {},
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('5.5'), findsWidgets);
    expect(find.text('Criterion by Criterion'), findsOneWidget);
    // Nothing to say, so nothing is said.
    expect(find.text('Corrections'), findsNothing);
    expect(find.text('What We Heard'), findsNothing);
  });

  testWidgets('the report renders on a dark ground too', (tester) async {
    tester.view.physicalSize = const Size(1400, 14000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(
      Scaffold(body: SpeakingReportView(attempt: _attempt())),
      dark: true,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the marking panel narrates the stages and follows the status', (tester) async {
    await tester.pumpWidget(_app(
      const Scaffold(body: SingleChildScrollView(child: SpeakingGradingProgress())),
    ));
    await tester.pump();

    expect(find.text('Marking your answer'), findsOneWidget);
    expect(find.text('Uploading your recording'), findsOneWidget);
    expect(find.textContaining('about a minute'), findsWidgets);

    // The clock is wall-clock driven, so a pumped frame advances the stages.
    await tester.pump(const Duration(seconds: 45));
    expect(tester.takeException(), isNull);

    // A transcribing attempt is at least past the upload however fast it got
    // there, so the first row is done rather than still spinning.
    await tester.pumpWidget(_app(
      const Scaffold(
        body: SingleChildScrollView(child: SpeakingGradingProgress(status: 'transcribing')),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Listening to your answer'), findsOneWidget);
  });
}
