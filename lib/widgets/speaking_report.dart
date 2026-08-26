import 'package:flutter/material.dart';

import 'writing_report.dart';

/// The AI Speaking report: the shared labels, the quote→timestamp matcher, and
/// the sections a marked spoken answer is drawn from.
///
/// Deliberately built on top of `writing_report.dart` rather than beside it.
/// The two reports mark different skills but they are the *same document* —
/// a band, a plan, the evidence — and a student who has read one should not
/// have to learn a second layout. So the colour roles (`context.wr`), the
/// cards, the band bars, the tags, the numbered steps and the vocabulary
/// swaps all come from there; only what is genuinely particular to speech
/// lives here.
///
/// What is particular to speech, and why each of these is not in the Writing
/// report:
///  * Pronunciation is a criterion the exam has and this grader cannot mark
///    from a transcript, so the report has to say so rather than draw three
///    bars where a student expects four.
///  * The measured half — pauses, speech rate, fillers — comes from the
///    recording's word timings, which no essay has.
///  * A correction can be *heard*: every quote is verbatim in the transcript
///    and the timings say when it was said, so each card can seek the audio.

// ---------------------------------------------------------------------------
// Labels
// ---------------------------------------------------------------------------

/// The four IELTS Speaking criteria, in the order every surface renders them.
///
/// `pronunciation` is listed because the exam has it and the report has to
/// account for it — not because it is scored. It arrives null with
/// `analysis.pronunciation_scored: false`, and the report says why rather than
/// inventing a fourth number out of a transcript.
const sCriterionKeys = <String>[
  'fluency_coherence',
  'lexical_resource',
  'grammar_range_accuracy',
  'pronunciation',
];

const sCriterionNames = <String, String>{
  'fluency_coherence': 'Fluency & coherence',
  'lexical_resource': 'Lexical resource',
  'grammar_range_accuracy': 'Grammatical range & accuracy',
  'pronunciation': 'Pronunciation',
};

const sCriterionShort = <String, String>{
  'fluency_coherence': 'Fluency',
  'lexical_resource': 'Lexis',
  'grammar_range_accuracy': 'Grammar',
  'pronunciation': 'Pronun.',
};

const sCriterionIcons = <String, IconData>{
  'fluency_coherence': Icons.waves_rounded,
  'lexical_resource': Icons.menu_book_rounded,
  'grammar_range_accuracy': Icons.rule_rounded,
  'pronunciation': Icons.record_voice_over_rounded,
};

/// Why pronunciation has no number, in the student's terms. Used when the
/// server sends no `pronunciation_note` of its own.
const sPronunciationFallback =
    'Pronunciation cannot be marked from a transcript — the words survive, the '
    'sounds do not. Book a tutor for feedback on how you sound.';

/// The error categories a *spoken* answer can have. Narrower than the Writing
/// list on purpose: nothing spoken has a spelling or a punctuation mistake.
const sCategoryNames = <String, String>{
  'grammar': 'Grammar',
  'vocabulary': 'Vocabulary',
  'cohesion': 'Linking',
  'task_response': 'Answering the question',
};

/// The band's tier, in the exam's own words. A bare "6.5" means nothing to a
/// student who has not memorised the descriptors.
String sBandTier(double band) {
  if (band >= 8.5) return 'Expert user';
  if (band >= 7) return 'Good user';
  if (band >= 6) return 'Competent user';
  if (band >= 5) return 'Modest user';
  return 'Still building';
}

/// `m:ss` — a spoken answer is measured in seconds, never in minutes alone.
String sClock(num seconds) {
  final safe = seconds.round().clamp(0, 1 << 20);
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}

/// How long an answer may run, by part — the exam's own limits.
///
/// Real caps, and shown as a countdown rather than sprung: Part 2 *is* two
/// minutes, and a trainer that lets you talk for six teaches you to fail the
/// real thing.
const sPartSeconds = <int, int>{1: 60, 2: 120, 3: 150};

int sCapForPart(int part) => sPartSeconds[part] ?? sPartSeconds[2]!;

// ---------------------------------------------------------------------------
// Quote → timestamp
// ---------------------------------------------------------------------------

