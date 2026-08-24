import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/models/ai_coach.dart';
import 'package:linka/theme/app_colors.dart';
import 'package:linka/widgets/coach_avatar.dart';
import 'package:linka/widgets/coach_pronunciation.dart';

/// The coach's surfaces read their colours from the [AppColors] theme
/// extension, the same way the app wires them up in `main.dart`.
MaterialApp _app(Widget child, {bool dark = false}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      extensions: [dark ? AppColors.dark : AppColors.light],
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

/// One turn's payload, with the traps that actually occur: a sound that failed
/// across three words, a word the speaker skipped entirely, and a clean word
/// that must not be listed back.
Map<String, dynamic> _turn() => <String, dynamic>{
      'reply': {
        'text': 'Say "are", not "is". Why interesting?',
        'audio': '',
        'audio_format': 'mp3',
      },
      'pronunciation': {
        'overall': 68.0,
        'accuracy': 66.0,
        'fluency': 74.0,
        'completeness': 100.0,
        'prosody': 52.0,
        'words': [
          {
            'word': 'think',
            'accuracy': 45.0,
            'error_type': 'Mispronunciation',
            'weak_phonemes': ['θ'],
          },
          {'word': 'the', 'accuracy': 0.0, 'error_type': 'Omission', 'weak_phonemes': []},
          {'word': 'job', 'accuracy': 92.0, 'error_type': 'None', 'weak_phonemes': []},
        ],
        'weak_sounds': {
          'θ': ['think', 'three', 'things'],
        },
      },
      'corrections': [
        {
          'type': 'grammar',
          'original': 'three things about my job is very interesting',
          'corrected': 'three things about my job are very interesting',
          'rule': 'subject-verb agreement',
          'explanation': 'Plural subject takes a plural verb.',
        },
      ],
      'fluency_note': '',
    };

void main() {
  group('CoachTurn', () {
    test('reads a scored voice turn', () {
      final turn = CoachTurn.fromJson(_turn());
      expect(turn.replyText, contains('Why interesting?'));
      // An empty audio string is no audio, not a zero-length file to play.
      expect(turn.replyAudio, isNull);
      expect(turn.pronunciation!.overall, 68.0);
      expect(turn.pronunciation!.weakSounds['θ'], hasLength(3));
      expect(turn.corrections.single.rule, 'subject-verb agreement');
    });

    test('survives a turn with no pronunciation', () {
      // The single most common shape in production: Azure unset on the server,
      // a take over a minute, or a typed turn. Everything else must still land.
      final payload = _turn()..['pronunciation'] = null;
      final turn = CoachTurn.fromJson(payload);
      expect(turn.pronunciation, isNull);
      expect(turn.corrections, hasLength(1));
      expect(turn.replyText, isNotEmpty);
    });

    test('survives a payload with nothing in it', () {
      final turn = CoachTurn.fromJson(const {});
      expect(turn.replyText, '');
      expect(turn.pronunciation, isNull);
      expect(turn.corrections, isEmpty);
    });

    test('lists back only the words worth looking at, worst first', () {
      final score = CoachTurn.fromJson(_turn()).pronunciation!;
      final weak = score.weakWords;
      expect(weak.map((word) => word.word), ['the', 'think']);
      expect(weak.every((word) => word.accuracy < 60), isTrue);
    });
  });

  group('CoachStats', () {
    test('reads the tracked mistakes', () {
      final stats = CoachStats.fromJson(const {
        'total_tracked': 3,
        'active': 2,
        'resolved': 1,
        'by_kind': {'grammar': 1},
        'top': [
          {
            'kind': 'pronunciation_phoneme',
            'key': '/θ/',
            'occurrences': 9,
            'correction': '',
            'explanation': 'Звук /θ/ проседает',
          },
        ],
      });
      expect(stats.active, 2);
      expect(stats.resolved, 1);
      expect(stats.top.single.occurrences, 9);
    });
  });

  group('widgets', () {
    testWidgets('the score card renders in both themes', (tester) async {
      final score = CoachTurn.fromJson(_turn()).pronunciation!;

      for (final dark in [false, true]) {
        // A key per theme: without it the second pump reuses the first card's
        // State and the word list is still open from the tap below.
        await tester.pumpWidget(
          _app(
            CoachPronunciationCard(
              key: ValueKey(dark),
              pronunciation: score,
            ),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('68'), findsOneWidget);
        expect(find.text('Understandable, not clean'), findsOneWidget);
        expect(find.text('/θ/'), findsOneWidget);
        expect(find.text('think · three · things'), findsOneWidget);
        // The word list is behind a tap: a take with twenty bad words needs a
        // lesson, not a longer card.
        expect(find.text('think'), findsNothing);
        await tester.tap(find.text('2 words to look at'));
        await tester.pumpAndSettle();
        expect(find.text('think'), findsOneWidget);
      }
    });

    testWidgets('a clean take says so instead of listing nothing',
        (tester) async {
      final payload = _turn();
      (payload['pronunciation'] as Map<String, dynamic>)
        ..['words'] = [
          {'word': 'job', 'accuracy': 92.0, 'error_type': 'None', 'weak_phonemes': []},
        ]
        ..['weak_sounds'] = <String, dynamic>{}
        ..['overall'] = 91.0;

      await tester.pumpWidget(
        _app(CoachPronunciationCard(
          pronunciation: CoachTurn.fromJson(payload).pronunciation!,
        )),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('Nothing came out badly in this one.'), findsOneWidget);
      expect(find.textContaining('to look at'), findsNothing);
    });

    testWidgets('every character paints, in every mood', (tester) async {
      for (final persona in const [
        'classic',
        'sarcastic',
        'strict',
        'buddy',
        'examiner',
        'a-character-added-later',
      ]) {
        for (final mood in CoachMood.values) {
          await tester.pumpWidget(
            _app(Center(
              child: CoachAvatar(
                persona: persona,
                accent: const Color(0xFF2563EB),
                mood: mood,
                level: 0.6,
                size: 96,
              ),
            )),
          );
          // Two frames of the blink cycle, so a painter that throws on a shut
          // eye is caught here rather than on someone's phone.
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(milliseconds: 5200));
          expect(tester.takeException(), isNull);
        }
      }
    });
  });
}
