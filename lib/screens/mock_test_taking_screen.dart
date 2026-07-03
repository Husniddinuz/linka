import 'dart:async';
import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import '../services/podcast_playback_service.dart';
import '../widgets/mock_test_question_widgets.dart';
import '../widgets/mock_test_styles.dart';
import 'mock_test_result_screen.dart';

class MockTestTakingScreen extends StatefulWidget {
  const MockTestTakingScreen({super.key, required this.testId, required this.testType});

  final int testId;
  final String testType; // 'reading' | 'listening'

  @override
  State<MockTestTakingScreen> createState() => _MockTestTakingScreenState();
}

class _MockTestTakingScreenState extends State<MockTestTakingScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _test;
  bool _loading = true;
  String? _error;

  int _sectionIndex = 0;
  late TabController _readingTabController;
  final Map<String, dynamic> _answers = {};

  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _submitting = false;

  bool get _isListening => widget.testType == 'listening';

  @override
  void initState() {
    super.initState();
    _readingTabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _readingTabController.dispose();
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
        _remaining = Duration(seconds: (data['duration_seconds'] as num?)?.toInt() ?? 3600);
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
      final groups = ((section['question_groups'] as List?) ?? const []).cast<Map<String, dynamic>>();
      for (final g in groups) {
        final questions = ((g['questions'] as List?) ?? const []).cast<Map<String, dynamic>>();
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
      final span = end != null ? (end.toInt() - (q!['number'] as num).toInt() + 1) : 1;
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text(
                  'Submit test?',
                  style: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.navy, fontWeight: FontWeight.w700),
                ),
                content: Text(
                  'You answered $_answeredCount of $_totalQuestions questions.',
                  style: const TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel', style: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      'Submit',
                      style: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.navy, fontWeight: FontWeight.w700),
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
        MaterialPageRoute(builder: (_) => MockTestResultScreen(attempt: result)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: MockTestColors.yellow)),
      );
    }
    if (_error != null || _test == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: mtAppBar(context, title: 'Mock test'),
        body: Center(
          child: Text(_error ?? 'Could not load test', style: const TextStyle(fontFamily: 'SF Pro')),
        ),
      );
    }

    final sections = _sections;
    final section = sections.isNotEmpty ? sections[_sectionIndex.clamp(0, sections.length - 1)] : null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(
        context,
        title: _test!['title']?.toString() ?? 'Mock test',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: MtPill(
                background: _remaining.inMinutes < 5 ? MockTestColors.redBg : MockTestColors.chipBg,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 15,
                      color: _remaining.inMinutes < 5 ? MockTestColors.red : MockTestColors.navy,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _formatDuration(_remaining),
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: _remaining.inMinutes < 5 ? MockTestColors.red : MockTestColors.navy,
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
      body: Column(
        children: [
          if (_isListening) const _AudioBar(),
          if (!_isListening && section != null)
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _readingTabController,
                labelColor: MockTestColors.navy,
                unselectedLabelColor: MockTestColors.greyLight,
                indicatorColor: MockTestColors.navy,
                labelStyle: const TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, fontWeight: FontWeight.w600),
                tabs: const [Tab(text: 'Passage'), Tab(text: 'Questions')],
              ),
            ),
          Expanded(
            child: section == null
                ? const Center(child: Text('No content', style: TextStyle(fontFamily: 'SF Pro')))
                : _isListening
                    ? _QuestionsView(
                        section: section,
                        answers: _answers,
                        onAnswer: (id, val) => setState(() => _answers[id] = val),
                      )
                    : TabBarView(
                        controller: _readingTabController,
                        children: [
                          _PassageView(bodyHtml: section['body_html']?.toString() ?? ''),
                          _QuestionsView(
                            section: section,
                            answers: _answers,
                            onAnswer: (id, val) => setState(() => _answers[id] = val),
                          ),
                        ],
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
                      color: selected ? MockTestColors.navy : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: selected ? MockTestColors.navy : const Color(0xFFDDDDDD),
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

class _PassageView extends StatelessWidget {
  const _PassageView({required this.bodyHtml});
  final String bodyHtml;

  List<String> get _paragraphs {
    final matches = RegExp(r'<p>(.*?)</p>', dotAll: true).allMatches(bodyHtml);
    return matches.map((m) => m.group(1) ?? '').where((s) => s.trim().isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final paras = _paragraphs;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: paras
            .map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    p,
                    style: const TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 14.5,
                      height: 1.6,
                      color: MockTestColors.navy,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _QuestionsView extends StatelessWidget {
  const _QuestionsView({required this.section, required this.answers, required this.onAnswer});

  final Map<String, dynamic> section;
  final Map<String, dynamic> answers;
  final void Function(String questionId, dynamic value) onAnswer;

  @override
  Widget build(BuildContext context) {
    final groups = ((section['question_groups'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: groups.map((group) {
          final questions = ((group['questions'] as List?) ?? const []).cast<Map<String, dynamic>>();
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
                    decoration: mtSoftCard(color: MockTestColors.chipBg, radius: 10),
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
                  decoration: const BoxDecoration(color: MockTestColors.navy, shape: BoxShape.circle),
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
                    final max = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
                    final value = pos.inMilliseconds.clamp(0, max.toInt()).toDouble();
                    return SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: MockTestColors.navy,
                        inactiveTrackColor: MockTestColors.divider,
                        thumbColor: MockTestColors.navy,
                        overlayColor: MockTestColors.navy.withValues(alpha: 0.12),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: value,
                        max: max,
                        onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
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
