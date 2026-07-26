import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How much of an episode has to be left for it to still count as "in
/// progress". Anything closer to the end is treated as finished, the way
/// podcast apps do — nobody wants a 4-second tail sitting in Continue
/// Listening forever.
const Duration _completionTail = Duration(seconds: 20);

/// The first stretch of an episode is treated as "not really started" so a
/// mis-tap doesn't fill the Continue Listening row with noise.
const Duration _startedThreshold = Duration(seconds: 15);

/// Where playback of one podcast got to, as last seen on this device.
@immutable
class PodcastProgress {
  final int podcastId;
  final Duration position;
  final Duration duration;
  final bool completed;

  /// Wall-clock ms of the last update — used to order Continue Listening.
  final int updatedAt;

  const PodcastProgress({
    required this.podcastId,
    required this.position,
    required this.duration,
    required this.completed,
    required this.updatedAt,
  });

  /// 0..1 share of the episode already heard. Zero when the duration is
  /// unknown (the player reports it asynchronously).
  double get fraction {
    if (completed) return 1;
    if (duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  Duration get remaining {
    if (duration <= position) return Duration.zero;
    return duration - position;
  }

  /// True once the listener is far enough in that resuming is worth offering.
  bool get started => !completed && position >= _startedThreshold;

  Map<String, dynamic> toJson() => {
        'p': position.inMilliseconds,
        'd': duration.inMilliseconds,
        'c': completed,
        't': updatedAt,
      };

  static PodcastProgress? fromJson(String id, Object? raw) {
    if (raw is! Map) return null;
    final podcastId = int.tryParse(id);
    if (podcastId == null) return null;
    return PodcastProgress(
      podcastId: podcastId,
      position: Duration(milliseconds: (raw['p'] as num?)?.toInt() ?? 0),
      duration: Duration(milliseconds: (raw['d'] as num?)?.toInt() ?? 0),
      completed: raw['c'] as bool? ?? false,
      updatedAt: (raw['t'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Per-episode listening progress, stored on the device.
///
/// The content API has no per-user playback state, so resume points live in
/// [SharedPreferences] as a single JSON blob keyed by podcast id. Everything
/// reads from an in-memory cache so widgets can look progress up synchronously
/// inside `build`; [revision] bumps whenever the cache changes so lists can
/// rebuild without polling.
class PodcastProgressService {
  PodcastProgressService._();

  static const _key = 'podcast_progress_v1';

  /// Cap on stored entries — oldest resume points are dropped first so the
  /// blob can't grow without bound.
  static const _maxEntries = 200;

  static final Map<int, PodcastProgress> _cache = {};

  /// Bumped on every mutation. Listen to rebuild progress UI live.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static SharedPreferences? _prefs;
  static bool _loaded = false;

  /// Last timestamp handed out. Two saves inside the same millisecond would
  /// otherwise tie, and Continue Listening would show the older episode.
  static int _lastStamp = 0;

  static int _now() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _lastStamp = now > _lastStamp ? now : _lastStamp + 1;
  }

  /// Reads the stored progress into memory. Safe to call more than once;
  /// only the first call touches disk.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs?.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((id, value) {
        final progress = PodcastProgress.fromJson(id.toString(), value);
        if (progress != null) _cache[progress.podcastId] = progress;
      });
      revision.value++;
    } catch (e) {
      debugPrint('[PodcastProgress] load failed: $e');
    }
  }

  static PodcastProgress? of(int podcastId) => _cache[podcastId];

  /// Where playback of [podcastId] should pick up: the stored position, or
  /// null when there is nothing worth resuming (finished, or barely started).
  static Duration? resumePosition(int podcastId) {
    final progress = _cache[podcastId];
    if (progress == null || !progress.started) return null;
    return progress.position;
  }

  /// Episodes with a resume point, most recently played first.
  static List<PodcastProgress> inProgress() {
    final list = _cache.values.where((p) => p.started).toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// Records playback position. Positions inside the last [_completionTail]
  /// of a known duration flip the episode to completed.
  static Future<void> save(
    int podcastId, {
    required Duration position,
    required Duration duration,
  }) async {
    final known = duration.inMilliseconds > 0;
    final done = known && position >= duration - _completionTail;
    _write(PodcastProgress(
      podcastId: podcastId,
      position: done ? duration : position,
      // Keep the last known duration if the player hasn't resolved one yet.
      duration: known ? duration : (_cache[podcastId]?.duration ?? Duration.zero),
      completed: done,
      updatedAt: _now(),
    ));
    await _flush();
  }

  static Future<void> markCompleted(int podcastId, {Duration? duration}) async {
    final existing = _cache[podcastId];
    final total = duration ?? existing?.duration ?? Duration.zero;
    _write(PodcastProgress(
      podcastId: podcastId,
      position: total,
      duration: total,
      completed: true,
      updatedAt: _now(),
    ));
    await _flush();
  }

  /// Forgets the resume point — "mark as unplayed".
  static Future<void> clear(int podcastId) async {
    if (_cache.remove(podcastId) == null) return;
    revision.value++;
    await _flush();
  }

  static void _write(PodcastProgress progress) {
    _cache[progress.podcastId] = progress;
    if (_cache.length > _maxEntries) {
      final oldest = _cache.values.toList()
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      for (final stale in oldest.take(_cache.length - _maxEntries)) {
        _cache.remove(stale.podcastId);
      }
    }
    revision.value++;
  }

  static Future<void> _flush() async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      final map = {
        for (final entry in _cache.entries)
          entry.key.toString(): entry.value.toJson(),
      };
      await prefs.setString(_key, jsonEncode(map));
    } catch (e) {
      debugPrint('[PodcastProgress] save failed: $e');
    }
  }

  /// Test hook: drops the in-memory cache and the "already loaded" latch.
  @visibleForTesting
  static void resetForTest() {
    _cache.clear();
    _prefs = null;
    _loaded = false;
    _lastStamp = 0;
    revision.value = 0;
  }
}
