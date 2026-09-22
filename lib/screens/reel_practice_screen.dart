import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/course_reel.dart';
import '../services/course_reels_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import '../widgets/reel_progress_markers.dart';

/// The practice for one lesson: sentence building, fill in the gaps and
/// writing a complete sentence, one task at a time.
///
/// Answers are checked by the server, which also marks the lesson's practice
/// complete (the green marker) once every required task is solved. The
/// screen writes the resulting progress back onto [lesson], so whoever pushed
/// it only has to rebuild when it pops.
class ReelPracticeScreen extends StatefulWidget {
  const ReelPracticeScreen({super.key, required this.lesson});

  final ReelLesson lesson;

  @override
  State<ReelPracticeScreen> createState() => _ReelPracticeScreenState();
}

class _ReelPracticeScreenState extends State<ReelPracticeScreen> {
  List<ReelExercise> _exercises = const [];
  bool _loading = true;
  bool _failed = false;

  int _step = 0;
  bool _finished = false;

  /// The answer the current task would submit; null while incomplete.
  Object? _answer;
  bool _checking = false;
  ReelAnswerResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final practice = await CourseReelsService.fetchPractice(widget.lesson.id);
      if (!mounted) return;
      final firstOpen = practice.exercises.indexWhere((e) => !e.solved);
      setState(() {
        _exercises = practice.exercises;
        widget.lesson.progress = practice.progress;
        _step = firstOpen >= 0 ? firstOpen : 0;
        _finished = practice.exercises.isNotEmpty && firstOpen < 0;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  ReelExercise get _current => _exercises[_step];

  Future<void> _check() async {
    final answer = _answer;
    if (answer == null || _checking) return;
    setState(() => _checking = true);
    try {
      final result = await CourseReelsService.submitAnswer(_current.id, answer);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _result = result;
        _current
          ..solved = result.solved
          ..attempts = result.attempts
          ..expected = result.expected
          ..sampleAnswer = result.sampleAnswer;
        widget.lesson.progress = result.lessonProgress;
      });
    } catch (_) {
      if (mounted) {
        AppNotify.show(context, message: 'Couldn\'t check your answer');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _next() {
    setState(() {
      _result = null;
      _answer = null;
      if (_step + 1 < _exercises.length) {
        _step += 1;
      } else {
        _finished = true;
      }
    });
  }

  void _tryAgain() => setState(() => _result = null);

  void _restart() {
    setState(() {
      _finished = false;
      _step = 0;
      _result = null;
      _answer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Symbols.close_rounded, color: c.textPrimary),
        ),
        titleSpacing: 0,
        title: _loading || _failed || _exercises.isEmpty
            ? Text(
                'Practice',
                style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              )
            : _StepBar(
                exercises: _exercises,
                step: _finished ? _exercises.length : _step,
              ),
        actions: const [SizedBox(width: 16)],
      ),
      body: SafeArea(top: false, child: _body(c)),
    );
  }

  Widget _body(AppColors c) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return Center(
        child: TextButton(
          onPressed: _load,
          child: const Text('Couldn\'t load practice — retry'),
        ),
      );
    }
    if (_exercises.isEmpty) {
      return Center(
        child: Text(
          'No practice for this lesson yet.',
          style: TextStyle(color: c.textSecondary),
        ),
      );
    }
    if (_finished) return _summary(c);

