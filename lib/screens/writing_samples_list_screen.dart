import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/api_service.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import '../widgets/sample_list_widgets.dart';
import '../widgets/task_segments.dart';
import '../widgets/writing_report.dart';
import 'plus_subscription_screen.dart';
import 'tutor_profile_screen.dart';
import 'writing_prompts_list_screen.dart';
import 'writing_sample_screen.dart';
import '../theme/app_colors.dart';

/// How many of a tutor's topics per task a non-Plus user can open for free; the
/// rest stay visible but locked and route to the Plus subscription screen.
const int _freeSamplesPerTask = 3;

/// Level 1: the tutors who have published Writing samples.
///
/// Deliberately the same list of rows as the Speaking library rather than the
/// photo grid it used to be — the grid was visually indistinguishable from the
/// Tutors directory, so students opened it expecting to book someone, and it
/// made the two sample libraries look like unrelated features. Rows plus an
/// explicit "read" header and per-tutor topic counts make it read as a library
/// index.
///
/// Tapping a tutor opens their topics (see [WritingSampleTutorTopicsScreen]).
class WritingSamplesListScreen extends StatefulWidget {
  const WritingSamplesListScreen({super.key, this.tutors});

  /// Pre-resolved tutor groups, so the index can be rendered without the
  /// network. Production always leaves this null and fetches. Same hatch as
  /// the topic list's `samples`.
  @visibleForTesting
  final Future<List<Map<String, dynamic>>>? tutors;

  @override
  State<WritingSamplesListScreen> createState() => _WritingSamplesListScreenState();
}

