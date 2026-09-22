import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/models/course_reel.dart';
import 'package:linka/screens/course_reels_map_screen.dart';
import 'package:linka/screens/reel_practice_screen.dart';
import 'package:linka/theme/app_colors.dart';

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
}
