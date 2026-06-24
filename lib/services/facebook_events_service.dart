import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper around the Facebook (Meta) App Events SDK.
///
/// The native SDK auto-initializes from the FacebookAppID / FacebookClientToken
/// declared in ios/Runner/Info.plist and android strings.xml, and
/// automatically logs install + session events for ad attribution. This service
/// just exposes a single instance plus helpers for custom/marketing events.
class FacebookEventsService {
  FacebookEventsService._();

  static final FacebookAppEvents _events = FacebookAppEvents();

  /// Enable automatic in-app event logging. Call once on app start.
  static Future<void> init() async {
    await _events.setAutoLogAppEventsEnabled(true);
  }

  /// Controls advertiser-ID collection (Android GAID / iOS IDFA). On iOS the
  /// SDK derives tracking consent from App Tracking Transparency automatically,
  /// so this mainly gates the Android advertiser ID.
  static Future<void> setAdvertiserIdCollectionEnabled(bool enabled) {
    return _events.setAdvertiserIdCollectionEnabled(enabled);
  }

  /// Show the iOS App Tracking Transparency prompt (if not yet decided) and
  /// gate advertiser-ID / IDFA collection on the user's choice.
  ///
  /// No-op on non-iOS platforms. Must be called once the app is in the
  /// foreground (e.g. from a post-frame callback) — iOS silently ignores the
  /// request otherwise. The native prompt is only shown the first time; later
  /// calls just read the stored status.
  static Future<void> requestTracking() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final status =
          await AppTrackingTransparency.requestTrackingAuthorization();
      await _events.setAdvertiserIdCollectionEnabled(
        status == TrackingStatus.authorized,
      );
    } catch (_) {
      // ATT unavailable (e.g. iOS < 14) — leave default collection behavior.
    }
  }

  /// Log an arbitrary marketing/funnel event.
  static Future<void> logEvent(
    String name, {
    Map<String, dynamic>? parameters,
  }) {
    return _events.logEvent(name: name, parameters: parameters);
  }

  /// Standard "completed registration" event — useful for signup attribution.
  static Future<void> logCompletedRegistration({String? method}) {
    return _events.logCompletedRegistration(registrationMethod: method);
  }
}
