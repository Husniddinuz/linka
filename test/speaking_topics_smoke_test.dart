import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/screens/speaking_topics_screen.dart';
import 'package:linka/theme/app_colors.dart';

/// The topic screen reads its colours from the [AppColors] theme extension,
/// the same way the app wires them up in `main.dart`.
MaterialApp _app(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.light,
      extensions: const [AppColors.light],
    ),
    home: child,
  );
}

/// One topic as `/speaking-topics/` returns it. Part 1 is deliberately a long
/// numbered list — that is what the real bank holds, and it is the case the
/// clamp exists for.
Map<String, dynamic> _topic({int sampleCount = 4}) => <String, dynamic>{
      'id': 15,
      'title': 'Work and studies.',
      'sample_count': sampleCount,
      'parts': [
        {
          'id': 40,
          'part': 1,
          'title': 'Work and studies.',
          'question_text': List.generate(10, (i) => '${i + 1}. Question number ${i + 1}?').join('\n\n'),
        },
        {
          'id': 41,
          'part': 2,
          'title': 'Describe a job you would like to do.',
          'question_text': 'You should say what it is and why it appeals to you.',
        },
      ],
    };

void main() {
  group('SpeakingTopicScreen', () {
    testWidgets('shows every part with its question and a way to answer it',
        (tester) async {
      await tester.pumpWidget(_app(SpeakingTopicScreen(topic: _topic())));

      expect(find.text('Work and studies.'), findsWidgets);
      expect(find.text('PART 1'), findsOneWidget);
      expect(find.text('PART 2'), findsOneWidget);
      expect(find.text('Describe a job you would like to do.'), findsOneWidget);
      // One record button per question — a topic is answered part by part.
      expect(find.text('Answer this yourself'), findsNWidgets(2));
    });

    testWidgets('a long question is clamped until it is expanded', (tester) async {
      await tester.pumpWidget(_app(SpeakingTopicScreen(topic: _topic())));

      final toggle = find.text('Show all questions');
      expect(toggle, findsOneWidget);
      // The short Part 2 question gets no toggle of its own.
      expect(find.text('Show less'), findsNothing);

      await tester.tap(toggle);
      await tester.pump();

      expect(find.text('Show less'), findsOneWidget);
      expect(find.text('Show all questions'), findsNothing);
    });

    testWidgets('offers the tutors who recorded the topic only when there are some',
        (tester) async {
      await tester.pumpWidget(_app(SpeakingTopicScreen(topic: _topic())));
      expect(find.text('Hear how 4 tutors answered this'), findsOneWidget);

      await tester.pumpWidget(_app(SpeakingTopicScreen(topic: _topic(sampleCount: 0))));
      expect(find.textContaining('Hear how'), findsNothing);
      // A topic nobody has recorded is still answerable.
      expect(find.text('Answer this yourself'), findsNWidgets(2));
    });
  });
}
