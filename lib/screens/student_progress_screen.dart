import 'package:flutter/material.dart';

import '../models/mock_test.dart';
import '../models/student_progress.dart';
import '../services/student_progress_service.dart';
import '../widgets/band_chart.dart';
import '../widgets/mock_test_styles.dart';
import '../widgets/writing_report.dart';
import 'mock_exams_screen.dart';
import 'mock_test_list_screen.dart';
import 'mock_test_result_screen.dart';
import 'speaking_attempts_screen.dart';
import 'speaking_samples_list_screen.dart';
import 'tutors_screen.dart';
import 'writing_progress_screen.dart';
import 'writing_prompts_list_screen.dart';
import 'writing_result_screen.dart';

/// Where the student stands, in one place.
///
/// Every number here already existed somewhere in the app — the band on each
/// mock-test sitting, the writing insights, the minutes on each finished
/// lesson — but each lived two or three taps deep inside its own flow, so a
/// student with eight essays and five papers had no screen that put them side
/// by side. The website's dashboard does; this is the same view on the phone.
///
/// The top strip mirrors the website's four tiles. Below it, one card per
/// skill: the latest / average / best numbers, the band over time, and the
/// most recent sittings, each opening the report it came from.
class StudentProgressScreen extends StatefulWidget {
  const StudentProgressScreen({super.key});

  @override
  State<StudentProgressScreen> createState() => _StudentProgressScreenState();
}

class _StudentProgressScreenState extends State<StudentProgressScreen> {
  late Future<StudentProgress> _future = StudentProgressService.fetch();

  void _reload() {
    setState(() => _future = StudentProgressService.fetch());
  }

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return Scaffold(
      backgroundColor: wr.page,
      appBar: mtAppBar(context, title: 'My Progress'),
      body: FutureBuilder<StudentProgress>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: wr.accent));
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _Message(
              icon: Icons.cloud_off_rounded,
              title: 'Progress unavailable',
              body: 'Your progress could not be loaded right now. Try again in a moment.',
              actionLabel: 'Try again',
              onAction: _reload,
            );
          }
          final progress = snapshot.data!;
          if (!progress.hasAny) {
            return _Message(
              icon: Icons.insights_rounded,
              title: 'Nothing to show yet',
              body: 'Sit a mock test, write an essay or book a lesson, and your bands will start to appear here.',
              actionLabel: 'Open Mock Exams',
              onAction: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MockExamsScreen()),
              ),
            );
          }
          return RefreshIndicator(
            color: wr.accent,
            onRefresh: () {
              _reload();
              return _future;
            },
            child: StudentProgressView(progress: progress),
          );
        },
      ),
    );
  }
}

/// The progress payload, rendered. Public so it can be built from a fixture
/// without standing up the four fetches.
class StudentProgressView extends StatelessWidget {
  const StudentProgressView({super.key, required this.progress});
  final StudentProgress progress;

  @override
  Widget build(BuildContext context) {
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

    section('Your Progress', ProgressTiles(progress: progress));

    section(
      'Writing',
      _SkillCard(
        skill: progress.writing,
        change: progress.writingChange,
        unit: const _Unit('essay', 'essays'),
        emptyBody: 'Write an essay to get a band.',
        emptyAction: 'Write an essay',
        onEmptyAction: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WritingPromptsListScreen()),
        ),
        detailLabel: 'Full writing insights',
        onDetail: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WritingProgressScreen()),
        ),
        onOpen: (entry) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WritingResultScreen(attempt: (entry.source as Map).cast<String, dynamic>()),
          ),
        ),
      ),
    );

    section(
      'Listening',
      _SkillCard(
        skill: progress.listening,
        change: progress.listening.change,
        unit: const _Unit('test', 'tests'),
        emptyBody: 'Sit a listening test to get a band.',
        emptyAction: 'Choose a test',
        onEmptyAction: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MockTestListScreen(testType: 'listening')),
        ),
        onOpen: (entry) => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MockTestResultScreen(attempt: entry.source as MockTestAttempt)),
        ),
      ),
    );

    section(
      'Reading',
      _SkillCard(
        skill: progress.reading,
        change: progress.reading.change,
        unit: const _Unit('test', 'tests'),
        emptyBody: 'Sit a reading test to get a band.',
        emptyAction: 'Choose a test',
        onEmptyAction: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MockTestListScreen(testType: 'reading')),
        ),
        onOpen: (entry) => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MockTestResultScreen(attempt: entry.source as MockTestAttempt)),
        ),
      ),
    );

    section(
      'Speaking',
      _SkillCard(
        skill: progress.speaking,
        change: progress.speaking.change,
        unit: const _Unit('answer', 'answers'),
        emptyBody: 'Record a speaking answer to get a band.',
        emptyAction: 'Answer a question',
        onEmptyAction: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SpeakingSamplesListScreen()),
        ),
        detailLabel: 'All speaking answers',
        onDetail: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SpeakingAttemptsScreen()),
        ),
        onOpen: (entry) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SpeakingAttemptScreen(
              attemptId: entry.id,
              preview: (entry.source as Map).cast<String, dynamic>(),
            ),
          ),
        ),
      ),
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: children,
    );
  }
}

