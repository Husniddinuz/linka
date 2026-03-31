import 'dart:developer' as dev;
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_service.dart';

class NotificationService {
  static FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  /// Requests permission, gets FCM token, and registers it with the backend.
  static Future<void> registerDevice() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        dev.log('🔕 Notification permission denied');
        return;
      }

      // On iOS, get the APNs token first
      if (Platform.isIOS) {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken == null) {
          dev.log('⏳ APNs token not yet available, skipping FCM registration');
          return;
        }
      }

      final fcmToken = await _messaging.getToken();
      if (fcmToken == null) {
        dev.log('⚠️ FCM token is null');
        return;
      }

      dev.log('🔔 FCM token: $fcmToken');

      final platform = Platform.isIOS ? 'ios' : 'android';

      await ApiService.post('/notifications/device/', {
        'token': fcmToken,
        'platform': platform,
      });

      dev.log('✅ Device registered for notifications ($platform)');
    } catch (e) {
      dev.log('❌ Failed to register device for notifications: $e');
    }
  }

  /// Listen for token refreshes and re-register with backend.
  static void listenTokenRefresh() {
    _messaging.onTokenRefresh.listen((newToken) async {
      dev.log('🔄 FCM token refreshed: $newToken');
      final platform = Platform.isIOS ? 'ios' : 'android';
      try {
        await ApiService.post('/notifications/device/', {
          'token': newToken,
          'platform': platform,
        });
        dev.log('✅ Refreshed token registered');
      } catch (e) {
        dev.log('❌ Failed to register refreshed token: $e');
      }
    });
  }
}
