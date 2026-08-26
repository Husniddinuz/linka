import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// The shared visual language and copy for the AI Writing report.
///
/// The web dashboard renders the grader's full diagnostic — corrections placed
/// back inside the essay, the habits behind them, the grammar to revise, an
/// ordered plan — while the app used to show only the four bands and one
/// feedback paragraph. Everything the report needs beyond the bands lives
/// here so the result screen, the past-attempt view and the progress screen
/// cannot end up describing the same criterion (or the same habit) two
/// different ways.

// ---------------------------------------------------------------------------
// Colours
// ---------------------------------------------------------------------------

/// The report's colour roles, resolved against the active theme.
///
/// The report is a marked document — one ink for the text, red for what was
/// written, green for the fix — and those roles have to hold in both themes,
/// so they are named by job rather than by hue and resolved from [AppColors]
/// rather than hardcoded. Reach for it as `context.wr`.
class WReport {
  const WReport(this.colors, this.isDark);

  final AppColors colors;
  final bool isDark;

  Color get text => colors.textPrimary;
  Color get muted => colors.textSecondary;
  Color get faint => colors.textTertiary;
  Color get bg => colors.background;
  Color get card => colors.surface;

  /// The page a report sits on.
  ///
  /// [AppColors] paints the light background pure white, which is also the
  /// card colour, so a page of white cards on it has nothing but a shadow to
  /// separate them. The report is card-heavy enough to need the tone; dark
  /// mode already has it, since its surface is lighter than its background.
  Color get page => isDark ? colors.background : const Color(0xFFF6F7FB);
  Color get soft => colors.surfaceAlt;
  Color get line => colors.border;
  Color get accent => colors.accentBlue;
  Color get good => colors.success;
  Color get bad => colors.error;
  Color get highlight => colors.accentYellow;

  /// The middle band tier. [AppColors] has no orange, and reusing the yellow
  /// would collide with the habit badges.
  Color get warn => isDark ? const Color(0xFFFFB74D) : const Color(0xFFF5A623);

  /// Cards lift off a light page with a shadow; on a dark one a shadow is
  /// invisible, so the same separation comes from a hairline instead.
  List<BoxShadow> get shadow => isDark
      ? const []
      : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8))];
}

extension WReportX on BuildContext {
  WReport get wr => WReport(colors, Theme.of(this).brightness == Brightness.dark);
}

/// The fixed brand colours for the shareable poster.
///
/// Deliberately *not* themed: the card is captured to a PNG and posted
/// somewhere else, so it must look the same whatever theme the student happens
/// to be running. Nothing on screen should use these.
class WPalette {
  static const primary = Color(0xFF2E3154);
  static const primaryLight = Color(0xFF454875);
  static const blue = Color(0xFF4F7CFF);
  static const purple = Color(0xFF8B5CF6);
  static const green = Color(0xFF30C48D);
  static const orange = Color(0xFFF5A623);
  static const red = Color(0xFFFF5C5C);
}

BoxDecoration wCardDecoration(BuildContext context, {Color? color, Color? borderColor, double radius = 20}) {
  final wr = context.wr;
  return BoxDecoration(
    color: color ?? wr.card,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: wr.shadow,
    // In dark mode every card carries the hairline; in light only the ones
    // asking to be picked out (an active correction, the weakest criterion).
    border: borderColor != null
        ? Border.all(color: borderColor, width: 1.4)
        : wr.isDark
            ? Border.all(color: wr.line)
            : null,
  );
}

Widget wSectionTitle(BuildContext context, String text, {String? subtitle}) {
  final wr = context.wr;
  return Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(fontFamily: 'SF Pro', fontSize: 19, fontWeight: FontWeight.w800, color: wr.text),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 13, height: 1.45, color: wr.muted),
          ),
        ],
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Value helpers
// ---------------------------------------------------------------------------

/// Bands arrive as DRF Decimal strings ("6.5") from the attempt endpoints and
/// as real numbers from the insights endpoint, so everything goes through here.
double wToDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double? wToDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int wToInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// A band is always written to one decimal — 9.0, 7.5 — so a whole band reads
/// as a band rather than as a count of something.
String wFormatBand(dynamic value) {
  final band = wToDoubleOrNull(value);
  return band == null ? '—' : band.toStringAsFixed(1);
}