// ---------------------------------------------------------------------------
// The four tiles — the website's dashboard strip
// ---------------------------------------------------------------------------

/// Writing band, listening band, reading band, hours studied. Each tile links
/// into the detail behind it, and a tile with no history says so instead of
/// printing a zero: "Band 0.0" is a mark, and it is not the one they got.
class ProgressTiles extends StatelessWidget {
  const ProgressTiles({super.key, required this.progress, this.onOpen});

  final StudentProgress progress;

  /// Where a tap goes. Defaults to the skill's own screen; the home strip
  /// overrides it so every tile opens the progress screen instead.
  final void Function(BuildContext context, ProgressTileKind kind)? onOpen;

  void _open(BuildContext context, ProgressTileKind kind) {
    if (onOpen != null) return onOpen!(context, kind);
    final Widget target = switch (kind) {
      ProgressTileKind.writing => const WritingProgressScreen(),
      ProgressTileKind.listening => const MockTestListScreen(testType: 'listening'),
      ProgressTileKind.reading => const MockTestListScreen(testType: 'reading'),
      ProgressTileKind.hours => const TutorsScreen(showBackButton: true),
    };
    Navigator.push(context, MaterialPageRoute(builder: (_) => target));
  }

  @override
  Widget build(BuildContext context) {
    final writing = progress.writing;
    final listening = progress.listening;
    final reading = progress.reading;
    final lessons = progress.lessons;

    final tiles = <Widget>[
      _Tile(
        icon: Icons.edit_note_rounded,
        label: 'Writing band',
        value: writing.hasBand ? wFormatBand(writing.latest) : null,
        fill: writing.latest,
        change: writing.hasBand ? progress.writingChange : null,
        caption: writing.attempts > 0 ? wPlural(writing.attempts, 'essay marked', 'essays marked') : null,
        empty: 'Write an essay to get a band',
        onTap: () => _open(context, ProgressTileKind.writing),
      ),
      _Tile(
        icon: Icons.headphones_rounded,
        label: 'Listening band',
        value: listening.hasBand ? wFormatBand(listening.latest) : null,
        fill: listening.latest,
        caption: listening.attempts > 0 ? wPlural(listening.attempts, 'test taken', 'tests taken') : null,
        empty: 'Sit a listening test to get a band',
        onTap: () => _open(context, ProgressTileKind.listening),
      ),
      _Tile(
        icon: Icons.menu_book_rounded,
        label: 'Reading band',
        value: reading.hasBand ? wFormatBand(reading.latest) : null,
        fill: reading.latest,
        caption: reading.attempts > 0 ? wPlural(reading.attempts, 'test taken', 'tests taken') : null,
        empty: 'Sit a reading test to get a band',
        onTap: () => _open(context, ProgressTileKind.reading),
      ),
      _Tile(
        icon: Icons.schedule_rounded,
        label: 'Hours studied',
        value: lessons.count > 0 ? lessons.hoursLabel : null,
        caption: lessons.count > 0 ? 'from ${wPlural(lessons.count, 'lesson', 'lessons')}' : null,
        empty: 'Book your first lesson',
        onTap: () => _open(context, ProgressTileKind.hours),
      ),
    ];

    // Two per row, each pair stretched to the taller of the two so an empty
    // tile's two-line hint does not leave its neighbour short.
    Widget pair(Widget a, Widget b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)],
          ),
        );

    return Column(
      children: [
        pair(tiles[0], tiles[1]),
        const SizedBox(height: 10),
        pair(tiles[2], tiles[3]),
      ],
    );
  }
}

