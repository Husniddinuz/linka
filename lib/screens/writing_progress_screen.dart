import 'package:flutter/material.dart';

import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import '../widgets/writing_report.dart';
import 'writing_result_screen.dart';

/// What the student keeps getting wrong, across every essay they have written.
///
/// The per-essay report can only say "you made an article mistake here". The
/// question a student actually needs answered is "what do I keep doing wrong",
/// and that takes a history to answer — which is what this screen is for. All
/// of it is counted server-side from stored reviews, so opening it costs
/// nothing and it gives the same answer twice.
class WritingProgressScreen extends StatefulWidget {
  const WritingProgressScreen({super.key});

  @override
  State<WritingProgressScreen> createState() => _WritingProgressScreenState();
}

class _WritingProgressScreenState extends State<WritingProgressScreen> {
  late Future<Map<String, dynamic>> _future = MockTestService.fetchWritingInsights();

  void _reload() {
    setState(() => _future = MockTestService.fetchWritingInsights());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.wr.page,
      appBar: mtAppBar(context, title: 'Writing Progress'),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.wr.accent));
          }
          // A failed fetch is not worth an error screen — the practice list is
          // one tap away and nothing here is on the critical path.
          if (snapshot.hasError || snapshot.data == null) {
            return _Message(
              title: 'Progress unavailable',
              body: 'Your progress could not be loaded right now. Try again in a moment.',
              actionLabel: 'Try again',
              onAction: _reload,
            );
          }

          final insights = snapshot.data!;
          if (insights['has_history'] != true) {
            final analysed = wToInt(insights['attempts_analysed']);
            return _Message(
              title: 'Not enough essays yet',
              body: 'You have ${analysed == 0 ? 'no graded essays' : wPlural(analysed, 'graded essay', 'graded essays')} '
                  'so far. Write one more and this screen will show you which mistakes keep coming back.',
              actionLabel: 'Write an essay',
              onAction: () => Navigator.pop(context),
            );
          }

          return WritingInsightsView(insights: insights);
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body, required this.actionLabel, required this.onAction});
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(color: wr.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(Icons.insights_rounded, size: 30, color: wr.accent),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 17, fontWeight: FontWeight.w800, color: wr.text),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 220,
              child: MtPrimaryButton(label: actionLabel, onPressed: onAction),
            ),
          ],
        ),
      ),
    );
  }
}

/// The insights payload, rendered. Public so it can be built from a fixture
/// without standing up the fetch.
class WritingInsightsView extends StatelessWidget {
  const WritingInsightsView({super.key, required this.insights});
  final Map<String, dynamic> insights;