/// A signed delta ("+0.5"). The sign is the point: an unsigned "0.5" beside a
/// trend arrow reads as a band, not as a change.
String wFormatDelta(double value) {
  final rounded = value.toStringAsFixed(1);
  return value > 0 ? '+$rounded' : rounded;
}

/// The band's colour. Four steps that have to stay apart on both grounds, so
/// they resolve through [WReport] rather than being fixed hues.
Color wScoreColor(BuildContext context, double score) {
  final wr = context.wr;
  if (score >= 7.5) return wr.good;
  if (score >= 6) return wr.accent;
  if (score >= 5) return wr.warn;
  return wr.bad;
}

List<Map<String, dynamic>> wMapList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

List<String> wStringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
}

/// Splits an admin-authored `_html` field into paragraphs of plain text.
///
/// The Writing prompts currently store plain text with newlines, but the field
/// is `prompt_html` and the admin can put markup in it at any time. Tags are
/// stripped rather than rendered: nothing in the app sanitises this content,
/// and losing bold is the right trade for not rendering whatever ends up in
/// there. Mirrors the web client's `htmlToParagraphs`, so both surfaces show
/// the same task the same way.
List<String> wPromptParagraphs(String? html) {
  if (html == null || html.isEmpty) return const [];
  final text = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li|h[1-6])>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  return text
      .split(RegExp(r'\n\s*\n'))
      .map((block) => block.trim())
      .where((block) => block.isNotEmpty)
      .toList();
}

// ---------------------------------------------------------------------------
// Labels
// ---------------------------------------------------------------------------

/// The four IELTS Writing criteria, in the order every surface renders them.
const wCriterionKeys = <String>[
  'task_achievement',
  'coherence_cohesion',
  'lexical_resource',
  'grammar_accuracy',
];

const wCriterionNames = <String, String>{
  'task_achievement': 'Task achievement',
  'coherence_cohesion': 'Coherence & cohesion',
  'lexical_resource': 'Lexical resource',
  'grammar_accuracy': 'Grammatical range & accuracy',
};

const wCriterionShort = <String, String>{
  'task_achievement': 'Task',
  'coherence_cohesion': 'Cohesion',
  'lexical_resource': 'Lexis',
  'grammar_accuracy': 'Grammar',
};

const wCriterionIcons = <String, IconData>{
  'task_achievement': Icons.flag_rounded,
  'coherence_cohesion': Icons.hub_rounded,
  'lexical_resource': Icons.menu_book_rounded,
  'grammar_accuracy': Icons.rule_rounded,
};

/// The server's closed grammar vocabulary. A key it adds before the app knows
/// about it is prettified rather than dropped — a new topic should render as
/// something, not take the report down.
const wGrammarTopicNames = <String, String>{
  'articles': 'Articles (a / an / the)',
  'subject_verb_agreement': 'Subject–verb agreement',
  'verb_tenses': 'Verb tenses',
  'prepositions': 'Prepositions',
  'plurals_countability': 'Plurals and countable nouns',
  'word_order': 'Word order',
  'relative_clauses': 'Relative clauses',
  'conditionals': 'Conditionals',
  'passive_voice': 'Passive voice',
  'modals': 'Modal verbs',
  'gerunds_infinitives': 'Gerunds and infinitives',
  'comparatives_superlatives': 'Comparatives and superlatives',
  'conjunctions_linking': 'Conjunctions and linking words',
  'pronoun_reference': 'Pronoun reference',
  'punctuation': 'Punctuation',
  'sentence_fragments': 'Sentence fragments',
  'run_on_sentences': 'Run-on sentences',
  'word_form': 'Word form',
  'collocation': 'Word partnerships',
  'spelling': 'Spelling',
};