enum ProgressTileKind { writing, listening, reading, hours }

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
    required this.empty,
    required this.onTap,
    this.fill,
    this.change,
    this.caption,
  });

  final IconData icon;
  final String label;

  /// Null when there is no history — the tile then shows [empty] in place of
  /// the caption and a dash in place of the number.
  final String? value;
  final String empty;
  final VoidCallback onTap;

  /// A band, for the meter under the number. Null for the hours tile, which
  /// has no ceiling to fill towards.
  final double? fill;
  final double? change;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final hasValue = value != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: wCardDecoration(context, radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: wr.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: wr.muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value ?? '—',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 26,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: hasValue ? wr.text : wr.faint,
                  ),
                ),
                if (hasValue && change != null) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _ChangeBadge(change: change!),
                  ),
                ],
              ],
            ),
            if (fill != null) ...[
              const SizedBox(height: 10),
              WBandBar(band: fill!, height: 5, color: hasValue ? wr.accent : wr.line),
            ],
            const SizedBox(height: 8),
            Text(
              hasValue ? (caption ?? '') : empty,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, height: 1.3, color: wr.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.change});
  final double change;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final up = change >= 0;
    final color = up ? wr.good : wr.bad;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(
        wFormatDelta(change),
        style: TextStyle(fontFamily: 'SF Pro', fontSize: 11, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One skill: stats, chart, recent sittings
// ---------------------------------------------------------------------------

class _Unit {
  const _Unit(this.one, this.many);
  final String one;
  final String many;
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.skill,
    required this.change,
    required this.unit,
    required this.emptyBody,
    required this.emptyAction,
    required this.onEmptyAction,
    required this.onOpen,
    this.detailLabel,
    this.onDetail,
  });

  final SkillProgress skill;
  final double? change;
  final _Unit unit;
  final String emptyBody;
  final String emptyAction;
  final VoidCallback onEmptyAction;
  final void Function(ProgressEntry entry) onOpen;
  final String? detailLabel;
  final VoidCallback? onDetail;

  /// Three is enough to see a direction without turning the card into the
  /// history screen it links to.
  static const _recentShown = 3;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;

    if (!skill.hasBand) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: wCardDecoration(context),
        child: Row(
          children: [
            Expanded(
              child: Text(
                emptyBody,
                style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.4, color: wr.muted),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onEmptyAction,
              style: TextButton.styleFrom(
                foregroundColor: wr.accent,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                emptyAction,
                style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    final tiles = <List<String>>[
      [wFormatBand(skill.latest), 'Latest band'],
      [wFormatBand(skill.average), 'Average'],
      [wFormatBand(skill.best), 'Best'],
      ['${skill.attempts}', '${skill.attempts == 1 ? unit.one : unit.many} marked'],
    ];
    final recent = skill.recent.take(_recentShown).toList();

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
                            fontFamily: 'SF Pro',
                            fontSize: 10.5,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: wr.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (skill.history.length >= 2) ...[
            const SizedBox(height: 20),
            BandChart(bands: skill.bands),
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
                        ? 'Up ${wFormatDelta(change!)} bands on your recent ${unit.many}.'
                        : 'Down ${wFormatDelta(change!)} bands on your recent ${unit.many}.',
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
          const SizedBox(height: 16),
          Container(height: 1, color: wr.line),
          const SizedBox(height: 6),
          for (final entry in recent) _EntryRow(entry: entry, onTap: () => onOpen(entry)),
          if (onDetail != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: onDetail,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    detailLabel ?? 'See all',
                    style: TextStyle(
                        fontFamily: 'SF Pro', fontSize: 13, fontWeight: FontWeight.w700, color: wr.accent),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 18, color: wr.accent),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.onTap});
  final ProgressEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: wr.soft, borderRadius: BorderRadius.circular(12)),
              child: Text(
                wFormatBand(entry.band),
                style: TextStyle(fontFamily: 'SF Pro', fontSize: 14, fontWeight: FontWeight.w800, color: wr.text),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title.isEmpty ? 'Untitled' : entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'SF Pro', fontSize: 13.5, fontWeight: FontWeight.w600, color: wr.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      _formatDate(entry.submittedAt),
                      if (entry.subtitle.isNotEmpty) entry.subtitle,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, color: wr.muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: wr.faint),
          ],
        ),
      ),
    );
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _formatDate(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final year = local.year == now.year ? '' : ' ${local.year}';
    return '${local.day} ${_months[local.month - 1]}$year';
  }
}

// ---------------------------------------------------------------------------
// Empty / error
// ---------------------------------------------------------------------------

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
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
              child: Icon(icon, size: 30, color: wr.accent),
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
