import 'dart:async';
import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import '../services/podcast_playback_service.dart';
import '../widgets/mock_test_question_widgets.dart';
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

  int get _answeredCount => _answers.values.where((v) {
        if (v is String) return v.trim().isNotEmpty;
        if (v is List) return v.isNotEmpty;
        return false;
      }).length;

  int get _totalQuestions => (_test?['total_questions'] as num?)?.toInt() ?? 0;

  Future<void> _confirmSubmit({bool auto = false}) async {
    if (_submitting) return;
    final proceed = auto
        ? true
        : await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Submit test?'),
                content: Text('You answered $_answeredCount of $_totalQuestions questions.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _test == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(_error ?? 'Could not load test')),
      );
    }

    final sections = _sections;
    final section = sections.isNotEmpty ? sections[_sectionIndex.clamp(0, sections.length - 1)] : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_test!['title']?.toString() ?? 'Mock test'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 18),
                  const SizedBox(width: 4),
                  Text(_formatDuration(_remaining), style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _SectionSelector(
            count: sections.length,
            selectedIndex: _sectionIndex,
            label: _isListening ? 'Part' : 'Passage',
            onSelected: (i) => setState(() => _sectionIndex = i),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_isListening) const _AudioBar(),
          if (!_isListening && section != null)
            TabBar(
              controller: _readingTabController,
              labelColor: Theme.of(context).colorScheme.primary,
              tabs: const [Tab(text: 'Passage'), Tab(text: 'Questions')],
            ),
          Expanded(
            child: section == null
                ? const Center(child: Text('No content'))
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
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _submitting ? null : () => _confirmSubmit(),
            child: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Submit ($_answeredCount/$_totalQuestions answered)'),
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
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == selectedIndex;
          return ChoiceChip(
            label: Text('$label ${i + 1}'),
            selected: selected,
            onSelected: (_) => onSelected(i),
          );
        },
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: paras
            .map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(p, style: const TextStyle(fontSize: 15, height: 1.6)),
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
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (instruction.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      instruction,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: StreamBuilder(
        stream: player.playerStateStream,
        builder: (context, snapshot) {
          final playing = player.isPlaying;
          return Row(
            children: [
              IconButton(
                icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 34),
                onPressed: player.togglePlay,
              ),
              Expanded(
                child: StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (context, posSnap) {
                    final pos = posSnap.data ?? Duration.zero;
                    final dur = player.duration;
                    final max = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
                    final value = pos.inMilliseconds.clamp(0, max.toInt()).toDouble();
                    return Slider(
                      value: value,
                      max: max,
                      onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
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