String wTopicLabel(String key) {
  final known = wGrammarTopicNames[key];
  if (known != null) return known;
  if (key.isEmpty) return 'Grammar';
  final words = key.split('_').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return key;
  return words
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

const wCategoryNames = <String, String>{
  'grammar': 'Grammar',
  'vocabulary': 'Vocabulary',
  'spelling': 'Spelling',
  'punctuation': 'Punctuation',
  'cohesion': 'Cohesion',
  'task_response': 'Task response',
};

const wSeverityNames = <String, String>{
  'high': 'Important',
  'medium': 'Worth fixing',
  'low': 'Minor',
};

/// The counted habits, named as a thing the student does rather than as a
/// metric — "You open sentences the same way", not "repeated_openers".
const wHabitNames = <String, String>{
  'repeated_openers': 'You open sentences the same way',
  'overused_linkers': 'You lean on the same linking words',
  'overused_words': 'You repeat the same words',
  'uniform_sentences': 'Your sentences are all the same length',
  'thin_paragraphing': 'You use too few paragraphs',
};

String wHabitName(String code) => wHabitNames[code] ?? wTopicLabel(code);

/// Each habit code gets its own sentence: the counts mean different things
/// (times used, sentences affected, paragraphs) and one generic phrasing would
/// be wrong for most of them.
String wHabitSentence(String code, String detail, int count) {
  switch (code) {
    case 'repeated_openers':
      return '$count sentences start with “$detail”.';
    case 'overused_linkers':
      return 'You used the linker “$detail” $count times.';
    case 'overused_words':
      return '“$detail” appears $count times in this essay.';
    case 'uniform_sentences':
      return 'Almost every sentence runs about $detail words — the rhythm never changes.';
    case 'thin_paragraphing':
      return 'The whole answer sits in $count ${count == 1 ? 'paragraph' : 'paragraphs'}.';
    default:
      return detail.isEmpty ? wHabitName(code) : '${wHabitName(code)}: $detail';
  }
}

String wPlural(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';

// ---------------------------------------------------------------------------
// Essay highlighting
// ---------------------------------------------------------------------------

class WEssaySegment {
  const WEssaySegment(this.text, this.errorIndex);
  final String text;

  /// Index into the errors list, or null for ordinary prose.
  final int? errorIndex;
}

/// Maps the grader's quoted errors back onto the essay so each one can be
/// marked where the student actually wrote it.
///
/// Safe to attempt because the server verifies every quote against the essay
/// before returning it. Its check normalises whitespace and this one cannot
/// (it needs real offsets into the original string), so a quote whose words
/// span a line break may still fail to place — that one is skipped silently
/// rather than treated as an error, since the correction is still listed in
/// full below the essay.
///
/// Only the first placeable occurrence of each quote is marked: marking every
/// instance of a short quote ("the education") would paint half the essay from
/// a single note.
List<WEssaySegment> wHighlightEssay(String essay, List<Map<String, dynamic>> errors) {
  if (essay.isEmpty) return const [];

  final haystack = essay.toLowerCase();
  final ranges = <List<int>>[]; // [start, end, errorIndex]

  for (var errorIndex = 0; errorIndex < errors.length; errorIndex++) {
    final needle = (errors[errorIndex]['quote']?.toString() ?? '').trim().toLowerCase();
    if (needle.isEmpty) continue;

    // Walk forward past any occurrence already claimed by an earlier error, so
    // two errors quoting overlapping spans both get placed where possible.
    var from = 0;
    while (true) {
      final at = haystack.indexOf(needle, from);
      if (at == -1) break;
      final end = at + needle.length;
      final overlaps = ranges.any((r) => at < r[1] && end > r[0]);
      if (!overlaps) {
        ranges.add([at, end, errorIndex]);
        break;
      }
      from = at + 1;
    }
  }

  if (ranges.isEmpty) return [WEssaySegment(essay, null)];
  ranges.sort((a, b) => a[0].compareTo(b[0]));

  final segments = <WEssaySegment>[];
  var cursor = 0;
  for (final range in ranges) {
    if (range[0] > cursor) {
      segments.add(WEssaySegment(essay.substring(cursor, range[0]), null));
    }
    segments.add(WEssaySegment(essay.substring(range[0], range[1]), range[2]));
    cursor = range[1];
  }
  if (cursor < essay.length) {
    segments.add(WEssaySegment(essay.substring(cursor), null));
  }
  return segments;
}

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------

/// Fades and slides its [child] up shortly after [delay], giving a long report
/// a staggered reveal without a shared AnimationController.
class WFadeSlideIn extends StatefulWidget {
  const WFadeSlideIn({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<WFadeSlideIn> createState() => _WFadeSlideInState();
}

class _WFadeSlideInState extends State<WFadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween(begin: const Offset(0, 0.06), end: Offset.zero)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fade, child: SlideTransition(position: _slide, child: widget.child));
  }
}

class WTag extends StatelessWidget {
  const WTag({super.key, required this.label, this.background, this.foreground, this.icon});
  final String label;
  final Color? background;
  final Color? foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final fg = foreground ?? wr.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background ?? wr.soft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 11, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

/// A thin 0–9 band bar. Used everywhere a criterion is shown so the four read
/// as one scale — a student compares the lengths, not the numbers.
class WBandBar extends StatelessWidget {
  const WBandBar({super.key, required this.band, this.color, this.height = 6, this.animate = true});
  final double band;
  final Color? color;
  final double height;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? wScoreColor(context, band);
    final target = (band / 9).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: fill.withValues(alpha: 0.14),
        child: animate
            ? TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: target),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: t,
                  child: Container(color: fill),
                ),
              )
            : FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: target,
                child: Container(color: fill),
              ),
      ),
    );
  }
}

