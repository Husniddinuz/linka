import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/ai_coach.dart';
import '../theme/app_colors.dart';

/// The three bands a pronunciation score falls into. Azure's own rough reading
/// of its 0–100 scale: below 60 a listener notices, above 80 they do not.
enum ScoreBand { weak, fair, good }

ScoreBand bandOf(double score) => score < 60
    ? ScoreBand.weak
    : score < 80
        ? ScoreBand.fair
        : ScoreBand.good;

Color bandColor(BuildContext context, double score) => switch (bandOf(score)) {
      ScoreBand.weak => context.colors.error,
      ScoreBand.fair => context.colors.accentYellow,
      ScoreBand.good => context.colors.success,
    };

/// The same bands as text.
///
/// The middle band is the exception: `accentYellow` is a fill colour, and a
/// yellow numeral on a white card is the one combination in the palette that
/// cannot be read. The ring beside it already carries the colour, so the
/// number can afford to be ink.
Color _bandInk(BuildContext context, double score) => switch (bandOf(score)) {
      ScoreBand.weak => context.colors.error,
      ScoreBand.fair => context.colors.textPrimary,
      ScoreBand.good => context.colors.success,
    };

String _bandLabel(double score) => switch (bandOf(score)) {
      ScoreBand.weak => 'A listener would notice',
      ScoreBand.fair => 'Understandable, not clean',
      ScoreBand.good => 'Clear',
    };

const _errorTypeLabels = {
  'Mispronunciation': 'mispronounced',
  'Omission': 'skipped',
  'Insertion': 'extra word',
};

/// How the last take sounded — Azure's scores, and the sounds behind them.
///
/// `weakSounds` leads rather than the word list because it is the finding:
/// /θ/ failing in *think*, *three* and *things* is one thing to practise, not
/// three. The words are the evidence, and they sit behind a tap.
class CoachPronunciationCard extends StatefulWidget {
  const CoachPronunciationCard({super.key, required this.pronunciation});

  final Pronunciation pronunciation;

  @override
  State<CoachPronunciationCard> createState() => _CoachPronunciationCardState();
}

class _CoachPronunciationCardState extends State<CoachPronunciationCard> {
  bool _wordsOpen = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final score = widget.pronunciation;
    final sounds = score.weakSounds.entries.toList();
    final words = score.weakWords;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        // The band colour as a left edge: the card is identifiable as good or
        // bad before a word of it is read.
        gradient: LinearGradient(
          colors: [
            bandColor(context, score.overall),
            bandColor(context, score.overall),
            colors.surface,
          ],
          stops: const [0, 0.008, 0.008],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Dial(score: score.overall),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HOW THAT SOUNDED',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: colors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _bandLabel(score.overall),
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SubScore(label: 'Sounds', value: score.accuracy),
                      _SubScore(label: 'Flow', value: score.fluency),
                      _SubScore(label: 'Stress', value: score.prosody),
                      _SubScore(label: 'Covered', value: score.completeness),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (sounds.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                color: colors.surfaceAlt.withValues(alpha: 0.5),
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SOUNDS TO WORK ON',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final sound in sounds)
                        _SoundChip(sound: sound.key, examples: sound.value),
                    ],
                  ),
                ],
              ),
            ),

          if (words.isNotEmpty) ...[
            InkWell(
              onTap: () => setState(() => _wordsOpen = !_wordsOpen),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${words.length} ${words.length == 1 ? 'word' : 'words'} to look at',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Icon(
                      _wordsOpen
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: colors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
            if (_wordsOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final word in words) _WordChip(word: word)],
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Text(
                'Nothing came out badly in this one.',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The score as a dial rather than a number with a slash in it: a ring reads
/// at a glance, which is how this is read — in the gap while the coach is
/// still talking.
class _Dial extends StatelessWidget {
  const _Dial({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 58,
      child: CustomPaint(
        painter: _DialPainter(
          score: score,
          track: context.colors.surfaceAlt,
          colour: bandColor(context, score),
        ),
        child: Center(
          child: Text(
            score.round().toString(),
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _bandInk(context, score),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.score,
    required this.track,
    required this.colour,
  });

  final double score;
  final Color track;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(3, 3, size.width - 6, size.height - 6);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = track;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * (score.clamp(0, 100) / 100),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = colour,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.score != score || old.colour != colour || old.track != track;
}

class _SubScore extends StatelessWidget {
  const _SubScore({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: colors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: value.clamp(0, 100) / 100,
                minHeight: 4,
                backgroundColor: colors.surfaceAlt,
                valueColor:
                    AlwaysStoppedAnimation(bandColor(context, value)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 24,
            child: Text(
              value.round().toString(),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoundChip extends StatelessWidget {
  const _SoundChip({required this.sound, required this.examples});

  final String sound;
  final List<String> examples;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: colors.errorBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '/$sound/',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: colors.error,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            examples.join(' · '),
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 11.5,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({required this.word});

  final PronouncedWord word;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final note = _errorTypeLabels[word.errorType];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                word.word,
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                word.accuracy.round().toString(),
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _bandInk(context, word.accuracy),
                ),
              ),
            ],
          ),
          if (note != null)
            Text(
              note,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 10,
                color: colors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}
