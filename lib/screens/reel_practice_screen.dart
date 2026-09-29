import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/course_reel.dart';
import '../services/api_service.dart';
import '../services/course_reels_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import '../widgets/reel_progress_markers.dart';

String _typeLabel(ReelExerciseType type) => switch (type) {
  ReelExerciseType.sentenceBuilding => 'Build the sentence',
  ReelExerciseType.fillGaps => 'Fill in the gaps',
  ReelExerciseType.writeSentence => 'Write a sentence',
  ReelExerciseType.multipleChoice => 'Choose the answer',
  ReelExerciseType.transformSentence => 'Rewrite the sentence',
  ReelExerciseType.chooseGaps => 'Choose for each gap',
  ReelExerciseType.writingAi => 'Writing',
  ReelExerciseType.speakingAi => 'Speaking',
  ReelExerciseType.unknown => 'More practice',
};

IconData _typeIcon(ReelExerciseType type) => switch (type) {
  ReelExerciseType.sentenceBuilding => Symbols.view_week_rounded,
  ReelExerciseType.fillGaps => Symbols.edit_note_rounded,
  ReelExerciseType.writeSentence => Symbols.edit_rounded,
  ReelExerciseType.multipleChoice => Symbols.checklist_rounded,
  ReelExerciseType.transformSentence => Symbols.change_circle_rounded,
  ReelExerciseType.chooseGaps => Symbols.format_list_bulleted_rounded,
  ReelExerciseType.writingAi => Symbols.edit_document_rounded,
  ReelExerciseType.speakingAi => Symbols.mic_rounded,
  ReelExerciseType.unknown => Symbols.quiz_rounded,
};

/// One part of a lesson's practice: the next [size] questions in the order
/// the admin sorted them, so a lesson of 50 exercises is 5 parts of 10.
class PracticePart {
  PracticePart(this.first, this.questions);

  static const size = 10;

  /// 1-based number of this part's first question within the lesson.
  final int first;
  final List<ReelExercise> questions;

  int get last => first + questions.length - 1;
  int get solved => questions.where((q) => q.solved).length;
  bool get done => solved == questions.length;

  /// The kinds of question in this part, in first-seen order.
  List<ReelExerciseType> get types =>
      {for (final q in questions) q.type}.toList();

  static List<PracticePart> split(
    List<ReelExercise> exercises, {
    int size = PracticePart.size,
  }) => [
    for (var i = 0; i < exercises.length; i += size)
      PracticePart(
        i + 1,
        exercises.sublist(i, (i + size).clamp(0, exercises.length)),
      ),
  ];
}

/// The practice for one lesson. The page lists its parts collapsed, so the
/// student sees how much there is; tapping one opens it full screen
/// ([PracticePartScreen]) and walks its questions one at a time.
///
/// Answers are checked by the server, which also marks the lesson's practice
/// complete (the green marker) once every required question is solved. The
/// screens write the resulting progress back onto [lesson], so whoever pushed
/// this one only has to rebuild when it pops.
class ReelPracticeScreen extends StatefulWidget {
  const ReelPracticeScreen({super.key, required this.lesson, this.practice});

  final ReelLesson lesson;

  /// Already loaded; skips the fetch (tests).
  @visibleForTesting
  final ReelPractice? practice;

  @override
  State<ReelPracticeScreen> createState() => _ReelPracticeScreenState();
}

