import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../widgets/mock_test_styles.dart';
import '../widgets/writing_report.dart';
import 'writing_test_screen.dart';

/// Read-only view of a real Writing sample essay: the task (with its chart),
/// the tutor who wrote the answer, their band, the model essay with
/// tap-to-reveal examiner notes, and the commentary explaining the score.
///
/// Dressed in the AI report's visual language ([WReport], `context.wr`) rather
/// than the mock-test one, because a student arrives here from the same place
/// they read their own marked essays — a model answer and a marked answer are
/// the same kind of document, and reading one straight after the other should
/// not feel like changing apps.
///
/// The task itself is drawn by the report's [WTaskCard], the same widget the
/// writing editor and the result screen use. That is what makes the chart
/// usable: a Task 1 chart at card width is a picture of a chart, and the axis
/// labels *are* the question, so the card's preview opens the full-screen
/// zoomable [WChartViewer] on tap.
class WritingSampleScreen extends StatelessWidget {
  const WritingSampleScreen({super.key, required this.sample});

  final Map<String, dynamic> sample;

  int get _taskNumber {
    final task = wToInt(sample['task_number']);
    return task == 0 ? 1 : task;
  }

  /// The sample's task, shaped as the prompt map [WTaskCard] and
  /// [WritingTestScreen] both read.
  ///
  /// A sample carries no `min_words` of its own, so this follows the exam
  /// (150 / 250) — the same floor the server puts on the mirrored prompt it
  /// grades an answer against, so the count the editor shows is the count the
  /// grader marks to.
  Map<String, dynamic> get _task => {
        'task_number': _taskNumber,
        'title': sample['title'],
        'prompt_html': sample['prompt_html'],
        'image_url': sample['image_url'],
        'min_words': _taskNumber == 1 ? 150 : 250,
      };

  void _openEditor(BuildContext context) {
    final id = (sample['id'] as num?)?.toInt();
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WritingTestScreen(prompt: _task, sampleId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final band = wToDoubleOrNull(sample['band_score']);
    final examinerComment = sample['examiner_comment']?.toString().trim() ?? '';
    final tutorName = sample['tutor_name']?.toString() ?? '';
    final essay = sample['sample_essay_html']?.toString() ?? '';
    final annotations = wMapList(sample['annotations'])
        .where((a) => (a['highlighted_text']?.toString() ?? '').isNotEmpty)
        .toList();
    final canAnswer = (sample['id'] as num?) != null;

    return Scaffold(
      backgroundColor: context.wr.page,
      appBar: mtAppBar(context, title: 'Task $_taskNumber sample'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (tutorName.isNotEmpty) ...[
            WFadeSlideIn(
              child: _TutorStrip(
                name: tutorName,
                imageUrl: sample['tutor_image_url']?.toString(),
                band: band,
              ),
            ),
            const SizedBox(height: 14),
          ],
          WFadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: WTaskCard(prompt: _task),
          ),
          const SizedBox(height: 22),
          WFadeSlideIn(
            delay: const Duration(milliseconds: 120),
            child: wSectionTitle(
              context,
              'Model answer',
              subtitle: annotations.isEmpty
                  ? 'The answer $tutorName wrote to this task.'
                  : 'Tap a highlighted phrase to read why it works.',
            ),
          ),
          const SizedBox(height: 12),
          WFadeSlideIn(
            delay: const Duration(milliseconds: 160),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              decoration: wCardDecoration(context),
              child: _SampleEssay(essay: essay, annotations: annotations),
            ),
          ),
          if (examinerComment.isNotEmpty) ...[
            const SizedBox(height: 22),
            WFadeSlideIn(
              delay: const Duration(milliseconds: 200),
              child: wSectionTitle(
                context,
                'Why this scores well',
                subtitle: 'The examiner commentary behind the band.',
              ),
            ),
            const SizedBox(height: 12),
            WFadeSlideIn(
              delay: const Duration(milliseconds: 240),
              child: _CommentaryCard(comment: examinerComment),
            ),
          ],
        ],
      ),
      bottomNavigationBar: canAnswer ? _TryItBar(onTap: () => _openEditor(context)) : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// Who wrote this answer and what it scored, on one line.
///
/// The band belongs beside the tutor rather than in a block of its own: it is
/// what *their* answer earned, and a full-width score panel above the task
/// read as the student's own result.
class _TutorStrip extends StatelessWidget {
  const _TutorStrip({required this.name, required this.imageUrl, required this.band});