/// A numbered step or focus item: the badge, a bold line, an optional detail.
class WNumberedCard extends StatelessWidget {
  const WNumberedCard({
    super.key,
    required this.number,
    required this.title,
    this.detail,
    this.badgeColor,
  });

  final String number;
  final String title;
  final String? detail;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: wCardDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: badgeColor ?? wr.accent, shape: BoxShape.circle),
            child: Text(
              number,
              // The dark theme's accent is a pale blue; white on it is barely
              // legible, so the numeral flips to the page colour instead.
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: wr.isDark ? wr.bg : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                      fontFamily: 'SF Pro', fontSize: 14.5, height: 1.4, fontWeight: FontWeight.w700, color: wr.text),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    detail!,
                    style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Report sections
// ---------------------------------------------------------------------------

/// The ordered plan. Sits directly under the band: the score is what the
/// student came for, this is what they can do about it.
class WNextSteps extends StatelessWidget {
  const WNextSteps({super.key, required this.steps});
  final List<Map<String, dynamic>> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          WNumberedCard(
            number: '${i + 1}',
            title: steps[i]['title']?.toString() ?? '',
            detail: steps[i]['detail']?.toString(),
          ),
        ],
      ],
    );
  }
}

/// Repetition, made concrete.
///
/// The counted habits come first and carry their number, because "you opened
/// nine sentences the same way" is checkable and therefore persuasive in a way
/// that "try to vary your sentences" is not. The grader's written observations
/// follow, covering the strategy habits no counter can see.
class WHabitsSection extends StatelessWidget {
  const WHabitsSection({super.key, required this.counted, required this.observed});
  final List<Map<String, dynamic>> counted;
  final List<Map<String, dynamic>> observed;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return Column(
      children: [
        for (final habit in counted) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: wCardDecoration(context),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 34),
                  height: 34,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    // A washed yellow plate reads as mud on a dark card, so
                    // there the tint drops back and the numeral carries the
                    // colour instead.
                    color: wr.highlight.withValues(alpha: wr.isDark ? 0.16 : 0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${wToInt(habit['count'])}',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: wr.isDark ? wr.highlight : wr.text,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wHabitSentence(
                          habit['code']?.toString() ?? '',
                          habit['detail']?.toString() ?? '',
                          wToInt(habit['count']),
                        ),
                        style: TextStyle(
                            fontFamily: 'SF Pro', fontSize: 14, height: 1.45, fontWeight: FontWeight.w600, color: wr.text),
                      ),
                      if (wStringList(habit['evidence']).length > 1) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final item in wStringList(habit['evidence'])) WTag(label: item),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        for (final habit in observed) ...[
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
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: wr.line)),
                    ),
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
      ],
    );
  }
}