class _ReelPracticeScreenState extends State<ReelPracticeScreen> {
  List<PracticePart> _parts = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final preloaded = widget.practice;
    if (preloaded != null) {
      _apply(preloaded);
    } else {
      _load();
    }
  }

  void _apply(ReelPractice practice) {
    _parts = PracticePart.split(practice.exercises);
    widget.lesson.progress = practice.progress;
    _loading = false;
    _failed = false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final practice = await CourseReelsService.fetchPractice(widget.lesson.id);
      if (!mounted) return;
      setState(() => _apply(practice));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  int get _questionCount => _parts.fold(0, (n, p) => n + p.questions.length);
  int get _solvedCount => _parts.fold(0, (n, p) => n + p.solved);

  /// The part to suggest: the first one with something left to solve.
  int? get _nextPart {
    final i = _parts.indexWhere((p) => !p.done);
    return i < 0 ? null : i;
  }

  Future<void> _openPart(int i) async {
    final goNext = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PracticePartScreen(
          lesson: widget.lesson,
          part: _parts[i],
          number: i + 1,
          hasNext: i + 1 < _parts.length,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {}); // solved counts and markers changed on the way
    if (goNext == true && i + 1 < _parts.length) _openPart(i + 1);
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
        title: Text(
          'Practice',
          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700),
        ),
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
    if (_parts.isEmpty) {
      return Center(
        child: Text(
          'No practice for this lesson yet.',
          style: TextStyle(color: c.textSecondary),
        ),
      );
    }
    final next = _nextPart;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _overview(c),
        const SizedBox(height: 16),
        for (final (i, part) in _parts.indexed) ...[
          _PartCard(
            number: i + 1,
            part: part,
            suggested: i == next,
            onTap: () => _openPart(i),
          ),
          const SizedBox(height: 12),
        ],
        if (next == null) ...[
          const SizedBox(height: 8),
          SizedBox(
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
        ],
      ],
    );
  }

  /// How much there is, how much is done, and the lesson's markers.
  Widget _overview(AppColors c) {
    final progress = widget.lesson.progress;
    final total = _questionCount;
    final solved = _solvedCount;
    final allSolved = solved == total;
    final parts = _parts.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: allSolved ? c.successBg : c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: allSolved ? c.success : c.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allSolved
                      ? 'Practice complete!'
                      : '$parts ${parts == 1 ? 'part' : 'parts'} · '
                            '$total ${total == 1 ? 'question' : 'questions'}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  allSolved
                      ? progress.watched
                            ? 'This lesson is now green on your map.'
                            : 'Finish the video to turn this lesson green.'
                      : '$solved of $total solved · open a part to start',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: c.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : solved / total,
                    minHeight: 8,
                    backgroundColor: c.surfaceAlt,
                    color: c.success,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          ReelProgressMarkers(
            progress: progress,
            practiceRequired: widget.lesson.practiceRequired,
            size: 26,
          ),
        ],
      ),
    );
  }
}

/// A collapsed part: number, which questions it holds, what kinds, and how
/// far the student got. Tapping it opens the part full screen.
class _PartCard extends StatelessWidget {
  const _PartCard({
    required this.number,
    required this.part,
    required this.suggested,
    required this.onTap,
  });

  final int number;
  final PracticePart part;