    final exercise = _current;
    final result = _result;
    final locked = result != null && result.correct;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(
                'TASK ${_step + 1} OF ${_exercises.length}',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                  color: c.textTertiary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                exercise.displayInstruction,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  height: 1.25,
                ),
              ),
              if (exercise.hint.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Symbols.lightbulb_rounded,
                      size: 18,
                      color: c.accentYellow,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        exercise.hint,
                        style: TextStyle(color: c.textSecondary, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              KeyedSubtree(
                key: ValueKey(exercise.id),
                child: switch (exercise.type) {
                  ReelExerciseType.sentenceBuilding => SentenceBuildingTask(
                    exercise: exercise,
                    locked: locked,
                    onChanged: (a) => setState(() => _answer = a),
                  ),
                  ReelExerciseType.fillGaps => FillGapsTask(
                    exercise: exercise,
                    locked: locked,
                    gapResults: result?.gapResults,
                    onChanged: (a) => setState(() => _answer = a),
                  ),
                  ReelExerciseType.writeSentence => WriteSentenceTask(
                    exercise: exercise,
                    locked: locked,
                    onChanged: (a) => setState(() => _answer = a),
                  ),
                  ReelExerciseType.unknown => Text(
                    'Update the app to open this task.',
                    style: TextStyle(color: c.textSecondary),
                  ),
                },
              ),
            ],
          ),
        ),
        _Footer(
          result: result,
          exercise: exercise,
          canCheck: _answer != null && !_checking,
          checking: _checking,
          onCheck: _check,
          onNext: _next,
          onTryAgain: _tryAgain,
        ),
      ],
    );
  }

  Widget _summary(AppColors c) {
    final progress = widget.lesson.progress;
    final solved = _exercises.where((e) => e.solved).length;
    final allSolved = solved == _exercises.length;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Icon(
            allSolved ? Symbols.task_alt_rounded : Symbols.pending_rounded,
            size: 72,
            color: allSolved ? c.success : c.accentYellow,
          ),
          const SizedBox(height: 16),
          Text(
            allSolved ? 'Practice complete!' : 'Almost there',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            allSolved
                ? progress.watched
                      ? 'This lesson is now green on your map.'
                      : 'Finish the video to turn this lesson green.'
                : '$solved of ${_exercises.length} tasks solved.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: c.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),
          ReelProgressMarkers(
            progress: progress,
            practiceRequired: widget.lesson.practiceRequired,
            size: 30,
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: c.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Back to lessons',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _restart,
            child: const Text('Review the tasks'),
          ),
        ],
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.exercises, required this.step});

  final List<ReelExercise> exercises;
  final int step;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        for (var i = 0; i < exercises.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: exercises[i].solved
                    ? c.success
                    : i == step
                    ? c.accentYellow
                    : c.surfaceAlt,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.result,
    required this.exercise,
    required this.canCheck,
    required this.checking,
    required this.onCheck,
    required this.onNext,
    required this.onTryAgain,
  });

  final ReelAnswerResult? result;
  final ReelExercise exercise;
  final bool canCheck;
  final bool checking;
  final VoidCallback onCheck;
  final VoidCallback onNext;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = result;
    final correct = r?.correct ?? false;
    final tone = r == null ? null : (correct ? c.success : c.error);
    final bg = r == null ? c.background : (correct ? c.successBg : c.errorBg);
    final reveal = r?.expected ?? (exercise.solved ? exercise.expected : null);
    final sample = r?.sampleAnswer;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: bg,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r != null) ...[
            Row(
              children: [
                Icon(
                  correct
                      ? Symbols.check_circle_rounded
                      : Symbols.cancel_rounded,
                  fill: 1,
                  color: tone,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.feedback,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: tone,
                    ),
                  ),
                ),
              ],
            ),
            if (reveal != null &&
                reveal.isNotEmpty &&
                exercise.type != ReelExerciseType.writeSentence) ...[
              const SizedBox(height: 6),
              Text(
                correct ? reveal : 'Answer: $reveal',
                style: TextStyle(fontSize: 14, color: c.textPrimary),
              ),
            ],
            if (sample != null && sample.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                exercise.type == ReelExerciseType.writeSentence
                    ? 'Example: $sample'
                    : sample,
                style: TextStyle(fontSize: 14, color: c.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            height: 52,
            child: r == null
                ? FilledButton(
                    onPressed: canCheck ? onCheck : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.success,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: c.surfaceAlt,
                      disabledForegroundColor: c.textTertiary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: checking
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Check',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  )
                : Row(
                    children: [
                      if (!correct) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onTryAgain,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              foregroundColor: c.textPrimary,
                              side: BorderSide(color: c.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Try again',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: FilledButton(
                          onPressed: onNext,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            backgroundColor: correct ? c.success : c.brand,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            correct ? 'Continue' : 'Skip',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// --- Task widgets -----------------------------------------------------------

/// Tap word tiles to build the sentence; tap a placed tile to take it back.
/// Reports the tiles in order, or null until every tile is placed.
class SentenceBuildingTask extends StatefulWidget {
  const SentenceBuildingTask({
    super.key,
    required this.exercise,
    required this.locked,
    required this.onChanged,
  });

  final ReelExercise exercise;
  final bool locked;
  final ValueChanged<List<String>?> onChanged;

  @override
  State<SentenceBuildingTask> createState() => _SentenceBuildingTaskState();
}

class _SentenceBuildingTaskState extends State<SentenceBuildingTask> {
  /// Indices into the tile bank, in the order the student placed them.
  final List<int> _placed = [];

  void _emit() {
    // Distractors may stay in the bank, so any non-empty order is submittable.
    widget.onChanged(
      _placed.isEmpty
          ? null
          : [for (final i in _placed) widget.exercise.tiles[i]],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tiles = widget.exercise.tiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.locked ? c.success : c.border,
              width: 1.5,
            ),
          ),
          child: _placed.isEmpty
              ? Center(
                  child: Text(
                    'Tap the words below',
                    style: TextStyle(color: c.textTertiary),
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var p = 0; p < _placed.length; p++)
                      _Tile(
                        text: tiles[_placed[p]],
                        highlighted: true,
                        onTap: widget.locked
                            ? null
                            : () {
                                setState(() => _placed.removeAt(p));
                                _emit();
                              },
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < tiles.length; i++)
              _Tile(
                text: tiles[i],
                used: _placed.contains(i),
                onTap: widget.locked || _placed.contains(i)
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        setState(() => _placed.add(i));
                        _emit();
                      },
              ),
          ],
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.text,
    this.onTap,
    this.used = false,
    this.highlighted = false,
  });

  final String text;
  final VoidCallback? onTap;
  final bool used;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: used ? 0.25 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlighted
                  ? c.textPrimary.withValues(alpha: 0.4)
                  : c.border,
              width: 1.5,
            ),
            boxShadow: [BoxShadow(color: c.border, offset: const Offset(0, 2))],
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The text with an inline field per gap. Reports one string per gap, or
/// null until every gap has something in it.
class FillGapsTask extends StatefulWidget {
  const FillGapsTask({
    super.key,
    required this.exercise,
    required this.locked,
    required this.gapResults,
    required this.onChanged,
  });

  final ReelExercise exercise;
  final bool locked;
  final List<bool>? gapResults;
  final ValueChanged<List<String>?> onChanged;

  @override
  State<FillGapsTask> createState() => _FillGapsTaskState();
}

class _FillGapsTaskState extends State<FillGapsTask> {
  late final List<TextEditingController> _fields;

  @override
  void initState() {
    super.initState();
    final count = widget.exercise.gapCount > 0
        ? widget.exercise.gapCount
        : widget.exercise.segments.where((s) => s.isGap).length;
    _fields = List.generate(count, (_) => TextEditingController());
  }

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final values = _fields.map((f) => f.text.trim()).toList();
    widget.onChanged(values.any((v) => v.isEmpty) ? null : values);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(fontSize: 19, height: 2.1, color: c.textPrimary);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final segment in widget.exercise.segments)
            if (!segment.isGap)
              TextSpan(text: segment.text)
            else if (segment.gapIndex! < _fields.length)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _gapField(c, segment.gapIndex!),
              ),
        ],
      ),
    );
  }

  Widget _gapField(AppColors c, int index) {
    final results = widget.gapResults;
    final ok = results != null && index < results.length
        ? results[index]
        : null;
    final color = widget.locked || ok == true
        ? c.success
        : ok == false
        ? c.error
        : c.accentBlue;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: IntrinsicWidth(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 72),
          child: TextField(
            controller: _fields[index],
            enabled: !widget.locked,
            autocorrect: false,
            enableSuggestions: false,
            textAlign: TextAlign.center,
            textInputAction: index == _fields.length - 1
                ? TextInputAction.done
                : TextInputAction.next,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 6,
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: color, width: 2),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: color, width: 2.5),
              ),
              disabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: color, width: 2),
              ),
            ),
            onChanged: (_) => _emit(),
          ),
        ),
      ),
    );
  }
}

