import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_colors.dart';

/// The coach, as a sphere of dots with rings orbiting it.
///
/// With the microphone open there is nothing to press and nothing to read, so
/// the screen has one job: show that something is there, and that it is doing
/// one of four things. A drawn face has to act, and every frame of that acting
/// is a claim about a person who does not exist. A point cloud claims only
/// what it is — and it can still breathe while it waits, ripple when it hears
/// you, tighten while it thinks, and swell on the amplitude of the reply that
/// is playing.
///
/// Two kinds of point: a shell, evenly spread over the sphere, which is the
/// body of the thing; and four rings on their own axes, whose dots run round
/// them. The shell says how big and how agitated, the rings say it is running
/// — a shell alone at rest is a photograph of a sphere.
///
/// The dots arrive scattered past the edges of the frame and gather into the
/// sphere over about two seconds, which is the first thing the student sees.
///
/// This is the same thing the web draws, at the same numbers, so the two
/// clients are recognisably one product.

/// What the sphere is doing. The names are the student's states, not the
/// screen's: what they are doing outranks what the coach is doing.
enum CoachMood { idle, listening, thinking, speaking }

/// Points in the shell. Fewer than the web's 760 — this runs on a phone, and
/// below about four hundred the surface stops reading as one.
const _shellCount = 520;

/// The golden angle. Points spaced by it on a spiral are the standard even-ish
/// distribution on a sphere; a lat/long grid clumps at the poles, and the
/// clumps rotate past like seams.
final _golden = math.pi * (3 - math.sqrt(5));

/// Brightness steps. Every dot in a step is drawn by one `drawRawPoints` call,
/// so a frame is a dozen draw calls rather than a thousand.
const _buckets = 14;

/// How long the cloud takes to gather.
const _assemblySeconds = 2.2;

/// A pulse of light runs through the cloud this often, and takes this long to
/// cross it. The one idle beat that is unmistakably a machine: a sphere doing
/// nothing at all reads as a still image.
const _sweepPeriod = 6.5;
const _sweepSeconds = 1.4;

/// What every dot carries: where it starts before the sphere assembles, when
/// it sets off, and its own number for the shimmer that keeps neighbours from
/// sitting at exactly the same brightness.
class _Placed {
  _Placed(int seed)
      : sx = math.cos(_hash(seed) * math.pi * 2) *
            (1.7 + _hash(seed + 17) * 1.6) *
            1.4,
        sy = math.sin(_hash(seed) * math.pi * 2) * (1.7 + _hash(seed + 17) * 1.6),
        sz = (_hash(seed + 41) - 0.5) * 2.8,
        delay = _hash(seed + 71),
        seed = seed.toDouble();

  final double sx;
  final double sy;
  final double sz;
  final double delay;
  final double seed;
}

/// A shell dot: a fixed direction out of the centre.
class _Dot extends _Placed {
  _Dot(this.x, this.y, this.z, int seed) : super(seed);

  final double x;
  final double y;
  final double z;
}

/// A ring dot: where on its ring it sits.
class _OrbitDot extends _Placed {
  _OrbitDot(this.phase, int seed) : super(seed);

  final double phase;
}

/// Deterministic noise. `Random` would do, but a stable scatter is easier to
/// look at while tuning it.
double _hash(int seed) {
  final value = math.sin(seed * 127.1 + 311.7) * 43758.5453;
  return value - value.floorToDouble();
}

final List<_Dot> _shell = List.generate(_shellCount, (index) {
  final y = 1 - (index / (_shellCount - 1)) * 2;
  final ring = math.sqrt(math.max(0, 1 - y * y));
  final theta = index * _golden;
  return _Dot(math.cos(theta) * ring, y, math.sin(theta) * ring, index);
});

/// One orbit: a ring on its own axis, turning at its own rate.
class _Orbit {
  _Orbit({
    required double tilt,
    required double turn,
    required this.radius,
    required this.speed,
    required int count,
    required int seed,
  })  : ux = math.cos(turn),
        uy = 0,
        uz = -math.sin(turn),
        vx = math.sin(turn) * math.cos(tilt),
        vy = math.sin(tilt),
        vz = math.cos(turn) * math.cos(tilt),
        dots = List.generate(
          count,
          (step) => _OrbitDot((step / count) * math.pi * 2, seed + step),
        );