  /// The first part with work left — outlined and labelled Start/Continue.
  final bool suggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = part.done;
    final solved = part.solved;
    final count = part.questions.length;
    final action = done
        ? 'Review'
        : solved > 0
        ? 'Continue'
        : 'Start';
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: suggested ? c.success : c.border,
              width: suggested ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? c.success : c.surfaceAlt,
                  shape: BoxShape.circle,
                ),
                child: done
                    ? const Icon(
                        Symbols.check_rounded,
                        size: 26,
                        weight: 700,
                        color: Colors.white,
                      )
                    : Text(
                        '$number',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'PART $number',
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                            color: c.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Wrap(
                            spacing: 4,
                            children: [
                              for (final type in part.types)
                                Icon(
                                  _typeIcon(type),
                                  size: 15,
                                  color: c.textTertiary,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count == 1
                          ? 'Question ${part.first}'
                          : 'Questions ${part.first}–${part.last}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: solved / count,
                              minHeight: 6,
                              backgroundColor: c.surfaceAlt,
                              color: c.success,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '$solved/$count',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: done ? c.success : c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (suggested)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: c.success,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    action,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                Icon(Symbols.chevron_right_rounded, color: c.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// One part, full screen, one question at a time: answer, Check, see the
/// result, Continue. Wrong answers can be retried or skipped. Walks only the
/// part's unsolved questions (all of them when the part is already done, as
/// a review), then shows a summary. Pops `true` when the student asks for the
/// next part.
class PracticePartScreen extends StatefulWidget {
  const PracticePartScreen({
    super.key,
    required this.lesson,
    required this.part,
    required this.number,
    required this.hasNext,
  });

  final ReelLesson lesson;
  final PracticePart part;
  final int number;
  final bool hasNext;

  @override
  State<PracticePartScreen> createState() => _PracticePartScreenState();
}

class _PracticePartScreenState extends State<PracticePartScreen> {
  List<ReelExercise> get _questions => widget.part.questions;

  /// Review mode: the part was already done when opened, so every question
  /// is shown; otherwise solved ones are passed over.
  late final bool _review = widget.part.done;

  late int _index;
  bool _finished = false;

  Object? _answer;
  ReelAnswerResult? _result;
  bool _checking = false;

  /// Checked wrong at least once this visit and not solved yet (red segment).
  final Set<int> _missed = {};

  @override
  void initState() {
    super.initState();
    _index = _review ? 0 : _nextFrom(0) ?? 0;
  }

  ReelExercise get _question => _questions[_index];

  /// The first question at or after [from] to walk through, or null.
  int? _nextFrom(int from) {
    for (var i = from; i < _questions.length; i++) {
      if (_review || !_questions[i].solved) return i;
    }
    return null;
  }

  void _goTo(int? i) {
    setState(() {
      _answer = null;
      _result = null;
      if (i == null) {
        _finished = true;
      } else {
        _index = i;
        _finished = false;
      }
    });
  }

  void _next() => _goTo(_nextFrom(_index + 1));

  /// From the summary: back through whatever is still unsolved.
  void _retryUnsolved() {
    final i = _questions.indexWhere((q) => !q.solved);
    if (i >= 0) _goTo(i);
  }

  Future<void> _check() async {
    final question = _question;
    final answer = _answer;
    if (answer == null || _checking) return;
    setState(() => _checking = true);
    try {
      final result = question.type == ReelExerciseType.speakingAi
          ? await CourseReelsService.submitSpeaking(
              question.id,
              File(answer as String),
            )
          : await CourseReelsService.submitAnswer(question.id, answer);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _result = result;
        question
          ..solved = result.solved
          ..attempts = result.attempts
          ..expected = result.expected
          ..sampleAnswer = result.sampleAnswer;
        if (result.solved) {
          _missed.remove(question.id);
        } else {
          _missed.add(question.id);
        }
        widget.lesson.progress = result.lessonProgress;
      });
    } catch (e) {
      if (mounted) {
        // 503 (AI down) and 429 (too many AI checks) say what happened.
        final message = e is ApiException && e.statusCode >= 429
            ? e.message
            : 'Couldn\'t check your answer';
        AppNotify.show(context, message: message);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _tryAgain() => setState(() => _result = null);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _topBar(c),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0.08, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: _finished
                    ? _Summary(
                        key: const ValueKey('summary'),
                        number: widget.number,
                        part: widget.part,
                      )
                    : _QuestionView(
                        // A fresh answer widget per question.
                        key: ValueKey(_question.id),
                        question: _question,
                        result: _result,
                        onChanged: (a) => setState(() => _answer = a),
                      ),
              ),
            ),
            _bottomBar(c),
          ],
        ),
      ),
    );
  }

  /// Close, then one segment per question: green solved, red missed,
  /// outlined current.
  Widget _topBar(AppColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: Icon(Symbols.close_rounded, color: c.textPrimary),
          ),
          Expanded(
            child: Row(
              children: [
                for (final (i, q) in _questions.indexed) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 8,
                      decoration: BoxDecoration(
                        color: q.solved
                            ? c.success
                            : _missed.contains(q.id)
                            ? c.error
                            : c.surfaceAlt,
                        borderRadius: BorderRadius.circular(4),
                        border: !_finished && i == _index
                            ? Border.all(color: c.textPrimary, width: 1.5)
                            : null,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _finished
                ? 'Part ${widget.number}'
                : '${_index + 1}/${_questions.length}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(AppColors c) {
    final Widget content;
    if (_finished) {
      final unsolved = widget.part.questions.length - widget.part.solved;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (unsolved > 0) ...[
            _SecondaryButton(
              label: 'Retry $unsolved unsolved',
              onPressed: _retryUnsolved,
            ),
            const SizedBox(height: 10),
          ],
          _PrimaryButton(
            label: widget.hasNext ? 'Next part' : 'Back to parts',
            onPressed: () => Navigator.pop(context, widget.hasNext),
          ),
        ],
      );
    } else {
      final r = _result;
      final q = _question;
      // Solved on an earlier visit: nothing to answer, just move on.
      final passed = (r?.correct ?? false) || (q.solved && r == null);
      if (passed || q.type == ReelExerciseType.unknown) {
        content = _PrimaryButton(label: 'Continue', onPressed: _next);
      } else if (r != null) {
        content = Row(
          children: [
            Expanded(
              child: _SecondaryButton(label: 'Skip', onPressed: _next),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PrimaryButton(label: 'Try again', onPressed: _tryAgain),
            ),
          ],
        );
      } else {
        content = Row(
          children: [
            TextButton(
              onPressed: _next,
              style: TextButton.styleFrom(foregroundColor: c.textSecondary),
              child: const Text(
                'Skip',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PrimaryButton(
                label: 'Check',
                loading: _checking,
                loadingLabel: q.type.isAi ? 'Checking with AI…' : null,
                onPressed: _answer != null && !_checking ? _check : null,
              ),
            ),
          ],
        );
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: content,
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.loadingLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  /// Shown next to the spinner (the AI takes a few seconds).
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: c.success,
          foregroundColor: Colors.white,
          disabledBackgroundColor: c.surfaceAlt,
          disabledForegroundColor: c.textTertiary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: loading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                  if (loadingLabel != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      loadingLabel!,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ],
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// One question filling the page: its kind, instruction, hint, the answer
/// widget and, once checked, the feedback.
class _QuestionView extends StatelessWidget {
  const _QuestionView({
    super.key,
    required this.question,
    required this.result,
    required this.onChanged,
  });

  final ReelExercise question;
  final ReelAnswerResult? result;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = result;
    final solvedBefore = question.solved && r == null;
    final locked = r?.correct ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(_typeIcon(question.type), size: 18, color: c.textTertiary),
              const SizedBox(width: 6),
              Text(
                _typeLabel(question.type).toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                  color: c.textTertiary,
                ),
              ),
              const Spacer(),
              if (question.solved)
                Icon(
                  Symbols.check_circle_rounded,
                  fill: 1,
                  size: 22,
                  color: c.success,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            question.displayInstruction,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
              height: 1.25,
            ),
          ),
          if (question.hint.isNotEmpty && !solvedBefore) ...[
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
                    question.hint,
                    style: TextStyle(color: c.textSecondary, fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
          if (question.imageUrl != null) ...[
            const SizedBox(height: 16),
            _ExerciseImage(url: question.imageUrl!),
          ],
          const SizedBox(height: 24),
          if (solvedBefore)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.successBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                question.expected ?? question.sampleAnswer ?? 'Solved',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.success,
                ),
              ),
            )
          else ...[
            switch (question.type) {
              ReelExerciseType.sentenceBuilding => SentenceBuildingTask(
                exercise: question,
                locked: locked,
                onChanged: onChanged,
              ),
              ReelExerciseType.fillGaps => FillGapsTask(
                exercise: question,
                locked: locked,
                gapResults: r?.gapResults,
                onChanged: onChanged,
              ),
              ReelExerciseType.writeSentence => WriteSentenceTask(
                exercise: question,
                locked: locked,
                onChanged: onChanged,
              ),
              ReelExerciseType.multipleChoice => MultipleChoiceTask(
                exercise: question,
                locked: locked,
                wrong: r != null && !r.correct,
                onChanged: onChanged,
              ),
              ReelExerciseType.transformSentence => TransformSentenceTask(
                exercise: question,
                locked: locked,
                onChanged: onChanged,
              ),
              ReelExerciseType.chooseGaps => ChooseGapsTask(
                exercise: question,
                locked: locked,
                gapResults: r?.gapResults,
                onChanged: onChanged,
              ),
              ReelExerciseType.writingAi => AiWritingTask(
                exercise: question,
                locked: locked,
                onChanged: onChanged,
              ),
              ReelExerciseType.speakingAi => AiSpeakingTask(
                exercise: question,
                locked: locked,
                onChanged: onChanged,
              ),
              ReelExerciseType.unknown => Text(
                'Update the app to open this question.',
                style: TextStyle(color: c.textSecondary),
              ),
            },
            if (r != null) ...[
              const SizedBox(height: 16),
              _Feedback(result: r, question: question),
            ],
          ],
        ],
      ),
    );
  }
}

