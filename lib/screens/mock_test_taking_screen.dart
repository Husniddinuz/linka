import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import '../services/podcast_playback_service.dart';
import '../services/prefs_service.dart';
import '../widgets/mock_test_question_widgets.dart';
import '../widgets/mock_test_styles.dart';
import 'mock_test_result_screen.dart';

/// Background tint choices for the reading passage, persisted locally so
/// they apply across every passage the learner opens.
const List<Color> kPassageBackgroundOptions = [
  Colors.white,
  Color(0xFFFBF3DF), // sepia
  Color(0xFFEAF3EA), // mint
  Color(0xFFF1F1F1), // grey
];

/// Font-size multipliers applied to the passage's base 14.5pt style.
const List<double> kPassageFontScales = [0.9, 1.0, 1.15, 1.3];

class MockTestTakingScreen extends StatefulWidget {
  const MockTestTakingScreen({
    super.key,
    required this.testId,
    required this.testType,
  });

  final int testId;
  final String testType; // 'reading' | 'listening'

  @override
  State<MockTestTakingScreen> createState() => _MockTestTakingScreenState();
}

class _MockTestTakingScreenState extends State<MockTestTakingScreen> {
  Map<String, dynamic>? _test;
  bool _loading = true;
  String? _error;

  int _sectionIndex = 0;
  final Map<String, dynamic> _answers = {};

  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _submitting = false;

  Color _passageBackground = kPassageBackgroundOptions.first;
  double _passageFontScale = 1.0;

  bool get _isListening => widget.testType == 'listening';

  @override
  void initState() {
    super.initState();
    _loadPassageSettings();
    _load();
  }