/// Where in the recording each quoted mistake was said.
///
/// The transcript is one string and the timings are a flat word list, so the
/// two are matched by walking the words and comparing the same normalised form
/// the server verified the quote against. A miss leaves the quote out and its
/// card simply loses the play button — a wrong seek would send the student to
/// the wrong sentence, which is worse than no seek at all.
Map<String, double> sQuoteTimes(Map<String, dynamic> attempt) {
  final times = <String, double>{};
  final words = wMapList(attempt['word_timings']);
  final errors = wMapList((attempt['analysis'] as Map?)?['errors']);
  if (words.isEmpty || errors.isEmpty) return times;

  String normalise(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s']"), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Kept parallel to `words` so a match index still points at a real timing.
  final spoken = <String>[];
  final starts = <double>[];
  for (final word in words) {
    final text = normalise(word['word']?.toString() ?? '');
    if (text.isEmpty) continue;
    spoken.add(text);
    starts.add(wToDouble(word['start']));
  }

  for (final error in errors) {
    final quote = error['quote']?.toString() ?? '';
    if (quote.isEmpty || times.containsKey(quote)) continue;
    final needle = normalise(quote).split(' ').where((w) => w.isNotEmpty).toList();
    if (needle.isEmpty) continue;

    for (var start = 0; start + needle.length <= spoken.length; start++) {
      var matched = true;
      for (var offset = 0; offset < needle.length; offset++) {
        if (spoken[start + offset] != needle[offset]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        // A moment before the quote, so playback starts on the run-up rather
        // than clipping the first syllable.
        times[quote] = (starts[start] - 0.4).clamp(0.0, double.infinity);
        break;
      }
    }
  }

  return times;
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

/// The band, its tier, the four criteria as bars — and, unavoidably, the one
/// that was not marked.
///
/// Pronunciation is drawn as an explicit "not scored" stub rather than left
/// out of the row: a student who knows IELTS has four Speaking criteria will
/// count three and assume the report is broken.
class SpeakingBandHero extends StatelessWidget {
  const SpeakingBandHero({super.key, required this.attempt, this.onShare, this.sharing = false});

  final Map<String, dynamic> attempt;
  final VoidCallback? onShare;
  final bool sharing;

  @override
  Widget build(BuildContext context) {
    final analysis = (attempt['analysis'] as Map?)?.cast<String, dynamic>() ?? const {};
    final overall = wToDoubleOrNull(attempt['overall_band']);
    final summary = (analysis['summary']?.toString() ?? '').trim();
    final feedback = (attempt['feedback']?.toString() ?? '').trim();
    final blurb = summary.isNotEmpty ? summary : feedback;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [WPalette.primary, WPalette.primaryLight],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: WPalette.primary.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 14)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mic_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      overall == null ? 'Speaking' : sBandTier(overall),
                      style: const TextStyle(
                          fontFamily: 'SF Pro', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (onShare != null)
                GestureDetector(
                  onTap: sharing ? null : onShare,
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: sharing
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.ios_share_rounded, size: 16, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'YOUR BAND',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            wFormatBand(attempt['overall_band']),
            style: const TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 52,
              height: 1.05,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final key in sCriterionKeys) ...[
                Expanded(child: _CriterionColumn(band: wToDoubleOrNull(attempt[key]), label: sCriterionShort[key]!)),
              ],
            ],
          ),
          if (blurb.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.only(top: 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.16))),
              ),
              child: Text(
                blurb,
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 13.5,
                  height: 1.55,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One criterion in the hero: a vertical bar filled to its band, or an empty
/// track and an "n/a" for the one that was not scored.
class _CriterionColumn extends StatelessWidget {
  const _CriterionColumn({required this.band, required this.label});
  final double? band;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scored = band != null;
    return Column(
      children: [
        Text(
          scored ? band!.toStringAsFixed(1) : '—',
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(alpha: scored ? 1 : 0.45),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 54,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: 7,
                height: 54,
                color: Colors.white.withValues(alpha: 0.2),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: scored ? (band! / 9).clamp(0.0, 1.0) : 0.0),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) => FractionallySizedBox(
                      heightFactor: t,
                      child: Container(color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        if (!scored)
          Text(
            'n/a',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.42),
            ),
          ),
      ],
    );
  }
}

