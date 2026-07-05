import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../widgets/mock_test_styles.dart';

/// Read-only view of a real Writing sample essay: tutor, prompt, sample
/// essay text (with tap-to-reveal examiner highlights), achieved band
/// score, and overall examiner commentary. No submission or grading.
class WritingSampleScreen extends StatelessWidget {
  const WritingSampleScreen({super.key, required this.sample});

  final Map<String, dynamic> sample;

  @override
  Widget build(BuildContext context) {
    final imageUrl = sample['image_url'] as String?;
    final band = sample['band_score']?.toString();
    final examinerComment = sample['examiner_comment']?.toString() ?? '';
    final tutorName = sample['tutor_name']?.toString() ?? '';
    final tutorImageUrl = sample['tutor_image_url'] as String?;
    final essay = sample['sample_essay_html']?.toString() ?? '';
    final annotations = ((sample['annotations'] as List?) ?? const []).cast<Map<String, dynamic>>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: sample['title']?.toString() ?? 'Writing sample'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (tutorName.isNotEmpty) ...[
            _TutorHeader(name: tutorName, imageUrl: tutorImageUrl),
            const SizedBox(height: 20),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: mtSoftCard(color: MockTestColors.chipBg, radius: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl != null && imageUrl.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      color: Colors.white,
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2, color: MockTestColors.yellow),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'Could not load chart image',
                              style: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.greyLight, fontSize: 12.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  sample['prompt_html']?.toString() ?? '',
                  style: const TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 14,
                    height: 1.5,
                    color: MockTestColors.navy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (band != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(color: MockTestColors.navy, borderRadius: BorderRadius.circular(20)),
              child: Column(
                children: [
                  const Text(
                    'BAND SCORE',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    band,
                    style: const TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text(
                'Sample essay',
                style: TextStyle(fontFamily: 'SF Pro', fontWeight: FontWeight.w700, fontSize: 15, color: MockTestColors.navy),
              ),
              if (annotations.isNotEmpty) ...[
                const SizedBox(width: 8),
                Icon(Icons.touch_app_rounded, size: 15, color: MockTestColors.grey),
                const SizedBox(width: 3),
                const Text(
                  'tap highlights for notes',
                  style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, color: MockTestColors.grey),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: mtSoftCard(radius: 14),
            child: _AnnotatedEssay(essay: essay, annotations: annotations),
          ),
          if (examinerComment.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Why this scores well',
              style: TextStyle(fontFamily: 'SF Pro', fontWeight: FontWeight.w700, fontSize: 15, color: MockTestColors.navy),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: mtSoftCard(color: MockTestColors.chipBg, radius: 14),
              child: Text(
                examinerComment,
                style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14, height: 1.5, color: MockTestColors.navy),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TutorHeader extends StatelessWidget {
  const _TutorHeader({required this.name, required this.imageUrl});
  final String name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: (imageUrl != null && imageUrl!.isNotEmpty)
              ? Image.network(
                  imageUrl!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _fallbackAvatar(),
                )
              : _fallbackAvatar(),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SAMPLE BY',
                style: TextStyle(fontFamily: 'SF Pro', fontSize: 11, fontWeight: FontWeight.w700, color: MockTestColors.greyLight, letterSpacing: 0.8),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: const TextStyle(fontFamily: 'SF Pro', fontSize: 16, fontWeight: FontWeight.w700, color: MockTestColors.navy),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fallbackAvatar() {
    return Container(
      width: 56,
      height: 56,
      color: MockTestColors.chipBg,
      alignment: Alignment.center,
      child: const Icon(Icons.person_rounded, color: MockTestColors.greyLight, size: 28),
    );
  }
}

/// Renders [essay] as plain text, except phrases matching an annotation's
/// `highlighted_text` are shown with a highlight background; tapping one
/// opens a bottom sheet with the examiner's note. Falls back to plain text
/// when there are no annotations or none of them match the essay.
class _AnnotatedEssay extends StatefulWidget {
  const _AnnotatedEssay({required this.essay, required this.annotations});

  final String essay;
  final List<Map<String, dynamic>> annotations;

  @override
  State<_AnnotatedEssay> createState() => _AnnotatedEssayState();
}

class _AnnotatedEssayState extends State<_AnnotatedEssay> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  void _showNote(String highlightedText, String note) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: mtSoftCard(color: MockTestColors.yellow.withValues(alpha: 0.25), radius: 8),
              child: Text(
                '"$highlightedText"',
                style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, fontStyle: FontStyle.italic, color: MockTestColors.navy),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              note,
              style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14.5, height: 1.5, color: MockTestColors.navy),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(fontFamily: 'SF Pro', fontSize: 14, height: 1.6, color: MockTestColors.navy);
    final highlightStyle = baseStyle.copyWith(
      fontWeight: FontWeight.w700,
      backgroundColor: MockTestColors.yellow.withValues(alpha: 0.35),
    );

    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    if (widget.annotations.isEmpty) {
      return Text(widget.essay, style: baseStyle);
    }

    final matches = <(int start, int end, String text, String note)>[];
    for (final a in widget.annotations) {
      final phrase = a['highlighted_text']?.toString() ?? '';
      if (phrase.isEmpty) continue;
      final start = widget.essay.indexOf(phrase);
      if (start == -1) continue;
      matches.add((start, start + phrase.length, phrase, a['note']?.toString() ?? ''));
    }
    matches.sort((a, b) => a.$1.compareTo(b.$1));

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in matches) {
      if (m.$1 < cursor) continue; // overlapping match — skip
      if (m.$1 > cursor) spans.add(TextSpan(text: widget.essay.substring(cursor, m.$1)));
      final recognizer = TapGestureRecognizer()..onTap = () => _showNote(m.$3, m.$4);
      _recognizers.add(recognizer);
      spans.add(TextSpan(text: m.$3, style: highlightStyle, recognizer: recognizer));
      cursor = m.$2;
    }
    if (cursor < widget.essay.length) {
      spans.add(TextSpan(text: widget.essay.substring(cursor)));
    }

    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }
}
