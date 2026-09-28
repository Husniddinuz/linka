import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The language the student wants Course Reels voiced in, kept on the
/// device. Null = each video's original language. A lesson without a dub in
/// the chosen language plays its original; the choice sticks for the next.
class CourseReelsAudioService {
  CourseReelsAudioService._();

  static const _key = 'course_reels_audio_language';

  static final ValueNotifier<String?> language = ValueNotifier(null);
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      language.value = prefs.getString(_key);
    } catch (_) {
      // No prefs: play originals.
    }
    _loaded = true;
  }

  static Future<void> choose(String? code) async {
    language.value = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (code == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, code);
      }
    } catch (_) {}
  }
}
