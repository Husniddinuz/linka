import 'package:flutter/material.dart';
import '../models/mock_test.dart';
import 'mock_test_styles.dart';
import '../theme/app_colors.dart';

/// Question prompt text. A function rather than a top-level const because the
/// colour is a theme lookup.
TextStyle _promptStyle(BuildContext context) => TextStyle(
  fontFamily: 'SF Pro',
  fontSize: 14.5,
  height: 1.45,
  color: context.colors.textPrimary,
);

class _QuestionShell extends StatelessWidget {
  const _QuestionShell({required this.question, required this.child});
  final Question question;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final prompt = question.promptText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _QuestionNumberBadge(label: question.label),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (prompt.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 3),
                    child: Text(prompt, style: _promptStyle(context)),
                  )
                else
                  const SizedBox(height: 3),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Question-number badge. Sized to fit its content (rather than a fixed
/// circle) so multi-question ranges like "37–40" don't wrap or clip.
class _QuestionNumberBadge extends StatelessWidget {
  const _QuestionNumberBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(color: context.colors.brand, borderRadius: BorderRadius.circular(14)),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: const TextStyle(
          fontFamily: 'SF Pro',
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

class TextAnswerField extends StatefulWidget {
  const TextAnswerField({
    super.key,
    required this.question,
    required this.value,
    required this.onChanged,
  });

  final Question question;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  State<TextAnswerField> createState() => _TextAnswerFieldState();
}

class _TextAnswerFieldState extends State<TextAnswerField> {
  // The controller must survive rebuilds: recreating one per build (with the
  // selection forced to the end) resets the cursor, IME composition, and the
  // paste toolbar on every parent setState — mid-word pastes landed at the
  // end of the text and the keyboard flickered.
  late final TextEditingController _controller = TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(covariant TextAnswerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt external answer changes only; edits typed here already live in
    // the controller (the parent echoes them back via onChanged → value).
    final external = widget.value ?? '';
    if (external != _controller.text) _controller.text = external;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _QuestionShell(
      question: widget.question,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          style: TextStyle(fontFamily: 'SF Pro', fontSize: 14.5, color: context.colors.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Your answer',
            hintStyle: TextStyle(fontFamily: 'SF Pro', color: context.colors.textTertiary),
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

/// Renders a group of fill-in-the-blank questions as one continuous block
/// of flowing text (matching the printed IELTS answer sheet), with each
/// question's `___` placeholder swapped for a compact inline number badge
/// + text field, instead of stacking every question in its own card.
class TextGroupInline extends StatelessWidget {
  const TextGroupInline({
    super.key,
    required this.questions,
    required this.answers,
    required this.onChanged,
  });

  final List<Question> questions;
  final Map<String, dynamic> answers;
  final void Function(String questionId, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontFamily: 'SF Pro', fontSize: 14.5, height: 2.2, color: context.colors.textPrimary);
    final spans = <InlineSpan>[];

    // Ingested note/summary/flow-chart groups duplicate a shared block onto
    // every question that has a blank in it — a summary paragraph is copied
    // to all six siblings, a flow-chart step to the two questions inside it.
    // Walk consecutive runs of identical prompts: when a run's blank count
    // matches its length, render the block once with its blanks assigned to
    // the run's questions in order; otherwise fall back to rendering each
    // question's own copy (every blank labeled with that question's number).
    var blankIndex = 0;
    void addPromptSpans(String prompt, List<Question> blankOwners) {
      final parts = prompt.split('___');
      for (var i = 0; i < parts.length; i++) {
        final text = parts[i].trim();
        if (text.isNotEmpty) spans.add(TextSpan(text: '$text '));
        if (i < parts.length - 1) {
          final owner = blankOwners[i < blankOwners.length ? i : blankOwners.length - 1];
          spans.add(_blankSpan(owner, blankIndex++));
        }
      }
    }

    var i = 0;
    while (i < questions.length) {
      final prompt = questions[i].promptText;
      var j = i + 1;
      while (j < questions.length && questions[j].promptText == prompt) {
        j++;
      }
      final run = questions.sublist(i, j);
      if (run.length > 1 && '___'.allMatches(prompt).length == run.length) {
        addPromptSpans(prompt, run);
      } else {
        for (final q in run) {
          addPromptSpans(q.promptText, [q]);
        }
      }
      i = j;
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }

  WidgetSpan _blankSpan(Question question, int blankIndex) {
    final id = question.id.toString();
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: _InlineBlank(
          // Keyed so each blank's text-field state (controller, cursor, IME
          // composition) is re-adopted when the span list is rebuilt on every
          // keystroke. The index disambiguates multi-blank questions.
          key: ValueKey('blank-$id-$blankIndex'),
          label: question.label,
          value: answers[id] as String?,
          onChanged: (v) => onChanged(id, v),
        ),
      ),
    );
  }
}

class _InlineBlank extends StatefulWidget {
  const _InlineBlank({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  State<_InlineBlank> createState() => _InlineBlankState();
}

class _InlineBlankState extends State<_InlineBlank> {
  // Persistent for the same reason as _TextAnswerFieldState's controller:
  // a fresh controller per build breaks cursor position, IME composition,
  // and pasting.
  late final TextEditingController _controller = TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(covariant _InlineBlank oldWidget) {
    super.didUpdateWidget(oldWidget);
    final external = widget.value ?? '';
    if (external != _controller.text) _controller.text = external;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: context.colors.brand, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: const TextStyle(fontFamily: 'SF Pro', fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 92,
          height: 30,
          child: TextField(
            controller: _controller,
            onChanged: widget.onChanged,
            textAlignVertical: TextAlignVertical.center,
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, color: context.colors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              filled: true,
              fillColor: context.colors.surfaceAlt,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
            ),
          ),
        ),
      ],
    );
  }
}

class SingleChoiceField extends StatelessWidget {
  const SingleChoiceField({
    super.key,
    required this.question,
    required this.group,
    required this.value,
    required this.onChanged,
  });

  final Question question;
  final QuestionGroup group;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = question.effectiveOptions(group);
    return _QuestionShell(
      question: question,
      child: Column(
        children: options.map((opt) {
          final optValue = opt.value;
          final selected = value == optValue;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => onChanged(optValue),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? context.colors.brand : context.colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                      size: 19,
                      color: selected ? Colors.white : context.colors.textTertiary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        opt.label.isNotEmpty ? opt.label : optValue,
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: selected ? Colors.white : context.colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class MultiSelectField extends StatelessWidget {
  const MultiSelectField({
    super.key,
    required this.question,
    required this.group,
    required this.values,
    required this.onChanged,
  });

  final Question question;
  final QuestionGroup group;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  /// "Choose FOUR letters" questions store the whole group as one question
  /// spanning `number`–`number_end`, e.g. 37–40. This is only a hint for the
  /// learner, not enforced: the backend's actual answer key can have fewer
  /// correct options than the span implies (seen in practice — a "choose
  /// FOUR" question whose stored answer key only has 3 correct letters), so
  /// hard-blocking selection at the span count can itself force a wrong
  /// answer. Selection stays unrestricted; grading is authoritative.
  int? get _expectedCount {
    final end = question.numberEnd;
    if (end == null) return null;
    return end - question.number + 1;
  }

  @override
  Widget build(BuildContext context) {
    final options = question.effectiveOptions(group);
    final expected = _expectedCount;
    return _QuestionShell(
      question: question,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (expected != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Select $expected (${values.length} chosen)',
                style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, fontWeight: FontWeight.w600, color: context.colors.textSecondary),
              ),
            ),
          ...options.map((opt) {
            final optValue = opt.value;
            final selected = values.contains(optValue);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  final next = List<String>.from(values);
                  if (selected) {
                    next.remove(optValue);
                  } else {
                    next.add(optValue);
                  }
                  onChanged(next);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected ? context.colors.brand : context.colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                        size: 19,
                        color: selected ? Colors.white : context.colors.textTertiary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          opt.label.isNotEmpty ? opt.label : optValue,
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: selected ? Colors.white : context.colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Matching-style group (headings / sentence endings / features / "which
/// paragraph contains…"). The source HTML renders these as drag-and-drop;
/// here every question gets a tappable gap and the group shares one bank of
/// answer chips underneath — tap a question to make its gap active, tap a
/// chip to fill it, and the active gap advances to the next unanswered
/// question. Chips already placed elsewhere stay tappable (some tasks reuse
/// a letter) but are dimmed, restoring the drag UI's "already used" cue.
class OptionBankGroup extends StatefulWidget {
  const OptionBankGroup({
    super.key,
    required this.group,
    required this.questions,
    required this.answers,
    required this.onAnswer,
  });

  final QuestionGroup group;
  final List<Question> questions;
  final Map<String, dynamic> answers;
  final void Function(String questionId, dynamic value) onAnswer;

  @override
  State<OptionBankGroup> createState() => _OptionBankGroupState();
}

class _OptionBankGroupState extends State<OptionBankGroup> {
  int? _activeId;

  String? _answerOf(Question q) {
    final v = widget.answers[q.id.toString()];
    if (v is! String || v.trim().isEmpty) return null;
    return v;
  }

  /// The gap chips act on: the explicitly selected question if it still
  /// exists, else the first unanswered one, else the first question.
  Question? get _active {
    for (final q in widget.questions) {
      if (q.id == _activeId) return q;
    }
    for (final q in widget.questions) {
      if (_answerOf(q) == null) return q;
    }
    return widget.questions.isEmpty ? null : widget.questions.first;
  }

  /// Chip-bank answering never needs the keyboard — dismiss one left open
  /// by a text-completion field so it stops covering the chips.
  void _dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  void _tapGap(Question q) {
    _dismissKeyboard();
    // Second tap on the already-active filled gap clears it (the gap shows
    // an ✕ in that state); any other tap just moves the active marker.
    if (_active?.id == q.id && _answerOf(q) != null) {
      widget.onAnswer(q.id.toString(), '');
    }
    setState(() => _activeId = q.id);
  }

  void _tapChip(QuestionOption opt) {
    _dismissKeyboard();
    final q = _active;
    if (q == null) return;
    if (_answerOf(q) == opt.value) {
      // Re-tapping the chip that's already in the active gap empties it.
      widget.onAnswer(q.id.toString(), '');
      setState(() => _activeId = q.id);
      return;
    }
    widget.onAnswer(q.id.toString(), opt.value);
    setState(() => _activeId = _nextUnansweredAfter(q)?.id ?? q.id);
  }

  /// Next gap to fill, scanning forward from [q] and wrapping around.
  /// `widget.answers` is the live map the parent just mutated, so the gap
  /// filled a moment ago is already excluded.
  Question? _nextUnansweredAfter(Question q) {
    final qs = widget.questions;
    final from = qs.indexWhere((x) => x.id == q.id);
    for (var i = 1; i <= qs.length; i++) {
      final candidate = qs[(from + i) % qs.length];
      if (_answerOf(candidate) == null) return candidate;
    }
    return null;
  }

  /// Word-bank summaries store the whole paragraph as every sibling's
  /// prompt, one `___` per question — render it once with each gap bound to
  /// its question, instead of repeating the paragraph per question.
  String? get _sharedParagraph {
    if (widget.questions.length < 2) return null;
    final prompts = widget.questions.map((q) => q.promptText).toList();
    final first = prompts.first;
    if (!first.contains('___') || prompts.toSet().length != 1) return null;
    return '___'.allMatches(first).length == prompts.length ? first : null;
  }

  Widget _sharedParagraphBlock(String paragraph, Question? active) {
    final parts = paragraph.split('___');
    final spans = <InlineSpan>[];
    for (var i = 0; i < parts.length; i++) {
      final text = parts[i].trim();
      if (text.isNotEmpty) spans.add(TextSpan(text: '$text '));
      if (i < parts.length - 1 && i < widget.questions.length) {
        final q = widget.questions[i];
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _GapSlot(
                label: q.label,
                value: _answerOf(q),
                active: active?.id == q.id,
                onTap: () => _tapGap(q),
              ),
            ),
          ),
        );
      }
    }
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: 'SF Pro',
          fontSize: 14.5,
          height: 2.0,
          color: context.colors.textPrimary,
        ),
        children: spans,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final options = widget.questions.isEmpty
        ? const <QuestionOption>[]
        : widget.questions.first.effectiveOptions(widget.group);
    final used = widget.questions.map(_answerOf).whereType<String>().toSet();
    final activeValue = active == null ? null : _answerOf(active);
    final shared = _sharedParagraph;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shared != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _sharedParagraphBlock(shared, active),
          )
        else
          ...widget.questions.map((q) => _questionRow(q, isActive: active?.id == q.id)),
        Padding(
          padding: EdgeInsets.only(top: 2, bottom: 8),
          child: Text(
            'Tap a question, then tap an answer below to fill its gap.',
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, color: context.colors.textSecondary),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final selected = opt.value == activeValue;
            return _BankChip(
              option: opt,
              selected: selected,
              dimmed: !selected && used.contains(opt.value),
              onTap: () => _tapChip(opt),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _questionRow(Question q, {required bool isActive}) {
    final value = _answerOf(q);
    final prompt = q.promptText;
    final spans = <InlineSpan>[];
    void addGap() => spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _GapSlot(value: value, active: isActive, onTap: () => _tapGap(q)),
      ),
    );
    // Prompts ingested from drag-drop sources carry a `___` where the drop
    // zone sat; matching-headings prompts ("Paragraph B") have no blank, so
    // the gap goes after the text.
    if (prompt.contains('___')) {
      final parts = prompt.split('___');
      for (var i = 0; i < parts.length; i++) {
        final text = parts[i].trim();
        if (text.isNotEmpty) spans.add(TextSpan(text: i == 0 ? '$text ' : ' $text '));
        if (i < parts.length - 1) addGap();
      }
    } else {
      if (prompt.isNotEmpty) spans.add(TextSpan(text: '$prompt  '));
      addGap();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _dismissKeyboard();
          setState(() => _activeId = q.id);
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _QuestionNumberBadge(label: q.label),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 14.5,
                      height: 1.7,
                      color: context.colors.textPrimary,
                    ),
                    children: spans,
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

class _GapSlot extends StatelessWidget {
  const _GapSlot({required this.value, required this.active, required this.onTap, this.label});

  final String? value;
  final bool active;
  final VoidCallback onTap;

  /// Question number shown inside the slot — needed when the slot sits in a
  /// flowing shared paragraph where no row badge identifies the question.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final filled = value != null;
    final Color bg;
    final Color fg;
    if (filled) {
      bg = active ? context.colors.textPrimary : context.colors.surfaceAlt;
      fg = active ? Colors.white : context.colors.textPrimary;
    } else {
      bg = active ? const Color(0xFFFDF4DA) : context.colors.surfaceAlt;
      fg = context.colors.textTertiary;
    }
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        constraints: const BoxConstraints(minWidth: 46),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? (filled ? context.colors.brand : MockTestColors.yellowDark)
                : context.colors.border,
            width: active ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null) ...[
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: active && filled ? context.colors.onBrand : context.colors.brand,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  label!,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: active && filled ? context.colors.textPrimary : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              filled ? value! : '···',
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13, fontWeight: FontWeight.w700, color: fg),
            ),
            if (filled && active) ...[
              const SizedBox(width: 5),
              const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
            ],
          ],
        ),
      ),
    );
  }
}

class _BankChip extends StatelessWidget {
  const _BankChip({
    required this.option,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  final QuestionOption option;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasLabel = option.label.isNotEmpty && option.label != option.value;
    final fg = selected
        ? Colors.white
        : context.colors.textPrimary.withValues(alpha: dimmed ? 0.4 : 1);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.brand
              : context.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: option.value,
                style: TextStyle(fontWeight: FontWeight.w700, color: fg),
              ),
              if (hasLabel)
                TextSpan(
                  text: '  ${option.label}',
                  style: TextStyle(fontWeight: FontWeight.w500, color: fg),
                ),
            ],
          ),
          style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.35),
        ),
      ),
    );
  }
}

