import 'mock_test.dart';

/// One scored sitting of any skill — an essay, a mock-test paper, a speaking
/// answer — reduced to what a progress screen needs: when, what, and the band.
class ProgressEntry {
  const ProgressEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.band,
    required this.submittedAt,
    this.source,
  });

  final int id;
  final String title;
  final String subtitle;
  final double band;
  final DateTime submittedAt;

  /// The payload this was folded from — a [MockTestAttempt] for a mock-test
  /// paper, the raw attempt map for a speaking answer, a writing preview map
  /// (`id`, `status`, `overall_band`, `prompt`, …) for an essay — so a row can
  /// open the same result screen the submit flow shows, without a refetch.
  final Object? source;
}

/// Where a student stands in one skill, folded from its attempt history.
///
/// `attempts` counts every finished sitting, but only the banded ones set the
/// bands — a submitted paper with no band (never in practice, but the field is
/// nullable) is still a test taken, just not a mark.
class SkillProgress {
  const SkillProgress({required this.attempts, required this.history});

  final int attempts;

  /// Oldest first, banded entries only — the order a chart reads them in.
  final List<ProgressEntry> history;

  static const empty = SkillProgress(attempts: 0, history: []);

  bool get hasBand => history.isNotEmpty;
  double? get latest => hasBand ? history.last.band : null;
  double? get best => hasBand ? history.map((e) => e.band).reduce((a, b) => a > b ? a : b) : null;
  double? get average => hasBand ? history.map((e) => e.band).reduce((a, b) => a + b) / history.length : null;
  List<double> get bands => [for (final e in history) e.band];

  /// Recent-window average minus the earlier average — the same rule the
  /// writing insights endpoint applies (`_trend`), so the four skills report
  /// change the same way. Null until there is enough history to say anything:
  /// last-minus-first would call half-band noise a trend.
  double? get change => trendOf(bands);

  static const _recentWindow = 3;

  static double? trendOf(List<double> values) {
    if (values.length < _recentWindow + 1) return null;
    final recent = values.sublist(values.length - _recentWindow);
    final earlier = values.sublist(0, values.length - _recentWindow);
    double mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
    return double.parse((mean(recent) - mean(earlier)).toStringAsFixed(2));
  }

  /// Newest first — for a list, the opposite of the chart.
  List<ProgressEntry> get recent => history.reversed.toList();

  /// Reading or Listening, from the shared mock-test attempts list.
  static SkillProgress fromMockAttempts(List<MockTestAttempt> attempts, String testType) {
    final done = attempts.where((a) => a.status == 'submitted' && a.testType == testType).toList();
    final entries = <ProgressEntry>[];
    for (final a in done) {
      final band = double.tryParse(a.bandScore ?? '');
      final at = DateTime.tryParse(a.submittedAt ?? '') ?? DateTime.tryParse(a.startedAt);
      if (band == null || at == null) continue;
      entries.add(ProgressEntry(
        id: a.id,
        title: a.testTitle,
        subtitle: a.rawScore != null && a.maxScore != null ? '${a.rawScore}/${a.maxScore} correct' : '',
        band: band,
        submittedAt: at,
        source: a,
      ));
    }
    entries.sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
    return SkillProgress(attempts: done.length, history: entries);
  }

  /// Writing, from the `band_history` of `/writing-attempts/insights/`, which
  /// the server already hands over oldest first.
  static SkillProgress fromWritingInsights(Map<String, dynamic> insights) {
    final raw = insights['band_history'];
    final entries = <ProgressEntry>[];
    if (raw is List) {
      for (final item in raw.whereType<Map>()) {
        final band = _toDouble(item['overall_band']);
        final at = DateTime.tryParse(item['submitted_at']?.toString() ?? '');
        final id = (item['attempt_id'] as num?)?.toInt();
        if (band == null || at == null || id == null) continue;
        final task = (item['task_number'] as num?)?.toInt();
        final words = (item['word_count'] as num?)?.toInt();
        entries.add(ProgressEntry(
          id: id,
          title: item['title']?.toString() ?? '',
          subtitle: [if (task != null) 'Task $task', if (words != null) '$words words'].join(' · '),
          band: band,
          submittedAt: at,
          // Enough of the attempt for the result screen to draw its header;
          // it fetches the full review itself from the id.
          source: <String, dynamic>{
            'id': id,
            'status': 'graded',
            'overall_band': band,
            'word_count': words,
            'submitted_at': item['submitted_at'],
            'prompt': {'title': item['title'], 'task_number': task},
          },
        ));
      }
    }
    entries.sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
    final graded = (insights['attempts_graded'] as num?)?.toInt() ?? entries.length;
    return SkillProgress(attempts: graded, history: entries);
  }

  /// Speaking, from `/speaking-attempts/` (newest first, graded and not).
  static SkillProgress fromSpeakingAttempts(List<Map<String, dynamic>> attempts) {
    final graded = attempts.where((a) => a['status']?.toString() == 'graded').toList();
    final entries = <ProgressEntry>[];
    for (final a in graded) {
      final band = _toDouble(a['overall_band']);
      final at = DateTime.tryParse(a['submitted_at']?.toString() ?? '');
      final id = (a['id'] as num?)?.toInt();
      if (band == null || at == null || id == null) continue;
      final part = (a['part'] as num?)?.toInt();
      entries.add(ProgressEntry(
        id: id,
        title: a['question_text']?.toString() ?? '',
        subtitle: part != null ? 'Part $part' : '',
        band: band,
        submittedAt: at,
        source: a,
      ));
    }
    entries.sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
    return SkillProgress(attempts: graded.length, history: entries);
  }
}

/// Time spent with a tutor, from finished bookings.
class LessonProgress {
  const LessonProgress({required this.count, required this.minutes});

  final int count;
  final int minutes;

  static const empty = LessonProgress(count: 0, minutes: 0);

  /// Hours to the nearest half — "2.5", "3" — the way the website shows it.
  /// Minutes are true but nobody reads their study time in minutes.
  double get hours => (minutes / 60 * 2).round() / 2;

  String get hoursLabel {
    final h = hours;
    return h == h.roundToDouble() ? h.toInt().toString() : h.toStringAsFixed(1);
  }

  static LessonProgress fromBookings(List<Map<String, dynamic>> bookings) {
    var count = 0;
    var minutes = 0;
    for (final b in bookings) {
      if (b['status']?.toString() != 'finished') continue;
      count++;
      minutes += (b['duration_minutes'] as num?)?.toInt() ?? 0;
    }
    return LessonProgress(count: count, minutes: minutes);
  }
}

/// Everything the progress screen shows, assembled from four endpoints that
/// each know one skill. See [StudentProgressService].
class StudentProgress {
  const StudentProgress({
    required this.writing,
    required this.listening,
    required this.reading,
    required this.speaking,
    required this.lessons,
    this.writingInsights,
  });

  final SkillProgress writing;
  final SkillProgress listening;
  final SkillProgress reading;
  final SkillProgress speaking;
  final LessonProgress lessons;

  /// The raw insights payload, kept so the writing change badge can use the
  /// server's own `band_change` rather than a client recomputation.
  final Map<String, dynamic>? writingInsights;

  double? get writingChange {
    final raw = writingInsights?['band_change'];
    if (raw is num) return raw.toDouble();
    return writing.change;
  }

  /// Nothing done in any skill means nothing to say. A row of em dashes is a
  /// worse welcome than no row at all.
  bool get hasAny =>
      writing.attempts > 0 ||
      listening.attempts > 0 ||
      reading.attempts > 0 ||
      speaking.attempts > 0 ||
      lessons.count > 0;
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