/// End of a part: how it went.
class _Summary extends StatelessWidget {
  const _Summary({super.key, required this.number, required this.part});

  final int number;
  final PracticePart part;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final solved = part.solved;
    final count = part.questions.length;
    final done = part.done;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: done ? c.success : c.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(
                done ? Symbols.emoji_events_rounded : Symbols.flag_rounded,
                size: 48,
                fill: done ? 1 : 0,
                color: done ? Colors.white : c.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              done ? 'Part $number complete!' : 'Part $number finished',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              done
                  ? 'All $count questions solved.'
                  : '$solved of $count solved — try the rest again or '
                        'come back later.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: c.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Right / wrong, plus the answer once the server reveals it.
class _Feedback extends StatelessWidget {
  const _Feedback({required this.result, required this.question});

  final ReelAnswerResult result;
  final ReelExercise question;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final correct = result.correct;
    final tone = correct ? c.success : c.error;
    final reveal = result.expected;
    final sample = result.sampleAnswer;
    // Answers with no single right version: the sample is an example.
    final freeText =
        question.type == ReelExerciseType.writeSentence || question.type.isAi;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: correct ? c.successBg : c.errorBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                correct ? Symbols.check_circle_rounded : Symbols.cancel_rounded,
                fill: 1,
                size: 20,
                color: tone,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.feedback,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tone,
                  ),
                ),
              ),
            ],
          ),
          if (result.ai case final review?)
            _AiReviewView(review: review, passed: correct),
          if (reveal != null && reveal.isNotEmpty && !freeText) ...[
            const SizedBox(height: 6),
            Text(
              correct ? reveal : 'Answer: $reveal',
              style: TextStyle(fontSize: 14, color: c.textPrimary),
            ),
          ],
          if (sample != null && sample.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              freeText ? 'Example: $sample' : sample,
              style: TextStyle(fontSize: 14, color: c.textSecondary),
            ),
          ],
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

