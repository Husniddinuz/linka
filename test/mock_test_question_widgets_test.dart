import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/models/mock_test.dart';
import 'package:linka/widgets/mock_test_question_widgets.dart';

Question _question(int id, int number, String prompt, {List<QuestionOption> options = const []}) =>
    Question(id: id, number: number, numberEnd: null, inputCount: 1, promptText: prompt, options: options);

QuestionGroup _group({
  required String type,
  required List<Question> questions,
  List<QuestionOption> sharedOptions = const [],
}) => QuestionGroup(
  id: 1,
  order: 1,
  type: type,
  questionStart: questions.first.number,
  questionEnd: questions.last.number,
  instructionHtml: '',
  sharedOptions: sharedOptions,
  imageUrl: '',
  questions: questions,
);

const _pool = [
  QuestionOption(value: 'A', label: 'The first heading'),
  QuestionOption(value: 'B', label: 'The second heading'),
  QuestionOption(value: 'C', label: 'The third heading'),
];

/// Mirrors _QuestionsView: one shared answers map mutated in setState, with
/// the group block rebuilt from the registry on every change.
class _GroupHarness extends StatefulWidget {
  const _GroupHarness({required this.group, required this.answers});
  final QuestionGroup group;
  final Map<String, dynamic> answers;

  @override
  State<_GroupHarness> createState() => _GroupHarnessState();
}

class _GroupHarnessState extends State<_GroupHarness> {
  @override
  Widget build(BuildContext context) {
    final block = questionTypeHandler(widget.group.type).buildGroupBlock?.call(
      widget.group,
      widget.group.questions,
      widget.answers,
      (id, val) => setState(() => widget.answers[id] = val),
    );
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: block ??
              Column(
                children: widget.group.questions
                    .map(
                      (q) => QuestionField(
                        question: q,
                        group: widget.group,
                        answer: widget.answers[q.id.toString()],
                        onChanged: (val) => setState(() => widget.answers[q.id.toString()] = val),
                      ),
                    )
                    .toList(),
              ),
        ),
      ),
    );
  }
}