/// The measured facts, as facts.
///
/// These are the numbers the grader was *given* rather than anything it
/// decided, which is exactly why they are worth showing: "your longest pause
/// was 3.4 seconds" is checkable, and a student can hear it in their own
/// recording. A figure that was not measured is left out rather than shown as
/// zero — see `timings_available`.
class SpeakingMeasuredStrip extends StatelessWidget {
  const SpeakingMeasuredStrip({super.key, required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final fillers = wMapList(stats['fillers']);

    final tiles = <List<String>>[
      ['${wToInt(stats['word_count'])}', 'Words spoken'],
      if (stats['speech_rate_wpm'] != null) ['${wToInt(stats['speech_rate_wpm'])}', 'Words per minute'],
      if (stats['pause_count'] != null) ['${wToInt(stats['pause_count'])}', 'Pauses over 0.5s'],
      if (stats['longest_pause_seconds'] != null)
        ['${wToDouble(stats['longest_pause_seconds']).toStringAsFixed(1)}s', 'Longest pause'],
      if (stats['words_per_run'] != null)
        [wToDouble(stats['words_per_run']).toStringAsFixed(1), 'Words per unbroken run'],
      ['${wToInt(stats['filler_count'])}', 'Fillers'],
    ];

    // Three across, sized off the page width the report is laid out in
    // (16pt gutters, 10pt between tiles) — same grid as the Writing stats.
    final tileWidth = (MediaQuery.of(context).size.width - 32 - 20) / 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: tileWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  decoration: wCardDecoration(context, radius: 16),
                  child: Column(
                    children: [
                      Text(
                        tile[0],
                        style: TextStyle(
                            fontFamily: 'SF Pro', fontSize: 18, fontWeight: FontWeight.w800, color: wr.text),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tile[1],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 10.5,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: wr.muted),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (fillers.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final filler in fillers)
                WTag(
                  label: '“${filler['phrase']}” ×${wToInt(filler['count'])}',
                  background: wr.highlight.withValues(alpha: wr.isDark ? 0.16 : 0.22),
                  foreground: wr.isDark ? wr.highlight : wr.text,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One criterion in full: the band, the grader's verdict on this answer, what
/// went well and what to change. The unscored one states why instead.
class SpeakingCriterionCard extends StatelessWidget {
  const SpeakingCriterionCard({
    super.key,
    required this.criterionKey,
    required this.band,
    this.detail,
    this.notScoredNote,
  });

  final String criterionKey;
  final double? band;
  final Map<String, dynamic>? detail;

  /// Shown in place of a band for a criterion the grader could not mark.
  final String? notScoredNote;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final name = sCriterionNames[criterionKey] ?? wTopicLabel(criterionKey);
    final icon = sCriterionIcons[criterionKey] ?? Icons.rule_rounded;
    final scored = band != null;

    if (!scored) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: wr.card.withValues(alpha: wr.isDark ? 1 : 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: wr.line, width: 1.2, strokeAlign: BorderSide.strokeAlignInside),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: wr.faint),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                        fontFamily: 'SF Pro', fontSize: 14, fontWeight: FontWeight.w700, color: wr.muted),
                  ),
                ),
                WTag(label: 'Not scored'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              notScoredNote?.trim().isNotEmpty == true ? notScoredNote!.trim() : sPronunciationFallback,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13, height: 1.5, color: wr.faint),
            ),
          ],
        ),
      );
    }

    final verdict = detail?['verdict']?.toString() ?? '';
    final strengths = wStringList(detail?['strengths']);
    final improvements = wStringList(detail?['improvements']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: wCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: wr.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                      fontFamily: 'SF Pro', fontSize: 14, fontWeight: FontWeight.w700, color: wr.text),
                ),
              ),
              Text(
                band!.toStringAsFixed(1),
                style: TextStyle(
                    fontFamily: 'SF Pro', fontSize: 19, fontWeight: FontWeight.w800, color: wr.text),
              ),
            ],
          ),
          const SizedBox(height: 12),
          WBandBar(band: band!),
          if (verdict.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              verdict,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
            ),
          ],
          for (final item in strengths) ...[
            const SizedBox(height: 9),
            _Bullet(icon: Icons.check_circle_rounded, color: wr.good, text: item),
          ],
          for (final item in improvements) ...[
            const SizedBox(height: 9),
            _Bullet(icon: Icons.arrow_forward_rounded, color: wr.accent, text: item),
          ],
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
          ),
        ),
      ],
    );
  }
}

