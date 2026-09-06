import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import '../services/random_test_picker.dart';
import '../theme/app_colors.dart';
import '../widgets/mock_test_styles.dart';
import '../widgets/random_test_card.dart';
import '../widgets/writing_report.dart';
import 'writing_progress_screen.dart';
import 'writing_test_screen.dart';

/// Writing Task 1 & 2 prompts. All prompts are open to everyone — the free
/// window is on AI-graded *submissions* (see WritingTestScreen's quota),
/// not on viewing prompts.
class WritingPromptsListScreen extends StatefulWidget {
  const WritingPromptsListScreen({super.key, this.prompts});

  /// Pre-resolved prompts, so the list can be rendered without the network.
  /// Production always leaves this null and fetches.
  @visibleForTesting
  final Future<List<Map<String, dynamic>>>? prompts;

  @override
  State<WritingPromptsListScreen> createState() => _WritingPromptsListScreenState();
}

class _WritingPromptsListScreenState extends State<WritingPromptsListScreen>
    with SingleTickerProviderStateMixin {
  // Built in initState rather than as a lazy `late` initialiser: the tabs are
  // only read once the prompts have loaded, so leaving the screen while it is
  // still fetching would otherwise construct the controller from inside
  // dispose() — which asks a deactivated element for its TickerMode and throws.
  late final TabController _tabController;
  int _tabIndex = 0;
  late final Future<List<Map<String, dynamic>>> _future;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = widget.prompts ?? MockTestService.fetchWritingPrompts();
    _tabController = TabController(length: 2, vsync: this)..addListener(_onTabChanged);
  }

  /// The segmented control paints its own selection, so it has to follow a
  /// swipe as well as a tap. The listener fires on every animation frame —
  /// only the index actually changing is worth a rebuild.
  void _onTabChanged() {
    if (!mounted || _tabController.index == _tabIndex) return;
    setState(() => _tabIndex = _tabController.index);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Title-only search. On these prompts the title *is* the question, so it is
  /// the only field worth matching — `prompt_html` is the same standing
  /// instruction on every task and would match everything.
  List<Map<String, dynamic>> _visible(List<Map<String, dynamic>> prompts, int taskNumber) {
    final needle = _query.trim().toLowerCase();
    return prompts.where((prompt) {
      if (wToInt(prompt['task_number']) != taskNumber) return false;
      if (needle.isEmpty) return true;
      return (prompt['title']?.toString().toLowerCase() ?? '').contains(needle);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: mtAppBar(context, title: 'Writing'),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: colors.accentYellow));
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'SF Pro', color: colors.textSecondary, fontSize: 14),
                ),
              ),
            );
          }

          final prompts = snapshot.data ?? const <Map<String, dynamic>>[];
          final task1 = _visible(prompts, 1);
          final task2 = _visible(prompts, 2);
          final searching = _query.trim().isNotEmpty;

          return Column(
            children: [
              // The way into the cross-essay view. Worth surfacing here rather
              // than only after a submission: the students who most need to
              // see what they keep repeating are the ones already several
              // essays in, who come straight to this list.
              const _ProgressCta(),
              _SearchField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
              ),
              // Task 1 and Task 2 each get their own list (rather than one long
              // scroll) so Task 2 stays a single tap away no matter how many
              // Task 1 prompts there are — burying it below a long Task 1 list
              // made students think only Task 1 existed.
              _TaskSegments(
                selected: _tabIndex,
                onSelect: _tabController.animateTo,
                labels: [
                  _SegmentLabel('Task 1', 'Charts & data', task1.length),
                  _SegmentLabel('Task 2', 'Essays', task2.length),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _PromptList(prompts: task1, searching: searching),
                    _PromptList(prompts: task2, searching: searching),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SegmentLabel {
  const _SegmentLabel(this.title, this.caption, this.count);
  final String title;
  final String caption;
  final int count;
}

/// The task switcher, as a segmented control rather than an underlined TabBar.
///
/// The old bar sat on a hardcoded white plate, which in dark mode was a white
/// stripe across the top of a dark screen. This one is built from theme
/// tokens, and being a filled pill it also carries what the underline could
/// not: what each paper actually is, and how many tasks are behind it.
class _TaskSegments extends StatelessWidget {
  const _TaskSegments({required this.selected, required this.onSelect, required this.labels});

  final int selected;
  final ValueChanged<int> onSelect;
  final List<_SegmentLabel> labels;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: selected == i ? colors.brand : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              labels[i].title,
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: selected == i ? colors.onBrand : colors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: selected == i
                                    ? colors.onBrand.withValues(alpha: 0.22)
                                    : colors.background,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${labels[i].count}',
                                style: TextStyle(
                                  fontFamily: 'SF Pro',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: selected == i ? colors.onBrand : colors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          labels[i].caption,
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: selected == i
                                ? colors.onBrand.withValues(alpha: 0.75)
                                : colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCta extends StatelessWidget {
  const _ProgressCta();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WritingProgressScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: mtSoftCard(context, radius: 14, border: Border.all(color: colors.border)),
          child: Row(
            children: [
              Icon(Icons.insights_rounded, size: 20, color: colors.accentBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'See what you keep repeating',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Band trend, recurring mistakes and habits',
                      style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontFamily: 'SF Pro', fontSize: 14.5, color: colors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.surfaceAlt,
          hintText: 'Search topics',
          hintStyle: TextStyle(fontFamily: 'SF Pro', fontSize: 14.5, color: colors.textTertiary),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: colors.textTertiary),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: colors.textTertiary),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _PromptList extends StatelessWidget {
  const _PromptList({required this.prompts, required this.searching});

  final List<Map<String, dynamic>> prompts;
  final bool searching;

  static final _picker = RandomTestPicker();

  void _openRandom(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WritingTestScreen(prompt: _picker.pick(prompts))),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (prompts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            searching ? 'No task matches that search.' : 'No tasks here yet. Check back soon.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 14, color: context.colors.textSecondary),
          ),
        ),
      );
    }
    // Once a student is searching they have a task in mind; the shuffle row
    // only earns its place when they don't.
    final leading = searching ? 0 : 1;
    final taskNumber = wToInt(prompts.first['task_number']);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: prompts.length + leading,
      itemBuilder: (context, index) {
        if (index < leading) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RandomTestCard(
              subtitle: 'Any of the ${prompts.length} Task $taskNumber prompts',
              onTap: () => _openRandom(context),
            ),
          );
        }
        final i = index - leading;
        return _PromptCard(prompt: prompts[i], number: i + 1);
      },
    );
  }
}