/// Text options, one per card, no letters. Reports the chosen option's text.
class MultipleChoiceTask extends StatefulWidget {
  const MultipleChoiceTask({
    super.key,
    required this.exercise,
    required this.locked,
    required this.wrong,
    required this.onChanged,
  });

  final ReelExercise exercise;
  final bool locked;

  /// The last check said the chosen option is wrong.
  final bool wrong;
  final ValueChanged<String?> onChanged;

  @override
  State<MultipleChoiceTask> createState() => _MultipleChoiceTaskState();
}

class _MultipleChoiceTaskState extends State<MultipleChoiceTask> {
  int? _chosen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ex = widget.exercise;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ex.prompt.isNotEmpty) ...[
          _PromptCard(text: ex.prompt),
          const SizedBox(height: 18),
        ],
        for (final (i, option) in ex.options.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          Builder(
            builder: (context) {
              final chosen = _chosen == i;
              final tone = !chosen
                  ? c.border
                  : widget.locked
                  ? c.success
                  : widget.wrong
                  ? c.error
                  : c.accentBlue;
              return Material(
                color: chosen && widget.locked
                    ? c.successBg
                    : chosen && widget.wrong
                    ? c.errorBg
                    : c.surface,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: widget.locked
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          setState(() => _chosen = i);
                          widget.onChanged(option);
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: tone, width: chosen ? 2 : 1.5),
                    ),
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: chosen ? FontWeight.w700 : FontWeight.w500,
                        color: c.textPrimary,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

/// A sentence to change and a field for the rewritten one.
class TransformSentenceTask extends StatefulWidget {
  const TransformSentenceTask({
    super.key,
    required this.exercise,
    required this.locked,
    required this.onChanged,
  });

  final ReelExercise exercise;
  final bool locked;
  final ValueChanged<String?> onChanged;

  @override
  State<TransformSentenceTask> createState() => _TransformSentenceTaskState();
}

class _TransformSentenceTaskState extends State<TransformSentenceTask> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PromptCard(text: widget.exercise.sentence),
        const SizedBox(height: 10),
        Center(
          child: Icon(
            Symbols.arrow_downward_rounded,
            color: c.textTertiary,
            size: 22,
          ),
        ),
        const SizedBox(height: 10),
        _AnswerField(
          controller: _text,
          enabled: !widget.locked,
          hint: 'Write the new sentence…',
          minLines: 2,
          maxLines: 4,
          success: widget.locked,
          onChanged: (v) =>
              widget.onChanged(v.trim().isEmpty ? null : v.trim()),
        ),
      ],
    );
  }
}

