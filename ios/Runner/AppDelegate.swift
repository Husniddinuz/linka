import Flutter
import UIKit
import PushKit
import FirebaseCore
import FirebaseMessaging
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()

    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    // PushKit: a VoIP push is the only thing that can ring this phone for a
    // video call while the app is closed. The token it hands us is sent to
    // the backend from Dart (NotificationService.registerDevice), and an
    // incoming push is turned into a CallKit call right here, before Flutter
    // is necessarily running.
    let voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
    voipRegistry.delegate = self
    voipRegistry.desiredPushTypes = [.voIP]

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Foundation.Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - PushKit

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    let info = payload.dictionaryPayload
    // Field names match what apps/notifications/services/push.py sends.
    let id = info["id"] as? String ?? UUID().uuidString
    let nameCaller = info["nameCaller"] as? String ?? "Linka"
    let handle = info["handle"] as? String ?? "Linka video call"
    let avatar = info["avatar"] as? String ?? ""
    let duration = info["duration"] as? Int ?? 45000

    let data = flutter_callkit_incoming.Data(id: id, nameCaller: nameCaller, handle: handle, type: 1)
    data.appName = "Linka"
    data.avatar = avatar
    data.duration = duration
    data.supportsVideo = true
    data.supportsDTMF = false
    data.supportsHolding = false
    data.supportsGrouping = false
    data.supportsUngrouping = false
    data.maximumCallGroups = 1
    data.maximumCallsPerCallGroup = 1
    data.handleType = "generic"
    data.audioSessionMode = "videoChat"
    // Everything Dart needs to accept the call is carried in `extra`.
    var extra: [String: Any] = [:]
    for key in ["call_id", "conversation_id", "channel_slug", "caller_id", "caller_name", "caller_avatar"] {
      extra[key] = (info[key] as? String) ?? ""
    }
    data.extra = extra as NSDictionary

    // iOS kills the app if a VoIP push does not report a CallKit call, and
    // `completion` must run once CallKit has it. The plugin does both.
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true) {
      completion()
    }
  }
}