/// One task in the list.
///
/// The card leads with the question itself, because on these prompts `title`
/// *is* the question — "The chart below shows the depth of snow…", "Some
/// people believe that…" — running to a couple of hundred characters. Squeezed
/// onto one ellipsised line beside an icon it told a student nothing, so it
/// gets the room a question needs and the metadata moves under it.
class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.prompt, required this.number});

  final Map<String, dynamic> prompt;

  /// Position in the list — the only stable handle a student has on a task,
  /// since the questions have no short names.
  final int number;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final imageUrl = prompt['image_url']?.toString();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final taskNumber = wToInt(prompt['task_number']);
    final minWords = (prompt['min_words'] as num?)?.toInt() ?? (taskNumber == 1 ? 150 : 250);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WritingTestScreen(prompt: prompt)),
        ),
        child: Container(
          decoration: mtSoftCard(context, radius: 18, border: Border.all(color: colors.border)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Task 1 is a chart question, so the chart is the card: it is
              // what a student recognises the question by, long before they
              // read the text. The charts are flat artwork drawn on white and
              // keep that plate in both themes — recolouring them would wreck
              // the axis labels the question is about.
              if (hasImage)
                Container(
                  height: 128,
                  width: double.infinity,
                  color: Colors.white,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.insert_chart_outlined_rounded,
                      size: 28,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prompt['title']?.toString() ?? '',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 14.5,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        MtPill(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          background: colors.brand,
                          child: Text(
                            'Task $taskNumber · #$number',
                            style: TextStyle(
                              fontFamily: 'SF Pro',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: colors.onBrand,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Min $minWords words',
                            style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, color: colors.textSecondary),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: colors.textTertiary, size: 22),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
