import 'package:flutter/material.dart';

/// The voice-call glyph used in a chat header: a thin outlined handset, drawn
/// as a single stroked contour.
///
/// Painted rather than picked from an icon font for the opposite reason to
/// [VideoCallIcon]: the Material handset — `call`, `call_outlined` and the
/// Symbols redraw alike — is a *solid* shape. A handset has no interior, so
/// the "outlined" variants have nothing to hollow out and all render as the
/// same filled blob, which sits much heavier than the outlined glyphs beside
/// it in the app bar. This traces the silhouette instead of filling it.
class PhoneCallIcon extends StatelessWidget {
  final double size;
  final Color color;

  /// Stroke weight at [size] 24; scaled with the icon so a larger button keeps
  /// the same visual weight.
  final double strokeWidth;

  const PhoneCallIcon({
    super.key,
    this.size = 24,
    required this.color,
    this.strokeWidth = 2,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PhoneCallIconPainter(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _PhoneCallIconPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const _PhoneCallIconPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    // Laid out on a 24×24 grid, then scaled to whatever the widget was given.
    final s = size.width / 24;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * s
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = color;

    // The handset contour, walked clockwise from the lower-right earpiece.
    // The two big-radius arcs are the gentle inward curve of the handset's
    // waist; the small r=2 arcs are its rounded corners.
    Offset p(double x, double y) => Offset(x * s, y * s);
    Radius r(double v) => Radius.circular(v * s);

    final path = Path()
      ..moveTo(22 * s, 16.92 * s)
      ..lineTo(22 * s, 19.92 * s)
      ..arcToPoint(p(19.82, 21.92), radius: r(2))
      ..arcToPoint(p(11.19, 18.85), radius: r(19.79))
      ..arcToPoint(p(5.19, 12.85), radius: r(19.5))
      ..arcToPoint(p(2.12, 4.18), radius: r(19.79))
      ..arcToPoint(p(4.11, 2), radius: r(2))
      ..lineTo(7.11 * s, 2 * s)
      ..arcToPoint(p(9.11, 3.72), radius: r(2))
      ..arcToPoint(p(9.81, 6.53), radius: r(12.84), clockwise: false)
      ..arcToPoint(p(9.36, 8.64), radius: r(2))
      ..lineTo(8.09 * s, 9.91 * s)
      ..arcToPoint(p(14.09, 15.91), radius: r(16), clockwise: false)
      ..lineTo(15.36 * s, 14.64 * s)
      ..arcToPoint(p(17.47, 14.19), radius: r(2))
      ..arcToPoint(p(20.28, 14.89), radius: r(12.84), clockwise: false)
      ..arcToPoint(p(22, 16.92), radius: r(2))
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PhoneCallIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
