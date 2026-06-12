import 'package:flutter/material.dart';

/// Ribbon-style "NEW" flag shown on recently published content (podcasts,
/// articles). Driven by the `is_new` flag from the content endpoints.
///
/// Rendered as a fishtail banner in the brand yellow with bold navy text so it
/// stays highly visible on a white row or on top of any colored card band.
class NewBadge extends StatelessWidget {
  /// When true, adds a white outline so the ribbon separates cleanly from a
  /// colored background (e.g. the article card image band).
  final bool onColored;

  const NewBadge({super.key, this.onColored = false});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RibbonPainter(outline: onColored),
      child: const Padding(
        // Extra right padding leaves room for the fishtail notch.
        padding: EdgeInsets.fromLTRB(9, 4, 15, 4),
        child: Text(
          'NEW',
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Color(0xFF272942),
            letterSpacing: 1.0,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  final bool outline;
  const _RibbonPainter({required this.outline});

  static const double _notch = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - _notch, size.height / 2)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    // Soft shadow so the ribbon lifts off the surface.
    canvas.drawShadow(path, const Color(0xFF000000), 2.0, false);

    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFD451), Color(0xFFF5B81E)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, fill);

    if (outline) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white;
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(_RibbonPainter oldDelegate) =>
      oldDelegate.outline != outline;
}
