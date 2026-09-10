import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/models/mock_test.dart';
import 'package:linka/models/student_progress.dart';
import 'package:linka/screens/student_progress_screen.dart';
import 'package:linka/theme/app_colors.dart';
import 'package:linka/widgets/band_chart.dart';

MaterialApp _app(Widget child, {bool dark = false}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      extensions: [dark ? AppColors.dark : AppColors.light],
    ),
    home: child,
  );
}

Map<String, dynamic> _mockAttempt({
  required int id,
  required String type,
  required String? band,
  required String status,
  required String submittedAt,
}) =>
    {
      'id': id,
      'test': {'id': id * 10, 'test_type': type, 'number': id, 'title': '$type test $id'},
      'status': status,
      'started_at': submittedAt,
      'submitted_at': status == 'submitted' ? submittedAt : null,
      'answers': <String, dynamic>{},
      'raw_score': 30,
      'max_score': 40,
      'band_score': band,
      'result_detail': <dynamic>[],
    };

void main() {
  group('SkillProgress folding', () {
    test('reading/listening: submitted only, chronological, latest and best', () {
      final attempts = MockTestAttempt.listFromJson([
        // Newest first, as the endpoint returns them.
        _mockAttempt(id: 3, type: 'reading', band: '6.5', status: 'submitted', submittedAt: '2026-08-03T10:00:00Z'),
        _mockAttempt(id: 2, type: 'reading', band: null, status: 'in_progress', submittedAt: '2026-08-02T10:00:00Z'),
        _mockAttempt(id: 1, type: 'reading', band: '7.0', status: 'submitted', submittedAt: '2026-08-01T10:00:00Z'),
        _mockAttempt(id: 4, type: 'listening', band: '5.5', status: 'submitted', submittedAt: '2026-08-04T10:00:00Z'),
      ]);

      final reading = SkillProgress.fromMockAttempts(attempts, 'reading');
      expect(reading.attempts, 2);
      expect(reading.bands, [7.0, 6.5]);
      expect(reading.latest, 6.5);
      expect(reading.best, 7.0);
      expect(reading.average, closeTo(6.75, 0.001));
      expect(reading.change, isNull, reason: 'two sittings is not a trend');
      expect(reading.recent.first.id, 3);

      final listening = SkillProgress.fromMockAttempts(attempts, 'listening');
      expect(listening.attempts, 1);
      expect(listening.latest, 5.5);
    });

    test('writing: from insights band_history, keeping the server count', () {
      final writing = SkillProgress.fromWritingInsights({
        'attempts_graded': 5,
        'band_history': [
          {'attempt_id': 1, 'submitted_at': '2026-07-01T09:00:00+00:00', 'task_number': 2, 'title': 'A', 'overall_band': 5.0, 'word_count': 250},
          {'attempt_id': 2, 'submitted_at': '2026-07-02T09:00:00+00:00', 'task_number': 2, 'title': 'B', 'overall_band': 5.5, 'word_count': 260},
          {'attempt_id': 3, 'submitted_at': '2026-07-03T09:00:00+00:00', 'task_number': 1, 'title': 'C', 'overall_band': 6.0, 'word_count': 180},
          {'attempt_id': 4, 'submitted_at': '2026-07-04T09:00:00+00:00', 'task_number': 2, 'title': 'D', 'overall_band': 6.5, 'word_count': 270},
        ],
      });
      expect(writing.attempts, 5);
      expect(writing.latest, 6.5);
      expect(writing.best, 6.5);
      // mean(5.5, 6.0, 6.5) - mean(5.0) = 1.0
      expect(writing.change, closeTo(1.0, 0.001));
      expect(writing.history.first.subtitle, 'Task 2 · 250 words');
      final source = writing.history.first.source as Map<String, dynamic>;
      expect(source['id'], 1);
      expect(source['status'], 'graded');
    });

    test('speaking: graded only, decimal strings', () {
      final speaking = SkillProgress.fromSpeakingAttempts([
        {'id': 9, 'part': 2, 'question_text': 'Describe a place', 'status': 'graded', 'overall_band': '6.0', 'submitted_at': '2026-08-02T10:00:00Z'},
        {'id': 8, 'part': 1, 'question_text': 'Hometown', 'status': 'pending', 'overall_band': null, 'submitted_at': '2026-08-01T10:00:00Z'},
      ]);
      expect(speaking.attempts, 1);
      expect(speaking.latest, 6.0);
      expect(speaking.history.single.subtitle, 'Part 2');
    });

    test('lessons: finished bookings only, hours to the nearest half', () {
      final lessons = LessonProgress.fromBookings([
        {'status': 'finished', 'duration_minutes': 60},
        {'status': 'finished', 'duration_minutes': 45},
        {'status': 'cancelled', 'duration_minutes': 60},
        {'status': 'paid', 'duration_minutes': 60},
      ]);
      expect(lessons.count, 2);
      expect(lessons.minutes, 105);
      expect(lessons.hours, 2.0);
      expect(lessons.hoursLabel, '2');
      expect(const LessonProgress(count: 1, minutes: 80).hoursLabel, '1.5');
    });

    test('hasAny is false with nothing done anywhere', () {
      const nothing = StudentProgress(
        writing: SkillProgress.empty,
        listening: SkillProgress.empty,
        reading: SkillProgress.empty,
        speaking: SkillProgress.empty,
        lessons: LessonProgress.empty,
      );
      expect(nothing.hasAny, isFalse);
    });
  });

  group('StudentProgressView', () {
    final attempts = MockTestAttempt.listFromJson([
      _mockAttempt(id: 3, type: 'reading', band: '6.5', status: 'submitted', submittedAt: '2026-08-03T10:00:00Z'),
      _mockAttempt(id: 1, type: 'reading', band: '7.0', status: 'submitted', submittedAt: '2026-08-01T10:00:00Z'),
    ]);
    final progress = StudentProgress(
      writing: SkillProgress.fromWritingInsights({
        'attempts_graded': 2,
        'band_change': 0.5,
        'band_history': [
          {'attempt_id': 1, 'submitted_at': '2026-07-01T09:00:00+00:00', 'task_number': 2, 'title': 'A', 'overall_band': 5.5, 'word_count': 250},
          {'attempt_id': 2, 'submitted_at': '2026-07-02T09:00:00+00:00', 'task_number': 2, 'title': 'B', 'overall_band': 6.0, 'word_count': 260},
        ],
      }),
      listening: SkillProgress.empty,
      reading: SkillProgress.fromMockAttempts(attempts, 'reading'),
      speaking: SkillProgress.empty,
      lessons: const LessonProgress(count: 3, minutes: 150),
      writingInsights: const {'band_change': 0.5},
    );

    testWidgets('renders the four tiles and a card per skill', (tester) async {
      await tester.pumpWidget(_app(Scaffold(body: StudentProgressView(progress: progress))));
      await tester.pumpAndSettle();

      expect(find.text('Your Progress'), findsOneWidget);
      expect(find.text('Writing band'), findsOneWidget);
      expect(find.text('Listening band'), findsOneWidget);
      expect(find.text('Reading band'), findsOneWidget);
      expect(find.text('Hours studied'), findsOneWidget);

      // Writing tile: latest band, the server's change badge, essay count.
      expect(find.text('+0.5'), findsOneWidget);
      expect(find.text('2 essays marked'), findsOneWidget);
      // Reading tile: latest band is the newest sitting, not the best.
      expect(find.text('2 tests taken'), findsOneWidget);
      // Hours: 150 minutes is 2.5 hours from 3 lessons.
      expect(find.text('2.5'), findsOneWidget);
      expect(find.text('from 3 lessons'), findsOneWidget);
      // A skill with nothing done still shows a number — zero — with the
      // caption saying what earns the first band.
      expect(find.text('Sit a listening test to get a band'), findsOneWidget);
      expect(find.text('0.0'), findsWidgets);

      // Per-skill cards, scrolled into view one by one (the list is lazy).
      expect(find.byType(BandChart), findsOneWidget);
      expect(find.text('Full writing insights'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Reading'), 200, scrollable: find.byType(Scrollable));
      await tester.pumpAndSettle();
      expect(find.byType(BandChart), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Record a speaking answer to get a band.'),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Record a speaking answer to get a band.'), findsOneWidget);
    });

    testWidgets('a brand-new student sees the same screen, reading zeros', (tester) async {
      const nothing = StudentProgress(
        writing: SkillProgress.empty,
        listening: SkillProgress.empty,
        reading: SkillProgress.empty,
        speaking: SkillProgress.empty,
        lessons: LessonProgress.empty,
      );
      await tester.pumpWidget(_app(Scaffold(body: StudentProgressView(progress: nothing))));
      await tester.pumpAndSettle();

      expect(find.text('Writing band'), findsOneWidget);
      expect(find.text('Hours studied'), findsOneWidget);
      // Three band tiles at 0.0, the hours tile at 0, each with its prompt.
      expect(find.text('0.0'), findsWidgets);
      expect(find.text('0'), findsWidgets);
      expect(find.text('Write an essay to get a band'), findsOneWidget);
      expect(find.text('Book your first lesson'), findsOneWidget);
      // The skill card keeps its stat row and offers the way in.
      expect(find.text('Latest band'), findsWidgets);
      expect(find.text('Write an essay'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(_app(Scaffold(body: StudentProgressView(progress: progress)), dark: true));
      await tester.pumpAndSettle();
      expect(find.text('Your Progress'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
