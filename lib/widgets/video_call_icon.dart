import 'package:flutter/material.dart';

/// The video-call glyph used in a chat header: a thin outlined camera body with
/// a wedge-shaped lens, drawn the way Instagram draws it.
///
/// Painted rather than picked from an icon font because no Material glyph has
/// this silhouette — `videocam` puts a solid triangle inside a filled block,
/// which reads as "record a video" rather than "call this person".
class VideoCallIcon extends StatelessWidget {
  final double size;
  final Color color;

  /// Stroke weight at [size] 24; scaled with the icon so a larger button keeps
  /// the same visual weight.
  final double strokeWidth;

  const VideoCallIcon({
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
        painter: _VideoCallIconPainter(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _VideoCallIconPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const _VideoCallIconPainter({required this.color, required this.strokeWidth});

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

    final body = RRect.fromRectAndRadius(
      Rect.fromLTRB(2.2 * s, 6.0 * s, 16.4 * s, 18.0 * s),
      Radius.circular(3.4 * s),
    );
    canvas.drawRRect(body, paint);

    // The lens: a trapezoid opening away from the body, its tall edge flush
    // with the right of the grid.
    final lens = Path()
      ..moveTo(18.0 * s, 10.6 * s)
      ..lineTo(22.0 * s, 7.6 * s)
      ..lineTo(22.0 * s, 16.4 * s)
      ..lineTo(18.0 * s, 13.4 * s)
      ..close();
    canvas.drawPath(lens, paint);
  }

  @override
  bool shouldRepaint(_VideoCallIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