/// The grammar syllabus this essay implies — what to go and revise.
class WGrammarTopics extends StatelessWidget {
  const WGrammarTopics({super.key, required this.topics});
  final List<Map<String, dynamic>> topics;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return Column(
      children: [
        for (final topic in topics)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: wCardDecoration(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        wTopicLabel(topic['topic']?.toString() ?? ''),
                        style: TextStyle(
                            fontFamily: 'SF Pro', fontSize: 14.5, fontWeight: FontWeight.w700, color: wr.text),
                      ),
                    ),
                    const SizedBox(width: 8),
                    WTag(
                      label: wPlural(wToInt(topic['error_count']), 'mistake', 'mistakes'),
                      background: wr.bad.withValues(alpha: 0.12),
                      foreground: wr.bad,
                    ),
                  ],
                ),
                if ((topic['why']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    topic['why'].toString(),
                    style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
                  ),
                ],
                if ((topic['practice']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: wr.soft, borderRadius: BorderRadius.circular(12)),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
                        children: [
                          TextSpan(
                            text: 'Practise: ',
                            style: TextStyle(fontWeight: FontWeight.w700, color: wr.text),
                          ),
                          TextSpan(text: topic['practice'].toString()),
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

/// One correction: what was written, what it should say, and the rule behind it.
class WCorrectionCard extends StatelessWidget {
  const WCorrectionCard({
    super.key,
    required this.error,
    required this.index,
    this.highlighted = false,
    this.onTap,
  });

  final Map<String, dynamic> error;
  final int index;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final category = error['category']?.toString() ?? 'grammar';
    final topic = error['grammar_topic']?.toString();
    final severity = error['severity']?.toString();
    final correction = error['correction']?.toString() ?? '';
    final explanation = error['explanation']?.toString() ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: wCardDecoration(context, borderColor: highlighted ? wr.accent : null),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
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
                WTag(label: wCategoryNames[category] ?? wTopicLabel(category)),
                if (topic != null && topic.isNotEmpty) WTag(label: wTopicLabel(topic)),
                if (severity == 'high')
                  WTag(
                    label: wSeverityNames['high']!,
                    background: wr.bad.withValues(alpha: 0.12),
                    foreground: wr.bad,
                  ),
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
                          fontFamily: 'SF Pro', fontSize: 14, height: 1.5, fontWeight: FontWeight.w700, color: wr.good),
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
      ),
    );
  }
}

/// The essay as the student wrote it, with every placeable correction marked
/// where it happened.
///
/// The web report lights a correction on hover; a phone has no hover, so a
/// marked span is tappable and opens its correction in a sheet. Reading the
/// mistake underlined in your own sentence is the whole point — a list of
/// notes beside an essay means holding both in your head at once.
class WAnnotatedEssay extends StatefulWidget {
  const WAnnotatedEssay({
    super.key,
    required this.essayText,
    required this.errors,
    required this.wordCount,
  });

  final String essayText;
  final List<Map<String, dynamic>> errors;
  final int wordCount;

  @override
  State<WAnnotatedEssay> createState() => _WAnnotatedEssayState();
}

class _WAnnotatedEssayState extends State<WAnnotatedEssay> {
  /// One recognizer per marked span, built once from the errors rather than
  /// per frame: a recognizer disposed mid-build can be one the gesture arena
  /// is still holding, and the marks do not change once the report is on
  /// screen anyway.
  late List<WEssaySegment> _segments;
  final _recognizers = <int, TapGestureRecognizer>{};
  int? _active;

  @override
  void initState() {
    super.initState();
    _buildSegments();
  }

