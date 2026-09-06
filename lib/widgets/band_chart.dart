import 'package:flutter/material.dart';

import 'writing_report.dart';

/// A band history as an animated sparkline: writing essays, mock-test
/// sittings, speaking answers — anything scored 0–9 over time.
///
/// Plotted against the full 0–9 scale rather than against the student's own
/// min and max: auto-scaling would turn a half-band wobble into a dramatic
/// climb, which is exactly the false encouragement a progress screen must not
/// give. Renders nothing with fewer than two points — one point is a number,
/// not a trend.
class BandChart extends StatelessWidget {
  const BandChart({super.key, required this.bands, this.height = 96, this.color});

  /// Oldest first — the chart reads left to right through time.
  final List<double> bands;
  final double height;

  /// The line colour. Defaults to the report accent.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (bands.length < 2) return const SizedBox.shrink();
    final wr = context.wr;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1000),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: BandChartPainter(
            bands: bands,
            progress: t,
            line: color ?? wr.accent,
            grid: wr.line,
            dot: wr.card,
          ),
        ),
      ),
    );
  }
}

class BandChartPainter extends CustomPainter {
  BandChartPainter({
    required this.bands,
    required this.progress,
    required this.line,
    required this.grid,
    required this.dot,
  });

  final List<double> bands;
  final double progress;
  final Color line;
  final Color grid;

  /// The ring drawn around each point, so it reads as a marker rather than a
  /// blob wherever the line doubles back. Matches the card behind it.
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.length < 2) return;

    const inset = 6.0;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final band in [9.0, 6.0, 3.0]) {
      final y = size.height - (band / 9) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final step = (size.width - inset * 2) / (bands.length - 1);
    final points = <Offset>[
      for (var i = 0; i < bands.length; i++)
        Offset(
          inset + i * step,
          size.height - (bands[i].clamp(0.0, 9.0) / 9) * (size.height - inset) - inset / 2,
        ),
    ];

    final visible = (points.length * progress).ceil().clamp(2, points.length);
    final shown = points.sublist(0, visible);

    final path = Path()..moveTo(shown.first.dx, shown.first.dy);
    for (final point in shown.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    final area = Path.from(path)
      ..lineTo(shown.last.dx, size.height)
      ..lineTo(shown.first.dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = line.withValues(alpha: 0.14));

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (final point in shown) {
      canvas.drawCircle(point, 3.6, Paint()..color = line);
      canvas.drawCircle(
        point,
        3.6,
        Paint()
          ..color = dot
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BandChartPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.bands != bands || oldDelegate.line != line;
}
