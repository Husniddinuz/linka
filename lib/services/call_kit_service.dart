import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show navigatorKey;
import '../screens/plus_subscription_screen.dart';
import '../screens/video_call_screen.dart';
import '../widgets/app_notify.dart';
import 'call_service.dart';
import 'notification_service.dart';
import 'token_service.dart';

/// Runs for a push that lands while the app is in the background or closed.
///
/// Registered from `main()` with `FirebaseMessaging.onBackgroundMessage`. It
/// runs in its own isolate with no widget tree, which is fine: raising the
/// native incoming-call screen is a platform call, not a Flutter one. On iOS
/// the ring itself arrives through PushKit and never comes here; this path
/// only ever *dismisses* an iPhone's ringing screen.
@pragma('vm:entry-point')
Future<void> linkaFirebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await CallKitService.handleRemoteMessage(message);
}

/// The phone's own call UI — CallKit on iOS, a full-screen incoming-call
/// activity on Android — wired to Linka's calls.
///
/// This is what makes a video call arrive the way a phone call does: ringtone,
/// caller's name over the lock screen, Accept and Decline, with the app
/// closed. The Flutter side only ever reacts: a push shows the native screen,
/// the native screen reports what the user tapped, and this class turns that
/// into the API calls and the in-call screen.
class CallKitService {
  static bool _initialised = false;
  static StreamSubscription<CallEvent?>? _events;
  static StreamSubscription<RemoteMessage>? _foreground;

  /// UUID of the call the in-call screen is currently showing, if any.
  /// Used to tell "the caller hung up before I answered" (dismiss the ring)
  /// from "my other phone told me this call was answered — by me, here"
  /// (ignore).
  static String? activeCallUuid;

  /// Fires with the native call id when the user ends a call from the
  /// phone's own UI (CallKit's red button, the Android notification). The
  /// in-call screen listens so it hangs up too instead of staying open on a
  /// dead room.
  static final StreamController<String> endedFromNative =
      StreamController<String>.broadcast();

  static final Set<String> _acceptsHandled = {};

  static const _fullScreenAskedKey = 'callkit_full_screen_intent_asked';

  /// The call this phone last answered, on disk rather than in memory: the
  /// "answered" push that tells this person's *other* phones to stop ringing
  /// also lands here, and when the app is in the background it is handled in
  /// a separate isolate that shares nothing with the screen — except disk.
  static const _acceptedUuidKey = 'callkit_accepted_call_uuid';

