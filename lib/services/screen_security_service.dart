import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps course videos out of screenshots and screen recordings.
///
/// - **Android:** `FLAG_SECURE` on the window, so screenshots, recordings,
///   casting and the recents thumbnail come out black.
/// - **iOS:** screen recording can't be blocked, only detected. [captured] is
///   true while the screen is recorded, AirPlayed or mirrored, and the feed
///   pauses and hides the video meanwhile. Screenshots can't be stopped.
///
/// Native side: `MainActivity.kt` and `ScreenSecurity` in `AppDelegate.swift`,
/// channel `linka/screen_security`.
class ScreenSecurityService {
  ScreenSecurityService._();

  static const _channel = MethodChannel('linka/screen_security');

  /// True while iOS reports the screen as captured. Always false on Android.
  static final ValueNotifier<bool> captured = ValueNotifier(false);

  /// Screens currently asking for protection; the flag drops at zero.
  static int _holders = 0;
  static bool _listening = false;

  /// Call from a protected screen's `initState`; pair with [release].
  static Future<void> protect() async {
    _holders += 1;
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'captureChanged') {
          captured.value = call.arguments == true;
        }
      });
    }
    if (_holders != 1) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': true});
      captured.value = await _channel.invokeMethod<bool>('isCaptured') ?? false;
    } on MissingPluginException {
      // Desktop/web/tests: nothing to protect with.
    } on PlatformException {
      // Never let protection break playback.
    }
  }

  /// Call from the protected screen's `dispose`.
  static Future<void> release() async {
    if (_holders == 0) return;
    _holders -= 1;
    if (_holders != 0) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': false});
    } on MissingPluginException {
      // See protect().
    } on PlatformException {
      // See protect().
    }
  }
}
