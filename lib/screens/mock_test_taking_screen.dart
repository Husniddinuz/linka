import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/mock_test.dart';
import '../services/mock_test_service.dart';
import '../services/podcast_playback_service.dart';
import '../services/prefs_service.dart';
import '../widgets/mock_test_question_widgets.dart';
import '../widgets/mock_test_styles.dart';
import 'mock_test_result_screen.dart';
import '../theme/app_colors.dart';

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
  MockTest? _test;
  bool _loading = true;
  String? _error;

  int _sectionIndex = 0;
  final Map<String, dynamic> _answers = {};

  /// What the shared player currently holds, so switching parts back and
  /// forth doesn't reload — and restart — a track that's already cued.
  String _loadedAudioUrl = '';

  Timer? _timer;

  /// Ticks once a second; a ValueNotifier (not setState) so the countdown
  /// doesn't rebuild the whole question tree every second — a per-second
  /// rebuild resets in-progress text edits and dismisses the paste toolbar.
  final ValueNotifier<Duration> _remaining = ValueNotifier(Duration.zero);
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
    _remaining.dispose();
    if (_isListening) {
      PodcastPlaybackService.instance.stop();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await MockTestService.fetchTestDetail(widget.testId);
      if (!mounted) return;
      _remaining.value = Duration(seconds: data.durationSeconds);
      setState(() {
        _test = data;
        _loading = false;
      });
      _startTimer();
      await _syncAudio();
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
      if (_remaining.value.inSeconds <= 0) {
        t.cancel();
        _confirmSubmit(auto: true);
        return;
      }
      _remaining.value -= const Duration(seconds: 1);
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  List<TestSection> get _sections => _test?.sections ?? const [];

  /// Whether this test carries a recording per part, the way the exam does.
  /// Tests authored before that have a single whole-test file on the test
  /// itself, and are played from it unchanged.
  bool get _hasPerPartAudio => _sections.any((s) => s.audioUrl.isNotEmpty);

  /// The recording belonging to the part currently on screen — '' when this
  /// part has none, which on a per-part test means exactly that part is
  /// missing its audio, not that the test is silent.
  String get _currentAudioUrl {
    if (!_isListening) return '';
    final sections = _sections;
    if (!_hasPerPartAudio) return _test?.audioUrl ?? '';
    if (sections.isEmpty) return '';
    return sections[_sectionIndex.clamp(0, sections.length - 1)].audioUrl;
  }

  /// Cues the current part's recording. Called on load and on every part
  /// switch; a no-op when the right track is already loaded.
  Future<void> _syncAudio() async {
    if (!_isListening) return;
    final url = _currentAudioUrl;
    if (url == _loadedAudioUrl) return;
    _loadedAudioUrl = url;

    final player = PodcastPlaybackService.instance;
    if (url.isEmpty) {
      await player.stop();
      return;
    }
    final testTitle = _test?.title ?? '';
    await player.loadAdHoc(
      'mock-listening-${widget.testId}-$_sectionIndex',
      Uri.parse(url),
      title: _hasPerPartAudio
          ? '${testTitle.isNotEmpty ? testTitle : 'Listening test'} — Part ${_sectionIndex + 1}'
          : (testTitle.isNotEmpty ? testTitle : 'Listening test'),
    );
  }

  /// question id -> Question, flattened across every section so
  /// answered-progress can be reported against the real IELTS question
  /// numbers (1-40) rather than UI rows — a "choose FOUR letters" question is
  /// one row in the answers map but spans 4 question numbers (37-40).
  Map<String, Question> get _questionIndex {
    final index = <String, Question>{};
    for (final section in _sections) {
      for (final g in section.questionGroups) {
        for (final q in g.questions) {
          index[q.id.toString()] = q;
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
      final end = q?.numberEnd;
      final span = end != null ? (end - q!.number + 1) : 1;
      if (value is String && value.trim().isNotEmpty) {
        count += 1;
      } else if (value is List && value.isNotEmpty) {
        count += value.length.clamp(0, span);
      }
    });
    return count;
  }

  int get _totalQuestions => _test?.totalQuestions ?? 0;

  Future<void> _confirmSubmit({bool auto = false}) async {
    if (_submitting) return;
    final proceed = auto
        ? true
        : await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: context.colors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: Text(
                    'Submit test?',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  content: Text(
                    'You answered $_answeredCount of $_totalQuestions questions.',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      color: context.colors.textSecondary,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        'Submit',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          color: context.colors.textPrimary,
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
      backgroundColor: context.colors.surface,
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
                  Text(
                    'Passage display',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Background',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textSecondary,
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
                                    ? context.colors.brand
                                    : context.colors.border,
                                width: selected ? 2.5 : 1,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Text size',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textSecondary,
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
                                  ? context.colors.brand
                                  : context.colors.surfaceAlt,
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
                                    : context.colors.textPrimary,
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
      return Scaffold(
        backgroundColor: context.colors.background,
        body: Center(
          child: CircularProgressIndicator(color: context.colors.accentYellow),
        ),
      );
    }
    if (_error != null || _test == null) {
      return Scaffold(
        backgroundColor: context.colors.background,
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
      backgroundColor: context.colors.background,
      appBar: mtAppBar(
        context,
        title: _test!.title.isNotEmpty ? _test!.title : 'Mock test',
        actions: [
          if (!_isListening)
            IconButton(
              onPressed: _openPassageSettings,
              icon: Icon(
                Icons.text_fields_rounded,
                color: context.colors.textPrimary,
              ),
              tooltip: 'Passage display settings',
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: ValueListenableBuilder<Duration>(
                valueListenable: _remaining,
                builder: (context, remaining, _) {
                  final urgent = remaining.inMinutes < 5;
                  return MtPill(
                    background: urgent
                        ? context.colors.errorBg
                        : context.colors.surfaceAlt,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 15,
                          color: urgent
                              ? context.colors.error
                              : context.colors.textPrimary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _formatDuration(remaining),
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: urgent
                                ? context.colors.error
                                : context.colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
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
                onSelected: (i) {
                  setState(() => _sectionIndex = i);
                  _syncAudio();
                },
              ),
              Divider(height: 1, color: context.colors.border),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_isListening)
            _AudioBar(
              // A per-part test labels the bar so it's obvious the recording
              // changes with the tab; a legacy whole-test file has no part to
              // name, so it stays unlabelled as before.
              partLabel: _hasPerPartAudio ? 'Part ${_sectionIndex + 1}' : null,
              hasAudio: _currentAudioUrl.isNotEmpty,
            ),
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
                    // Keyboard dismissal is scoped to the passage pane only:
                    // a Listener over the whole body also fired for taps and
                    // long-presses inside the answer fields themselves, so
                    // every touch in the questions pane bounced the keyboard
                    // (and broke paste). A Listener (not GestureDetector) so
                    // the passage's SelectionArea can't swallow the event.
                    passage: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (_) => FocusScope.of(context).unfocus(),
                      child: _PassageView(
                        passageKey: '${widget.testId}_$_sectionIndex',
                        bodyHtml: section.bodyHtml,
                        background: _passageBackground,
                        fontScale: _passageFontScale,
                      ),
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
                      color: selected ? context.colors.brand : context.colors.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: selected
                            ? context.colors.brand
                            : context.colors.border,
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
                        color: selected ? Colors.white : context.colors.textPrimary,
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
                    color: context.colors.surfaceAlt,
                    alignment: Alignment.center,
                    child: Container(
                      width: 34,
                      height: 3,
                      decoration: BoxDecoration(
                        color: context.colors.textTertiary,
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
      backgroundColor: context.colors.accentYellow.withValues(alpha: 0.45),
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
      color: context.colors.textPrimary,
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

  final TestSection section;
  final Map<String, dynamic> answers;
  final void Function(String questionId, dynamic value) onAnswer;

  @override
  Widget build(BuildContext context) {
    final groups = section.questionGroups;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: groups.map((group) {
          final questions = group.questions;
          final instruction = group.instructionHtml;
          return Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (instruction.isNotEmpty)
                  GroupInstructionCard(instruction: instruction),
                if (group.imageUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        group.imageUrl,
                        width: double.infinity,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                if (questionTypeHandler(
                      group.type,
                    ).buildGroupBlock?.call(group, questions, answers, onAnswer)
                    case final block?)
                  block
                else
                  ...questions.map((q) {
                    final id = q.id.toString();
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
  const _AudioBar({this.partLabel, this.hasAudio = true});

  /// 'Part 2' on a test with a recording per part, null on a legacy
  /// whole-test recording.
  final String? partLabel;

  /// False when the part on screen has no recording of its own.
  final bool hasAudio;

  @override
  Widget build(BuildContext context) {
    final player = PodcastPlaybackService.instance;

    if (!hasAudio) {
      return Container(
        width: double.infinity,
        color: context.colors.surfaceAlt,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          'No recording for this part yet.',
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 12.5,
            color: context.colors.textSecondary,
          ),
        ),
      );
    }

    return Container(
      color: context.colors.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: StreamBuilder(
        stream: player.playerStateStream,
        builder: (context, snapshot) {
          final playing = player.isPlaying;
          return Row(
            children: [
              if (partLabel != null) ...[
                Text(
                  partLabel!,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: player.togglePlay,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: context.colors.brand,
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
                        activeTrackColor: context.colors.textPrimary,
                        inactiveTrackColor: context.colors.border,
                        thumbColor: context.colors.textPrimary,
                        overlayColor: context.colors.textPrimary.withValues(
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
