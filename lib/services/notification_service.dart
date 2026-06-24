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
        return;
      }

      // On iOS, get the APNs token first
      if (Platform.isIOS) {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken == null) {
          return;
        }
      }

      final fcmToken = await _messaging.getToken();
      if (fcmToken == null) {
        return;
      }


      final platform = Platform.isIOS ? 'ios' : 'android';

      await ApiService.post('/notifications/device/', {
        'token': fcmToken,
        'platform': platform,
      });

    } catch (_) {
      // Registration is best-effort; ignore failures.
    }
  }

  /// Listen for token refreshes and re-register with backend.
  static void listenTokenRefresh() {
    _messaging.onTokenRefresh.listen((newToken) async {
      final platform = Platform.isIOS ? 'ios' : 'android';
      try {
        await ApiService.post('/notifications/device/', {
          'token': newToken,
          'platform': platform,
        });
      } catch (e) {
      }
    });
  }

  // ─── Inbox ──────────────────────────────────────────────────────────────

  /// Returns `true` when the user has unread notifications. Never throws;
  /// returns `false` on network/parse failure so the bell indicator fails
  /// safely (no false positive).
  static Future<bool> hasNew() async {
    try {
      final data = await ApiService.get('/notifications/inbox/has-new/');
      return data['has_new'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the notifications inbox. The backend may return either a bare
  /// JSON array or a paginated `{results: [...]}` object — both are handled.
  static Future<List<Map<String, dynamic>>> fetchInbox({
    int page = 1,
    int limit = 20,
    String? status,
    String? type,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'limit': '$limit',
      'status': ?status,
      'type': ?type,
    };
    final qs = query.entries.map((e) => '${e.key}=${e.value}').join('&');
    final path = '/notifications/inbox/?$qs';

    try {
      final list = await ApiService.getList(path);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      // Fall through to try the wrapped-object shape (ApiException on HTTP
      // error, TypeError when the body is a Map instead of a List).
    }
    final data = await ApiService.get(path);
    final results = data['results'];
    if (results is List) return results.cast<Map<String, dynamic>>();
    return const [];
  }

  static Future<void> markRead(String notificationId) async {
    await ApiService.post('/notifications/inbox/$notificationId/read/', {});
  }

  static Future<void> markAllRead() async {
    await ApiService.post('/notifications/inbox/mark-all-read/', {});
  }
}
