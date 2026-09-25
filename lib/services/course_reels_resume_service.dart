import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/course_reel.dart';
import 'api_service.dart';
import 'course_reels_service.dart';

/// Where the student was in Course Reels, as last seen on this device.
@immutable
class ReelResumePoint {
  final int courseId;
  final int lessonId;
  final double positionSeconds;
  final double durationSeconds;

  /// Wall-clock ms of the last update.
  final int updatedAt;

  const ReelResumePoint({
    required this.courseId,
    required this.lessonId,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'c': courseId,
    'l': lessonId,
    'p': positionSeconds,
    'd': durationSeconds,
    't': updatedAt,
  };

  static ReelResumePoint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final course = (raw['c'] as num?)?.toInt();
    final lesson = (raw['l'] as num?)?.toInt();
    if (course == null || lesson == null) return null;
    return ReelResumePoint(
      courseId: course,
      lessonId: lesson,
      positionSeconds: (raw['p'] as num?)?.toDouble() ?? 0,
      durationSeconds: (raw['d'] as num?)?.toDouble() ?? 0,
      updatedAt: (raw['t'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Keeps the Course Reels resume point on the device and trickles playback
/// progress to the server.
///
/// The server is the source of truth (`/course-reels/resume/`, so a student
/// picks up on any device), but the app can be killed mid-video before a
/// request lands. So every position is written to [SharedPreferences] first,
/// queued per lesson, and flushed every few seconds, on pause and on app
/// background. Anything still queued at the next launch is sent then.
class CourseReelsResumeService {
  CourseReelsResumeService._();

  static const _key = 'course_reels_resume_v1';
  static const _introsKey = 'course_reels_intros_seen_v1';

  /// How often a playing video reports its position to the server.
  static const syncInterval = Duration(seconds: 6);

  static SharedPreferences? _prefs;
  static bool _loaded = false;

  static ReelResumePoint? _last;

  /// Unsent positions by lesson id; a `true` in [_pendingCompleted] means the
  /// lesson reached its end and must be reported as watched.
  static final Map<int, ReelResumePoint> _pending = {};
  static final Set<int> _pendingCompleted = {};

  /// Course sections whose intro this student has been through.
  static final Set<int> _introsSeen = {};

  static Timer? _syncTimer;
  static Future<void>? _flushing;

  /// Bumped when the resume point moves, so the home card can rebuild.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// The most recent local resume point, if any.
  static ReelResumePoint? get last => _last;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      _introsSeen.addAll(
        (_prefs?.getStringList(_introsKey) ?? const [])
            .map(int.tryParse)
            .whereType<int>(),
      );
      final raw = _prefs?.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _last = ReelResumePoint.fromJson(decoded['last']);
      final pending = decoded['pending'];
      if (pending is Map) {
        for (final value in pending.values) {
          final point = ReelResumePoint.fromJson(value);
          if (point != null) _pending[point.lessonId] = point;
        }
      }
      final done = decoded['done'];
      if (done is List) {
        _pendingCompleted.addAll(done.whereType<num>().map((e) => e.toInt()));
      }
    } catch (_) {
      // A corrupt blob only costs the local resume point; the server has one.
    }
  }

  /// Whether the student has been through section [sectionId]'s intro on
  /// this device. Call [load] first.
  static bool introSeen(int sectionId) => _introsSeen.contains(sectionId);

  static Future<void> markIntroSeen(int sectionId) async {
    await load();
    if (!_introsSeen.add(sectionId)) return;
    await _prefs?.setStringList(_introsKey, [
      for (final id in _introsSeen) '$id',
    ]);
  }

  /// Where to start [lessonId]: this device's position while it is still
  /// unsent (the app died before syncing), otherwise the server's.
  static double positionFor(int lessonId, double serverSeconds) =>
      _pending[lessonId]?.positionSeconds ?? serverSeconds;

  /// The lesson this device last played in [courseId], when that play hasn't
  /// reached the server yet. Once synced, the server's `last_lesson_id` is
  /// authoritative — it also knows about other devices.
  static int? unsyncedLessonIn(int courseId) {
    final last = _last;
    if (last == null || last.courseId != courseId) return null;
    return _pending.containsKey(last.lessonId) ? last.lessonId : null;
  }

  /// Records playback. Cheap enough to call on every player tick.
  static void record({
    required int courseId,
    required int lessonId,
    required double positionSeconds,
    required double durationSeconds,
    bool completed = false,
  }) {
    final point = ReelResumePoint(
      courseId: courseId,
      lessonId: lessonId,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final lessonChanged = _last?.lessonId != lessonId;
    _last = point;
    _pending[lessonId] = point;
    if (completed && _pendingCompleted.add(lessonId)) {
      unawaited(flush());
    }
    if (lessonChanged) revision.value++;
    _persist();
    _syncTimer ??= Timer(syncInterval, () {
      _syncTimer = null;
      unawaited(flush());
    });
  }

  /// Sends every queued position. Safe to call often; calls coalesce.
  static Future<void> flush() {
    return _flushing ??= _doFlush().whenComplete(() => _flushing = null);
  }

  /// Latest server progress per lesson from the last flush — lets the feed
  /// refresh its markers without refetching the course.
  static final Map<int, ReelLessonProgress> serverProgress = {};

  static Future<void> _doFlush() async {
    final batch = Map<int, ReelResumePoint>.from(_pending);
    for (final point in batch.values) {
      final completed = _pendingCompleted.contains(point.lessonId);
      try {
        final progress = await CourseReelsService.saveProgress(
          point.lessonId,
          positionSeconds: point.positionSeconds,
          durationSeconds: point.durationSeconds,
          completed: completed,
        );
        serverProgress[point.lessonId] = progress;
        // Only drop it if nothing newer was recorded while the request ran.
        if (identical(_pending[point.lessonId], point)) {
          _pending.remove(point.lessonId);
        }
        if (completed) _pendingCompleted.remove(point.lessonId);
      } catch (e) {
        // A 404 means the lesson was unpublished — never retry it.
        if (e is ApiException && e.statusCode == 404) {
          _pending.remove(point.lessonId);
          _pendingCompleted.remove(point.lessonId);
        }
        // Offline or server error: keep it for the next flush.
      }
    }
    _persist();
  }

  static void _persist() {
    final prefs = _prefs;
    if (prefs == null) return;
    prefs.setString(
      _key,
      jsonEncode({
        'last': _last?.toJson(),
        'pending': {
          for (final e in _pending.entries) '${e.key}': e.value.toJson(),
        },
        'done': _pendingCompleted.toList(),
      }),
    );
  }

  /// For logout: forget this device's resume point.
  static Future<void> clear() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    _last = null;
    _pending.clear();
    _pendingCompleted.clear();
    _introsSeen.clear();
    await _prefs?.remove(_key);
    await _prefs?.remove(_introsKey);
    revision.value++;
  }
}
