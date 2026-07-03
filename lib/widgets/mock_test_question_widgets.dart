import 'package:flutter/material.dart';

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
    final prompt = (question['prompt_text'] as String?) ?? '';
    final controller = TextEditingController(text: value ?? '');
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _QuestionBadge(label: questionLabel(question)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (prompt.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(prompt, style: const TextStyle(fontSize: 14.5, height: 1.4)),
                  ),
                TextField(
                  controller: controller,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Your answer',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
    final prompt = (question['prompt_text'] as String?) ?? '';
    final options = questionOptions(question, group);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _QuestionBadge(label: questionLabel(question)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (prompt.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(prompt, style: const TextStyle(fontSize: 14.5, height: 1.4)),
                  ),
                ...options.map((opt) {
                  final optValue = opt['value']?.toString() ?? '';
                  final selected = value == optValue;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onChanged(optValue),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                            width: selected ? 1.6 : 1,
                          ),
                          color: selected
                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected ? Icons.radio_button_checked : Icons.radio_button_off,
                              size: 18,
                              color: selected ? Theme.of(context).colorScheme.primary : Colors.grey,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                opt['label']?.toString() ?? optValue,
                                style: const TextStyle(fontSize: 14),
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
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final options = questionOptions(question, group);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _QuestionBadge(label: questionLabel(question)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: options.map((opt) {
                final optValue = opt['value']?.toString() ?? '';
                final selected = values.contains(optValue);
                return CheckboxListTile(
                  value: selected,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(opt['label']?.toString() ?? optValue, style: const TextStyle(fontSize: 14)),
                  onChanged: (checked) {
                    final next = List<String>.from(values);
                    if (checked == true) {
                      if (!next.contains(optValue)) next.add(optValue);
                    } else {
                      next.remove(optValue);
                    }
                    onChanged(next);
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionBadge extends StatelessWidget {
  const _QuestionBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
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
