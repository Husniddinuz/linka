import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';

import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import '../widgets/speaking_report.dart';
import '../widgets/writing_report.dart';

/// Same cadence as the answer screen: marking takes about a minute, and three
/// seconds is responsive without being a load.
const _pollInterval = Duration(seconds: 3);

/// Every answer this student has recorded and sent for marking.
///
/// This is not a nice-to-have list: without it, a report lives for exactly as
/// long as the screen that produced it. The attempt is saved server-side from
/// the moment the upload lands, the marking copy explicitly tells students
/// they may leave — and until this screen existed there was nowhere for them
/// to come back to.
///
/// The averages are arithmetic over the list rather than a second endpoint.
/// There is no speaking equivalent of `/writing-attempts/insights/` yet, and
/// four numbers over a page of rows do not need one; a real cross-attempt
/// diagnostic wants server-side aggregation behind it.
class SpeakingAttemptsScreen extends StatefulWidget {
  const SpeakingAttemptsScreen({super.key});

  @override
  State<SpeakingAttemptsScreen> createState() => _SpeakingAttemptsScreenState();
}

class _SpeakingAttemptsScreenState extends State<SpeakingAttemptsScreen> {
  late Future<List<Map<String, dynamic>>> _future = MockTestService.fetchSpeakingAttempts();

