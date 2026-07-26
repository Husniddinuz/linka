import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Curated cover gradients. Episodes ship without artwork, so each one gets a
/// stable gradient picked from this set — deep, saturated pairs that sit
/// comfortably next to the navy brand color in both light and dark mode.
const List<List<Color>> _coverGradients = [
  [Color(0xFF3A3D6B), Color(0xFF272942)],
  [Color(0xFF4B3A6B), Color(0xFF2B2440)],
  [Color(0xFF1F5C63), Color(0xFF1B3140)],
  [Color(0xFF6B4A2E), Color(0xFF3A2A20)],
  [Color(0xFF2E5A8C), Color(0xFF1E2E4A)],
  [Color(0xFF6B3350), Color(0xFF361F30)],
  [Color(0xFF3E6B45), Color(0xFF1F3527)],
  [Color(0xFF5A4B8C), Color(0xFF2A2447)],
];

/// Deterministic gradient for [seed] (an episode title or id) so the same
/// episode always looks the same, in every list and on the player.
List<Color> podcastGradient(String seed) {
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _coverGradients[hash % _coverGradients.length];
}

/// Episode cover art: the remote image when one exists, otherwise a generated
/// gradient tile with the podcast glyph and a soft arc motif.
///
/// Optionally overlays animated equalizer bars while the episode is the one
/// currently playing.
class PodcastArtwork extends StatelessWidget {
  final String seed;
  final String? imageUrl;
  final double size;
  final double borderRadius;

  /// Shows the animated now-playing bars over the cover.
  final bool playing;

  const PodcastArtwork({
    super.key,
    required this.seed,
    this.imageUrl,
    this.size = 56,
    this.borderRadius = 14,
    this.playing = false,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = podcastGradient(seed);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null && imageUrl!.isNotEmpty)
              Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _GeneratedCover(
                  gradient: gradient,
                  size: size,
                ),
              )
            else
              _GeneratedCover(gradient: gradient, size: size),
            if (playing)
              Container(
                color: Colors.black.withValues(alpha: 0.35),
                alignment: Alignment.center,
                child: EqualizerBars(
                  color: Colors.white,
                  height: math.max(12, size * 0.28),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GeneratedCover extends StatelessWidget {
  final List<Color> gradient;
  final double size;
  const _GeneratedCover({required this.gradient, required this.size});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      child: CustomPaint(
        painter: _ArcMotifPainter(color: Colors.white.withValues(alpha: 0.08)),
        child: Center(
          child: SvgPicture.asset(
            'assets/images/icons/podcast.svg',
            width: size * 0.4,
            height: size * 0.4,
            colorFilter: ColorFilter.mode(
              Colors.white.withValues(alpha: 0.92),
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }
}

/// Concentric arcs radiating from the bottom-left — a broadcast-signal motif
/// that gives the generated covers some texture without competing with the
/// glyph.
class _ArcMotifPainter extends CustomPainter {
  final Color color;
  const _ArcMotifPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.045
      ..color = color;
    final center = Offset(size.width * 0.12, size.height * 0.92);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, size.width * 0.22 * i, paint);
    }
  }

  @override
  bool shouldRepaint(_ArcMotifPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Four bars bouncing at slightly different rates — the universal "audio is
/// playing right now" cue. Stops animating (and rests flat) when [playing] is
/// false so a paused row doesn't draw the eye.
class EqualizerBars extends StatefulWidget {
  final Color color;
  final double height;
  final bool playing;

  const EqualizerBars({
    super.key,
    required this.color,
    this.height = 16,
    this.playing = true,
  });

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  // Phase offsets keep the bars out of lockstep.
  static const _phases = [0.0, 0.35, 0.6, 0.85];

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barWidth = widget.height * 0.18;
    return SizedBox(
      height: widget.height,
      width: barWidth * 7,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final phase in _phases) ...[
                _bar(barWidth, phase),
                if (phase != _phases.last) SizedBox(width: barWidth * 0.7),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _bar(double width, double phase) {
    final t = widget.playing
        ? (math.sin((_controller.value + phase) * 2 * math.pi) + 1) / 2
        : 0.0;
    return Container(
      width: width,
      height: widget.height * (0.25 + 0.75 * t),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(width),
      ),
    );
  }
}
