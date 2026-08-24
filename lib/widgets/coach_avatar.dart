import 'dart:math' as math;

import 'package:flutter/material.dart';

/// What the character is doing.
enum CoachMood { idle, listening, thinking, speaking }

/// The character's own palette.
///
/// Deliberately not in [AppColors]: a face is a face in both themes — skin
/// that flipped to a dark tone at night would read as a different person
/// rather than the same one in a dark room — so these never flip, and five
/// non-flipping fields would be five fields of ceremony in a token class whose
/// whole point is flipping. Only the panel behind the character is themed. Its
/// hair and shirt are not here either: those are the persona's accent colour,
/// which the API sends.
const _skin = Color(0xFFF3CFB2);
const _skinShade = Color(0xFFE0B394);
const _ink = Color(0xFF2B2C3D);
const _eyeWhite = Color(0xFFFFFFFF);
const _mouthColor = Color(0xFF8C4450);

/// One blink every five and a bit seconds, shut for a twentieth of that.
const _blinkPeriod = Duration(milliseconds: 5400);

/// The idle bob: a breath, not a bounce.
const _bobPeriod = Duration(milliseconds: 3400);

/// The coach, drawn.
///
/// An emoji in a circle is a label; this is meant to be someone to talk to. It
/// blinks on its own, looks up while it is thinking, and opens its mouth to
/// [level] while the reply plays. It is painted rather than shipped as an
/// asset: five characters at every size, themed and animated, out of one file
/// and no downloads.
///
/// Mirrors `CoachAvatar.tsx` on the web, down to the coordinates — both draw
/// on a 120×120 canvas, so a change to one can be read across to the other.
class CoachAvatar extends StatefulWidget {
  const CoachAvatar({
    super.key,
    required this.persona,
    required this.accent,
    this.mood = CoachMood.idle,
    this.level = 0,
    this.size = 44,
  });

  final String persona;

  /// The character's colour, straight from the API: its hair and its shirt.
  final Color accent;
  final CoachMood mood;

  /// 0–1, how wide the mouth is open right now.
  final double level;
  final double size;

  @override
  State<CoachAvatar> createState() => _CoachAvatarState();
}

class _CoachAvatarState extends State<CoachAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: _blinkPeriod)..repeat();
  late final AnimationController _bob =
      AnimationController(vsync: this, duration: _bobPeriod)..repeat();

  @override
  void dispose() {
    _blink.dispose();
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A character that will not hold still is exactly what someone who asked
    // for less motion asked to be spared. Eyes open, head level.
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final bobbing =
        widget.mood == CoachMood.idle || widget.mood == CoachMood.thinking;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_blink, _bob]),
        builder: (context, _) {
          // Shut for the last 6% of the cycle, which is roughly a real blink
          // against a five-second gap.
          final phase = _blink.value;
          final openness = still
              ? 1.0
              : phase < 0.94
                  ? 1.0
                  : phase < 0.97
                      ? 0.06
                      : 1.0;
          final bob = !still && bobbing
              ? -2 * math.sin(_bob.value * 2 * math.pi).abs()
              : 0.0;

          return CustomPaint(
            painter: _CoachPainter(
              persona: widget.persona,
              accent: widget.accent,
              mood: widget.mood,
              level: widget.level.clamp(0.0, 1.0),
              eyeOpenness: openness,
              bob: bob,
            ),
          );
        },
      ),
    );
  }
}

class _CoachPainter extends CustomPainter {
  _CoachPainter({
    required this.persona,
    required this.accent,
    required this.mood,
    required this.level,
    required this.eyeOpenness,
    required this.bob,
  });

  final String persona;
  final Color accent;
  final CoachMood mood;
  final double level;
  final double eyeOpenness;
  final double bob;