  /// Two perpendicular vectors in the ring's plane. A dot on the ring is a
  /// turn of the first towards the second, which is cheaper per frame than
  /// carrying a rotation matrix.
  final double ux;
  final double uy;
  final double uz;
  final double vx;
  final double vy;
  final double vz;
  final double radius;
  final double speed;
  final List<_OrbitDot> dots;
}

/// The axes are deliberately unrelated — rings sharing an axis are a
/// gyroscope, and a gyroscope has a front. These do not, so the sphere reads
/// the same from anywhere and never settles into a pose.
final List<_Orbit> _orbits = [
  _Orbit(tilt: 0.25, turn: 0.4, radius: 1.06, speed: 0.55, count: 84, seed: 5000),
  _Orbit(tilt: 1.15, turn: 2.1, radius: 1.13, speed: -0.38, count: 90, seed: 5400),
  _Orbit(tilt: 2.0, turn: 4.0, radius: 1.0, speed: 0.72, count: 76, seed: 5800),
  _Orbit(tilt: 1.6, turn: 5.3, radius: 1.19, speed: -0.26, count: 96, seed: 6200),
];

/// What the sphere does in each mood.
///
/// `spin` is radians a second, `wobble` the resting deformation of the shell,
/// `scale` the size it settles at, `drive` how much of the amplitude reaches
/// the surface, and `charge` the extra light in it. These are targets: the
/// renderer eases towards whichever set is current, so a change of mood is the
/// sphere changing its mind over half a second rather than a cut.
const _motion = <CoachMood, ({
  double spin,
  double wobble,
  double scale,
  double drive,
  double charge
})>{
  CoachMood.idle: (spin: 0.16, wobble: 0.03, scale: 1, drive: 0, charge: 0),
  CoachMood.listening:
      (spin: 0.24, wobble: 0.045, scale: 1.03, drive: 0.22, charge: 0.1),
  // Thinking pulls in and speeds up: the one mood that should look like work
  // rather than like waiting.
  CoachMood.thinking:
      (spin: 1.15, wobble: 0.075, scale: 0.9, drive: 0.1, charge: 0.06),
  CoachMood.speaking:
      (spin: 0.4, wobble: 0.04, scale: 1.06, drive: 0.3, charge: 0.18),
};

/// Everything the ticker advances and the painter reads. One mutable object
/// rather than a rebuilt painter per frame: at sixty frames a second the
/// allocation is the expensive part.
class _Motion extends ChangeNotifier {
  double clock = 0;
  double spinAngle = 0;
  double spin = 0.16;
  double wobble = 0.03;
  double scale = 1;
  double drive = 0;
  double charge = 0;
  double amplitude = 0;
  double assembly = 0;

  CoachMood mood = CoachMood.idle;
  double level = 0;
  bool calm = false;

  void advance(double step) {
    final target = _motion[mood]!;
    // A first-order chase, framerate-independent: the same half-second settle
    // at 60fps and at 120.
    final ease = 1 - math.pow(0.0015, step).toDouble();
    spin += (target.spin * (calm ? 0.3 : 1) - spin) * ease;
    wobble += (target.wobble * (calm ? 0.35 : 1) - wobble) * ease;
    scale += (target.scale - scale) * ease;
    drive += (target.drive * (calm ? 0.5 : 1) - drive) * ease;
    charge += (target.charge - charge) * ease;
    // The amplitude eases faster: it is the part that has to feel connected to
    // the sound in the room.
    amplitude += (level.clamp(0.0, 1.0) - amplitude) *
        (1 - math.pow(0.02, step).toDouble());

    clock += step;
    spinAngle += spin * step;
    assembly = calm ? 1 : math.min(1, clock / _assemblySeconds);
    notifyListeners();
  }
}

class CoachOrb extends StatefulWidget {
  const CoachOrb({
    super.key,
    this.mood = CoachMood.idle,
    this.level = 0,
    required this.accent,
  });

  final CoachMood mood;

  /// 0–1: the microphone while the student talks, the reply while the coach
  /// does. Whichever of the two is making sound.
  final double level;

  /// The persona's colour, straight from the API.
  final Color accent;

  @override
  State<CoachOrb> createState() => _CoachOrbState();
}