  static Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    _events = FlutterCallkitIncoming.onEvent.listen(_onNativeEvent);
    _foreground = FirebaseMessaging.onMessage.listen(handleRemoteMessage);
  }

  static Future<void> dispose() async {
    await _events?.cancel();
    await _foreground?.cancel();
    _initialised = false;
  }

  /// The PushKit token the backend rings this iPhone with. Null elsewhere.
  static Future<String?> voipToken() async {
    if (!Platform.isIOS) return null;
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }

  // ─── Pushes ────────────────────────────────────────────────────────────────

  /// Routes a Firebase message. Foreground and background alike, since the
  /// data payload is the same and the native screen does not care which.
  static Future<void> handleRemoteMessage(RemoteMessage message) async {
    final data = message.data;
    switch (data['linka_type']) {
      case 'video_call':
        await showIncoming(data);
      case 'video_call_ended':
        await dismissIncoming(data);
    }
  }

  /// Raises the native incoming-call screen for a push payload.
  static Future<void> showIncoming(Map<String, dynamic> data) async {
    final uuid = data['call_uuid']?.toString() ?? '';
    if (uuid.isEmpty) return;
    // Android: iOS gets here only when the app is open and the VoIP path is
    // not configured; CallKit would refuse a second entry for the same UUID
    // anyway, so this is safe to call even if PushKit already rang.
    final ringSeconds = int.tryParse(data['ring_seconds']?.toString() ?? '') ?? 45;
    await FlutterCallkitIncoming.showCallkitIncoming(_params(
      uuid: uuid,
      callerName: data['caller_name']?.toString() ?? 'Linka',
      avatar: data['caller_avatar']?.toString(),
      extra: _extraFrom(data),
      ringMillis: ringSeconds * 1000,
    ));
  }

  /// Takes a ringing screen down: the caller hung up, or the call was
  /// answered on another of this person's phones.
  static Future<void> dismissIncoming(Map<String, dynamic> data) async {
    final uuid = data['call_uuid']?.toString() ?? '';
    if (uuid.isEmpty) return;
    if (data['status'] == 'accepted' &&
        (uuid == activeCallUuid || uuid == await _rememberedAccepted())) {
      // "Answered" arrives on the phone that answered too. That one is in
      // the call and must keep the native entry alive.
      return;
    }
    try {
      await FlutterCallkitIncoming.endCall(uuid);
    } catch (_) {}
  }

  static Future<void> _rememberAccepted(String uuid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_acceptedUuidKey, uuid);
    } catch (_) {}
  }

  static Future<String?> _rememberedAccepted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getString(_acceptedUuidKey);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _extraFrom(Map<String, dynamic> data) => {
        'call_id': data['call_id']?.toString() ?? '',
        'conversation_id': data['conversation_id']?.toString() ?? '',
        'channel_slug': data['channel_slug']?.toString() ?? '',
        'caller_id': data['caller_id']?.toString() ?? '',
        'caller_name': data['caller_name']?.toString() ?? '',
        'caller_avatar': data['caller_avatar']?.toString() ?? '',
      };

  static CallKitParams _params({
    required String uuid,
    required String callerName,
    String? avatar,
    required Map<String, dynamic> extra,
    required int ringMillis,
  }) =>
      CallKitParams(
        id: uuid,
        nameCaller: callerName,
        appName: 'Linka',
        avatar: (avatar == null || avatar.isEmpty) ? null : avatar,
        handle: 'Linka video call',
        type: 1,
        duration: ringMillis,
        extra: extra,
        missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Missed video call',
          callbackText: 'Call back',
        ),
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#13152A',
          actionColor: '#4CAF50',
          textColor: '#FFFFFF',
          isShowFullLockedScreen: true,
          isImportant: true,
          incomingCallNotificationChannelName: 'Incoming calls',
          missedCallNotificationChannelName: 'Missed calls',
          isShowCallID: false,
          textAccept: 'Accept',
          textDecline: 'Decline',
        ),
        ios: const IOSParams(
          iconName: 'CallKitLogo',
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          supportsDTMF: false,
          supportsHolding: false,
          supportsGrouping: false,
          supportsUngrouping: false,
          audioSessionMode: 'videoChat',
          audioSessionActive: true,
          ringtonePath: 'system_ringtone_default',
        ),
      );

  /// Shows the outgoing call on the phone's own UI — the green bar and the
  /// Recents entry on iOS, an ongoing-call notification on Android — so the
  /// call survives the app being swiped away mid-conversation.
  static Future<void> showOutgoing(CallInfo call) async {
    try {
      await FlutterCallkitIncoming.startCall(CallKitParams(
        id: call.roomId,
        nameCaller: call.other.displayName,
        appName: 'Linka',
        avatar: call.other.profileImage,
        handle: 'Linka video call',
        type: 1,
        extra: {
          'call_id': call.id.toString(),
          'conversation_id': call.conversationId.toString(),
        },
        callingNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Video call',
          callbackText: 'Hang up',
        ),
        android: const AndroidParams(
          isCustomNotification: true,
          isShowCallID: false,
        ),
        ios: const IOSParams(
          handleType: 'generic',
          supportsVideo: true,
          audioSessionMode: 'videoChat',
        ),
      ));
    } catch (_) {}
  }

  static Future<void> markConnected(String uuid) async {
    try {
      await FlutterCallkitIncoming.setCallConnected(uuid);
    } catch (_) {}
  }

  static Future<void> endNative(String uuid) async {
    try {
      await FlutterCallkitIncoming.endCall(uuid);
    } catch (_) {}
  }

  // ─── What the user tapped on the native screen ──────────────────────────────

  static Future<void> _onNativeEvent(CallEvent? event) async {
    switch (event) {
      case CallEventActionCallAccept(:final callKitParams):
        await _acceptFromNative(callKitParams);
      case CallEventActionCallDecline(:final callKitParams):
        await _declineFromNative(callKitParams);
      case CallEventActionCallEnded(:final callKitParams):
        endedFromNative.add(callKitParams.id);
      case CallEventActionCallCallback(:final id):
        await _callBackFromMissed(id);
      case CallEventActionDidUpdateDevicePushTokenVoip():
        // A fresh PushKit token has to reach the backend or the next call
        // will ring nothing.
        NotificationService.registerDevice();
      default:
        break;
    }
  }

  /// A call the user accepted while the app was closed shows up here once
  /// the app is running. Called after the navigator exists, and again on
  /// every return to the foreground.
  static Future<void> resumeAcceptedCall() async {
    List<CallKitParams> active;
    try {
      active = await FlutterCallkitIncoming.activeCalls();
    } catch (_) {
      return;
    }
    for (final params in active) {
      if (params.isAccepted && _acceptsHandled.add('resume:${params.id}')) {
        await _acceptFromNative(params);
      }
    }
  }

  static Future<void> _acceptFromNative(CallKitParams params) async {
    final callId = int.tryParse(params.extra?['call_id']?.toString() ?? '');
    if (callId == null || !_acceptsHandled.add(params.id)) {
      return;
    }
    if (await TokenService.getAccessToken() == null) {
      // Logged out since the push was sent. Nothing to answer with.
      await endNative(params.id);
      return;
    }
    if (!await _waitForNavigator()) {
      await endNative(params.id);
      return;
    }

    // Claimed before the server is told: the "answered" push it sends in
    // reply can beat the response back to this phone.
    activeCallUuid = params.id;
    await _rememberAccepted(params.id);

    CallSession session;
    try {
      session = await CallService.accept(callId);
    } on CallNotRinging catch (e) {
      activeCallUuid = null;
      await endNative(params.id);
      _notify(e.message);
      return;
    } catch (_) {
      activeCallUuid = null;
      await endNative(params.id);
      _notify('Could not join the call.');
      return;
    }
    if (session.signaling == null) {
      activeCallUuid = null;
      await endNative(params.id);
      return;
    }
    await navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(session: session, incoming: true),
        fullscreenDialog: true,
      ),
    );
  }

  static Future<void> _declineFromNative(CallKitParams params) async {
    final callId = int.tryParse(params.extra?['call_id']?.toString() ?? '');
    if (callId == null) return;
    try {
      await CallService.decline(callId);
    } catch (_) {
      // The server expires an unanswered ring on its own; a lost decline
      // costs the caller a few extra seconds, not a stuck call.
    }
  }

  /// "Call back" on a missed-call notification. The notification only knows
  /// the native id, and the plugin hands back nothing else, so the last
  /// incoming call's conversation is looked up from what was stored.
  static Future<void> _callBackFromMissed(String uuid) async {
    final conversationId = await _conversationForUuid(uuid);
    if (conversationId == null || !await _waitForNavigator()) return;
    await startCallFromAnywhere(conversationId);
  }

  static Future<int?> _conversationForUuid(String uuid) async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final c in calls) {
        if (c.id == uuid) {
          return int.tryParse(c.extra?['conversation_id']?.toString() ?? '');
        }
      }
    } catch (_) {}
    return null;
  }

  /// Places a call from outside a screen: the missed-call notification's
  /// "Call back". Refusals are shown the way the thread's own button shows
  /// them, Plus included.
  static Future<void> startCallFromAnywhere(int conversationId) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    try {
      final session = await CallService.start(conversationId);
      activeCallUuid = session.call.roomId;
      await nav.push(MaterialPageRoute(
        builder: (_) => VideoCallScreen(session: session, incoming: false),
        fullscreenDialog: true,
      ));
    } on CallRefused catch (e) {
      if (e.needsPlus) {
        await nav.push(MaterialPageRoute(
            builder: (_) => const PlusSubscriptionScreen()));
      } else {
        _notify(e.message);
      }
    } catch (_) {
      _notify('Could not start the call.');
    }
  }

  // ─── Android: permission to take over the lock screen ──────────────────────

  /// Android 14+ lets an app show a full-screen call only with a permission
  /// the user grants in Settings. Asked once, the first time a private
  /// thread is opened — that is the moment a call becomes possible.
  static Future<void> ensureAndroidFullScreenPermission() async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterCallkitIncoming.canUseFullScreenIntent()) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_fullScreenAskedKey) == true) return;
      await prefs.setBool(_fullScreenAskedKey, true);
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {}
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  /// On a cold start from the native call screen the navigator may not
  /// exist yet. Waits up to ten seconds for it.
  static Future<bool> _waitForNavigator() async {
    for (var i = 0; i < 200; i++) {
      if (navigatorKey.currentState != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return navigatorKey.currentState != null;
  }

  static void _notify(String message) {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    AppNotify.show(context, message: message);
  }

  @visibleForTesting
  static void resetForTests() {
    _acceptsHandled.clear();
    activeCallUuid = null;
  }
}