class _WritingSamplesListScreenState extends State<WritingSamplesListScreen> {
  late final Future<List<Map<String, dynamic>>> _future;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = widget.tutors ?? MockTestService.fetchWritingSampleTutors();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: mtAppBar(context, title: 'Writing Samples'),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.accentYellow));
          }
          if (snapshot.hasError) {
            return SampleErrorState(error: snapshot.error);
          }
          final tutors = snapshot.data ?? const [];
          if (tutors.isEmpty) {
            return const SampleEmptyState(message: 'No writing samples yet');
          }

          final query = _query.trim().toLowerCase();
          final visible = query.isEmpty
              ? tutors
              : tutors
                  .where((t) => (t['tutor_name']?.toString() ?? '')
                      .toLowerCase()
                      .contains(query))
                  .toList();
          final totalTopics = tutors.fold<int>(
            0,
            (sum, t) => sum + ((t['sample_count'] as num?)?.toInt() ?? 0),
          );

          return Column(
            children: [
              SampleIntroHeader(
                icon: Symbols.menu_book_rounded,
                title: 'Read real high-band essays',
                subtitle:
                    '$totalTopics model answers from ${tutors.length} tutors, with the tutor\'s note on every line',
              ),
              // The way out of reading and into writing, offered where students
              // already are when they go looking for a question — but it leads
              // to the prompt bank rather than to one tutor's topics: the same
              // questions, none of them behind a face.
              SampleCtaRow(
                icon: Symbols.edit_note_rounded,
                title: 'Write an essay yourself',
                subtitle:
                    'Pick any Task 1 or Task 2 question and AI marks it against the band descriptors',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WritingPromptsListScreen()),
                ),
              ),
              SampleSearchField(
                controller: _searchController,
                hint: 'Search a tutor',
                query: _query,
                onChanged: (value) => setState(() => _query = value),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const SampleEmptyState(message: 'No tutors match that search.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _TutorRow(tutor: visible[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One tutor in the level-1 list: big photo, name, how many topics they have
/// published, and their own IELTS Writing credential.
class _TutorRow extends StatelessWidget {
  const _TutorRow({required this.tutor});
  final Map<String, dynamic> tutor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = tutor['tutor_name']?.toString() ?? '';
    final imageUrl = tutor['tutor_image_url'] as String?;
    final score = (tutor['tutor_writing_score'] as num?)?.toString();
    final count = (tutor['sample_count'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WritingSampleTutorTopicsScreen(
            tutorId: (tutor['tutor_id'] as num?)?.toInt(),
            tutorName: name,
            tutorImageUrl: imageUrl,
            tutorWritingScore: score,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: mtSoftCard(context, radius: 16),
        child: Row(
          children: [
            SampleArtwork(imageUrl: imageUrl, size: 82, fallbackIcon: Symbols.edit_note_rounded),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(Symbols.article_rounded, size: 14, color: colors.textTertiary),
                      const SizedBox(width: 5),
                      Text(
                        '$count topic${count == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (score != null) ...[
                    const SizedBox(height: 8),
                    SampleChip(
                      label: 'IELTS WRITING $score',
                      color: colors.textPrimary,
                      background: colors.accentYellow.withValues(alpha: 0.25),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Symbols.chevron_right_rounded, size: 22, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ─── Level 2: one tutor's topics ────────────────────────────────────────────

/// The topics a single tutor has published. The tutor is already chosen, so
/// their photo sits once in the header and each row leads with the chart (or
/// the band, where there is no chart) instead of repeating the same face down
/// the page.
///
/// Non-Plus users can open only the first [_freeSamplesPerTask] samples of each
/// task; the rest stay visible but locked, and tapping one opens the Plus
/// subscription screen.
class WritingSampleTutorTopicsScreen extends StatefulWidget {
  const WritingSampleTutorTopicsScreen({
    super.key,
    required this.tutorId,
    required this.tutorName,
    required this.tutorImageUrl,
    this.tutorWritingScore,
    this.samples,
  });

  /// Pre-resolved samples, so the task tabs can be driven without the network.
  /// Production always leaves this null and fetches. Same hatch as the prompt
  /// list's `prompts`.
  @visibleForTesting
  final Future<List<Map<String, dynamic>>>? samples;

  final int? tutorId;
  final String tutorName;
  final String? tutorImageUrl;
  final String? tutorWritingScore;

  @override
  State<WritingSampleTutorTopicsScreen> createState() =>
      _WritingSampleTutorTopicsScreenState();
}

class _WritingSampleTutorTopicsScreenState extends State<WritingSampleTutorTopicsScreen>
    with SingleTickerProviderStateMixin {
  late final Future<List<Map<String, dynamic>>> _future;
  late final TabController _tabController;
  int _tabIndex = 0;
  bool _isLocked = false;

  /// The tutor's catalogue entry, when they have one. It is what decides
  /// whether this author can actually be booked: an admin-authored sample has
  /// no account behind it at all, and an id that no longer resolves is a tutor
  /// who has stopped teaching. Null in both cases, and the CTA stays off.
  Map<String, dynamic>? _bookable;

  @override
  void initState() {
    super.initState();
    _future = widget.samples ??
        MockTestService.fetchWritingSamples(
          tutorId: widget.tutorId,
          tutorName: widget.tutorId == null ? widget.tutorName : null,
        );
    _tabController = TabController(length: 2, vsync: this)..addListener(_onTabChanged);
    _checkPlusStatus();
    _loadBookable();
  }

  /// The id to offer a lesson with, or null when there is nothing to offer:
  /// no tutor account, an outage, or a tutor who is not taking students.
  int? get _bookableTutorId =>
      _bookable?['is_enrollable'] == true ? widget.tutorId : null;

  Future<void> _loadBookable() async {
    final id = widget.tutorId;
    if (id == null) return;
    try {
      final tutor = await ApiService.get('/tutors/$id/');
      if (!mounted) return;
      setState(() => _bookable = tutor);
    } catch (_) {
      // The samples are the screen; a catalogue outage costs the CTA, not the
      // list.
    }
  }

  /// The segmented control paints its own selection, so it has to follow a
  /// swipe as well as a tap. The listener fires on every animation frame —
  /// only the index actually changing is worth a rebuild.
  void _onTabChanged() {
    if (!mounted || _tabController.index == _tabIndex) return;
    setState(() => _tabIndex = _tabController.index);
  }

  Future<void> _checkPlusStatus() async {
    final locked = await mtCheckContentLocked();
    if (!mounted) return;
    setState(() => _isLocked = locked);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: mtAppBar(context, title: widget.tutorName),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.accentYellow));
          }
          if (snapshot.hasError) {
            return SampleErrorState(error: snapshot.error);
          }
          final samples = snapshot.data ?? const <Map<String, dynamic>>[];
          if (samples.isEmpty) {
            return const SampleEmptyState(message: 'No writing samples yet');
          }
          final task1 = samples.where((s) => s['task_number'] == 1).toList();
          final task2 = samples.where((s) => s['task_number'] == 2).toList();

          return Column(
            children: [
              _buildTutorHeader(samples.length),
              // A tutor's Task 1 topics can run to a screen or two on their own,
              // and stacking Task 2 underneath them meant a student who did not
              // scroll never saw it. The same switcher as the prompt list.
              TaskSegments(
                selected: _tabIndex,
                onSelect: _tabController.animateTo,
                labels: [
                  TaskSegmentLabel('Task 1', 'Charts & data', task1.length),
                  TaskSegmentLabel('Task 2', 'Essays', task2.length),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _TaskList(
                      icon: Symbols.bar_chart_rounded,
                      samples: task1,
                      isLocked: _isLocked,
                      emptyLabel: 'No Task 1 topics yet',
                    ),
                    _TaskList(
                      icon: Symbols.edit_note_rounded,
                      samples: task2,
                      isLocked: _isLocked,
                      emptyLabel: 'No Task 2 topics yet',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTutorHeader(int count) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        children: [
          SampleArtwork(
            imageUrl: widget.tutorImageUrl,
            size: 88,
            fallbackIcon: Symbols.edit_note_rounded,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.tutorName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: colors.textPrimary,
                  ),
                ),
                if (widget.tutorWritingScore != null) ...[
                  const SizedBox(height: 7),
                  SampleChip(
                    label: 'IELTS WRITING ${widget.tutorWritingScore}',
                    color: colors.textPrimary,
                    background: colors.accentYellow.withValues(alpha: 0.25),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '$count model answer${count == 1 ? '' : 's'} · tap a highlight for the note',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 12.5,
                    height: 1.3,
                    color: colors.textSecondary,
                  ),
                ),
                // A student who has read three of someone's essays has already
                // decided whether they like how they teach. Offering the lesson
                // here saves them going back out to the tutors directory to
                // find the same name again.
                if (_bookableTutorId != null) ...[
                  const SizedBox(height: 10),
                  _BookTutorButton(tutorId: _bookableTutorId!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Takes the student from a tutor's published essays to their booking page.
class _BookTutorButton extends StatelessWidget {
  const _BookTutorButton({required this.tutorId});
  final int tutorId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TutorProfileScreen(tutorId: tutorId)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: colors.brand,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.event_available_rounded, size: 15, color: colors.onBrand),
            const SizedBox(width: 6),
            Text(
              'Book a lesson',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.onBrand,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One task's topics, as its own scrolling list behind the task tabs. The tab
/// carries the label and the count, so the list is rows and nothing else.
class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.icon,
    required this.samples,
    required this.isLocked,
    required this.emptyLabel,
  });

  final IconData icon;
  final List<Map<String, dynamic>> samples;
  final bool isLocked;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) return SampleEmptyState(message: emptyLabel);
    // The backend is the source of truth for locking ('locked' items arrive
    // with their essay/annotations stripped); the index check is a fallback for
    // backends that predate server-side gating. [samples] is always one tutor's
    // one task, so a plain index is the per-tutor, per-task count.
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: samples.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _TopicRow(
        sample: samples[i],
        emptyIcon: icon,
        locked: samples[i]['locked'] == true || (isLocked && i >= _freeSamplesPerTask),
      ),
    );
  }
}

/// One published topic. The chart is the artwork where the task has one — a
/// Task 1 question is *about* a specific graph, and a thumbnail of it says
/// which topic this is faster than the opening words can, since every one of
/// them starts "The chart below shows…". Tasks without a chart (all of Task 2,
/// and any Task 1 whose chart has not been uploaded) lead with the band the
/// essay earned instead, which is the other reason to pick one answer over
/// another.
class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.sample, required this.emptyIcon, required this.locked});

  final Map<String, dynamic> sample;

  /// Stands in on a locked row, whose band and chart are withheld along with
  /// the rest of its content.
  final IconData emptyIcon;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = sample['title']?.toString().trim() ?? '';
    final band = sample['band_score']?.toString();
    final highlights = ((sample['annotations'] as List?) ?? const []).length;
    // Withheld along with the rest of a locked sample's content, so a locked
    // row falls back to the plain tile on its own.
    final imageUrl = sample['image_url']?.toString();
    final hasChart = imageUrl != null && imageUrl.isNotEmpty;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              locked ? const PlusSubscriptionScreen() : WritingSampleScreen(sample: sample),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: mtSoftCard(context, radius: 16),
        child: Opacity(
          opacity: locked ? 0.6 : 1,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasChart)
                _ChartTile(imageUrl: imageUrl, emptyIcon: emptyIcon)
              else
                SampleBandTile(score: locked ? null : band, emptyIcon: emptyIcon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isNotEmpty ? title : 'Writing sample',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        // No task chip: the tab above the list already says
                        // which task these are, and every row would carry the
                        // same one.
                        //
                        // The band lives in the leading tile unless the chart
                        // took it, in which case it needs a chip of its own —
                        // it is half the reason to open one answer over another.
                        if (hasChart && !locked && band != null)
                          SampleChip(
                            label: 'BAND $band',
                            color: wScoreColor(context, wToDouble(band)),
                            background:
                                wScoreColor(context, wToDouble(band)).withValues(alpha: 0.14),
                          ),
                        if (!locked && highlights > 0)
                          SampleChip(
                            label: '$highlights NOTE${highlights == 1 ? '' : 'S'}',
                            icon: Symbols.format_quote_rounded,
                            color: colors.textSecondary,
                            background: colors.surface,
                          ),
                        if (locked)
                          SampleChip(
                            label: 'LINKA PLUS',
                            icon: Symbols.lock_rounded,
                            color: colors.textPrimary,
                            background: colors.accentYellow.withValues(alpha: 0.25),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: locked ? colors.surface : colors.brand,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  locked ? Symbols.lock_rounded : Symbols.chevron_right_rounded,
                  size: locked ? 17 : 22,
                  color: locked ? colors.textTertiary : colors.onBrand,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The task's chart at tile size.
///
/// Charts are flat artwork drawn on white and keep that plate in both themes —
/// recolouring one would wreck the axis labels the question is about. Cropped
/// to fill rather than fitted: this is an identifier, not a readable chart, and
/// the readable one is a tap away inside the sample.
class _ChartTile extends StatelessWidget {
  const _ChartTile({required this.imageUrl, required this.emptyIcon});

  final String imageUrl;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 62,
        height: 62,
        color: Colors.white,
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => SampleBandTile(score: null, emptyIcon: emptyIcon),
        ),
      ),
    );
  }
}
