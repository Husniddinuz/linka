import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// One word of a cue with the slice of time it is spoken in.
class TimedWord {
  final String text;
  final Duration start;
  final Duration end;
  const TimedWord({required this.text, required this.start, required this.end});
}

/// A single timed subtitle line: [text] is shown from [start] to [end].
class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;

  /// Who is speaking, when the track labels its lines (`Speaker 1: …`,
  /// `HOST: …`). Null for unlabelled tracks.
  final String? speaker;

  SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
    this.speaker,
  });

  Duration get duration => end > start ? end - start : Duration.zero;

  /// Word-level timings for karaoke-style highlighting.
  ///
  /// SRT and WebVTT are line-timed, not word-timed, so each word is given a
  /// share of the cue proportional to its length (longer words take longer to
  /// say than short ones — closer than splitting the cue evenly). Computed
  /// once per cue and cached.
  late final List<TimedWord> words = _computeWords();

  List<TimedWord> _computeWords() {
    final tokens = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (tokens.isEmpty) return const [];
    final totalMs = duration.inMilliseconds;
    if (totalMs <= 0) {
      return [
        for (final token in tokens)
          TimedWord(text: token, start: start, end: end),
      ];
    }
    final weights = tokens.map((w) => w.length + 1).toList();
    final totalWeight = weights.reduce((a, b) => a + b);

    final result = <TimedWord>[];
    var elapsed = 0;
    for (var i = 0; i < tokens.length; i++) {
      final slice = i == tokens.length - 1
          ? totalMs - elapsed
          : (totalMs * weights[i] / totalWeight).round();
      result.add(TimedWord(
        text: tokens[i],
        start: start + Duration(milliseconds: elapsed),
        end: start + Duration(milliseconds: elapsed + slice),
      ));
      elapsed += slice;
    }
    return result;
  }

  /// Index of the word being spoken at [position], or -1 before/after the cue.
  int wordIndexAt(Duration position) {
    if (position < start) return -1;
    if (position >= end) return words.length - 1;
    for (var i = 0; i < words.length; i++) {
      if (position < words[i].end) return i;
    }
    return words.length - 1;
  }
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

  /// Matches a leading speaker label — `Speaker 1:`, `HOST:`, `- Anna:`,
  /// `>> Dr. Lee:`. Kept deliberately tight (short, no sentence punctuation)
  /// so ordinary prose like `One thing to remember: …` isn't mistaken for one.
  static final _speakerPattern =
      RegExp(r'^(?:[->\s]{0,4})([A-Za-z][A-Za-z0-9 .&#-]{0,23}):\s+(?=\S)');

  /// Styling/positioning markup that shouldn't reach the transcript:
  /// VTT tags (`<v Bob>`, `<i>`), and SSA overrides (`{\an8}`).
  static final _markupPattern = RegExp(r'<[^>]*>|\{\\[^}]*\}');

  /// Parses a WebVTT or SRT subtitle string into cues, sorted by start time.
  /// Handles both `.` (VTT) and `,` (SRT) as the millisecond separator, and
  /// lifts per-line speaker labels into [SubtitleCue.speaker] when the track
  /// consistently uses them.
  static List<SubtitleCue> parseSubtitle(String content) {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized.split(RegExp(r'\n[ \t]*\n'));

    // First pass: timings + raw text. Speaker labels are resolved afterwards,
    // once the whole file is known (see _acceptedSpeakers).
    final parsed = <({Duration start, Duration end, String text})>[];
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

      final text = lines
          .sublist(timingIndex + 1)
          .join('\n')
          .replaceAll(_markupPattern, '')
          .replaceAll(RegExp(r'\s*\n\s*'), ' ')
          .trim();
      if (text.isEmpty) continue;

      parsed.add((start: start, end: end, text: text));
    }

    final accepted = _acceptedSpeakers(parsed.map((p) => p.text));

    final cues = <SubtitleCue>[];
    for (final entry in parsed) {
      var text = entry.text;
      String? speaker;
      final match = _speakerPattern.firstMatch(text);
      final label = match?.group(1)?.trim();
      if (label != null && accepted.contains(label.toLowerCase())) {
        speaker = label;
        text = text.substring(match!.end).trim();
      }
      if (text.isEmpty) continue;
      cues.add(SubtitleCue(
        start: entry.start,
        end: entry.end,
        text: text,
        speaker: speaker,
      ));
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  /// Share of labelled lines above which a track is taken to be a properly
  /// speaker-labelled transcript, so even a label used once (a guest with a
  /// single line) is treated as a speaker.
  static const _labelledTrackRatio = 0.6;

  /// Decides which `Label:` prefixes are really speaker names.
  ///
  /// A one-off `Note: …` or `Warning: …` inside prose would otherwise be
  /// promoted to a speaker. Two signals rule that out: either most of the
  /// track is labelled (so labelling is the file's convention), or the label
  /// recurs — real transcripts name the same handful of people over and over.
  static Set<String> _acceptedSpeakers(Iterable<String> texts) {
    final counts = <String, int>{};
    var total = 0;
    var labelled = 0;
    for (final text in texts) {
      total++;
      final label = _speakerPattern.firstMatch(text)?.group(1)?.trim();
      if (label == null) continue;
      labelled++;
      final key = label.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    if (total > 0 && labelled / total >= _labelledTrackRatio) {
      return counts.keys.toSet();
    }
    return counts.entries.where((e) => e.value >= 2).map((e) => e.key).toSet();
  }

  /// Distinct speakers in [cues], in the order they first speak.
  static List<String> speakers(List<SubtitleCue> cues) {
    final seen = <String>[];
    for (final cue in cues) {
      final speaker = cue.speaker;
      if (speaker != null && !seen.contains(speaker)) seen.add(speaker);
    }
    return seen;
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

  /// Like [activeCueIndex], but holds on the line that just finished when
  /// [position] falls in the silence between two cues, so a follow-along
  /// transcript doesn't blank out between sentences. -1 before the first cue.
  /// Assumes [cues] is sorted by start time.
  static int nearestCueIndex(List<SubtitleCue> cues, Duration position) {
    var low = 0;
    var high = cues.length - 1;
    var found = -1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (cues[mid].start <= position) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }
}