/// A free-text sentence with live checks for the required words and length.
class WriteSentenceTask extends StatefulWidget {
  const WriteSentenceTask({
    super.key,
    required this.exercise,
    required this.locked,
    required this.onChanged,
  });

  final ReelExercise exercise;
  final bool locked;
  final ValueChanged<String?> onChanged;

  @override
  State<WriteSentenceTask> createState() => _WriteSentenceTaskState();
}

class _WriteSentenceTaskState extends State<WriteSentenceTask> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[’‘`]'), "'")
      .replaceAll(RegExp(r"[^\w\s']"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _uses(String phrase) {
    final target = _norm(phrase);
    if (target.isEmpty) return true;
    return RegExp(
      "(?<![\\w'])${RegExp.escape(target)}(?![\\w'])",
    ).hasMatch(_norm(_text.text));
  }

  int get _wordCount =>
      _norm(_text.text).split(' ').where((w) => w.isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ex = widget.exercise;
    final enough = _wordCount >= ex.minWords;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ex.prompt.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              ex.prompt,
              style: TextStyle(fontSize: 16, color: c.textPrimary, height: 1.4),
            ),
          ),
        if (ex.requiredWords.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final word in ex.requiredWords)
                _Requirement(label: word, met: _uses(word)),
            ],
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _text,
          enabled: !widget.locked,
          minLines: 3,
          maxLines: 6,
          maxLength: 400,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(fontSize: 17, color: c.textPrimary, height: 1.4),
          decoration: InputDecoration(
            hintText: 'Write your sentence…',
            hintStyle: TextStyle(color: c.textTertiary),
            filled: true,
            fillColor: c.surface,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: c.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: c.border, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: c.accentBlue, width: 1.5),
            ),
          ),
          onChanged: (value) {
            setState(() {});
            widget.onChanged(value.trim().isEmpty ? null : value.trim());
          },
        ),
        const SizedBox(height: 8),
        Text(
          '$_wordCount / ${ex.minWords} words',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: enough ? c.success : c.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _Requirement extends StatelessWidget {
  const _Requirement({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: met ? c.successBg : c.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            met ? Symbols.check_rounded : Symbols.add_rounded,
            size: 16,
            color: met ? c.success : c.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: met ? c.success : c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