/// A group instruction split for display: the "Questions 1–7" range (if the
/// text opens with one) and the remaining instruction body.
class InstructionParts {
  const InstructionParts({required this.header, required this.body});
  final String? header;
  final String body;
}

/// Normalizes a group's raw instruction line for display. Handles the three
/// data quirks of ingested instructions: the question range can be glued to
/// the first sentence ("Questions 1-7Complete the notes below"), the range
/// separator varies (-, –, "to", "and"), and most lines end with the printed
/// test's boilerplate ("Write your answers in boxes 1-7 on your answer
/// sheet.") which means nothing in the app — any sentence mentioning the
/// answer sheet is dropped.
InstructionParts parseInstruction(String raw) {
  var text = raw.trim();
  String? header;
  final m = RegExp(
    r'^Questions?\s*(\d+)\s*(?:(?:[-–—]|to|and|&)\s*(\d+))?\s*:?\s*',
    caseSensitive: false,
  ).firstMatch(text);
  if (m != null) {
    final start = m.group(1);
    final end = m.group(2);
    header = end != null ? 'Questions $start–$end' : 'Question $start';
    text = text.substring(m.end);
  }
  text = text
      .replaceAll(
        RegExp(r'[^.!?]*\banswer sheet\b[^.!?]*[.!?]?', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return InstructionParts(header: header, body: text);
}

/// Splits [body] into spans, bolding the shouted constraint runs ("NO MORE
/// THAN TWO WORDS AND/OR A NUMBER", "TRUE", "A–G") the learner must obey. A
/// run is consecutive all-caps tokens (single "A"s, digits, and commas may
/// sit inside one) containing at least two capital letters overall — so a
/// sentence-initial "A" alone never triggers it.
List<TextSpan> instructionBodySpans(String body, TextStyle strong) {
  final matches = RegExp(
    r'\b(?:[A-Z][A-Z/]+|[A-Z][-–—][A-Z]|A|\d+)(?:(?:[ ,]|, )*(?:[A-Z][A-Z/]+|[A-Z][-–—][A-Z]|A|\d+))*\b',
  ).allMatches(body);
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final m in matches) {
    final run = m.group(0)!;
    final capCount = RegExp(r'[A-Z]').allMatches(run).length;
    if (capCount < 2) continue;
    if (m.start > cursor) spans.add(TextSpan(text: body.substring(cursor, m.start)));
    spans.add(TextSpan(text: run, style: strong));
    cursor = m.end;
  }
  if (cursor < body.length) spans.add(TextSpan(text: body.substring(cursor)));
  return spans;
}

/// The instruction banner above a question group: the question range as a
/// navy pill, the instruction body under it with the answer-length / letter
/// constraints bolded.
class GroupInstructionCard extends StatelessWidget {
  const GroupInstructionCard({super.key, required this.instruction});

  final String instruction;

  @override
  Widget build(BuildContext context) {
    final parts = parseInstruction(instruction);
    if (parts.header == null && parts.body.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: mtSoftCard(context, color: context.colors.surfaceAlt, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (parts.header != null)
            Padding(
              padding: EdgeInsets.only(bottom: parts.body.isEmpty ? 0 : 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.colors.brand,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  parts.header!,
                  style: const TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (parts.body.isNotEmpty)
            Text.rich(
              TextSpan(
                children: instructionBodySpans(
                  parts.body,
                  const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: context.colors.textPrimary,
                height: 1.45,
              ),
            ),
        ],
      ),
    );
  }
}

/// Everything a question type needs to describe how it renders, in one
/// place: [buildField] renders a single question's answer input (used by
/// [QuestionField]); the optional [buildGroupBlock] lets a type render its
/// whole group as one block instead of stacking per-question fields (e.g.
/// [TextGroupInline]'s flowing fill-in-the-blank paragraph) — return null to
/// fall back to per-question [buildField] cards.
///
/// Adding a new question type means adding one [QuestionTypeHandler] entry
/// to [kQuestionTypeRegistry] — nothing else in this file branches on
/// `group.type`.
class QuestionTypeHandler {
  const QuestionTypeHandler({required this.buildField, this.buildGroupBlock});

  final Widget Function(
    BuildContext context, {
    required Question question,
    required QuestionGroup group,
    required dynamic answer,
    required ValueChanged<dynamic> onChanged,
  })
  buildField;

  final Widget? Function(
    QuestionGroup group,
    List<Question> questions,
    Map<String, dynamic> answers,
    void Function(String questionId, dynamic value) onAnswer,
  )?
  buildGroupBlock;
}

final Map<String, QuestionTypeHandler> kQuestionTypeRegistry = {
  'text': QuestionTypeHandler(
    buildField: (context, {required question, required group, required answer, required onChanged}) =>
        TextAnswerField(question: question, value: answer as String?, onChanged: onChanged),
    buildGroupBlock: (group, questions, answers, onAnswer) {
      // Renders the whole group as one flowing paragraph only when every
      // question's prompt actually has a blank to fill; otherwise falls
      // back to per-question TextAnswerField cards (same fallback as every
      // other type).
      final everyPromptHasBlank = questions.every((q) => q.promptText.contains('___'));
      if (!everyPromptHasBlank) return null;
      return TextGroupInline(questions: questions, answers: answers, onChanged: onAnswer);
    },
  ),
  'single_choice': QuestionTypeHandler(
    buildField: (context, {required question, required group, required answer, required onChanged}) =>
        SingleChoiceField(question: question, group: group, value: answer as String?, onChanged: onChanged),
    buildGroupBlock: (group, questions, answers, onAnswer) {
      // Matching-style groups (headings / endings / features / paragraph
      // letters) share one option pool across every question — those get the
      // gap + chip-bank block. MCQ questions each carry their own A–D answer
      // texts, so their option lists differ and they keep the per-question
      // radio cards. (The ingester copies the shared pool onto each question,
      // so "shared" is detected by comparing lists, not by absence.)
      if (questions.length < 2) return null;
      String sig(List<QuestionOption> opts) =>
          opts.map((o) => '${o.value}\u0000${o.label}').join('\u0001');
      final pool = questions.first.effectiveOptions(group);
      if (pool.length < 2) return null;
      final poolSig = sig(pool);
      if (questions.any((q) => sig(q.effectiveOptions(group)) != poolSig)) return null;
      return OptionBankGroup(
        key: ValueKey('option-bank-${group.id}'),
        group: group,
        questions: questions,
        answers: answers,
        onAnswer: onAnswer,
      );
    },
  ),
  'true_false_ng': QuestionTypeHandler(
    buildField: (context, {required question, required group, required answer, required onChanged}) =>
        SingleChoiceField(question: question, group: group, value: answer as String?, onChanged: onChanged),
  ),
  'multi_select': QuestionTypeHandler(
    buildField: (context, {required question, required group, required answer, required onChanged}) =>
        MultiSelectField(
          question: question,
          group: group,
          values: (answer as List?)?.cast<String>() ?? const [],
          onChanged: onChanged,
        ),
  ),
};

/// Looks up the handler for [type], falling back to the 'text' handler for
/// any unrecognized type — mirrors the previous switch statement's implicit
/// `default:` fallthrough.
QuestionTypeHandler questionTypeHandler(String type) =>
    kQuestionTypeRegistry[type] ?? kQuestionTypeRegistry['text']!;

/// Renders one question of any type, dispatching via [kQuestionTypeRegistry].
class QuestionField extends StatelessWidget {
  const QuestionField({
    super.key,
    required this.question,
    required this.group,
    required this.answer,
    required this.onChanged,
  });

  final Question question;
  final QuestionGroup group;
  final dynamic answer;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) => questionTypeHandler(
    group.type,
  ).buildField(context, question: question, group: group, answer: answer, onChanged: onChanged);
}