class _CoachOrbState extends State<CoachOrb>
    with SingleTickerProviderStateMixin {
  final _motionState = _Motion();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _motionState.mood = widget.mood;
    _motionState.level = widget.level;
    _ticker.start();
  }

  @override
  void didUpdateWidget(covariant CoachOrb old) {
    super.didUpdateWidget(old);
    _motionState.mood = widget.mood;
    _motionState.level = widget.level;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _motionState.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    // Clamped: a screen that came back from the background returns with a
    // several-second gap, and an unclamped one spins the sphere half a turn on
    // the frame it returns.
    final step = _last == Duration.zero
        ? 0.016
        : math.min(0.05, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    _motionState.advance(step);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    _motionState.calm = MediaQuery.of(context).disableAnimations;
    return RepaintBoundary(
      // Clipped, because the dots start their gathering well outside the box
      // they end up in — a canvas in Flutter paints past its own bounds unless
      // it is told not to, and unclipped this scatters over the whole screen
      // for the first two seconds of every conversation.
      child: ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: _OrbPainter(
            motion: _motionState,
            accent: widget.accent,
            glow: colors.coachGlow,
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.motion,
    required this.accent,
    required this.glow,
  })  : _fills = _palette(accent, glow),
        super(repaint: motion);

  final _Motion motion;
  final Color accent;
  final Color glow;

  /// One colour per brightness step. Near dots run towards the glow token
  /// rather than towards more of the accent: light bleaches, and a hot dot
  /// that stays saturated reads as a bigger dot instead of a nearer one.
  final List<Color> _fills;

  static List<Color> _palette(Color accent, Color glow) =>
      List.generate(_buckets, (bucket) {
        final presence = bucket / (_buckets - 1);
        final amount = math.pow(presence, 1.4).toDouble() * 0.75;
        // Depth as opacity: the far side sits behind the near one without a
        // z-buffer and without sorting a thousand dots a frame.
        final alpha = 0.1 + 0.9 * math.pow(presence, 1.5).toDouble();
        return Color.lerp(accent, glow, amount)!.withValues(alpha: alpha);
      });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final centre = Offset(size.width / 2, size.height / 2);
    // Loudness swells the whole sphere as well as rippling its surface: a
    // deformation alone at speaking volume stops reading as a sphere, and what
    // a loud reply should look like is bigger, not more tangled.
    final radius = math.min(size.width, size.height) *
        0.29 *
        motion.scale *
        (1 + motion.amplitude * 0.07);
    final dotSize = math.max(0.9, radius * 0.017);

    // The glow behind the cloud. Without it the sphere is a scatter of specks
    // with no presence on the screen and no answer to a reply getting loud.
    final haloAlpha = (0.16 + motion.amplitude * 0.18) * motion.assembly;
    final haloRadius = radius * (1.7 + motion.amplitude * 0.35);
    canvas.drawCircle(
      centre,
      haloRadius,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: haloAlpha),
            accent.withValues(alpha: haloAlpha * 0.4),
            accent.withValues(alpha: 0),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: centre, radius: haloRadius)),
    );

    final buckets = List.generate(_buckets, (_) => <double>[]);
    final sizes = List.filled(_buckets, 0.0);
    final counts = List.filled(_buckets, 0);

    final cosSpin = math.cos(motion.spinAngle);
    final sinSpin = math.sin(motion.spinAngle);
    // A fixed tilt with a slow drift: a sphere spun about a perfectly vertical
    // axis reads as a flat disc of moving dots.
    final tilt = 0.3 + math.sin(motion.clock * 0.21) * 0.07;
    final cosTilt = math.cos(tilt);
    final sinTilt = math.sin(tilt);
    final breathe = math.sin(motion.clock * 0.85) * 0.015;

    // The idle pulse, running through the cloud from one side to the other.
    final sweepPhase = motion.clock % _sweepPeriod;
    final sweeping = sweepPhase < _sweepSeconds && motion.assembly > 0.9;
    final sweep = 1.3 - (sweepPhase / _sweepSeconds) * 2.6;

    /// Places one dot and files it under a brightness.
    ///
    /// Everything the sphere does happens here: the dot flies in from wherever
    /// it started, the whole cloud turns, perspective makes the near side
    /// larger, and the light falls off with depth.
    void plot(
      double x,
      double y,
      double z,
      double length,
      _Placed dot,
      double bright,
      double base,
    ) {
      var px = x * length;
      var py = y * length;
      var pz = z * length;

      final progress =
          ((motion.assembly - dot.delay * 0.42) / 0.58).clamp(0.0, 1.0);
      if (progress < 1) {
        final eased = 1 - math.pow(1 - progress, 3).toDouble();
        px = dot.sx + (px - dot.sx) * eased;
        py = dot.sy + (py - dot.sy) * eased;
        pz = dot.sz + (pz - dot.sz) * eased;
      }

      final spunX = px * cosSpin + pz * sinSpin;
      final spunZ = pz * cosSpin - px * sinSpin;
      final finalY = py * cosTilt - spunZ * sinTilt;
      final finalZ = py * sinTilt + spunZ * cosTilt;

      // Perspective: the near side spreads and the far side gathers, which is
      // most of what separates a sphere from a circle of dots.
      final perspective = 2.7 / (2.7 - finalZ);
      final depth = ((finalZ + 1) / 2).clamp(0.0, 1.0);

      // A band of light passing through, and a shimmer that never lets two
      // neighbouring dots sit at exactly the same level.
      final fromSweep = (finalZ - sweep) / 0.35;
      final pulse = sweeping ? math.exp(-fromSweep * fromSweep) * 0.35 : 0.0;
      final shimmer = math.sin(motion.clock * 2.2 + dot.seed * 0.7) * 0.04;

      final presence = ((0.12 +
                  depth * 0.72 +
                  motion.charge +
                  motion.amplitude * 0.1 +
                  pulse +
                  shimmer)
              .clamp(0.0, 1.0) *
          bright)
          .clamp(0.0, 1.0);
      final bucket = (presence * (_buckets - 1)).round().clamp(0, _buckets - 1);

      buckets[bucket]
        ..add(centre.dx + spunX * radius * perspective)
        ..add(centre.dy - finalY * radius * perspective);
      // Dots in a step are drawn in one call, so they share a size: the
      // average of what each of them asked for.
      sizes[bucket] += base * perspective * (0.7 + presence * 0.55);
      counts[bucket] += 1;
    }

    final hearing = motion.mood == CoachMood.listening;
    final working = motion.mood == CoachMood.thinking;

    for (final dot in _shell) {
      // Three sines over the three axes: an organic wobble that never repeats
      // on a short cycle, for a fraction of the cost of real noise.
      final wave = math.sin(dot.x * 2.7 + motion.clock * 1.1) *
          math.sin(dot.y * 3.1 - motion.clock * 0.9) *
          math.sin(dot.z * 2.3 + motion.clock * 1.4);

      // A wave running up the sphere while it hears you, so being heard
      // travels rather than merely inflating.
      final ripple = hearing
          ? math.sin(dot.y * 6.5 - motion.clock * 5) * motion.amplitude * 0.17
          : 0.0;
      // A tight band circling while it works.
      final churn =
          working ? math.sin(dot.y * 9 + motion.clock * 6) * 0.05 : 0.0;

      plot(
        dot.x,
        dot.y,
        dot.z,
        1 +
            breathe +
            wave * (motion.wobble + motion.amplitude * motion.drive) +
            ripple +
            churn,
        dot,
        1,
        dotSize,
      );
    }

    // The orbits. Their dots run round their own rings rather than sitting on
    // the shell, and they widen on a loud moment — which is what makes a reply
    // look like it is coming out of the thing.
    for (final orbit in _orbits) {
      final length = orbit.radius * (1 + motion.amplitude * 0.14 + breathe);
      final travel = motion.clock * orbit.speed * (1 + motion.amplitude * 0.8) +
          motion.spinAngle;
      for (final dot in orbit.dots) {
        final angle = dot.phase + travel;
        final cosAngle = math.cos(angle);
        final sinAngle = math.sin(angle);
        plot(
          orbit.ux * cosAngle + orbit.vx * sinAngle,
          orbit.uy * cosAngle + orbit.vy * sinAngle,
          orbit.uz * cosAngle + orbit.vz * sinAngle,
          length,
          dot,
          // Brighter than the shell: the rings are the part that says this is
          // running, so they have to survive the shell behind them.
          1.25,
          dotSize * 0.85,
        );
      }
    }

    for (var bucket = 0; bucket < _buckets; bucket++) {
      final points = buckets[bucket];
      if (points.isEmpty) continue;
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(points),
        Paint()
          // Round caps on a point list is how a canvas draws a thousand dots
          // in one call.
          ..strokeCap = StrokeCap.round
          ..strokeWidth = (sizes[bucket] / counts[bucket]) * 2
          ..blendMode = BlendMode.plus
          ..color = _fills[bucket],
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.accent != accent || old.glow != glow;
}
