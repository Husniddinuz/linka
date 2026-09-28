import 'package:flutter_test/flutter_test.dart';
import 'package:linka/models/course_reel.dart';

Map<String, dynamic> _lesson({List<Map<String, dynamic>>? tracks}) => {
  'id': 1,
  'course_id': 1,
  'title': 'L1',
  'video_url': 'https://api/video/orig.mp4',
  'audio_language': 'uz',
  if (tracks != null) 'audio_tracks': tracks,
};

void main() {
  group('audio tracks', () {
    final tracks = [
      {
        'language': 'uz',
        'is_original': true,
        'video_url': 'https://api/video/orig.mp4',
      },
      {
        'language': 'ru',
        'is_original': false,
        'video_url': 'https://api/video/ru.mp4',
      },
    ];

    test('the preferred dub plays when the lesson has it', () {
      final lesson = ReelLesson.fromJson(_lesson(tracks: tracks));
      expect(lesson.hasDubs, isTrue);
      expect(lesson.videoUrlFor('ru'), 'https://api/video/ru.mp4');
      expect(lesson.trackFor('ru')!.isOriginal, isFalse);
    });

    test('a missing language or no preference falls back to the original', () {
      final lesson = ReelLesson.fromJson(_lesson(tracks: tracks));
      expect(lesson.videoUrlFor('en'), 'https://api/video/orig.mp4');
      expect(lesson.videoUrlFor(null), 'https://api/video/orig.mp4');
      expect(lesson.trackFor('en')!.language, 'uz');
    });

    test('an older backend without tracks still plays video_url', () {
      final lesson = ReelLesson.fromJson(_lesson());
      expect(lesson.hasDubs, isFalse);
      expect(lesson.trackFor('ru'), isNull);
      expect(lesson.videoUrlFor('ru'), 'https://api/video/orig.mp4');
    });

    test('names known languages and upper-cases unknown ones', () {
      expect(reelAudioLanguageName('ru'), 'Русский');
      expect(reelAudioLanguageName('de'), 'DE');
    });
  });
}