  @override
  Widget build(BuildContext context) {
    final history = wMapList(insights['band_history']);
    final criteria = wMapList(insights['criteria']);
    final focus = wMapList(insights['focus']);
    final habits = wMapList(insights['persistent_habits']);
    // Topics that show up across several essays, not just once — a bad day is
    // not a gap, and only a gap is worth studying.
    final topics = wMapList(insights['recurring_topics']).where((t) => t['is_persistent'] == true).toList();
    final change = wToDoubleOrNull(insights['band_change']);

    var step = 0;
    Duration nextDelay() => Duration(milliseconds: 60 * step++);

    final children = <Widget>[];

    void section(String title, Widget body, {String? subtitle}) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 26));
      children
        ..add(WFadeSlideIn(delay: nextDelay(), child: wSectionTitle(context, title, subtitle: subtitle)))
        ..add(const SizedBox(height: 12))
        ..add(WFadeSlideIn(delay: nextDelay(), child: body));
    }

    section(
      'Band Over Time',
      _TrendCard(insights: insights, history: history, change: change),
    );

    if (focus.isNotEmpty) {
      section(
        'Focus On These',
        Column(
          children: [
            for (var i = 0; i < focus.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              WNumberedCard(
                number: '${i + 1}',
                title: _focusLine(focus[i]),
                detail: focus[i]['practice']?.toString(),
              ),
            ],
          ],
        ),
        subtitle: 'The shortlist. Fix these and your band moves.',
      );
    }

    if (topics.isNotEmpty) {
      section(
        'Mistakes You Keep Repeating',
        Column(children: [for (final topic in topics) _RecurringTopicCard(topic: topic)]),
        subtitle: 'These grammar points have gone wrong across several essays, not just once. '
            'That makes them worth studying rather than proofreading.',
      );
    }

    if (habits.isNotEmpty) {
      section(
        'Habits Across Your Essays',
        Column(children: [for (final habit in habits) _PersistentHabitCard(habit: habit)]),
        subtitle: 'The same moves, essay after essay. Breaking one of these changes how every future essay reads.',
      );
    }

    if (criteria.isNotEmpty) {
      section(
        'Criteria Over All Essays',
        Column(
          children: [
            for (final criterion in criteria) _CriterionAverageCard(criterion: criterion),
          ],
        ),
      );
    }

    if (history.isNotEmpty) {
      section(
        'Your Essays',
        Column(
          children: [
            // Newest first — the opposite of the chart, which has to read left
            // to right through time.
            for (final entry in history.reversed) _EssayRow(entry: entry),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: children,
    );
  }

  /// Each focus kind gets its own sentence: the number means a band for a
  /// criterion and an essay count for the other two.
  String _focusLine(Map<String, dynamic> item) {
    final kind = item['kind']?.toString();
    final key = item['key']?.toString() ?? '';
    final value = wToDouble(item['value']);
    if (kind == 'criterion') {
      final name = wCriterionNames[key] ?? wTopicLabel(key);
      return '$name is your weakest criterion, averaging ${value.toStringAsFixed(1)}.';
    }
    if (kind == 'grammar_topic') {
      return '${wTopicLabel(key)} has cost you marks in ${wPlural(value.round(), 'essay', 'essays')}.';
    }
    return '${wHabitName(key)} — in ${wPlural(value.round(), 'essay', 'essays')}.';
  }
}

// ---------------------------------------------------------------------------
// Trend
// ---------------------------------------------------------------------------

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.insights, required this.history, required this.change});
  final Map<String, dynamic> insights;
  final List<Map<String, dynamic>> history;
  final double? change;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final tiles = <List<String>>[
      [wFormatBand(insights['band_latest']), 'Latest band'],
      [wFormatBand(insights['band_average']), 'Average'],
      [wFormatBand(insights['band_best']), 'Best'],
      ['${wToInt(insights['attempts_graded'])}', 'Essays marked'],
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: wCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        tiles[i][0],
                        style: TextStyle(
                            fontFamily: 'SF Pro', fontSize: 21, fontWeight: FontWeight.w800, color: wr.text),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tiles[i][1],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: 'SF Pro', fontSize: 10.5, height: 1.25, fontWeight: FontWeight.w600, color: wr.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (history.length >= 2) ...[
            const SizedBox(height: 20),
            SizedBox(
              height: 96,
              width: double.infinity,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => CustomPaint(
                  painter: _BandChartPainter(
                    bands: [for (final entry in history) wToDouble(entry['overall_band'])],
                    progress: t,
                    line: wr.accent,
                    grid: wr.line,
                    dot: wr.card,
                  ),
                ),
              ),
            ),
          ],
          if (change != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  change! >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  size: 17,
                  color: change! >= 0 ? wr.good : wr.bad,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    change! >= 0
                        ? 'Up ${wFormatDelta(change!)} bands on your recent essays.'
                        : 'Down ${wFormatDelta(change!)} bands on your recent essays.',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: change! >= 0 ? wr.good : wr.bad,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The band history as a sparkline.
///
/// Plotted against the full 0–9 scale rather than against the student's own
/// min and max: auto-scaling would turn a half-band wobble into a dramatic
/// climb, which is exactly the false encouragement this screen must not give.
class _BandChartPainter extends CustomPainter {
  _BandChartPainter({
    required this.bands,
    required this.progress,
    required this.line,
    required this.grid,
    required this.dot,
  });

  final List<double> bands;
  final double progress;
  final Color line;
  final Color grid;

  /// The ring drawn around each point, so it reads as a marker rather than a
  /// blob wherever the line doubles back. Matches the card behind it.
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.length < 2) return;

    const inset = 6.0;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final band in [9.0, 6.0, 3.0]) {
      final y = size.height - (band / 9) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final step = (size.width - inset * 2) / (bands.length - 1);
    final points = <Offset>[
      for (var i = 0; i < bands.length; i++)
        Offset(
          inset + i * step,
          size.height - (bands[i].clamp(0.0, 9.0) / 9) * (size.height - inset) - inset / 2,
        ),
    ];

    final visible = (points.length * progress).ceil().clamp(2, points.length);
    final shown = points.sublist(0, visible);

    final path = Path()..moveTo(shown.first.dx, shown.first.dy);
    for (final point in shown.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    final area = Path.from(path)
      ..lineTo(shown.last.dx, size.height)
      ..lineTo(shown.first.dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = line.withValues(alpha: 0.14));

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (final point in shown) {
      canvas.drawCircle(point, 3.6, Paint()..color = line);
      canvas.drawCircle(
        point,
        3.6,
        Paint()
          ..color = dot
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BandChartPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.bands != bands || oldDelegate.line != line;
}

// ---------------------------------------------------------------------------
// Recurring mistakes, habits, criteria
// ---------------------------------------------------------------------------

class _RecurringTopicCard extends StatelessWidget {
  const _RecurringTopicCard({required this.topic});
  final Map<String, dynamic> topic;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final share = wToDouble(topic['share_of_attempts']).clamp(0.0, 1.0);
    return Container(
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
                label: 'In ${wToInt(topic['attempt_count'])} of ${wToInt(topic['attempts_analysed'])} essays',
                background: wr.bad.withValues(alpha: 0.12),
                foreground: wr.bad,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // How much of the student's history this topic spans — the "over and
          // over" made visible.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 6,
              color: wr.bad.withValues(alpha: 0.14),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: share,
                child: Container(color: wr.bad),
              ),
            ),
          ),
          if ((topic['why']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
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
    );
  }
}

class _PersistentHabitCard extends StatelessWidget {
  const _PersistentHabitCard({required this.habit});
  final Map<String, dynamic> habit;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final examples = wStringList(habit['examples']);
    return Container(
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
              color: wr.highlight.withValues(alpha: wr.isDark ? 0.16 : 0.22),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${wToInt(habit['attempt_count'])}',
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
                  wHabitName(habit['code']?.toString() ?? ''),
                  style: TextStyle(
                      fontFamily: 'SF Pro', fontSize: 14.5, fontWeight: FontWeight.w700, color: wr.text),
                ),
                const SizedBox(height: 5),
                Text(
                  'Seen in ${wToInt(habit['attempt_count'])} of your last ${wToInt(habit['attempts_analysed'])} essays.',
                  style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
                ),
                if (examples.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final example in examples) WTag(label: example)],
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

class _CriterionAverageCard extends StatelessWidget {
  const _CriterionAverageCard({required this.criterion});
  final Map<String, dynamic> criterion;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final key = criterion['key']?.toString() ?? '';
    final average = wToDouble(criterion['average']);
    final change = wToDoubleOrNull(criterion['change']);
    final weakest = criterion['is_weakest'] == true;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: wCardDecoration(context, borderColor: weakest ? wr.bad.withValues(alpha: 0.55) : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(wCriterionIcons[key] ?? Icons.rule_rounded, size: 17, color: weakest ? wr.bad : wr.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  wCriterionNames[key] ?? wTopicLabel(key),
                  style: TextStyle(
                      fontFamily: 'SF Pro', fontSize: 14, fontWeight: FontWeight.w700, color: wr.text),
                ),
              ),
              Text(
                average.toStringAsFixed(1),
                style: TextStyle(
                    fontFamily: 'SF Pro', fontSize: 19, fontWeight: FontWeight.w800, color: wr.text),
              ),
            ],
          ),
          const SizedBox(height: 12),
          WBandBar(band: average, color: weakest ? wr.bad : wr.accent),
          if (weakest || change != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (weakest)
                  WTag(
                    label: 'Weakest',
                    background: wr.bad.withValues(alpha: 0.12),
                    foreground: wr.bad,
                  ),
                if (weakest && change != null) const SizedBox(width: 8),
                if (change != null)
                  Text(
                    '${wFormatDelta(change)} recently',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: change >= 0 ? wr.good : wr.bad,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One past essay. Opens the identical report the composer shows on submit —
/// a student comparing this month's essay with last month's should be reading
/// the same layout, not two dialects of one screen.
class _EssayRow extends StatelessWidget {
  const _EssayRow({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final taskNumber = wToInt(entry['task_number']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            // Enough of the attempt to draw the band immediately; the result
            // screen fetches the full review itself from the id.
            builder: (_) => WritingResultScreen(attempt: {
              'id': entry['attempt_id'],
              'status': 'graded',
              'overall_band': entry['overall_band'],
              'word_count': entry['word_count'],
              'submitted_at': entry['submitted_at'],
              'prompt': {'title': entry['title'], 'task_number': entry['task_number']},
            }),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: wCardDecoration(context, radius: 18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: wr.soft, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  wFormatBand(entry['overall_band']),
                  style: TextStyle(
                      fontFamily: 'SF Pro', fontSize: 15, fontWeight: FontWeight.w800, color: wr.text),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry['title']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'SF Pro', fontSize: 14.5, fontWeight: FontWeight.w600, color: wr.text),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Task $taskNumber · ${wToInt(entry['word_count'])} words',
                      style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, color: wr.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: wr.faint),
            ],
          ),
        ),
      ),
    );
  }
}
