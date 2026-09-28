import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/models/course_reel.dart';
import 'package:linka/screens/course_reels_map_screen.dart';
import 'package:linka/screens/reel_practice_screen.dart';
import 'package:linka/screens/ielts_course_screen.dart';
import 'package:linka/theme/app_colors.dart';
import 'package:linka/utils/course_icons.dart';
import 'package:material_symbols_icons/symbols.dart';

MaterialApp _app(Widget child, {bool dark = false}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      extensions: [dark ? AppColors.dark : AppColors.light],
    ),
    home: child,
  );
}

Map<String, dynamic> _lessonJson(int id, {bool watched = false, bool completed = false}) => {
      'id': id,
      'course_id': 1,
      'course_title': 'Everyday English',
      'title': 'Lesson $id',
      'description': '',
      'video_url': 'https://cdn.example.com/$id.mp4',
      'poster_url': null,
      'duration_seconds': 0,
      'like_count': 3,
      'comment_count': 1,
      'exercise_count': 2,
      'liked': false,
      'saved': true,
      'practice_required': true,
      'progress': {
        'position_seconds': 12.5,
        'duration_seconds': 40,
        'watched': watched,
        'practice_completed': completed,
        'completed': completed,
      },
    };

void main() {
  group('course sections', () {
    test('detail parses sections, icons and each lesson\'s section', () {
      final course = ReelCourse.fromJson({
        'id': 7,
        'title': 'Linka IELTS',
        'icon': 'language',
        'sections': [
          {
            'id': 3,
            'title': 'Speaking',
            'description': 'Talk every day.',
            'icon': 'record_voice_over',
            'planned_lessons': 10,
            'lessons_count': 2,
            'owned': false,
          },
        ],
        'subscription': {
          'price_uzs': 99000,
          'duration_days': 30,
          'is_free': false,
          'active': false,
          'ends_at': null,
        },
        'lessons': [
          {..._lessonJson(1, watched: true, completed: true), 'section_id': 3},
          {..._lessonJson(2), 'section_id': 3, 'locked': true},
          _lessonJson(3),
        ],
      });
      expect(courseIcon(course.icon), Symbols.language_rounded);
      final section = course.sections.single;
      expect(course.subscription!.priceUzs, 99000);
      expect(course.subscription!.periodLabel, 'month');
      expect(course.subscription!.active, isFalse);
      expect(courseIcon(section.icon), Symbols.record_voice_over_rounded);
      expect(course.lessons.map((l) => l.sectionId), [3, 3, null]);
      expect(section.owned, isFalse);
      expect(course.lessons.map((l) => l.locked), [false, true, false]);

      final part = IeltsPart(section, 0, course.lessons.take(2).toList());
      expect(part.unitCount, 10); // planned, not just uploaded
      expect(part.completed, 1);
    });

    test('an active subscription carries its end date', () {
      final sub = ReelSubscription.fromJson({
        'price_uzs': '99000',
        'duration_days': 7,
        'active': true,
        'ends_at': '2026-10-26T10:00:00Z',
      });
      expect(sub.priceUzs, 99000);
      expect(sub.periodLabel, '7 days');
      expect(sub.endsAt!.toUtc(), DateTime.utc(2026, 10, 26, 10));
    });

    test('unknown or empty icon names fall back', () {
      expect(courseIcon(''), Symbols.school_rounded);
      expect(courseIcon('from_a_newer_admin'), Symbols.school_rounded);
    });
  });

  group('models', () {
    test('course detail parses lessons and progress', () {
      final course = ReelCourse.fromJson({
        'id': 1,
        'title': 'Everyday English',
        'language': 'English',
        'lessons_count': 2,
        'completed_count': 1,
        'last_lesson_id': 11,
        'started': true,
        'lessons': [_lessonJson(10, watched: true, completed: true), _lessonJson(11)],
      });
      expect(course.lessons, hasLength(2));
      expect(course.completedFraction, 0.5);
      expect(course.lastLessonId, 11);
      expect(course.lessons.first.progress.completed, isTrue);
      expect(course.lessons.last.progress.positionSeconds, 12.5);
      expect(course.lessons.last.saved, isTrue);
    });

    test('signed video links report when they are about to expire', () {
      final soon = DateTime.now().add(const Duration(minutes: 1));
      final later = DateTime.now().add(const Duration(hours: 3));
      ReelLesson withExpiry(DateTime? at) => ReelLesson.fromJson({
            ..._lessonJson(1),
            'video_url_expires_at':
                at == null ? null : at.millisecondsSinceEpoch ~/ 1000,
          });
      expect(withExpiry(soon).videoUrlExpiring, isTrue);
      expect(withExpiry(later).videoUrlExpiring, isFalse);
      expect(withExpiry(null).videoUrlExpiring, isFalse); // CDN links
    });

    test('markWatched turns green only when no practice is required', () {
      const p = ReelLessonProgress.empty;
      expect(p.markWatched(practiceRequired: true).completed, isFalse);
      expect(p.markWatched(practiceRequired: false).completed, isTrue);
    });

    test('exercise segments and default instructions', () {
      final ex = ReelExercise.fromJson({
        'id': 5,
        'type': 'fill_gaps',
        'instruction': '',
        'segments': [
          {'type': 'text', 'value': 'I '},
          {'type': 'gap', 'index': 0},
          {'type': 'text', 'value': ' here.'},
        ],
        'gap_count': 1,
      });
      expect(ex.type, ReelExerciseType.fillGaps);
      expect(ex.displayInstruction, 'Fill in the gaps');
      expect(ex.segments.where((s) => s.isGap), hasLength(1));
    });
  });

  testWidgets('sentence building reports the tiles in tap order', (tester) async {
    final ex = ReelExercise.fromJson({
      'id': 1,
      'type': 'sentence_building',
      'tiles': ['tea', 'I', 'like'],
    });
    List<String>? answer;
    await tester.pumpWidget(_app(Scaffold(
      body: SentenceBuildingTask(exercise: ex, locked: false, onChanged: (a) => answer = a),
    )));
    await tester.tap(find.text('I'));
    await tester.tap(find.text('like'));
    await tester.tap(find.text('tea'));
    await tester.pump();
    expect(answer, ['I', 'like', 'tea']);
  });

  testWidgets('fill gaps waits for every gap', (tester) async {
    final ex = ReelExercise.fromJson({
      'id': 2,
      'type': 'fill_gaps',
      'segments': [
        {'type': 'gap', 'index': 0},
        {'type': 'text', 'value': ' and '},
        {'type': 'gap', 'index': 1},
      ],
      'gap_count': 2,
    });
    List<String>? answer = const ['x'];
    await tester.pumpWidget(_app(Scaffold(
      body: FillGapsTask(exercise: ex, locked: false, gapResults: null, onChanged: (a) => answer = a),
    )));
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.first, 'salt');
    expect(answer, isNull);
    await tester.enterText(fields.last, 'pepper');
    expect(answer, ['salt', 'pepper']);
  });

  for (final dark in [false, true]) {
    testWidgets('progress map renders every stop (dark: $dark)', (tester) async {
      final lessons = [
        ReelLesson.fromJson(_lessonJson(1, watched: true, completed: true)),
        ReelLesson.fromJson(_lessonJson(2, watched: true)),
        for (var i = 3; i <= 8; i++) ReelLesson.fromJson(_lessonJson(i)),
      ];
      final course = ReelCourse.fromJson({'id': 1, 'title': 'Everyday English', 'lessons_count': 8});
      await tester.pumpWidget(_app(
        CourseReelsMapScreen(course: course, lessons: lessons, currentIndex: 2),
        dark: dark,
      ));
      await tester.pump();
      expect(find.text('Watched 2/8'), findsOneWidget);
      expect(find.text('Practised 1/8'), findsOneWidget);
      expect(find.text('Lesson 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('new exercise types', () {
    ReelExercise ex(Map<String, dynamic> json) =>
        ReelExercise.fromJson({'id': 1, 'solved': false, ...json});

    test('parses options, gap options, sentence and the AI review', () {
      final mc = ex({'type': 'multiple_choice', 'prompt': 'Q?', 'options': ['went', 'goes']});
      expect(mc.type, ReelExerciseType.multipleChoice);
      expect(mc.options, ['went', 'goes']);
      final cg = ex({
        'type': 'choose_gaps',
        'gap_options': [
          ['has', 'have'],
          ['for', 'since'],
        ],
      });
      expect(cg.gapOptions[1], ['for', 'since']);
      expect(ex({'type': 'transform_sentence', 'sentence': 'He go.'}).sentence, 'He go.');
      expect(ex({'type': 'speaking_ai'}).type.isAi, isTrue);
      expect(ex({'type': 'fill_gaps'}).type.isAi, isFalse);

      final r = ReelAnswerResult.fromJson({
        'correct': true,
        'ai': {
          'score': 82,
          'pass_score': 60,
          'corrections': [
            {'original': 'a park', 'corrected': 'the park', 'explanation': 'specific'},
          ],
          'improved': 'Better.',
          'transcript': null,
        },
      });
      expect(r.ai!.score, 82);
      expect(r.ai!.corrections.single.corrected, 'the park');
      expect(r.ai!.transcript, isNull);
      expect(ReelAnswerResult.fromJson({'correct': false}).ai, isNull);
    });

    testWidgets('multiple choice reports the tapped option text', (tester) async {
      String? answer;
      await tester.pumpWidget(_app(Scaffold(
        body: MultipleChoiceTask(
          exercise: ex({'type': 'multiple_choice', 'prompt': 'Yesterday I ___.', 'options': ['went', 'goes', 'going']}),
          locked: false,
          wrong: false,
          onChanged: (a) => answer = a,
        ),
      )));
      await tester.tap(find.text('goes'));
      expect(answer, 'goes');
      await tester.tap(find.text('went'));
      expect(answer, 'went');
    });

    testWidgets('choose gaps fills gap by gap and waits for all', (tester) async {
      List<String>? answer;
      await tester.pumpWidget(_app(Scaffold(
        body: ChooseGapsTask(
          exercise: ex({
            'type': 'choose_gaps',
            'segments': [
              {'type': 'text', 'value': 'She '},
              {'type': 'gap', 'index': 0},
              {'type': 'text', 'value': ' lived here '},
              {'type': 'gap', 'index': 1},
            ],
            'gap_options': [
              ['has', 'have', 'had'],
              ['for', 'since', 'from'],
            ],
          }),
          locked: false,
          gapResults: null,
          onChanged: (a) => answer = a,
        ),
      )));
      expect(find.text('GAP 1'), findsOneWidget);
      await tester.tap(find.text('has'));
      await tester.pump();
      expect(answer, isNull);
      expect(find.text('GAP 2'), findsOneWidget); // moved on by itself
      await tester.tap(find.text('since'));
      await tester.pump();
      expect(answer, ['has', 'since']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('transform sentence shows the sentence and reports the rewrite', (tester) async {
      String? answer;
      await tester.pumpWidget(_app(Scaffold(
        body: TransformSentenceTask(
          exercise: ex({'type': 'transform_sentence', 'sentence': 'They built it.'}),
          locked: false,
          onChanged: (a) => answer = a,
        ),
      )));
      expect(find.text('They built it.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), ' It was built. ');
      expect(answer, 'It was built.');
    });
  });

  group('practice page', () {
    Map<String, dynamic> q(int id, String type, {bool solved = false}) => {
          'id': id,
          'type': type,
          'tiles': ['a$id', 'b$id'],
          'prompt': 'Write about $id',
          'segments': [
            {'type': 'text', 'value': 'x$id '},
            {'type': 'gap', 'index': 0},
          ],
          'gap_count': 1,
          'solved': solved,
          'expected': solved ? 'answer $id' : null,
        };

    final practice = {
      'exercises': [
        q(1, 'sentence_building', solved: true),
        q(2, 'fill_gaps'),
        q(3, 'sentence_building'),
        q(4, 'write_sentence'),
      ],
      'progress': {'watched': true},
    };

    test('splits questions into parts of 10, in lesson order', () {
      final many = ReelPractice.fromJson({
        'exercises': [for (var i = 1; i <= 23; i++) q(i, 'fill_gaps', solved: i <= 10)],
        'progress': <String, dynamic>{},
      }).exercises;
      final parts = PracticePart.split(many);
      expect(parts.map((p) => p.questions.length), [10, 10, 3]);
      expect(parts.map((p) => '${p.first}-${p.last}'), ['1-10', '11-20', '21-23']);
      expect(parts.first.done, isTrue);
      expect(parts[1].solved, 0);
    });

    testWidgets('parts start collapsed; a part opens full screen, one question at a time', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(ReelPracticeScreen(
        lesson: ReelLesson.fromJson(_lessonJson(9)),
        practice: ReelPractice.fromJson(practice),
      )));
      expect(find.text('1 part · 4 questions'), findsOneWidget);
      expect(find.text('Questions 1–4'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget); // 1 of 4 solved
      expect(find.text('a3'), findsNothing);

      await tester.tap(find.text('Questions 1–4'));
      await tester.pumpAndSettle();
      // Q1 was solved earlier, so the runner starts at Q2.
      expect(find.text('2/4'), findsOneWidget);
      expect(find.textContaining('x2'), findsOneWidget);
      expect(find.text('a3'), findsNothing);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('3/4'), findsOneWidget);
      expect(find.text('a3'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('Part 1 finished'), findsOneWidget);
      expect(find.text('Retry 3 unsolved'), findsOneWidget);
      expect(find.text('Back to parts'), findsOneWidget);

      await tester.tap(find.text('Back to parts'));
      await tester.pumpAndSettle();
      expect(find.text('1 part · 4 questions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
