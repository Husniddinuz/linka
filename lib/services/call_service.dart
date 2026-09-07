import 'api_service.dart';
import 'chat_service.dart';

/// One side of a video call, as the server describes them.
class CallPerson {
  final int userId;
  final String displayName;
  final String? profileImage;

  const CallPerson({
    required this.userId,
    required this.displayName,
    this.profileImage,
  });

  factory CallPerson.fromJson(Map<String, dynamic> json) => CallPerson(
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
        displayName: json['display_name']?.toString() ?? 'Linka user',
        profileImage:
            ChatService.absoluteUrl(json['profile_image'] as String?),
      );
}

/// Where a call stands. Mirrors `VideoCall` on the server: `ringing` until
/// the other side answers, then `accepted`, then one of the four ways it can
/// be over.
class CallInfo {
  final int id;

  /// The WebRTC room on the relay *and* the native call UUID on both phones.
  /// One id follows the call from the API through the push to the screen.
  final String roomId;
  final int conversationId;
  final String channelId;
  final CallPerson caller;
  final CallPerson callee;
  final String status;
  final bool isActive;

  /// True for the person who placed the call.
  final bool isMine;
  final DateTime? answeredAt;
  final int durationSeconds;
  final int ringSeconds;

  const CallInfo({
    required this.id,
    required this.roomId,
    required this.conversationId,
    required this.channelId,
    required this.caller,
    required this.callee,
    required this.status,
    required this.isActive,
    required this.isMine,
    this.answeredAt,
    this.durationSeconds = 0,
    this.ringSeconds = 45,
  });

  /// The person on the other end, whichever side of the call this is.
  CallPerson get other => isMine ? callee : caller;

  bool get isRinging => status == 'ringing';
  bool get isAccepted => status == 'accepted';

  factory CallInfo.fromJson(Map<String, dynamic> json) => CallInfo(
        id: (json['id'] as num?)?.toInt() ?? 0,
        roomId: json['room_id']?.toString() ?? '',
        conversationId: (json['conversation_id'] as num?)?.toInt() ?? 0,
        channelId: json['channel_id']?.toString() ?? '',
        caller: CallPerson.fromJson(
            (json['caller'] as Map?)?.cast<String, dynamic>() ?? const {}),
        callee: CallPerson.fromJson(
            (json['callee'] as Map?)?.cast<String, dynamic>() ?? const {}),
        status: json['status']?.toString() ?? 'ended',
        isActive: json['is_active'] as bool? ?? false,
        isMine: json['is_mine'] as bool? ?? false,
        answeredAt: DateTime.tryParse(json['answered_at']?.toString() ?? ''),
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
        ringSeconds: (json['ring_seconds'] as num?)?.toInt() ?? 45,
      );
}

/// What the relay needs from us: where it is, who we are, and how to reach
/// the other peer once signaling is done.
class CallSignaling {
  final String roomId;
  final String url;
  final String token;
  final List<Map<String, dynamic>> iceServers;

  const CallSignaling({
    required this.roomId,
    required this.url,
    required this.token,
    required this.iceServers,
  });

  factory CallSignaling.fromJson(Map<String, dynamic> json) => CallSignaling(
        roomId: json['room_id']?.toString() ?? '',
        url: json['signaling_url']?.toString() ?? '',
        token: json['signaling_token']?.toString() ?? '',
        iceServers: ((json['ice_servers'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList(),
      );
}

class CallSession {
  final CallInfo call;

  /// Present only while the call is live; a finished call has no room.
  final CallSignaling? signaling;

  /// False when the other person has no registered device: nothing will ring,
  /// and the screen should say so instead of counting down in silence.
  final bool calleeReachable;

  const CallSession({
    required this.call,
    this.signaling,
    this.calleeReachable = true,
  });

  factory CallSession.fromJson(Map<String, dynamic> json) => CallSession(
        call: CallInfo.fromJson(
            (json['call'] as Map).cast<String, dynamic>()),
        signaling: json['signaling'] is Map
            ? CallSignaling.fromJson(
                (json['signaling'] as Map).cast<String, dynamic>())
            : null,
        calleeReachable: json['callee_reachable'] as bool? ?? true,
      );
}

/// A refusal to place a call.
///
/// [code] is what the UI branches on, the same way it does for a refused
/// conversation: `plus_required` leads to the subscription screen, `busy`
/// means a call in this thread is already ringing or connected, and
/// everything else is a dead end with a sentence to show.
class CallRefused extends ApiException {
  final String code;

  const CallRefused(super.message,
      {required this.code, required super.statusCode});

  bool get needsPlus => code == 'plus_required';
  bool get isBusy => code == 'busy';
}

/// Answering or declining a call that has stopped ringing in the meantime:
/// the caller hung up, it timed out, or it was picked up on another phone.
/// Carries the call so the screen can say which.
class CallNotRinging implements Exception {
  final CallInfo call;
  final String message;
  const CallNotRinging(this.call, this.message);

  @override
  String toString() => message;
}

class CallService {
  /// Rings the other participant of [conversationId].
  ///
  /// Only *placing* a call costs Plus; answering never does. Throws
  /// [CallRefused] so the caller can send a `plus_required` to the
  /// subscription screen and show everything else as a sentence.
  static Future<CallSession> start(int conversationId) async {
    try {
      final data = await ApiService.post(
          '/chats/conversations/$conversationId/calls/', const {});
      return CallSession.fromJson(data);
    } on ApiException catch (e) {
      throw CallRefused(
        e.message,
        code: e.errorCode ?? 'unavailable',
        statusCode: e.statusCode,
      );
    }
  }

  /// The call's current state, with fresh credentials while it is live.
  static Future<CallSession> fetch(int callId) async {
    final data = await ApiService.get('/chats/calls/$callId/');
    return CallSession.fromJson(data);
  }

  /// Picks up. Throws [CallNotRinging] when there is nothing left to pick up.
  static Future<CallSession> accept(int callId) async {
    try {
      final data = await ApiService.post('/chats/calls/$callId/accept/', const {});
      return CallSession.fromJson(data);
    } on ApiException catch (e) {
      _throwIfNotRinging(e);
      rethrow;
    }
  }

  static Future<void> decline(int callId) async {
    try {
      await ApiService.post('/chats/calls/$callId/decline/', const {});
    } on ApiException catch (e) {
      _throwIfNotRinging(e);
      rethrow;
    }
  }

  /// Hangs up from either side. Safe to call on a call that is already over.
  static Future<CallInfo?> end(int callId) async {
    try {
      final data = await ApiService.post('/chats/calls/$callId/end/', const {});
      final call = data['call'];
      return call is Map ? CallInfo.fromJson(call.cast<String, dynamic>()) : null;
    } on ApiException {
      return null;
    }
  }

  static void _throwIfNotRinging(ApiException e) {
    final call = e.data?['call'];
    if (e.errorCode == 'not_ringing' && call is Map) {
      throw CallNotRinging(
          CallInfo.fromJson(call.cast<String, dynamic>()), e.message);
    }
  }
}