/// A text whose gaps are picked from each gap's own 3–4 options: tap a gap,
/// then one of the options under the text. Choosing moves on to the next
/// empty gap. Reports the chosen texts in gap order, or null until all are
/// filled.
class ChooseGapsTask extends StatefulWidget {
  const ChooseGapsTask({
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
  State<ChooseGapsTask> createState() => _ChooseGapsTaskState();
}

class _ChooseGapsTaskState extends State<ChooseGapsTask> {
  late final List<String?> _picked = List.filled(
    widget.exercise.gapOptions.length,
    null,
  );
  int _active = 0;

  void _pick(String option) {
    HapticFeedback.selectionClick();
    setState(() {
      _picked[_active] = option;
      // On to the next empty gap, wrapping around; stay put when all are full.
      for (var step = 1; step <= _picked.length; step++) {
        final i = (_active + step) % _picked.length;
        if (_picked[i] == null) {
          _active = i;
          break;
        }
      }
    });
    widget.onChanged(
      _picked.any((p) => p == null) ? null : List<String>.from(_picked),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ex = widget.exercise;
    final options = _active < ex.gapOptions.length
        ? ex.gapOptions[_active]
        : const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 19, height: 2.1, color: c.textPrimary),
            children: [
              for (final segment in ex.segments)
                if (!segment.isGap)
                  TextSpan(text: segment.text)
                else if (segment.gapIndex! < _picked.length)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: _gap(c, segment.gapIndex!),
                  ),
            ],
          ),
        ),
        if (!widget.locked && options.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'GAP ${_active + 1}',
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
              color: c.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: [
              for (final option in options)
                _Tile(
                  text: option,
                  highlighted: _picked[_active] == option,
                  onTap: () => _pick(option),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _gap(AppColors c, int index) {
    final results = widget.gapResults;
    final ok = results != null && index < results.length
        ? results[index]
        : null;
    final active = !widget.locked && index == _active;
    final color = widget.locked || ok == true
        ? c.success
        : ok == false
        ? c.error
        : c.accentBlue;
    final text = _picked[index];
    return GestureDetector(
      onTap: widget.locked ? null : () => setState(() => _active = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        constraints: const BoxConstraints(minWidth: 64),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border(bottom: BorderSide(color: color, width: 2.5)),
        ),
        child: Text(
          text ?? ' ',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            height: 1.4,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// A longer written answer the AI marks: the task, required words, a word
/// count against the minimum.
class AiWritingTask extends StatefulWidget {
  const AiWritingTask({
    super.key,
    required this.exercise,
    required this.locked,
    required this.onChanged,
  });

  final ReelExercise exercise;
  final bool locked;
  final ValueChanged<String?> onChanged;

  @override
  State<AiWritingTask> createState() => _AiWritingTaskState();
}

class _AiWritingTaskState extends State<AiWritingTask> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _wordCount =>
      _text.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ex = widget.exercise;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ex.prompt.isNotEmpty) _PromptCard(text: ex.prompt),
        if (ex.requiredWords.isNotEmpty) ...[
          const SizedBox(height: 12),
          _RequiredWords(words: ex.requiredWords),
        ],
        const SizedBox(height: 16),
        _AnswerField(
          controller: _text,
          enabled: !widget.locked,
          hint: 'Write your answer…',
          minLines: 5,
          maxLines: 12,
          maxLength: 4000,
          success: widget.locked,
          onChanged: (v) {
            setState(() {});
            widget.onChanged(v.trim().isEmpty ? null : v.trim());
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              ex.minWords > 0
                  ? '$_wordCount / ${ex.minWords} words'
                  : '$_wordCount words',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _wordCount >= ex.minWords ? c.success : c.textTertiary,
              ),
            ),
            const Spacer(),
            const _AiBadge(),
          ],
        ),
      ],
    );
  }
}

