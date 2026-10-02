import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// The right / wrong chimes played when a practice answer comes back.
/// Mixes with whatever else is playing (the student's music isn't stopped),
/// and a failure to play is never the student's problem, so it's swallowed.
class PracticeSounds {
  PracticeSounds._();

  static AudioPlayer? _success;
  static AudioPlayer? _fail;

  static Future<AudioPlayer> _player() async {
    final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    await player.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
    );
    return player;
  }

  static Future<void> _play(AudioPlayer player, String asset) async {
    await player.stop();
    await player.play(AssetSource(asset));
  }

  static void correct() => _run(() async {
    await _fail?.stop();
    _success ??= await _player();
    await _play(_success!, 'sounds/practice_success.mp3');
  });

  static void wrong() => _run(() async {
    await _success?.stop();
    _fail ??= await _player();
    await _play(_fail!, 'sounds/practice_fail.mp3');
  });

  static void _run(Future<void> Function() play) {
    play().catchError((Object e) {
      debugPrint('Practice sound failed: $e');
    });
  }
}