/// One correction, and the moment it happened.
///
/// [onHear] is what makes this worth more than the essay equivalent: the quote
/// is guaranteed verbatim in the transcript and the word timings say when it
/// was said, so the student can hear themselves make the mistake instead of
/// reading about it. Absent when the quote could not be placed in the timings.
class SpeakingCorrectionCard extends StatelessWidget {
  const SpeakingCorrectionCard({
    super.key,
    required this.error,
    required this.index,
    this.onHear,
  });

  final Map<String, dynamic> error;
  final int index;
  final VoidCallback? onHear;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final category = error['category']?.toString() ?? 'grammar';
    final topic = error['grammar_topic']?.toString();
    final severity = error['severity']?.toString();
    final correction = error['correction']?.toString() ?? '';
    final explanation = error['explanation']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: wCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: wr.soft, shape: BoxShape.circle),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                            fontFamily: 'SF Pro', fontSize: 10, fontWeight: FontWeight.w800, color: wr.muted),
                      ),
                    ),
                    WTag(label: sCategoryNames[category] ?? wTopicLabel(category)),
                    if (topic != null && topic.isNotEmpty) WTag(label: wTopicLabel(topic)),
                    if (severity == 'high')
                      WTag(
                        label: wSeverityNames['high']!,
                        background: wr.bad.withValues(alpha: 0.12),
                        foreground: wr.bad,
                      ),
                  ],
                ),
              ),
              if (onHear != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onHear,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: wr.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded, size: 14, color: wr.accent),
                        const SizedBox(width: 3),
                        Text(
                          'Hear it',
                          style: TextStyle(
                              fontFamily: 'SF Pro', fontSize: 11, fontWeight: FontWeight.w700, color: wr.accent),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            error['quote']?.toString() ?? '',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 14,
              height: 1.5,
              color: wr.bad,
              decoration: TextDecoration.lineThrough,
              decorationColor: wr.bad,
            ),
          ),
          if (correction.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: wr.good),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    correction,
                    style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        color: wr.good),
                  ),
                ),
              ],
            ),
          ],
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              explanation,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// A spoken habit the grader named — what it is, and what it costs.
class SpeakingHabits extends StatelessWidget {
  const SpeakingHabits({super.key, required this.habits});
  final List<Map<String, dynamic>> habits;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return Column(
      children: [
        for (final habit in habits)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: wCardDecoration(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  habit['title']?.toString() ?? '',
                  style: TextStyle(
                      fontFamily: 'SF Pro', fontSize: 14.5, fontWeight: FontWeight.w700, color: wr.text),
                ),
                if ((habit['detail']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    habit['detail'].toString(),
                    style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
                  ),
                ],
                if ((habit['cost']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.only(top: 10),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: wr.line))),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
                        children: [
                          TextSpan(
                            text: 'What it costs: ',
                            style: TextStyle(fontWeight: FontWeight.w700, color: wr.text),
                          ),
                          TextSpan(text: habit['cost'].toString()),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The whole report
// ---------------------------------------------------------------------------

/// Every section of a marked spoken answer, in the order the Writing report
/// uses: the band, then what to do about it, then the evidence. A student who
/// reads only the top of the screen should still leave with an action.
///
/// Every section is independently optional — the grader can legitimately
/// return nothing for one (a mistake-free answer has no corrections), and an
/// attempt marked before a section shipped simply has no key for it. So the
/// report degrades to the bands and the transcript rather than erroring.
class SpeakingReportView extends StatelessWidget {
  const SpeakingReportView({
    super.key,
    required this.attempt,
    this.onHear,
    this.header,
    this.footer,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 28),
  });

  final Map<String, dynamic> attempt;

  /// Seeks the player above the report to a moment in the recording. Absent
  /// when there is no player on screen, which drops the "Hear it" buttons.
  final void Function(double seconds)? onHear;

  /// Sits above the band hero — the recording's own player, typically.
  final Widget? header;

  /// Sits below the transcript — the actions that follow from the report.
  final Widget? footer;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final analysis = (attempt['analysis'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final criteria = (analysis['criteria'] as Map?)?.cast<String, dynamic>();
    final stats = (analysis['stats'] as Map?)?.cast<String, dynamic>();
    final errors = wMapList(analysis['errors']);
    final nextSteps = wMapList(analysis['next_steps']);
    final habits = wMapList(analysis['habits']);
    final grammarTopics = wMapList(analysis['grammar_topics']);
    final vocabulary = wMapList(analysis['vocabulary_upgrades']);
    final transcript = attempt['transcript']?.toString().trim() ?? '';
    final quoteTimes = onHear == null ? const <String, double>{} : sQuoteTimes(attempt);

    // One running stagger for the whole report rather than hand-numbered
    // delays, so inserting a section never re-times the ones below it.
    var step = 0;
    Duration nextDelay() => Duration(milliseconds: 60 * step++);

    final children = <Widget>[
      if (header != null) ...[header!, const SizedBox(height: 14)],
      WFadeSlideIn(child: SpeakingBandHero(attempt: attempt)),
    ];

    void section(String title, Widget body, {String? subtitle}) {
      children
        ..add(const SizedBox(height: 26))
        ..add(WFadeSlideIn(delay: nextDelay(), child: wSectionTitle(context, title, subtitle: subtitle)))
        ..add(const SizedBox(height: 12))
        ..add(WFadeSlideIn(delay: nextDelay(), child: body));
    }

    if (nextSteps.isNotEmpty) {
      section('What to Practise Next', WNextSteps(steps: nextSteps));
    }

    if (stats != null) {
      section(
        'What We Measured',
        SpeakingMeasuredStrip(stats: stats),
        subtitle: stats['timings_available'] == true
            ? 'Taken from your recording, not from an opinion — you can hear every one of these in your own audio.'
            : 'Word timings were unavailable for this recording, so pauses and speech rate could not be measured.',
      );
    }

    // The four criteria, always all four: pronunciation states why it has no
    // number rather than being dropped from a row a student will count.
    children
      ..add(const SizedBox(height: 26))
      ..add(WFadeSlideIn(delay: nextDelay(), child: wSectionTitle(context, 'Criterion by Criterion')))
      ..add(const SizedBox(height: 12));
    for (final key in sCriterionKeys) {
      final detail = (criteria?[key] as Map?)?.cast<String, dynamic>();
      final band = detail != null ? wToDoubleOrNull(detail['band']) : wToDoubleOrNull(attempt[key]);
      children
        ..add(WFadeSlideIn(
          delay: nextDelay(),
          child: SpeakingCriterionCard(
            criterionKey: key,
            band: band,
            detail: detail,
            notScoredNote: analysis['pronunciation_note']?.toString(),
          ),
        ))
        ..add(const SizedBox(height: 12));
    }
    children.removeLast();

    if (errors.isNotEmpty) {
      section(
        'Corrections',
        Column(
          children: [
            for (var i = 0; i < errors.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Builder(builder: (context) {
                final at = quoteTimes[errors[i]['quote']?.toString() ?? ''];
                return SpeakingCorrectionCard(
                  error: errors[i],
                  index: i,
                  onHear: at == null || onHear == null ? null : () => onHear!(at),
                );
              }),
            ],
          ],
        ),
        subtitle: onHear == null
            ? 'Every quote is your own words, taken from the transcript below.'
            : 'Every quote is your own words. Tap “Hear it” to play the moment you said it.',
      );
    }

    if (habits.isNotEmpty) {
      section(
        'Habits to Break',
        SpeakingHabits(habits: habits),
        subtitle: 'The moves an examiner notices immediately — and the easiest marks to win back.',
      );
    }

    if (grammarTopics.isNotEmpty) {
      section(
        'Grammar to Revise',
        WGrammarTopics(topics: grammarTopics),
        subtitle: 'The rules behind the mistakes in this answer. Revise the top one first.',
      );
    }

    if (vocabulary.isNotEmpty) {
      section('Stronger Word Choices', WVocabularyUpgrades(upgrades: vocabulary));
    }

    if (transcript.isNotEmpty) {
      section(
        'What We Heard',
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: wCardDecoration(context),
          child: Text(
            transcript,
            style: TextStyle(
                fontFamily: 'SF Pro', fontSize: 14, height: 1.6, color: context.wr.muted),
          ),
        ),
        subtitle: 'The transcription your answer was marked from.',
      );
    }

    if (footer != null) {
      children
        ..add(const SizedBox(height: 30))
        ..add(WFadeSlideIn(delay: nextDelay(), child: footer!));
    }

    return ListView(padding: padding, children: children);
  }
}