  final String name;
  final String? imageUrl;
  final double? band;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: wCardDecoration(context, radius: 18),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: (imageUrl != null && imageUrl!.isNotEmpty)
                ? Image.network(
                    imageUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _fallbackAvatar(context),
                  )
                : _fallbackAvatar(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MODEL ANSWER BY',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: wr.faint,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: wr.text,
                  ),
                ),
              ],
            ),
          ),
          if (band != null) ...[
            const SizedBox(width: 10),
            _BandBadge(band: band!),
          ],
        ],
      ),
    );
  }

  Widget _fallbackAvatar(BuildContext context) {
    final wr = context.wr;
    return Container(
      width: 48,
      height: 48,
      color: wr.soft,
      alignment: Alignment.center,
      child: Icon(Symbols.person_rounded, color: wr.faint, size: 26),
    );
  }
}

/// The band as a tinted plate, coloured by [wScoreColor] so it reads on the
/// same scale as every band elsewhere in the app.
class _BandBadge extends StatelessWidget {
  const _BandBadge({required this.band});
  final double band;

  @override
  Widget build(BuildContext context) {
    final color = wScoreColor(context, band);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'BAND',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: color,
            ),
          ),
          Text(
            wFormatBand(band),
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 20,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Essay
// ---------------------------------------------------------------------------

/// The model essay, with the tutor's highlighted phrases tappable.
///
/// Two layers of markup meet in this one string: the annotations the server
/// parsed out of the `==phrase==(note)` markup, given back as phrases to find
/// again, and the `**bold**` the tutor typed. The highlights are placed first
/// (they are offsets into the text the server measured) and each plain run
/// between them is then parsed for bold, so neither can swallow the other.
class _SampleEssay extends StatefulWidget {
  const _SampleEssay({required this.essay, required this.annotations});

  final String essay;
  final List<Map<String, dynamic>> annotations;

  @override
  State<_SampleEssay> createState() => _SampleEssayState();
}

class _SampleEssayState extends State<_SampleEssay> {
  /// One recognizer per highlight, built once rather than per frame: a
  /// recognizer disposed mid-build can be one the gesture arena is still
  /// holding, and the highlights never change once the sample is on screen.
  final _recognizers = <int, TapGestureRecognizer>{};
  late List<_Run> _runs;

  /// The highlight the open sheet belongs to, so it stays visibly picked out
  /// underneath it.
  int? _active;

  @override
  void initState() {
    super.initState();
    _buildRuns();
  }

  @override
  void didUpdateWidget(_SampleEssay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.essay != widget.essay || oldWidget.annotations != widget.annotations) {
      _disposeRecognizers();
      _buildRuns();
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _buildRuns() {
    final essay = widget.essay;
    final matches = <List<int>>[]; // [start, end, annotationIndex]

    for (var i = 0; i < widget.annotations.length; i++) {
      final phrase = widget.annotations[i]['highlighted_text']?.toString() ?? '';
      if (phrase.isEmpty) continue;
      // Walk past any occurrence an earlier note already claimed, so two
      // notes on the same repeated phrase both land somewhere.
      var from = 0;
      while (true) {
        final at = essay.indexOf(phrase, from);
        if (at == -1) break;
        final end = at + phrase.length;
        if (!matches.any((m) => at < m[1] && end > m[0])) {
          matches.add([at, end, i]);
          break;
        }
        from = at + 1;
      }
    }
    matches.sort((a, b) => a[0].compareTo(b[0]));

    _runs = [];
    var cursor = 0;
    for (final match in matches) {
      if (match[0] > cursor) _runs.add(_Run(essay.substring(cursor, match[0]), null));
      _runs.add(_Run(essay.substring(match[0], match[1]), match[2]));
      _recognizers[match[2]] = TapGestureRecognizer()..onTap = () => _openNote(match[2]);
      cursor = match[1];
    }
    if (cursor < essay.length) _runs.add(_Run(essay.substring(cursor), null));
  }

  void _openNote(int index) {
    setState(() => _active = index);
    final annotation = widget.annotations[index];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final wr = sheetContext.wr;
        return Container(
          decoration: BoxDecoration(
            color: wr.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: wr.faint,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Text(
                    'HIGHLIGHT ${index + 1} OF ${widget.annotations.length}',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                      color: wr.faint,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: wr.highlight.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(12),
                              border: Border(
                                left: BorderSide(color: wr.highlight, width: 3),
                              ),
                            ),
                            child: Text(
                              annotation['highlighted_text']?.toString() ?? '',
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 14,
                                height: 1.5,
                                fontStyle: FontStyle.italic,
                                color: wr.text,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            annotation['note']?.toString() ?? '',
                            style: TextStyle(
                              fontFamily: 'SF Pro',
                              fontSize: 14.5,
                              height: 1.55,
                              color: wr.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) setState(() => _active = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final base = TextStyle(fontFamily: 'SF Pro', fontSize: 14.5, height: 1.7, color: wr.text);
    final bold = base.copyWith(fontWeight: FontWeight.w700);

    if (widget.essay.trim().isEmpty) {
      return Text(
        'This sample has no essay text yet.',
        style: base.copyWith(color: wr.muted, fontSize: 13.5),
      );
    }

    final spans = <InlineSpan>[];
    for (final run in _runs) {
      final index = run.annotationIndex;
      if (index == null) {
        spans.addAll(wInlineBoldSpans(run.text, boldStyle: bold));
        continue;
      }
      spans.add(
        TextSpan(
          text: run.text,
          recognizer: _recognizers[index],
          style: base.copyWith(
            fontWeight: FontWeight.w600,
            backgroundColor: wr.highlight.withValues(alpha: _active == index ? 0.65 : 0.32),
          ),
        ),
      );
    }

    return Text.rich(TextSpan(style: base, children: spans));
  }
}

class _Run {
  const _Run(this.text, this.annotationIndex);
  final String text;

  /// Index into the annotations list, or null for ordinary prose.
  final int? annotationIndex;
}

// ---------------------------------------------------------------------------
// Commentary
// ---------------------------------------------------------------------------

/// The examiner's write-up, as paragraphs rather than one wall of text.
///
/// Tutors write these in markdown — a bold band line, then a bold heading per
/// criterion — so it goes through [wInlineBoldSpans] and splits on blank lines.
class _CommentaryCard extends StatelessWidget {
  const _CommentaryCard({required this.comment});
  final String comment;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final base = TextStyle(fontFamily: 'SF Pro', fontSize: 14, height: 1.6, color: wr.text);
    final bold = base.copyWith(fontWeight: FontWeight.w700);
    final paragraphs = comment
        .split(RegExp(r'\n\s*\n'))
        .map((block) => block.trim())
        .where((block) => block.isNotEmpty)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: wCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < paragraphs.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Text.rich(TextSpan(style: base, children: wInlineBoldSpans(paragraphs[i], boldStyle: bold))),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Try it yourself
// ---------------------------------------------------------------------------

/// Pinned invitation to answer the same task.
///
/// Below the model answer rather than above it: a student who came here came
/// to read one, and the moment they have is the moment they can write it
/// themselves. The editor it opens is the ordinary one, with its own quota
/// pill and Plus wall, so nothing about the limits is decided here.
class _TryItBar extends StatelessWidget {
  const _TryItBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return Container(
      decoration: BoxDecoration(
        color: wr.card,
        border: Border(top: BorderSide(color: wr.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Write your own answer and have it marked by AI',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, color: wr.muted),
              ),
              const SizedBox(height: 10),
              MtPrimaryButton(label: 'Try this question yourself', onPressed: onTap),
            ],
          ),
        ),
      ),
    );
  }
}
