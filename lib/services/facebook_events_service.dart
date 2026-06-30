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

  /// Enable automatic in-app event logging. On iOS, call only after ATT
  /// consent is resolved via [requestTracking] to avoid collecting data
  /// before the user has been prompted.
  static Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) return;
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
  /// No-op on non-iOS platforms. Must be called from a post-frame callback
  /// after a short delay — iPadOS requires the app window to be fully
  /// presented before it will display the system prompt.
  static Future<void> requestTracking() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      // Wait for the app window to be fully on-screen. Without this delay
      // iPadOS silently drops the system ATT dialog on first launch.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final status =
          await AppTrackingTransparency.requestTrackingAuthorization();
      final authorized = status == TrackingStatus.authorized;
      await Future.wait([
        _events.setAutoLogAppEventsEnabled(authorized),
        _events.setAdvertiserIdCollectionEnabled(authorized),
      ]);
    } catch (_) {
      // ATT unavailable (e.g. iOS < 14) — leave default collection behavior.
      await _events.setAutoLogAppEventsEnabled(true);
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