  @override
  void didUpdateWidget(WAnnotatedEssay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.essayText != widget.essayText || oldWidget.errors != widget.errors) {
      _disposeRecognizers();
      _buildSegments();
    }
  }

  void _buildSegments() {
    _segments = wHighlightEssay(widget.essayText, widget.errors);
    for (final segment in _segments) {
      final index = segment.errorIndex;
      if (index == null) continue;
      _recognizers[index] = TapGestureRecognizer()..onTap = () => _openCorrection(index);
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _openCorrection(int index) {
    setState(() => _active = index);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: sheetContext.wr.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: sheetContext.wr.faint,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(
                            'Correction ${index + 1} of ${widget.errors.length}',
                            style: TextStyle(
                                fontFamily: 'SF Pro', fontSize: 12, fontWeight: FontWeight.w700, color: sheetContext.wr.muted),
                          ),
                        ),
                        WCorrectionCard(error: widget.errors[index], index: index, highlighted: true),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _active = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final spans = <TextSpan>[];
    for (final segment in _segments) {
      if (segment.errorIndex == null) {
        spans.add(TextSpan(text: segment.text));
        continue;
      }
      final index = segment.errorIndex!;
      spans.add(
        TextSpan(
          text: segment.text,
          recognizer: _recognizers[index],
          style: TextStyle(
            color: _active == index ? wr.bad : wr.text,
            backgroundColor: _active == index ? wr.bad.withValues(alpha: 0.12) : null,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.wavy,
            decorationColor: wr.bad,
            decorationThickness: 1.6,
          ),
        ),
      );
    }

    // Count what is actually underlined, not how many corrections there are:
    // a quote whose words span a line break cannot be placed, and promising a
    // mark the reader then cannot find is worse than a smaller number. The
    // unplaced ones are still listed in full below the essay.
    final markedCount = _segments.where((segment) => segment.errorIndex != null).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: wCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_rounded, size: 16, color: wr.muted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  markedCount > 0
                      ? '${wPlural(markedCount, 'correction is', 'corrections are')} marked below — tap one to read it.'
                      : '${widget.wordCount} words',
                  style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, height: 1.4, color: wr.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SelectionArea(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontFamily: 'SF Pro', fontSize: 14.5, height: 1.65, color: wr.text),
                children: spans,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Word-level swaps that would lift Lexical Resource.
class WVocabularyUpgrades extends StatelessWidget {
  const WVocabularyUpgrades({super.key, required this.upgrades});
  final List<Map<String, dynamic>> upgrades;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return Column(
      children: [
        for (final upgrade in upgrades)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: wCardDecoration(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      upgrade['original']?.toString() ?? '',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: wr.muted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: wr.muted),
                    Text(
                      upgrade['suggestion']?.toString() ?? '',
                      style: TextStyle(
                          fontFamily: 'SF Pro', fontSize: 14, fontWeight: FontWeight.w800, color: wr.good),
                    ),
                  ],
                ),
                if ((upgrade['note']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    upgrade['note'].toString(),
                    style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// The measured shape of the writing — the numbers the habits were counted
/// from, so a student can check the claim rather than take it on trust.
class WStatsStrip extends StatelessWidget {
  const WStatsStrip({super.key, required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final tiles = <List<String>>[
      ['${wToInt(stats['word_count'])}', 'Words'],
      ['${wToInt(stats['sentence_count'])}', 'Sentences'],
      ['${wToInt(stats['paragraph_count'])}', 'Paragraphs'],
      [wToDouble(stats['avg_sentence_length']).toStringAsFixed(1), 'Avg. sentence'],
      ['${wToInt(stats['unique_words'])}', 'Distinct words'],
      ['${(wToDouble(stats['lexical_diversity']) * 100).round()}%', 'Lexical variety'],
    ];

    // Three across, sized off the page width the report is laid out in
    // (16pt gutters, 10pt between tiles) so the six tiles land as two even rows.
    final tileWidth = (MediaQuery.of(context).size.width - 32 - 20) / 3;

    return Wrap(
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
                        fontFamily: 'SF Pro', fontSize: 10.5, height: 1.25, fontWeight: FontWeight.w600, color: wr.muted),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}


/// The task, as the student has to answer it.
///
/// `title` is not a label — it carries the actual question ("The chart below
/// shows…", "Some people believe that…"), while `prompt_html` is only the
/// standing instruction ("Summarise the information…", "Write at least 250
/// words"). Showing the instruction without the question, which is what an
/// app-bar-only title amounted to, leaves the student nothing to write about.
/// So the question leads, in reading size, and the instruction follows in
/// secondary text.
class WTaskCard extends StatelessWidget {
  const WTaskCard({super.key, required this.prompt, this.maxImageHeight = 300});

  final Map<String, dynamic> prompt;

  /// How much room the Task 1 chart preview gets. Shorter in the report, where
  /// the essay is already written — it is context there, not the task.
  final double maxImageHeight;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final taskNumber = wToInt(prompt['task_number']);
    final minWords = (prompt['min_words'] as num?)?.toInt() ?? (taskNumber == 1 ? 150 : 250);
    final imageUrl = prompt['image_url']?.toString();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final question = prompt['title']?.toString().trim() ?? '';
    final instructions = wPromptParagraphs(prompt['prompt_html']?.toString());

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: wCardDecoration(context, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WTag(
                label: 'Task ${taskNumber == 0 ? 1 : taskNumber}',
                background: wr.colors.brand,
                foreground: wr.colors.onBrand,
              ),
              const SizedBox(width: 8),
              WTag(label: 'Minimum $minWords words'),
            ],
          ),
          if (question.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              question,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 15.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: wr.text,
              ),
            ),
          ],
          if (hasImage) ...[
            const SizedBox(height: 12),
            // A chart at card size is a picture of a chart, not a readable
            // one — the axis labels and legend are the question. So this is a
            // preview that opens the real thing.
            GestureDetector(
              onTap: () => WChartViewer.open(context, imageUrl, caption: question),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      // The charts are flat artwork drawn on white. They keep
                      // that plate in both themes: recolouring them would
                      // wreck the axis labels the question is about.
                      color: Colors.white,
                      constraints: BoxConstraints(maxHeight: maxImageHeight),
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2, color: wr.accent),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'Could not load chart image',
                              style: TextStyle(fontFamily: 'SF Pro', color: WPalette.primary, fontSize: 12.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // The hint sits under the chart rather than on it: these charts
            // put their labels and legend right at the edges, and a badge
            // floating over the corner covers the numbers being asked about.
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => WChartViewer.open(context, imageUrl, caption: question),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.zoom_in_rounded, size: 15, color: wr.accent),
                  const SizedBox(width: 5),
                  Text(
                    'Tap the chart to enlarge',
                    style: TextStyle(
                        fontFamily: 'SF Pro', fontSize: 12.5, fontWeight: FontWeight.w700, color: wr.accent),
                  ),
                ],
              ),
            ),
          ],
          for (final block in instructions) ...[
            const SizedBox(height: 10),
            Text(
              block,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
            ),
          ],
        ],
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// Chart viewer
// ---------------------------------------------------------------------------

/// A Task 1 chart, full screen and zoomable.
///
/// The chart *is* the question — axis labels, legend, four or five series of
/// figures — and at the size it can have inside a task card none of that is
/// readable. So the card holds a preview and the real thing opens here: pinch
/// or double-tap to zoom, drag to pan, and rotate the phone, since these
/// charts are almost all wider than they are tall.
class WChartViewer extends StatefulWidget {
  const WChartViewer({super.key, required this.imageUrl, this.caption});

  final String imageUrl;

  /// The question the chart belongs to, kept on screen so a student zooming
  /// into a series still knows what they are being asked to describe.
  final String? caption;

  /// Opens the viewer, allowing rotation while it is up and restoring the
  /// app's portrait lock on the way out.
  static Future<void> open(BuildContext context, String imageUrl, {String? caption}) async {
    // Fired rather than awaited: the push must not wait on a platform channel
    // round-trip, and rotation becoming available a frame late costs nothing.
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => WChartViewer(imageUrl: imageUrl, caption: caption),
      ),
    );
    unawaited(SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]));
  }

  @override
  State<WChartViewer> createState() => _WChartViewerState();
}