void main() {
  group('single_choice group block selection', () {
    test('shared-pool (matching) groups get the option bank', () {
      final g = _group(
        type: 'single_choice',
        sharedOptions: _pool,
        questions: [_question(11, 1, 'Paragraph A'), _question(12, 2, 'Paragraph B')],
      );
      final block = questionTypeHandler('single_choice').buildGroupBlock!(g, g.questions, {}, (_, _) {});
      expect(block, isA<OptionBankGroup>());
    });

    test('MCQ groups with per-question options keep radio cards', () {
      final g = _group(
        type: 'single_choice',
        questions: [
          _question(11, 1, 'First stem?', options: const [
            QuestionOption(value: 'A', label: 'red'),
            QuestionOption(value: 'B', label: 'blue'),
          ]),
          _question(12, 2, 'Second stem?', options: const [
            QuestionOption(value: 'A', label: 'cat'),
            QuestionOption(value: 'B', label: 'dog'),
          ]),
        ],
      );
      final block = questionTypeHandler('single_choice').buildGroupBlock!(g, g.questions, {}, (_, _) {});
      expect(block, isNull);
    });
  });

  group('OptionBankGroup interaction', () {
    testWidgets('tapping chips fills gaps in order and advances', (tester) async {
      final answers = <String, dynamic>{};
      final g = _group(
        type: 'single_choice',
        sharedOptions: _pool,
        questions: [_question(11, 1, 'Paragraph A'), _question(12, 2, 'Paragraph B')],
      );
      await tester.pumpWidget(_GroupHarness(group: g, answers: answers));

      // First unanswered question (11) is active by default; chip fills it.
      await tester.tap(find.textContaining('The second heading'));
      await tester.pumpAndSettle();
      expect(answers['11'], 'B');

      // Active gap advanced to question 12; next chip lands there.
      await tester.tap(find.textContaining('The first heading'));
      await tester.pumpAndSettle();
      expect(answers['12'], 'A');
    });

    testWidgets('re-tapping the placed chip clears the active gap', (tester) async {
      final answers = <String, dynamic>{};
      final g = _group(
        type: 'single_choice',
        sharedOptions: _pool,
        questions: [_question(11, 1, 'Paragraph A'), _question(12, 2, 'Paragraph B')],
      );
      await tester.pumpWidget(_GroupHarness(group: g, answers: answers));

      await tester.tap(find.textContaining('The third heading'));
      await tester.pumpAndSettle();
      expect(answers['11'], 'C');

      // Re-activate question 1's row, then re-tap its chip to clear it.
      await tester.tap(find.textContaining('Paragraph A'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('The third heading'));
      await tester.pumpAndSettle();
      expect(answers['11'], '');
    });
  });

  group('OptionBankGroup shared paragraph', () {
    testWidgets('renders word-bank summary once with per-question gaps', (tester) async {
      final answers = <String, dynamic>{};
      const paragraph = 'Laughter evolved out of ___ and may share the same ___ with chimps.';
      final g = _group(
        type: 'single_choice',
        sharedOptions: _pool,
        questions: [
          _question(31, 7, paragraph),
          _question(32, 8, paragraph),
        ],
      );
      await tester.pumpWidget(_GroupHarness(group: g, answers: answers));

      // The paragraph text appears exactly once, not per question.
      expect(find.textContaining('Laughter evolved out of'), findsOneWidget);

      // First gap is active by default; a chip fills question 7, then 8.
      await tester.tap(find.textContaining('The first heading'));
      await tester.pumpAndSettle();
      expect(answers['31'], 'A');
      await tester.tap(find.textContaining('The second heading'));
      await tester.pumpAndSettle();
      expect(answers['32'], 'B');
    });
  });

  group('parseInstruction', () {
    test('splits a glued question range and drops answer-sheet boilerplate', () {
      final p = parseInstruction(
        'Questions 1-7Complete the notes below. Write NO MORE THAN TWO WORDS '
        'for each answer. Write your answers in boxes 1-7 on your answer sheet.',
      );
      expect(p.header, 'Questions 1–7');
      expect(p.body, 'Complete the notes below. Write NO MORE THAN TWO WORDS for each answer.');
    });

    test('handles a single question and no boilerplate', () {
      final p = parseInstruction('Question 40 Choose the correct answer.');
      expect(p.header, 'Question 40');
      expect(p.body, 'Choose the correct answer.');
    });

    test('leaves headerless instructions intact', () {
      final p = parseInstruction('Choose the correct heading for paragraphs from the list below.');
      expect(p.header, isNull);
      expect(p.body, 'Choose the correct heading for paragraphs from the list below.');
    });

    test('bolds constraint runs but not sentence-initial A', () {
      final spans = instructionBodySpans(
        'A summary follows. Write NO MORE THAN TWO WORDS AND/OR A NUMBER for each answer.',
        const TextStyle(fontWeight: FontWeight.w700),
      );
      final bold = spans.where((s) => s.style?.fontWeight == FontWeight.w700).map((s) => s.text).toList();
      expect(bold, ['NO MORE THAN TWO WORDS AND/OR A NUMBER']);
    });
  });

  group('TextAnswerField editing state', () {
    testWidgets('typed text survives parent rebuilds', (tester) async {
      final answers = <String, dynamic>{};
      final g = _group(
        type: 'text',
        questions: [_question(21, 5, 'No blank marker here')],
      );
      await tester.pumpWidget(_GroupHarness(group: g, answers: answers));

      await tester.enterText(find.byType(TextField), 'coral reefs');
      await tester.pumpAndSettle();
      expect(answers['21'], 'coral reefs');
      expect(find.text('coral reefs'), findsOneWidget);
    });
  });
}