  void _reload() {
    setState(() => _future = MockTestService.fetchSpeakingAttempts());
  }

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return Scaffold(
      backgroundColor: wr.page,
      appBar: mtAppBar(context, title: 'Your Speaking Answers'),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: wr.accent));
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _Message(
              icon: Icons.cloud_off_rounded,
              title: 'Answers unavailable',
              body: 'Your answers could not be loaded right now. Try again in a moment.',
              actionLabel: 'Try again',
              onAction: _reload,
            );
          }

          final attempts = snapshot.data!;
          if (attempts.isEmpty) {
            return _Message(
              icon: Icons.mic_none_rounded,
              title: 'No answers yet',
              body: 'Pick a tutor’s question, record your answer, and AI marks it '
                  'against the band descriptors. Everything you send is kept here.',
              actionLabel: 'Find a question to answer',
              onAction: () => Navigator.pop(context),
            );
          }

          final bands = <double>[
            for (final attempt in attempts)
              if (wToDoubleOrNull(attempt['overall_band']) != null)
                wToDoubleOrNull(attempt['overall_band'])!,
          ];

          return RefreshIndicator(
            color: wr.accent,
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                if (bands.isNotEmpty) ...[
                  _StatsRow(bands: bands),
                  const SizedBox(height: 20),
                ],
                for (final attempt in attempts) ...[
                  _AttemptRow(attempt: attempt, onReturn: _reload),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.bands});

  /// Newest first, as the endpoint returns them — so the first band is the
  /// latest one.
  final List<double> bands;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final average = bands.reduce((a, b) => a + b) / bands.length;
    final tiles = <List<String>>[
      [bands.first.toStringAsFixed(1), 'Latest band'],
      [average.toStringAsFixed(1), 'Average'],
      [bands.reduce((a, b) => a > b ? a : b).toStringAsFixed(1), 'Best'],
      ['${bands.length}', 'Answers marked'],
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: wCardDecoration(context),
      child: Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Column(
                children: [
                  Text(
                    tiles[i][0],
                    style: TextStyle(
                        fontFamily: 'SF Pro', fontSize: 21, fontWeight: FontWeight.w800, color: wr.text),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tiles[i][1],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 10.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: wr.muted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One past answer. Opens the identical report the answer screen showed on the
/// day — a student comparing this week's answer with last week's should be
/// reading the same layout, not two dialects of one screen.
class _AttemptRow extends StatelessWidget {
  const _AttemptRow({required this.attempt, required this.onReturn});
  final Map<String, dynamic> attempt;

  /// A row opened while still marking can come back graded, which changes the
  /// averages above it.
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final band = wToDoubleOrNull(attempt['overall_band']);
    final status = attempt['status']?.toString() ?? 'pending';
    final part = (attempt['part'] as num?)?.toInt() ?? 0;
    final seconds = (attempt['duration_seconds'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: () async {
        final id = (attempt['id'] as num?)?.toInt();
        if (id == null) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SpeakingAttemptScreen(attemptId: id, preview: attempt)),
        );
        onReturn();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: wCardDecoration(context, radius: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      WTag(label: 'Part $part'),
                      Text(
                        _formatDate(attempt['submitted_at']),
                        style: TextStyle(
                            fontFamily: 'SF Pro', fontSize: 11.5, fontWeight: FontWeight.w600, color: wr.faint),
                      ),
                      if (seconds > 0)
                        Text(
                          sClock(seconds),
                          style: TextStyle(
                              fontFamily: 'SF Pro', fontSize: 11.5, fontWeight: FontWeight.w600, color: wr.faint),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    attempt['question_text']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'SF Pro', fontSize: 14, height: 1.35, fontWeight: FontWeight.w600, color: wr.text),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (band != null)
              Column(
                children: [
                  Text(
                    band.toStringAsFixed(1),
                    style: TextStyle(
                        fontFamily: 'SF Pro', fontSize: 20, fontWeight: FontWeight.w800, color: wr.text),
                  ),
                  Text(
                    'Band',
                    style: TextStyle(
                        fontFamily: 'SF Pro', fontSize: 10, fontWeight: FontWeight.w700, color: wr.faint),
                  ),
                ],
              )
            else
              WTag(
                label: status == 'failed' ? 'Not marked' : 'Marking…',
                background: status == 'failed' ? wr.bad.withValues(alpha: 0.12) : wr.soft,
                foreground: status == 'failed' ? wr.bad : wr.muted,
              ),
          ],
        ),
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (parsed == null) return '';
    return '${parsed.day} ${_months[parsed.month - 1]} ${parsed.year}';
  }
}

// ---------------------------------------------------------------------------
// One attempt, reopened
// ---------------------------------------------------------------------------

/// A past answer's report, fetched by id.
///
/// The list endpoint omits `analysis`, `transcript` and the per-word timings —
/// tens of KB each, and a list exists to choose an attempt rather than to read
/// one — so the report always comes from the detail endpoint.
///
/// An attempt that is still being marked lands here too: the work runs
/// server-side and outlives the screen that started it, so rather than a dead
/// panel with a "reload" hint this polls the same endpoint the answer screen
/// does and turns into the report when it settles.
class SpeakingAttemptScreen extends StatefulWidget {
  const SpeakingAttemptScreen({super.key, required this.attemptId, this.preview});

  final int attemptId;

  /// The row this was opened from, if any — enough to draw the header while
  /// the full attempt is on its way.
  final Map<String, dynamic>? preview;

  @override
  State<SpeakingAttemptScreen> createState() => _SpeakingAttemptScreenState();
}

class _SpeakingAttemptScreenState extends State<SpeakingAttemptScreen> {
  final _player = ap.AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<void>? _completeSub;
  Timer? _pollTimer;

  /// Starts as the row this was opened from so the band and the question are
  /// on screen immediately, then is replaced by the full record — the list
  /// endpoint carries every band but none of the review.
  late Map<String, dynamic>? _attempt = widget.preview;
  late bool _loading = widget.preview == null;
  bool _failedToLoad = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool get _settled {
    final status = _attempt?['status']?.toString();
    return status == 'graded' || status == 'failed';
  }

  @override
  void initState() {
    super.initState();
    _positionSub = _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _durationSub = _player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final attempt = await MockTestService.fetchSpeakingAttempt(widget.attemptId);
      if (!mounted) return;
      setState(() {
        _attempt = attempt;
        _loading = false;
      });
      if (_settled) {
        await _prepareAudio();
      } else {
        _startPolling();
      }
    } catch (_) {
      if (!mounted) return;
      // With a preview in hand this is not fatal: the bands are already drawn
      // and the screen simply stays at that level of detail.
      setState(() {
        _loading = false;
        _failedToLoad = _attempt?['analysis'] == null;
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (timer) async {
      try {
        final fresh = await MockTestService.fetchSpeakingAttempt(widget.attemptId);
        if (!mounted) return;
        setState(() => _attempt = fresh);
        if (_settled) {
          timer.cancel();
          await _prepareAudio();
        }
      } catch (_) {
        // A failed poll is not a failed attempt. Try again on the next tick.
      }
    });
  }

  Future<void> _prepareAudio() async {
    final url = _attempt?['audio_url']?.toString();
    if (url == null || url.isEmpty) return;
    try {
      await _player.setSourceUrl(url);
    } catch (_) {
      // The report still reads; it just loses its player.
    }
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    await _player.resume();
    if (mounted) setState(() => _playing = true);
  }

  Future<void> _seek(double seconds) async {
    try {
      await _player.seek(Duration(milliseconds: (seconds * 1000).round()));
      await _player.resume();
      if (mounted) setState(() => _playing = true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return Scaffold(
      backgroundColor: wr.page,
      appBar: mtAppBar(context, title: 'Your Answer'),
      body: Builder(builder: (context) {
        if (_loading) {
          return Center(child: CircularProgressIndicator(color: wr.accent));
        }
        if (_attempt == null || (_failedToLoad && _attempt!['analysis'] == null)) {
          return _Message(
            icon: Icons.cloud_off_rounded,
            title: 'Report unavailable',
            body: 'This answer could not be loaded right now. Try again in a moment.',
            actionLabel: 'Try again',
            onAction: () {
              setState(() {
                _loading = true;
                _failedToLoad = false;
              });
              _load();
            },
          );
        }

        final attempt = _attempt!;
        if (!_settled) return _PendingView(attempt: attempt);
        if (attempt['status']?.toString() == 'failed') {
          return _Message(
            icon: Icons.error_outline_rounded,
            title: 'We could not mark that answer',
            body: (attempt['error_message']?.toString() ?? '').trim().isNotEmpty
                ? attempt['error_message'].toString()
                : 'Record it again and send it for marking.',
            actionLabel: 'Back to your answers',
            onAction: () => Navigator.pop(context),
            tone: wr.bad,
          );
        }

        final hasPlayer = (attempt['audio_url']?.toString() ?? '').isNotEmpty;
        return SpeakingReportView(
          attempt: attempt,
          onHear: hasPlayer ? _seek : null,
          header: hasPlayer ? _buildPlayer(attempt) : null,
        );
      }),
    );
  }

  Widget _buildPlayer(Map<String, dynamic> attempt) {
    final wr = context.wr;
    final total = _duration.inMilliseconds > 0
        ? _duration
        : Duration(seconds: (attempt['duration_seconds'] as num?)?.toInt() ?? 0);
    final progress =
        total.inMilliseconds == 0 ? 0.0 : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: wCardDecoration(context),
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: wr.accent, shape: BoxShape.circle),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 24,
                color: wr.isDark ? wr.bg : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your answer',
                  style: TextStyle(
                      fontFamily: 'SF Pro', fontSize: 13.5, fontWeight: FontWeight.w700, color: wr.text),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Container(
                    height: 5,
                    color: wr.soft,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: Container(color: wr.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${sClock(_position.inSeconds)} / ${sClock(total.inSeconds)}',
                  style: TextStyle(fontFamily: 'SF Pro', fontSize: 11.5, color: wr.faint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An attempt that is still being marked, reopened from the history.
class _PendingView extends StatelessWidget {
  const _PendingView({required this.attempt});
  final Map<String, dynamic> attempt;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final transcribing = attempt['status']?.toString() == 'transcribing';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: wCardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2, color: wr.accent),
                  ),
                  const SizedBox(width: 11),
                  Text(
                    transcribing ? 'Listening to your answer…' : 'Sending your answer…',
                    style: TextStyle(
                        fontFamily: 'SF Pro', fontSize: 14.5, fontWeight: FontWeight.w800, color: wr.text),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'This answer is still being transcribed and marked. It takes about a '
                'minute — this screen updates itself when it is done.',
                style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: wCardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WTag(label: 'Part ${(attempt['part'] as num?)?.toInt() ?? 0}'),
              const SizedBox(height: 10),
              Text(
                attempt['question_text']?.toString() ?? '',
                style: TextStyle(
                    fontFamily: 'SF Pro', fontSize: 14.5, height: 1.55, fontWeight: FontWeight.w600, color: wr.text),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.tone,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final colour = tone ?? wr.accent;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(color: colour.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: colour),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 17, fontWeight: FontWeight.w800, color: wr.text),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 240,
              child: MtPrimaryButton(label: actionLabel, onPressed: onAction),
            ),
          ],
        ),
      ),
    );
  }
}