class _WChartViewerState extends State<WChartViewer> with SingleTickerProviderStateMixin {
  final _transformation = TransformationController();

  /// Built here rather than as a lazy `late` initialiser: nothing touches it
  /// unless the chart is double-tapped, so closing the viewer without zooming
  /// would otherwise construct it from inside dispose(), where asking for a
  /// TickerMode throws.
  late final AnimationController _animation;
  Animation<Matrix4>? _zoom;

  /// How far a double-tap zooms in. Enough to read an axis label on a phone.
  static const _doubleTapScale = 3.0;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() {
        if (_zoom != null) _transformation.value = _zoom!.value;
      });
  }

  @override
  void dispose() {
    _animation.dispose();
    _transformation.dispose();
    super.dispose();
  }

  void _handleDoubleTap(TapDownDetails details) {
    final current = _transformation.value;
    final Matrix4 target;
    if (current.getMaxScaleOnAxis() > 1.05) {
      target = Matrix4.identity();
    } else {
      // Zoom about the point that was tapped, so the series under the finger
      // is the one that fills the screen.
      final position = details.localPosition;
      target = Matrix4.identity()
        ..translateByDouble(
          -position.dx * (_doubleTapScale - 1),
          -position.dy * (_doubleTapScale - 1),
          0,
          1,
        )
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, _doubleTapScale, 1);
    }
    _zoom = Matrix4Tween(begin: current, end: target)
        .animate(CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic));
    _animation.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTapDown: _handleDoubleTap,
              // The handler lives on the down event, which carries the tap
              // position; this one only completes the gesture.
              onDoubleTap: () {},
              child: InteractiveViewer(
                transformationController: _transformation,
                minScale: 1,
                maxScale: 8,
                // Room to drag a zoomed-in corner away from the edge.
                boundaryMargin: const EdgeInsets.all(80),
                child: Center(
                  child: Image.network(
                    widget.imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Text(
                        'Could not load the chart.',
                        style: TextStyle(fontFamily: 'SF Pro', color: Colors.white70, fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
          ),
          if (widget.caption != null && widget.caption!.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Text(
                    widget.caption!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'SF Pro', fontSize: 12.5, height: 1.4, color: Colors.white70),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
