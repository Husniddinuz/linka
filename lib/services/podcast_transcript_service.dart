import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'subtitle_service.dart';

/// Resolves and caches podcast transcripts.
///
/// Two places follow along with the same track — the player screen and the
/// mini player — and reopening the player shouldn't re-download a transcript
/// that's already in memory, so the fetch (and the several fallbacks needed to
/// find the subtitle URL in the first place) lives here rather than in a
/// screen's state.
class PodcastTranscriptService {
  PodcastTranscriptService._();

  static final Map<int, List<SubtitleCue>> _cache = {};
  static final Map<int, Future<List<SubtitleCue>>> _inflight = {};

  /// Already-loaded cues for [podcastId], or null if none have been fetched.
  /// Synchronous, for use inside `build`.
  static List<SubtitleCue>? cached(int podcastId) => _cache[podcastId];

  /// Loads the transcript for [podcastId]. Falls back through the subtitle URL
  /// the caller has, then the podcast detail endpoint, then a URL derived from
  /// the audio filename. Returns an empty list when there is no transcript.
  /// Concurrent calls for the same episode share one fetch.
  static Future<List<SubtitleCue>> load(
    int podcastId, {
    String? subtitleUrl,
    String? audioUrl,
  }) {
    final cached = _cache[podcastId];
    if (cached != null) return Future.value(cached);
    return _inflight[podcastId] ??= _load(
      podcastId,
      subtitleUrl: subtitleUrl,
      audioUrl: audioUrl,
    ).whenComplete(() => _inflight.remove(podcastId));
  }

  static Future<List<SubtitleCue>> _load(
    int podcastId, {
    String? subtitleUrl,
    String? audioUrl,
  }) async {
    var url = subtitleUrl;
    if (url == null || url.isEmpty) {
      try {
        final data = await ApiService.get('/content/podcasts/$podcastId/');
        final podcast = data['data'] as Map<String, dynamic>? ?? data;
        url = podcast['subtitle_url'] as String?;
        audioUrl ??= podcast['audio_url'] as String?;
      } catch (_) {
        url = null;
      }
    }
    if ((url == null || url.isEmpty) && audioUrl != null && audioUrl.isNotEmpty) {
      url = deriveSubtitleUrl(audioUrl);
    }

    final cues = await SubtitleService.fetchCues(url);
    // Cache misses too — an episode without a transcript shouldn't be retried
    // on every position tick from the mini player.
    _cache[podcastId] = cues;
    debugPrint('[Subtitle] podcast=$podcastId cues=${cues.length} url=$url');
    return cues;
  }

  /// Derives the subtitle URL from [audioUrl] by inserting `srt/` after
  /// `podcasts/` in the path and swapping the audio extension for `.srt`,
  /// e.g. `.../podcasts/audio.mp3` → `.../podcasts/srt/audio.srt`. Returns
  /// null when the URL doesn't follow that layout.
  static String? deriveSubtitleUrl(String audioUrl) {
    final withSubdir = audioUrl.replaceFirst('podcasts/', 'podcasts/srt/');
    final srtUrl = withSubdir.replaceFirst(
      RegExp(r'\.(mp3|m4a|wav|aac|ogg)$', caseSensitive: false),
      '.srt',
    );
    if (srtUrl == audioUrl) {
      debugPrint('[Subtitle] URL did not match expected pattern: $audioUrl');
      return null;
    }
    return srtUrl;
  }

  @visibleForTesting
  static void clearCache() {
    _cache.clear();
    _inflight.clear();
  }
}