/// Record a spoken answer the AI marks. Reports the recording's file path
/// once there is a usable take, null while recording or with none.
class AiSpeakingTask extends StatefulWidget {
  const AiSpeakingTask({
    super.key,
    required this.exercise,
    required this.locked,
    required this.onChanged,
  });

  final ReelExercise exercise;
  final bool locked;
  final ValueChanged<String?> onChanged;

  @override
  State<AiSpeakingTask> createState() => _AiSpeakingTaskState();
}

class _AiSpeakingTaskState extends State<AiSpeakingTask> {
  static const _maxSeconds = 120;
  static const _minBytes = 2000;

  final _recorder = AudioRecorder();
  final _player = ap.AudioPlayer();
  StreamSubscription<void>? _playerDone;
  Timer? _timer;

  bool _recording = false;
  bool _playing = false;
  int _elapsed = 0;
  String? _take;
  int _takeSeconds = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _playerDone = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _playerDone?.cancel();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        setState(() => _error = 'Allow the microphone to record your answer.');
      }
      return;
    }
    await _player.stop();
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/reel_answer_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100),
      path: path,
    );
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    widget.onChanged(null);
    setState(() {
      _recording = true;
      _playing = false;
      _elapsed = 0;
      _error = null;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
      if (_elapsed >= _maxSeconds) _stop();
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    _timer = null;
    final seconds = _elapsed;
    final path = await _recorder.stop();
    if (!mounted) return;
    final usable =
        path != null &&
        seconds >= 1 &&
        await File(path).exists() &&
        await File(path).length() >= _minBytes;
    if (!mounted) return;
    setState(() {
      _recording = false;
      if (usable) {
        _take = path;
        _takeSeconds = seconds;
      } else {
        _error = 'That recording was too short — try again.';
      }
    });
    widget.onChanged(_take);
  }

  Future<void> _togglePlay() async {
    final take = _take;
    if (take == null) return;
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    await _player.play(ap.DeviceFileSource(take));
    if (mounted) setState(() => _playing = true);
  }

  static String _clock(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ex = widget.exercise;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ex.prompt.isNotEmpty) _PromptCard(text: ex.prompt),
        if (ex.requiredWords.isNotEmpty) ...[
          const SizedBox(height: 12),
          _RequiredWords(words: ex.requiredWords),
        ],
        const SizedBox(height: 28),
        if (!widget.locked)
          Center(
            child: Semantics(
              button: true,
              label: _recording ? 'Stop recording' : 'Record your answer',
              child: GestureDetector(
                onTap: _recording ? _stop : _start,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: _recording ? c.error : c.success,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_recording ? c.error : c.success).withValues(
                          alpha: 0.35,
                        ),
                        blurRadius: _recording ? 24 : 12,
                        spreadRadius: _recording ? 4 : 0,
                      ),
                    ],
                  ),
                  child: Icon(
                    _recording ? Symbols.stop_rounded : Symbols.mic_rounded,
                    fill: 1,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          _recording
              ? 'Recording… ${_clock(_elapsed)} / ${_clock(_maxSeconds)}'
              : _take != null
              ? 'Tap the mic to record again'
              : 'Tap the mic and speak'
                    '${ex.minWords > 0 ? ' — at least ${ex.minWords} words' : ''}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _recording ? c.error : c.textSecondary,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: c.error),
          ),
        ],
        if (_take != null && !_recording) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: _playing ? 'Pause' : 'Play your answer',
                  onPressed: _togglePlay,
                  icon: Icon(
                    _playing
                        ? Symbols.pause_rounded
                        : Symbols.play_arrow_rounded,
                    fill: 1,
                    color: c.textPrimary,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Your answer',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                Text(
                  _clock(_takeSeconds),
                  style: TextStyle(fontSize: 14, color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Align(alignment: Alignment.centerRight, child: _AiBadge()),
      ],
    );
  }
}

