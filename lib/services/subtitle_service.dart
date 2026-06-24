import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// A single timed subtitle line: [text] is shown from [start] to [end].
class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

/// Fetches and parses subtitle tracks for podcasts.
///
/// Supports WebVTT (.vtt) and SubRip (.srt) formats. The URL may be an HTTP(S)
/// URL or an `asset://path` reference for bundled test files.
class SubtitleService {
  /// Downloads the subtitle file at [url] and returns its cues, sorted by
  /// start time. Supports `asset://` URLs for local assets. Returns an empty
  /// list if the URL is empty, unreachable, or contains no parseable cues.
  static Future<List<SubtitleCue>> fetchCues(String? url) async {
    if (url == null || url.trim().isEmpty) return const [];
    try {
      if (url.startsWith('asset://')) {
        final assetPath = url.substring('asset://'.length);
        final content = await rootBundle.loadString(assetPath);
        return parseSubtitle(content);
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return const [];
      return parseSubtitle(response.body);
    } catch (_) {
      return const [];
    }
  }

  /// Parses a WebVTT or SRT subtitle string into cues, sorted by start time.
  /// Handles both `.` (VTT) and `,` (SRT) as the millisecond separator.
  static List<SubtitleCue> parseSubtitle(String content) {
    final cues = <SubtitleCue>[];
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized.split(RegExp(r'\n[ \t]*\n'));

    for (final block in blocks) {
      final lines = block.split('\n');
      final timingIndex = lines.indexWhere((l) => l.contains('-->'));
      if (timingIndex == -1) continue;

      final timing = lines[timingIndex];
      final arrow = timing.indexOf('-->');
      final startStr = timing.substring(0, arrow).trim();
      final endStr =
          timing.substring(arrow + 3).trim().split(RegExp(r'\s')).first;

      final start = _parseTimestamp(startStr);
      final end = _parseTimestamp(endStr);
      if (start == null || end == null) continue;

      final text = lines.sublist(timingIndex + 1).join('\n').trim();
      if (text.isEmpty) continue;

      cues.add(SubtitleCue(start: start, end: end, text: text));
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  /// Parses `HH:MM:SS.mmm`, `HH:MM:SS,mmm`, or `MM:SS.mmm` / `MM:SS,mmm`
  /// into a [Duration]. The comma form is used by SRT files. Returns null if
  /// the stamp is malformed.
  static Duration? _parseTimestamp(String value) {
    // Normalize SRT comma separator to dot
    final normalized = value.replaceAll(',', '.');
    final parts = normalized.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    try {
      int hours = 0, minutes, secondsAndMillis;
      if (parts.length == 3) {
        hours = int.parse(parts[0]);
        minutes = int.parse(parts[1]);
        secondsAndMillis = 2;
      } else {
        minutes = int.parse(parts[0]);
        secondsAndMillis = 1;
      }
      final secParts = parts[secondsAndMillis].split('.');
      final seconds = int.parse(secParts[0]);
      final millis = secParts.length > 1
          ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
          : 0;
      return Duration(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        milliseconds: millis,
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns the index of the cue active at [position], or -1 if none.
  /// Assumes [cues] is sorted by start time.
  static int activeCueIndex(List<SubtitleCue> cues, Duration position) {
    for (var i = 0; i < cues.length; i++) {
      if (position >= cues[i].start && position < cues[i].end) return i;
    }
    return -1;
  }
}
