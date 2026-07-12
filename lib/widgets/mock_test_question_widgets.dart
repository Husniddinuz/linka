import 'package:flutter/material.dart';
import 'mock_test_styles.dart';

/// Returns this question's own options, falling back to the group's shared
/// legend (matching/true-false/MCQ groups usually only store options once,
/// on the group, since every question in the group shares the same choices).
List<Map<String, dynamic>> questionOptions(
  Map<String, dynamic> question,
  Map<String, dynamic> group,
) {
  final own = (question['options'] as List?) ?? const [];
  if (own.isNotEmpty) return own.cast<Map<String, dynamic>>();
  final shared = (group['shared_options'] as List?) ?? const [];
  return shared.cast<Map<String, dynamic>>();
}

String questionLabel(Map<String, dynamic> question) {
  final end = question['number_end'];
  final n = question['number'];
  return end != null ? '$n–$end' : '$n';
}

const _promptStyle = TextStyle(
  fontFamily: 'SF Pro',
  fontSize: 14.5,
  height: 1.45,
  color: MockTestColors.navy,
);

class _QuestionShell extends StatelessWidget {
  const _QuestionShell({required this.question, required this.child});
  final Map<String, dynamic> question;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final prompt = (question['prompt_text'] as String?) ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _QuestionNumberBadge(label: questionLabel(question)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (prompt.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 3),
                    child: Text(prompt, style: _promptStyle),
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
      decoration: BoxDecoration(color: MockTestColors.navy, borderRadius: BorderRadius.circular(14)),
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

class TextAnswerField extends StatelessWidget {
  const TextAnswerField({
    super.key,
    required this.question,
    required this.value,
    required this.onChanged,
  });

  final Map<String, dynamic> question;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: value ?? '');
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
    return _QuestionShell(
      question: question,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14.5, color: MockTestColors.navy),
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Your answer',
            hintStyle: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.greyLight),
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

  final List<Map<String, dynamic>> questions;
  final Map<String, dynamic> answers;
  final void Function(String questionId, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontFamily: 'SF Pro', fontSize: 14.5, height: 2.2, color: MockTestColors.navy);
    final spans = <InlineSpan>[];

    // Some ingested note/summary groups duplicate the whole shared paragraph
    // onto every sibling question (one full copy per blank) instead of
    // splitting it once. Detect that so the paragraph renders a single time
    // with its blanks assigned to the sibling questions in order, instead of
    // repeating the text once per question with every blank mislabeled the
    // same number.
    final prompts = questions.map((q) => (q['prompt_text'] as String?) ?? '').toList();
    final shared = prompts.isNotEmpty && prompts.toSet().length == 1 ? prompts.first : null;
    final sharedBlankCount = shared != null ? '___'.allMatches(shared).length : 0;

    if (shared != null && questions.length > 1 && sharedBlankCount == questions.length) {
      final parts = shared.split('___');
      for (var i = 0; i < parts.length; i++) {
        final text = parts[i].trim();
        if (text.isNotEmpty) spans.add(TextSpan(text: '$text '));
        if (i < parts.length - 1) {
          spans.add(_blankSpan(questions[i]));
        }
      }
    } else {
      for (final q in questions) {
        final prompt = (q['prompt_text'] as String?) ?? '';
        final parts = prompt.split('___');
        for (var i = 0; i < parts.length; i++) {
          final text = parts[i].trim();
          if (text.isNotEmpty) spans.add(TextSpan(text: '$text '));
          if (i < parts.length - 1) spans.add(_blankSpan(q));
        }
      }
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }

  WidgetSpan _blankSpan(Map<String, dynamic> question) {
    final id = question['id'].toString();
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: _InlineBlank(
          label: questionLabel(question),
          value: answers[id] as String?,
          onChanged: (v) => onChanged(id, v),
        ),
      ),
    );
  }
}

class _InlineBlank extends StatelessWidget {
  const _InlineBlank({required this.label, required this.value, required this.onChanged});

  final String label;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: value ?? '');
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(color: MockTestColors.navy, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(fontFamily: 'SF Pro', fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 92,
          height: 30,
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, color: MockTestColors.navy),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              filled: true,
              fillColor: const Color(0xFFF5F5F7),
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

  final Map<String, dynamic> question;
  final Map<String, dynamic> group;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = questionOptions(question, group);
    return _QuestionShell(
      question: question,
      child: Column(
        children: options.map((opt) {
          final optValue = opt['value']?.toString() ?? '';
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
                  color: selected ? MockTestColors.navy : const Color(0xFFF5F5F7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                      size: 19,
                      color: selected ? Colors.white : MockTestColors.greyLight,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        opt['label']?.toString() ?? optValue,
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: selected ? Colors.white : MockTestColors.navy,
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

  final Map<String, dynamic> question;
  final Map<String, dynamic> group;
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
    final start = (question['number'] as num?)?.toInt();
    final end = (question['number_end'] as num?)?.toInt();
    if (start == null || end == null) return null;
    return end - start + 1;
  }

  @override
  Widget build(BuildContext context) {
    final options = questionOptions(question, group);
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
                style: const TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, fontWeight: FontWeight.w600, color: MockTestColors.grey),
              ),
            ),
          ...options.map((opt) {
            final optValue = opt['value']?.toString() ?? '';
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
                    color: selected ? MockTestColors.navy : const Color(0xFFF5F5F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                        size: 19,
                        color: selected ? Colors.white : MockTestColors.greyLight,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          opt['label']?.toString() ?? optValue,
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: selected ? Colors.white : MockTestColors.navy,
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

/// Renders one question of any type, dispatching on the group's `type`.
class QuestionField extends StatelessWidget {
  const QuestionField({
    super.key,
    required this.question,
    required this.group,
    required this.answer,
    required this.onChanged,
  });

  final Map<String, dynamic> question;
  final Map<String, dynamic> group;
  final dynamic answer;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    switch (group['type']) {
      case 'multi_select':
        return MultiSelectField(
          question: question,
          group: group,
          values: (answer as List?)?.cast<String>() ?? const [],
          onChanged: onChanged,
        );
      case 'single_choice':
      case 'true_false_ng':
        return SingleChoiceField(
          question: question,
          group: group,
          value: answer as String?,
          onChanged: onChanged,
        );
      case 'text':
      default:
        return TextAnswerField(
          question: question,
          value: answer as String?,
          onChanged: onChanged,
        );
    }
  }
}
