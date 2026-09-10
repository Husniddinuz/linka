import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'writing_report.dart';

/// The stages of marking a spoken answer, with the second each one starts.
///
/// Unlike the essay grader, part of this *is* observable: the attempt's own
/// `status` moves from `pending` to `transcribing` on the server, so the first
/// two rows can be driven by fact rather than by a stopwatch. Everything after
/// transcription happens inside one model call that reports nothing until it
/// is done, so those rows are timed to a typical run and say so by never
/// filling the bar.
const _stages = <List<Object>>[
  ['Uploading your recording', 0],
  ['Listening to your answer', 5],
  ['Timing your pauses and fillers', 18],
  ['Marking against the band descriptors', 26],
  ['Writing your report', 38],
];

/// The bar eases towards this and stops. It must never reach 1 on a timer: a
/// full bar with nothing happening is worse than a slow one.
const _progressCeiling = 0.94;

/// Controls how fast the easing decays. Roughly 63% of the way at 30s.
const _progressTau = 30.0;

/// After this long the wait has left "normal" and deserves acknowledging.
const _slowAfterSeconds = 100;

/// What the student looks at while their answer is being transcribed and
/// marked.
///
/// Marking runs about a minute — long enough that a bare spinner reads as a
/// frozen screen and gets backed out of, which on a free-quota feature costs
/// the student a marking for nothing. So this does three jobs: prove the
/// screen is alive, say *why* it is slow, and name what is being worked on so
/// the time feels accounted for.
///
/// It also says the one thing that is actually true and useful here: the work
/// is server-side and outlives this screen, so leaving does not lose it.
class SpeakingGradingProgress extends StatefulWidget {
  const SpeakingGradingProgress({
    super.key,
    this.status,
    this.onOpenHistory,
  });

  /// The attempt's own status, once there is an attempt. Null until the upload
  /// has landed, which is exactly the first stage.
  final String? status;

  /// Opens the answers history. The copy promises the result is saved either
  /// way; this is the link that makes the promise checkable.
  final VoidCallback? onOpenHistory;

  @override
  State<SpeakingGradingProgress> createState() => _SpeakingGradingProgressState();
}

class _SpeakingGradingProgressState extends State<SpeakingGradingProgress>
    with SingleTickerProviderStateMixin {
  late final DateTime _startedAt = DateTime.now();
  late final Timer _timer;
  late final AnimationController _halo =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  double _seconds = 0;

  @override
  void initState() {
    super.initState();
    // Driven off the wall clock rather than a tick counter, so a run that is
    // throttled in the background resumes showing the true elapsed time.
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() => _seconds = DateTime.now().difference(_startedAt).inMilliseconds / 1000);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _halo.dispose();
    super.dispose();
  }

  /// An asymptotic estimate of how far along marking is. Deliberately never
  /// linear and never complete: it moves quickly at first, visibly slows, and
  /// leaves the last sliver for the response to fill, so nothing is promised
  /// about an arrival the server has not committed to.
  double get _progress => _progressCeiling * (1 - exp(-_seconds / _progressTau));

  /// Which row is live. The clock proposes; the attempt's real status
  /// disposes — an upload that has landed is at least on row 1 however fast it
  /// got there, and one that has not cannot be past row 0 however slow.
  int get _activeIndex {
    var found = 0;
    for (var i = 0; i < _stages.length; i++) {
      if (_seconds >= (_stages[i][1] as int)) found = i;
    }
    final status = widget.status;
    if (status == null) return 0;
    if (status == 'pending') return found.clamp(0, 1);
    return found < 1 ? 1 : found;
  }

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final active = _activeIndex;
    final isSlow = _seconds >= _slowAfterSeconds;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
      decoration: wCardDecoration(context, radius: 24),
      child: Column(
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: AnimatedBuilder(
              animation: _halo,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Two rings on the same animation, half a cycle apart.
                    for (final offset in [0.0, 0.5]) _ring(offset, wr.accent),
                    child!,
                  ],
                );
              },
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [wr.accent, wr.colors.brand]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Symbols.graphic_eq_rounded, color: Colors.white, size: 24),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Marking your answer',
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 18, fontWeight: FontWeight.w800, color: wr.text),
          ),
          const SizedBox(height: 8),
          Text(
            'Your recording is being transcribed, timed and marked against the '
            'band descriptors. This takes about a minute — and it keeps running '
            'on our side, so you can leave this screen without losing it.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 13, height: 1.5, color: wr.muted),
          ),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 6,
              color: wr.soft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _progress),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                builder: (context, value, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: LinearGradient(colors: [wr.accent, const Color(0xFF8B5CF6)]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < _stages.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Center(
                      child: i < active
                          ? Icon(Symbols.check_circle_rounded, size: 17, color: wr.good)
                          : i == active
                              ? SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: wr.accent),
                                )
                              : Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(color: wr.line, shape: BoxShape.circle),
                                ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _stages[i][0] as String,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 14,
                        fontWeight: i == active ? FontWeight.w700 : FontWeight.w500,
                        color: i <= active ? wr.text : wr.faint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            isSlow
                ? 'Still working — this is taking longer than usual. The marking is '
                    'not lost; leaving this screen will not stop it.'
                : 'This usually takes about a minute.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, height: 1.45, color: wr.muted),
          ),
          if (widget.onOpenHistory != null) ...[
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: widget.onOpenHistory,
              icon: Icon(Symbols.history_rounded, size: 17, color: wr.muted),
              label: Text(
                'All your answers',
                style: TextStyle(
                    fontFamily: 'SF Pro', fontSize: 13.5, fontWeight: FontWeight.w700, color: wr.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// One expanding, fading ring, [offset] of a cycle behind the controller.
  Widget _ring(double offset, Color color) {
    final t = (_halo.value + offset) % 1.0;
    return Opacity(
      opacity: (1 - t) * 0.35,
      child: Container(
        width: 52 + 24 * t,
        height: 52 + 24 * t,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.4), shape: BoxShape.circle),
      ),
    );
  }
}