  Future<void> _loadPassageSettings() async {
    final bgValue = await PrefsService.getReaderBackgroundColor();
    final fontScale = await PrefsService.getReaderFontScale();
    if (!mounted) return;
    setState(() {
      if (bgValue != null) _passageBackground = Color(bgValue);
      _passageFontScale = fontScale;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_isListening) {
      PodcastPlaybackService.instance.stop();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await MockTestService.fetchTestDetail(widget.testId);
      if (!mounted) return;
      setState(() {
        _test = data;
        _loading = false;
        _remaining = Duration(
          seconds: (data['duration_seconds'] as num?)?.toInt() ?? 3600,
        );
      });
      _startTimer();
      if (_isListening) {
        final audioUrl = data['audio_url'] as String?;
        if (audioUrl != null && audioUrl.isNotEmpty) {
          await PodcastPlaybackService.instance.loadAdHoc(
            'mock-listening-${widget.testId}',
            Uri.parse(audioUrl),
            title: data['title']?.toString() ?? 'Listening test',
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining.inSeconds <= 0) {
        t.cancel();
        _confirmSubmit(auto: true);
        return;
      }
      setState(() => _remaining -= const Duration(seconds: 1));
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  List<Map<String, dynamic>> get _sections =>
      ((_test?['sections'] as List?) ?? const []).cast<Map<String, dynamic>>();

  /// question id -> {number, number_end}, flattened across every section so
  /// answered-progress can be reported against the real IELTS question
  /// numbers (1-40) rather than UI rows — a "choose FOUR letters" question is
  /// one row in the answers map but spans 4 question numbers (37-40).
  Map<String, Map<String, dynamic>> get _questionIndex {
    final index = <String, Map<String, dynamic>>{};
    for (final section in _sections) {
      final groups = ((section['question_groups'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      for (final g in groups) {
        final questions = ((g['questions'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
        for (final q in questions) {
          index[q['id'].toString()] = q;
        }
      }
    }
    return index;
  }

  int get _answeredCount {
    final index = _questionIndex;
    var count = 0;
    _answers.forEach((id, value) {
      final q = index[id];
      final end = q?['number_end'] as num?;
      final span = end != null
          ? (end.toInt() - (q!['number'] as num).toInt() + 1)
          : 1;
      if (value is String && value.trim().isNotEmpty) {
        count += 1;
      } else if (value is List && value.isNotEmpty) {
        count += value.length.clamp(0, span);
      }
    });
    return count;
  }

  int get _totalQuestions => (_test?['total_questions'] as num?)?.toInt() ?? 0;

  Future<void> _confirmSubmit({bool auto = false}) async {
    if (_submitting) return;
    final proceed = auto
        ? true
        : await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Text(
                    'Submit test?',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      color: MockTestColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  content: Text(
                    'You answered $_answeredCount of $_totalQuestions questions.',
                    style: const TextStyle(
                      fontFamily: 'SF Pro',
                      color: MockTestColors.grey,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          color: MockTestColors.grey,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text(
                        'Submit',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          color: MockTestColors.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ) ??
              false;
    if (!proceed) return;

    setState(() => _submitting = true);
    _timer?.cancel();
    try {
      final result = await MockTestService.submitTest(widget.testId, _answers);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MockTestResultScreen(attempt: result),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    }
  }

  Future<void> _openPassageSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Passage display',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: MockTestColors.navy,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Background',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MockTestColors.grey,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: kPassageBackgroundOptions.map((color) {
                      final selected =
                          color.toARGB32() == _passageBackground.toARGB32();
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _passageBackground = color);
                            setSheetState(() {});
                            PrefsService.setReaderBackgroundColor(
                              color.toARGB32(),
                            );
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? MockTestColors.navy
                                    : MockTestColors.divider,
                                width: selected ? 2.5 : 1,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Text size',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MockTestColors.grey,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: kPassageFontScales.map((scale) {
                      final selected = scale == _passageFontScale;
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _passageFontScale = scale);
                            setSheetState(() {});
                            PrefsService.setReaderFontScale(scale);
                          },
                          child: Container(
                            width: 44,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? MockTestColors.navy
                                  : MockTestColors.chipBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'A',
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontWeight: FontWeight.w700,
                                fontSize: 14 * scale,
                                color: selected
                                    ? Colors.white
                                    : MockTestColors.navy,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: MockTestColors.yellow),
        ),
      );
    }
    if (_error != null || _test == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: mtAppBar(context, title: 'Mock test'),
        body: Center(
          child: Text(
            _error ?? 'Could not load test',
            style: const TextStyle(fontFamily: 'SF Pro'),
          ),
        ),
      );
    }

    final sections = _sections;
    final section = sections.isNotEmpty
        ? sections[_sectionIndex.clamp(0, sections.length - 1)]
        : null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(
        context,
        title: _test!['title']?.toString() ?? 'Mock test',
        actions: [
          if (!_isListening)
            IconButton(
              onPressed: _openPassageSettings,
              icon: const Icon(
                Icons.text_fields_rounded,
                color: MockTestColors.navy,
              ),
              tooltip: 'Passage display settings',
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: MtPill(
                background: _remaining.inMinutes < 5
                    ? MockTestColors.redBg
                    : MockTestColors.chipBg,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 15,
                      color: _remaining.inMinutes < 5
                          ? MockTestColors.red
                          : MockTestColors.navy,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _formatDuration(_remaining),
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: _remaining.inMinutes < 5
                            ? MockTestColors.red
                            : MockTestColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Column(
            children: [
              _SectionSelector(
                count: sections.length,
                selectedIndex: _sectionIndex,
                label: _isListening ? 'Part' : 'Passage',
                onSelected: (i) => setState(() => _sectionIndex = i),
              ),
              const Divider(height: 1, color: MockTestColors.divider),
            ],
          ),
        ),
      ),
      body: Listener(
        // A plain GestureDetector's onTap can lose the tap-gesture arena to
        // descendants that install their own recognizers (e.g. the passage's
        // SelectionArea), so it never fires. Listener sees every pointer
        // down regardless of who ends up winning the arena.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            if (_isListening) const _AudioBar(),
            Expanded(
              child: section == null
                  ? const Center(
                      child: Text(
                        'No content',
                        style: TextStyle(fontFamily: 'SF Pro'),
                      ),
                    )
                  : _isListening
                  ? _QuestionsView(
                      section: section,
                      answers: _answers,
                      onAnswer: (id, val) => setState(() => _answers[id] = val),
                    )
                  : _ReadingSplitView(
                      passage: _PassageView(
                        passageKey: '${widget.testId}_$_sectionIndex',
                        bodyHtml: section['body_html']?.toString() ?? '',
                        background: _passageBackground,
                        fontScale: _passageFontScale,
                      ),
                      questions: _QuestionsView(
                        section: section,
                        answers: _answers,
                        onAnswer: (id, val) =>
                            setState(() => _answers[id] = val),
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: MtPrimaryButton(
            label: 'Submit ($_answeredCount/$_totalQuestions answered)',
            loading: _submitting,
            onPressed: () => _confirmSubmit(),
          ),
        ),
      ),
    );
  }
}

class _SectionSelector extends StatelessWidget {
  const _SectionSelector({
    required this.count,
    required this.selectedIndex,
    required this.label,
    required this.onSelected,
  });

  final int count;
  final int selectedIndex;
  final String label;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SizedBox(
        height: 44,
        child: Row(
          children: List.generate(count, (i) {
            final selected = i == selectedIndex;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == count - 1 ? 0 : 8),
                child: GestureDetector(
                  onTap: () => onSelected(i),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? MockTestColors.navy : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: selected
                            ? MockTestColors.navy
                            : const Color(0xFFDDDDDD),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      '$label ${i + 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : MockTestColors.navy,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Draggable split between the reading passage (top) and questions
/// (bottom), separated by a center handle the learner can drag to resize
/// either pane.
class _ReadingSplitView extends StatefulWidget {
  const _ReadingSplitView({required this.passage, required this.questions});

  final Widget passage;
  final Widget questions;

  @override
  State<_ReadingSplitView> createState() => _ReadingSplitViewState();
}

class _ReadingSplitViewState extends State<_ReadingSplitView>
    with SingleTickerProviderStateMixin {
  static const _handleHeight = 14.0;

  /// Fraction of the available height (excluding the handle) given to the
  /// passage pane.
  double _ratio = 0.45;

  // Briefly nudges the split on first open so the handle reads as
  // draggable, rather than a static divider.
  late final AnimationController _hintController;
  late final Animation<double> _hintOffset;

  @override
  void initState() {
    super.initState();
    _hintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _hintOffset = TweenSequence<double>([
      TweenSequenceItem(
        weight: 40,
        tween: Tween(
          begin: 0.0,
          end: 0.05,
        ).chain(CurveTween(curve: Curves.easeOut)),
      ),
      TweenSequenceItem(
        weight: 35,
        tween: Tween(
          begin: 0.05,
          end: -0.03,
        ).chain(CurveTween(curve: Curves.easeInOut)),
      ),
      TweenSequenceItem(
        weight: 25,
        tween: Tween(
          begin: -0.03,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
      ),
    ]).animate(_hintController);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _hintController.forward();
    });
  }

  @override
  void dispose() {
    _hintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = (constraints.maxHeight - _handleHeight).clamp(
          0.0,
          double.infinity,
        );
        return AnimatedBuilder(
          animation: _hintOffset,
          builder: (context, _) {
            final ratio = (_ratio + _hintOffset.value).clamp(0.15, 0.85);
            final topHeight = available * ratio;
            final bottomHeight = available - topHeight;
            return Column(
              children: [
                SizedBox(height: topHeight, child: widget.passage),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) {
                    if (_hintController.isAnimating) {
                      _hintController.stop();
                      _hintController.value = 0;
                    }
                  },
                  onVerticalDragUpdate: (details) {
                    if (available <= 0) return;
                    setState(() {
                      final nextTop = (topHeight + details.delta.dy).clamp(
                        available * 0.15,
                        available * 0.85,
                      );
                      _ratio = nextTop / available;
                    });
                  },
                  child: Container(
                    height: _handleHeight,
                    width: double.infinity,
                    color: MockTestColors.softBg,
                    alignment: Alignment.center,
                    child: Container(
                      width: 34,
                      height: 3,
                      decoration: BoxDecoration(
                        color: MockTestColors.greyLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: bottomHeight, child: widget.questions),
              ],
            );
          },
        );
      },
    );
  }
}

/// The reading passage: selectable (copy/paste elsewhere) with a custom
/// "Highlight" action in the selection toolbar. Highlighted phrases persist
/// locally per [passageKey] and are re-applied whenever the passage reopens.
class _PassageView extends StatefulWidget {
  const _PassageView({
    required this.passageKey,
    required this.bodyHtml,
    required this.background,
    required this.fontScale,
  });

  final String passageKey;
  final String bodyHtml;
  final Color background;
  final double fontScale;

  @override
  State<_PassageView> createState() => _PassageViewState();
}

class _PassageViewState extends State<_PassageView> {
  List<String> _highlights = [];
  final List<TapGestureRecognizer> _recognizers = [];
  String _pendingSelection = '';

  List<String> get _paragraphs {
    final matches = RegExp(
      r'<p>(.*?)</p>',
      dotAll: true,
    ).allMatches(widget.bodyHtml);
    return matches
        .map((m) => m.group(1) ?? '')
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadHighlights();
  }

  @override
  void didUpdateWidget(covariant _PassageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.passageKey != widget.passageKey) {
      _loadHighlights();
    }
  }

  Future<void> _loadHighlights() async {
    final saved = await PrefsService.getPassageHighlights(widget.passageKey);
    if (!mounted) return;
    setState(() => _highlights = saved);
  }

  Future<void> _addHighlight(String text) async {
    final phrase = text.trim();
    if (phrase.length < 2 || _highlights.contains(phrase)) return;
    setState(() => _highlights = [..._highlights, phrase]);
    await PrefsService.addPassageHighlight(widget.passageKey, phrase);
  }

  Future<void> _removeHighlight(String phrase) async {
    setState(
      () => _highlights = _highlights.where((h) => h != phrase).toList(),
    );
    await PrefsService.removePassageHighlight(widget.passageKey, phrase);
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  List<InlineSpan> _buildParagraphSpans(String paragraph, TextStyle baseStyle) {
    if (_highlights.isEmpty) return [TextSpan(text: paragraph)];

    final matches = <(int start, int end)>[];
    for (final phrase in _highlights) {
      if (phrase.isEmpty) continue;
      var from = 0;
      while (true) {
        final idx = paragraph.indexOf(phrase, from);
        if (idx == -1) break;
        matches.add((idx, idx + phrase.length));
        from = idx + phrase.length;
      }
    }
    if (matches.isEmpty) return [TextSpan(text: paragraph)];
    matches.sort((a, b) => a.$1.compareTo(b.$1));

    final highlightStyle = baseStyle.copyWith(
      backgroundColor: MockTestColors.yellow.withValues(alpha: 0.45),
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in matches) {
      if (m.$1 < cursor) continue; // overlapping match — skip
      if (m.$1 > cursor)
        spans.add(TextSpan(text: paragraph.substring(cursor, m.$1)));
      final phrase = paragraph.substring(m.$1, m.$2);
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _removeHighlight(phrase);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(text: phrase, style: highlightStyle, recognizer: recognizer),
      );
      cursor = m.$2;
    }
    if (cursor < paragraph.length)
      spans.add(TextSpan(text: paragraph.substring(cursor)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final paras = _paragraphs;
    final baseStyle = TextStyle(
      fontFamily: 'SF Pro',
      fontSize: 14.5 * widget.fontScale,
      height: 1.6,
      color: MockTestColors.navy,
    );

    return Container(
      color: widget.background,
      child: SelectionArea(
        onSelectionChanged: (content) =>
            _pendingSelection = content?.plainText.trim() ?? '',
        contextMenuBuilder: (context, selectableRegionState) {
          final buttonItems = List<ContextMenuButtonItem>.from(
            selectableRegionState.contextMenuButtonItems,
          );
          if (_pendingSelection.length >= 2) {
            buttonItems.insert(
              0,
              ContextMenuButtonItem(
                label: 'Highlight',
                onPressed: () {
                  _addHighlight(_pendingSelection);
                  selectableRegionState.hideToolbar();
                },
              ),
            );
          }
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: selectableRegionState.contextMenuAnchors,
            buttonItems: buttonItems,
          );
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: paras
                .map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text.rich(
                      TextSpan(
                        style: baseStyle,
                        children: _buildParagraphSpans(p, baseStyle),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _QuestionsView extends StatelessWidget {
  const _QuestionsView({
    required this.section,
    required this.answers,
    required this.onAnswer,
  });

  final Map<String, dynamic> section;
  final Map<String, dynamic> answers;
  final void Function(String questionId, dynamic value) onAnswer;

  @override
  Widget build(BuildContext context) {
    final groups = ((section['question_groups'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: groups.map((group) {
          final questions = ((group['questions'] as List?) ?? const [])
              .cast<Map<String, dynamic>>();
          final instruction = group['instruction_html']?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (instruction.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: mtSoftCard(
                      color: MockTestColors.chipBg,
                      radius: 10,
                    ),
                    child: Text(
                      instruction,
                      style: const TextStyle(
                        fontFamily: 'SF Pro',
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: MockTestColors.navy,
                        height: 1.4,
                      ),
                    ),
                  ),
                if (group['type'] == 'text' &&
                    questions.every(
                      (q) =>
                          (q['prompt_text'] as String?)?.contains('___') ??
                          false,
                    ))
                  TextGroupInline(
                    questions: questions,
                    answers: answers,
                    onChanged: onAnswer,
                  )
                else
                  ...questions.map((q) {
                    final id = q['id'].toString();
                    return QuestionField(
                      question: q,
                      group: group,
                      answer: answers[id],
                      onChanged: (val) => onAnswer(id, val),
                    );
                  }),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AudioBar extends StatelessWidget {
  const _AudioBar();

  @override
  Widget build(BuildContext context) {
    final player = PodcastPlaybackService.instance;
    return Container(
      color: MockTestColors.softBg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: StreamBuilder(
        stream: player.playerStateStream,
        builder: (context, snapshot) {
          final playing = player.isPlaying;
          return Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: player.togglePlay,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: MockTestColors.navy,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (context, posSnap) {
                    final pos = posSnap.data ?? Duration.zero;
                    final dur = player.duration;
                    final max = dur.inMilliseconds > 0
                        ? dur.inMilliseconds.toDouble()
                        : 1.0;
                    final value = pos.inMilliseconds
                        .clamp(0, max.toInt())
                        .toDouble();
                    return SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: MockTestColors.navy,
                        inactiveTrackColor: MockTestColors.divider,
                        thumbColor: MockTestColors.navy,
                        overlayColor: MockTestColors.navy.withValues(
                          alpha: 0.12,
                        ),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: value,
                        max: max,
                        onChanged: (v) =>
                            player.seek(Duration(milliseconds: v.toInt())),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