/// The exercise's picture; tap to open it full screen and zoom.
class _ExerciseImage extends StatelessWidget {
  const _ExerciseImage({required this.url});

  final String url;

  void _openFullScreen(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.pop(dialogContext),
        child: InteractiveViewer(
          maxScale: 5,
          child: Center(child: Image.network(url, fit: BoxFit.contain)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: Container(
            width: double.infinity,
            color: c.surfaceAlt,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator()),
                    ),
              errorBuilder: (context, error, stack) => SizedBox(
                height: 120,
                child: Center(
                  child: Icon(
                    Symbols.broken_image_rounded,
                    size: 32,
                    color: c.textTertiary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
          height: 1.4,
        ),
      ),
    );
  }
}

class _RequiredWords extends StatelessWidget {
  const _RequiredWords({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Use:',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: c.textSecondary,
          ),
        ),
        for (final w in words) _Requirement(label: w, met: false),
      ],
    );
  }
}

class _AnswerField extends StatelessWidget {
  const _AnswerField({
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.minLines,
    required this.maxLines,
    required this.success,
    required this.onChanged,
    this.maxLength = 400,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final int minLines;
  final int maxLines;
  final int maxLength;
  final bool success;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: 1.5),
    );
    return TextField(
      controller: controller,
      enabled: enabled,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(fontSize: 17, color: c.textPrimary, height: 1.4),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: c.textTertiary),
        filled: true,
        fillColor: c.surface,
        counterText: '',
        border: border(c.border),
        enabledBorder: border(c.border),
        disabledBorder: border(success ? c.success : c.border),
        focusedBorder: border(c.accentBlue),
      ),
      onChanged: onChanged,
    );
  }
}

class _AiBadge extends StatelessWidget {
  const _AiBadge();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Symbols.auto_awesome_rounded, size: 15, color: c.textTertiary),
        const SizedBox(width: 4),
        Text(
          'Checked by AI',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: c.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// The AI's marking under the feedback line: score against the pass mark,
/// what it heard (speaking), each correction, and a better version.
class _AiReviewView extends StatelessWidget {
  const _AiReviewView({required this.review, required this.passed});

  final ReelAiReview review;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final score = review.score;
    TextStyle label() => TextStyle(
      fontSize: 10.5,
      letterSpacing: 1,
      fontWeight: FontWeight.w800,
      color: c.textTertiary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (score != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '$score',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: passed ? c.success : c.error,
                ),
              ),
              Text(
                ' / 100',
                style: TextStyle(fontSize: 15, color: c.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Pass mark ${review.passScore}',
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
              ),
            ],
          ),
        ],
        if (review.transcript != null) ...[
          const SizedBox(height: 12),
          Text('WE HEARD', style: label()),
          const SizedBox(height: 4),
          Text(
            review.transcript!,
            style: TextStyle(
              fontSize: 14.5,
              fontStyle: FontStyle.italic,
              color: c.textPrimary,
              height: 1.4,
            ),
          ),
        ],
        if (review.corrections.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('CORRECTIONS', style: label()),
          for (final fix in review.corrections) ...[
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 14.5, color: c.textPrimary),
                children: [
                  TextSpan(
                    text: fix.original,
                    style: TextStyle(
                      color: c.error,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const TextSpan(text: '  →  '),
                  TextSpan(
                    text: fix.corrected,
                    style: TextStyle(
                      color: c.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (fix.explanation.isNotEmpty)
              Text(
                fix.explanation,
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
          ],
        ],
        if (review.improved != null) ...[
          const SizedBox(height: 12),
          Text('A BETTER VERSION', style: label()),
          const SizedBox(height: 4),
          Text(
            review.improved!,
            style: TextStyle(fontSize: 14.5, color: c.textPrimary, height: 1.4),
          ),
        ],
      ],
    );
  }
}