  /// Where the pupils sit. Looking up while thinking and straight ahead while
  /// listening is most of the acting this face does.
  Offset get _gaze => switch (mood) {
        CoachMood.thinking => const Offset(-1.6, -1.8),
        CoachMood.listening => const Offset(0, 0.6),
        _ => Offset.zero,
      };

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 120, size.height / 120);

    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Shoulders, in the character's colour: at bubble size this is often the
    // only part of them big enough to read, and it is what makes a row of
    // replies identifiable at a glance.
    final shoulders = Path()
      ..moveTo(18, 120)
      ..cubicTo(18, 104, 32, 94, 60, 94)
      ..cubicTo(88, 94, 102, 104, 102, 120)
      ..close();
    canvas.drawPath(shoulders, fill..color = accent.withValues(alpha: 0.9));
    canvas.drawRect(
      const Rect.fromLTWH(52, 84, 16, 14),
      fill..color = _skinShade,
    );

    canvas.save();
    canvas.translate(0, bob);

    // Ears sit a little proud of the head, or the silhouette is a rounded
    // rectangle and the character reads as an icon.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(28, 59), width: 10, height: 13),
      fill..color = _skinShade,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(92, 59), width: 10, height: 13),
      fill..color = _skinShade,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(30, 26, 60, 64),
        const Radius.circular(26),
      ),
      fill..color = _skin,
    );

    _paintHair(canvas, fill);
    _paintBrows(canvas, stroke);
    _paintEyes(canvas, fill);
    if (persona == 'classic' || persona == 'examiner') {
      _paintGlasses(canvas, stroke);
    }
    _paintMouth(canvas, fill, stroke);

    canvas.restore();
    canvas.restore();
  }

  /// Hair and headgear, which is where the five characters separate. Anything
  /// unrecognised gets the plain style in its own colour, so a sixth character
  /// added in the database is not a bald one.
  void _paintHair(Canvas canvas, Paint fill) {
    final shade = Color.lerp(accent, Colors.black, 0.28)!;

    switch (persona) {
      case 'classic':
        final hair = Path()
          ..moveTo(28, 44)
          ..cubicTo(28, 28, 42, 20, 60, 20)
          ..cubicTo(78, 20, 92, 28, 92, 44)
          ..lineTo(92, 47)
          ..cubicTo(88, 39, 78, 35, 60, 35)
          ..cubicTo(42, 35, 32, 39, 28, 47)
          ..close();
        canvas.drawPath(hair, fill..color = accent);

        // Mortarboard.
        final board = Path()
          ..moveTo(60, 8)
          ..lineTo(96, 22)
          ..lineTo(60, 36)
          ..lineTo(24, 22)
          ..close();
        canvas.drawPath(board, fill..color = shade);
        canvas.drawLine(
          const Offset(92, 24),
          const Offset(92, 37),
          Paint()
            ..color = shade
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(const Offset(92, 39), 3, fill..color = shade);

      case 'buddy':
        final cap = Path()
          ..moveTo(28, 44)
          ..cubicTo(28, 28, 42, 18, 60, 18)
          ..cubicTo(78, 18, 92, 28, 92, 44)
          ..lineTo(92, 46)
          ..lineTo(28, 46)
          ..close();
        canvas.drawPath(cap, fill..color = accent);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(26, 45, 68, 6),
            const Radius.circular(3),
          ),
          fill..color = shade,
        );
        // Worn backwards, which is the whole character in one shape.
        final flap = Path()
          ..moveTo(22, 46)
          ..lineTo(32, 46)
          ..lineTo(32, 55)
          ..cubicTo(25, 55, 22, 51, 22, 46)
          ..close();
        canvas.drawPath(flap, fill..color = shade);

      case 'sarcastic':
        final hair = Path()
          ..moveTo(27, 48)
          ..cubicTo(25, 29, 40, 18, 60, 18)
          ..cubicTo(80, 18, 94, 29, 92, 48)
          ..cubicTo(89, 38, 83, 33, 76, 31)
          ..cubicTo(68, 38, 52, 41, 41, 37)
          ..cubicTo(33, 39, 29, 43, 27, 48)
          ..close();
        canvas.drawPath(hair, fill..color = accent);

      default:
        final hair = Path()
          ..moveTo(28, 46)
          ..cubicTo(28, 29, 42, 20, 60, 20)
          ..cubicTo(78, 20, 92, 29, 92, 46)
          ..lineTo(92, 48)
          ..cubicTo(88, 38, 77, 33, 60, 33)
          ..cubicTo(43, 33, 32, 38, 28, 48)
          ..close();
        canvas.drawPath(hair, fill..color = accent);
        if (persona == 'examiner') {
          // A parting: the only character whose hair has a line in it.
          canvas.drawPath(
            Path()
              ..moveTo(52, 22)
              ..cubicTo(48, 28, 44, 30, 36, 31),
            Paint()
              ..style = PaintingStyle.stroke
              ..color = Color.lerp(accent, Colors.black, 0.25)!
              ..strokeWidth = 2.2
              ..strokeCap = StrokeCap.round,
          );
        }
    }
  }

  /// Brows carry the state: up while thinking, angled down for the strict one,
  /// one raised for the sarcastic one.
  void _paintBrows(Canvas canvas, Paint stroke) {
    final lift = mood == CoachMood.thinking ? -3.0 : 0.0;
    final paint = stroke
      ..color = _ink
      ..strokeWidth = 2.6;

    switch (persona) {
      case 'strict':
        canvas.drawLine(
            Offset(39, 45 + lift), Offset(52, 49 + lift), paint);
        canvas.drawLine(
            Offset(81, 45 + lift), Offset(68, 49 + lift), paint);
      case 'sarcastic':
        canvas.drawPath(
          Path()
            ..moveTo(40, 47 + lift)
            ..quadraticBezierTo(46, 44 + lift, 52, 46 + lift),
          paint,
        );
        // The raised one. Everything else about this character follows it.
        canvas.drawPath(
          Path()
            ..moveTo(68, 42 + lift)
            ..quadraticBezierTo(74, 38 + lift, 80, 42 + lift),
          paint,
        );
      default:
        canvas.drawPath(
          Path()
            ..moveTo(40, 46 + lift)
            ..quadraticBezierTo(46, 42 + lift, 52, 45 + lift),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(80, 46 + lift)
            ..quadraticBezierTo(74, 42 + lift, 68, 45 + lift),
          paint,
        );
    }
  }

  void _paintEyes(Canvas canvas, Paint fill) {
    for (final cx in const [46.0, 74.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, 57),
          width: 12.8,
          // The lid, as a squash rather than a drawn eyelid: one number, and
          // it stays correct at every size.
          height: 14.4 * eyeOpenness,
        ),
        fill..color = _eyeWhite,
      );
      if (eyeOpenness < 0.5) continue;
      canvas.drawCircle(
        Offset(cx + _gaze.dx, 57 + _gaze.dy),
        3.4,
        fill..color = _ink,
      );
      // The catchlight. Without it the pupils are holes.
      canvas.drawCircle(
        Offset(cx + _gaze.dx + 1.3, 57 + _gaze.dy - 1.6),
        1.1,
        fill..color = _eyeWhite,
      );
    }
  }

  void _paintGlasses(Canvas canvas, Paint stroke) {
    final paint = stroke
      ..color = _ink.withValues(alpha: 0.85)
      ..strokeWidth = 1.8;
    if (persona == 'examiner') {
      for (final left in const [38.0, 66.0]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, 50, 16, 14),
            const Radius.circular(3),
          ),
          paint,
        );
      }
    } else {
      canvas.drawCircle(const Offset(46, 57), 8, paint);
      canvas.drawCircle(const Offset(74, 57), 8, paint);
    }
    canvas.drawLine(const Offset(54, 57), const Offset(66, 57), paint);
  }

  /// Speaking scales one shape rather than swapping between drawn visemes: the
  /// level is a volume, not a phoneme, and a mouth that changes shape on
  /// loudness alone lands in the uncanny valley the moment it disagrees with
  /// the consonant being said. Open and closed on the envelope is honest, and
  /// reads correctly at any size.
  void _paintMouth(Canvas canvas, Paint fill, Paint stroke) {
    if (mood == CoachMood.speaking) {
      final open = 1.6 + level * 7;
      canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(60, 72), width: 15, height: open * 2),
        fill..color = _mouthColor,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(60, 72 + open * 0.45),
          width: 9.2,
          height: open * 0.8,
        ),
        fill..color = _skinShade.withValues(alpha: 0.55),
      );
      return;
    }

    final paint = stroke
      ..color = _ink
      ..strokeWidth = 2.4;

    switch (persona) {
      case 'strict':
        // A straight line. The one character who does not smile at rest.
        canvas.drawLine(const Offset(52, 72), const Offset(68, 72), paint);
      case 'sarcastic':
        // Up on one side only.
        canvas.drawPath(
          Path()
            ..moveTo(52, 71)
            ..quadraticBezierTo(59, 77, 67, 69),
          paint,
        );
      case 'buddy':
        canvas.drawPath(
          Path()
            ..moveTo(50, 70)
            ..quadraticBezierTo(60, 79, 70, 70),
          paint,
        );
      default:
        canvas.drawPath(
          Path()
            ..moveTo(53, 71)
            ..quadraticBezierTo(60, 76, 67, 71),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_CoachPainter old) =>
      old.persona != persona ||
      old.accent != accent ||
      old.mood != mood ||
      old.level != level ||
      old.eyeOpenness != eyeOpenness ||
      old.bob != bob;
}
