import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/models/podcast.dart';
import 'package:linka/screens/podcasts_list_screen.dart';
import 'package:linka/services/podcast_progress_service.dart';
import 'package:linka/services/podcast_transcript_service.dart';
import 'package:linka/services/subtitle_service.dart';
import 'package:linka/widgets/podcast_artwork.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SubtitleService.parseSubtitle', () {
    test('parses SRT cues with comma millisecond separators', () {
      const srt = '''
1
00:00:00,000 --> 00:00:05,440
Welcome back to the Deep Dive.

2
00:00:05,740 --> 00:00:09,680
Today we look at health and fitness.
''';
      final cues = SubtitleService.parseSubtitle(srt);

      expect(cues, hasLength(2));
      expect(cues.first.start, Duration.zero);
      expect(cues.first.end, const Duration(milliseconds: 5440));
      expect(cues.first.text, 'Welcome back to the Deep Dive.');
      expect(cues.first.speaker, isNull);
    });

    test('joins wrapped lines and strips VTT/SSA markup', () {
      const vtt = '''
WEBVTT

00:00:01.000 --> 00:00:04.000
{\\an8}<i>A wrapped
line of text</i>
''';
      final cues = SubtitleService.parseSubtitle(vtt);

      expect(cues.single.text, 'A wrapped line of text');
    });

    test('lifts recurring speaker labels out of the text', () {
      const srt = '''
1
00:00:00,000 --> 00:00:02,000
Speaker 1: So where do we start?

2
00:00:02,000 --> 00:00:04,000
Speaker 2: With the basics.

3
00:00:04,000 --> 00:00:06,000
Speaker 1: Makes sense.
''';
      final cues = SubtitleService.parseSubtitle(srt);

      expect(cues.map((c) => c.speaker), ['Speaker 1', 'Speaker 2', 'Speaker 1']);
      expect(cues.first.text, 'So where do we start?');
      expect(SubtitleService.speakers(cues), ['Speaker 1', 'Speaker 2']);
    });

    test('leaves a one-off "Word:" prefix in the text', () {
      const srt = '''
1
00:00:00,000 --> 00:00:02,000
Note: this is ordinary prose.

2
00:00:02,000 --> 00:00:04,000
And so is this.
''';
      final cues = SubtitleService.parseSubtitle(srt);

      expect(cues.first.speaker, isNull);
      expect(cues.first.text, 'Note: this is ordinary prose.');
      expect(SubtitleService.speakers(cues), isEmpty);
    });
  });

  group('SubtitleCue word timings', () {
    final cue = SubtitleCue(
      start: const Duration(seconds: 10),
      end: const Duration(seconds: 14),
      text: 'one two three four',
    );

    test('splits the cue into words spanning its whole duration', () {
      expect(cue.words.map((w) => w.text), ['one', 'two', 'three', 'four']);
      expect(cue.words.first.start, const Duration(seconds: 10));
      expect(cue.words.last.end, const Duration(seconds: 14));
    });

    test('word timings run forward without gaps', () {
      for (var i = 1; i < cue.words.length; i++) {
        expect(cue.words[i].start, cue.words[i - 1].end);
        expect(cue.words[i].end, greaterThan(cue.words[i].start));
      }
    });

    test('wordIndexAt tracks position through the line', () {
      expect(cue.wordIndexAt(const Duration(seconds: 9)), -1);
      expect(cue.wordIndexAt(const Duration(seconds: 10)), 0);
      expect(cue.wordIndexAt(const Duration(seconds: 13, milliseconds: 900)),
          cue.words.length - 1);
      // Past the end, the whole line stays lit.
      expect(cue.wordIndexAt(const Duration(seconds: 20)), cue.words.length - 1);
    });

    test('handles a zero-length cue without dividing by zero', () {
      final instant = SubtitleCue(
        start: const Duration(seconds: 5),
        end: const Duration(seconds: 5),
        text: 'blink and miss',
      );
      expect(instant.words, hasLength(3));
      expect(instant.wordIndexAt(const Duration(seconds: 5)), 2);
    });
  });

  group('cue lookup', () {
    final cues = [
      SubtitleCue(
        start: const Duration(seconds: 0),
        end: const Duration(seconds: 2),
        text: 'first',
      ),
      SubtitleCue(
        start: const Duration(seconds: 5),
        end: const Duration(seconds: 7),
        text: 'second',
      ),
    ];

    test('activeCueIndex reports -1 in the silence between cues', () {
      expect(SubtitleService.activeCueIndex(cues, const Duration(seconds: 3)), -1);
    });

    test('nearestCueIndex holds the line that just finished', () {
      expect(SubtitleService.nearestCueIndex(cues, const Duration(seconds: 3)), 0);
      expect(SubtitleService.nearestCueIndex(cues, const Duration(seconds: 6)), 1);
      expect(SubtitleService.nearestCueIndex(cues, const Duration(seconds: 9)), 1);
    });

    test('nearestCueIndex reports -1 before the first cue starts', () {
      final later = [
        SubtitleCue(
          start: const Duration(seconds: 4),
          end: const Duration(seconds: 6),
          text: 'late start',
        ),
      ];
      expect(
        SubtitleService.nearestCueIndex(later, const Duration(seconds: 1)),
        -1,
      );
    });
  });

  group('PodcastTranscriptService.deriveSubtitleUrl', () {
    test('maps a podcast audio URL to its srt sibling', () {
      expect(
        PodcastTranscriptService.deriveSubtitleUrl(
            'https://cdn.linka.uz/podcasts/audio_729.mp3'),
        'https://cdn.linka.uz/podcasts/srt/audio_729.srt',
      );
    });

    test('returns null when the URL does not follow the layout', () {
      expect(
        PodcastTranscriptService.deriveSubtitleUrl('https://cdn.linka.uz/x.txt'),
        isNull,
      );
    });
  });

  group('PodcastProgressService', () {
    setUp(() {
      PodcastProgressService.resetForTest();
      SharedPreferences.setMockInitialValues({});
    });

    test('records a resume point once past the start threshold', () async {
      await PodcastProgressService.load();
      await PodcastProgressService.save(
        7,
        position: const Duration(minutes: 3),
        duration: const Duration(minutes: 30),
      );

      final progress = PodcastProgressService.of(7)!;
      expect(progress.started, isTrue);
      expect(progress.completed, isFalse);
      expect(progress.remaining, const Duration(minutes: 27));
      expect(progress.fraction, closeTo(0.1, 0.001));
      expect(PodcastProgressService.resumePosition(7), const Duration(minutes: 3));
    });

    test('a few seconds in is not worth resuming', () async {
      await PodcastProgressService.load();
      await PodcastProgressService.save(
        7,
        position: const Duration(seconds: 4),
        duration: const Duration(minutes: 30),
      );

      expect(PodcastProgressService.of(7)!.started, isFalse);
      expect(PodcastProgressService.resumePosition(7), isNull);
      expect(PodcastProgressService.inProgress(), isEmpty);
    });

    test('the tail of an episode counts as played', () async {
      await PodcastProgressService.load();
      await PodcastProgressService.save(
        7,
        position: const Duration(minutes: 29, seconds: 55),
        duration: const Duration(minutes: 30),
      );

      final progress = PodcastProgressService.of(7)!;
      expect(progress.completed, isTrue);
      expect(progress.fraction, 1.0);
      expect(PodcastProgressService.resumePosition(7), isNull);
    });

    test('keeps the last known duration when the player reports none',
        () async {
      await PodcastProgressService.load();
      await PodcastProgressService.save(
        7,
        position: const Duration(minutes: 2),
        duration: const Duration(minutes: 30),
      );
      await PodcastProgressService.save(
        7,
        position: const Duration(minutes: 3),
        duration: Duration.zero,
      );

      expect(PodcastProgressService.of(7)!.duration, const Duration(minutes: 30));
    });

    test('inProgress lists the most recently played episode first', () async {
      await PodcastProgressService.load();
      await PodcastProgressService.save(
        1,
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 30),
      );
      await PodcastProgressService.save(
        2,
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 30),
      );

      expect(
        PodcastProgressService.inProgress().map((p) => p.podcastId),
        containsAll([1, 2]),
      );
      expect(PodcastProgressService.inProgress().first.podcastId, 2);
    });

    test('clear forgets the resume point', () async {
      await PodcastProgressService.load();
      await PodcastProgressService.save(
        7,
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 30),
      );
      await PodcastProgressService.clear(7);

      expect(PodcastProgressService.of(7), isNull);
    });

    test('survives a reload from disk', () async {
      await PodcastProgressService.load();
      await PodcastProgressService.save(
        7,
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 30),
      );

      // Same backing store, fresh in-memory cache.
      PodcastProgressService.resetForTest();
      await PodcastProgressService.load();

      expect(PodcastProgressService.of(7)!.position, const Duration(minutes: 5));
    });
  });

  group('Podcast model', () {
    test('reads the optional fields the content API may omit', () {
      final podcast = Podcast.fromJson({
        'id': 3,
        'title': 'Deep Dive',
        'audio_url': 'https://cdn.linka.uz/podcasts/a.mp3',
        'cover_url': 'https://cdn.linka.uz/covers/a.jpg',
        'duration': 3720,
      });

      expect(podcast.imageUrl, 'https://cdn.linka.uz/covers/a.jpg');
      expect(podcast.playable, isTrue);
      expect(podcast.duration, const Duration(seconds: 3720));
      expect(podcast.formattedDuration, '1 h 2 min');
      expect(podcast.isNew, isFalse);
    });

    test('an episode without audio is not playable', () {
      final podcast = Podcast.fromJson({'id': 3, 'title': 'Soon'});
      expect(podcast.playable, isFalse);
      expect(podcast.formattedDuration, '');
    });
  });

  group('duration formatting', () {
    test('formatClock pads and only shows hours when needed', () {
      expect(formatClock(const Duration(seconds: 7)), '0:07');
      expect(formatClock(const Duration(minutes: 12, seconds: 5)), '12:05');
      expect(formatClock(const Duration(hours: 1, minutes: 7, seconds: 4)),
          '1:07:04');
      expect(formatClock(const Duration(seconds: -5)), '0:00');
    });

    test('formatRemainingLabel reads like a podcast app', () {
      expect(formatRemainingLabel(const Duration(minutes: 12)), '12 min left');
      expect(formatRemainingLabel(const Duration(seconds: 45)), '45 sec left');
      expect(formatRemainingLabel(const Duration(seconds: 5)), 'Almost done');
      expect(formatRemainingLabel(const Duration(hours: 1, minutes: 5)),
          '1 h 5 min left');
      expect(formatRemainingLabel(const Duration(hours: 2)), '2 h left');
    });
  });

  group('artwork', () {
    test('gradients are stable per episode and vary between them', () {
      expect(podcastGradient('Deep Dive'), podcastGradient('Deep Dive'));
      final distinct = {
        for (final title in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'])
          podcastGradient(title).toString(),
      };
      expect(distinct.length, greaterThan(1));
    });

    testWidgets('renders generated cover art without a network image',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PodcastArtwork(seed: 'Deep Dive', size: 80),
        ),
      ));

      expect(find.byType(PodcastArtwork), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });
}
