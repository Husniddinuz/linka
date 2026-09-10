import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/api_service.dart';
import '../services/mock_test_service.dart';
import '../widgets/app_notify.dart';
import '../widgets/mock_test_styles.dart';
import '../widgets/speaking_grading_progress.dart';
import '../widgets/speaking_report.dart';
import '../widgets/writing_report.dart';
import 'plus_subscription_screen.dart';
import 'speaking_attempts_screen.dart';

/// How often to ask whether marking has finished. Transcription plus a long
/// completion runs to a minute or so; three seconds is responsive without
/// being a load.
const _pollInterval = Duration(seconds: 3);

/// Below this the file has no answer in it — an empty container, or a
/// recording stopped before it started. The server rejects the same size, so
/// catching it here saves a round trip and a confusing 400.
const _minRecordingBytes = 2000;

/// The student's turn at one Speaking question.
///
/// The tutor's own recording is deliberately *not* on this screen until after
/// the answer has been marked: hearing a band-8 answer and then giving your
/// own version of it measures recall, not speaking, and the mark would come
/// back flattering and useless. It reappears at the bottom of the report, as
/// a comparison, which is what it is actually good for.
///
/// The shape is forced by one fact: marking happens *after* the request that
/// uploads the recording. So this owns a small state machine rather than a
/// submit handler — the attempt exists on the server before the report does,
/// which is also what makes backing out survivable and a failure legible.
class SpeakingAnswerScreen extends StatefulWidget {
  const SpeakingAnswerScreen({
    super.key,
    required this.part,
    required this.tutorName,
  }) : fromTopicBank = false;

  /// The same screen for a question taken straight from the topic bank, with
  /// no tutor recording behind it.
  ///
  /// Only two things change: the id posts to the topic endpoint (topic part
  /// ids and sample part ids come from different tables), and there is no
  /// tutor to name or to compare against afterwards.
  const SpeakingAnswerScreen.fromTopic({super.key, required this.part})
      : tutorName = null,
        fromTopicBank = true;

  /// One entry from a sample's `parts`: `{id, part, title, question_text,
  /// audio_url, …}` — or from a topic's, which carries the first four and no
  /// audio.
  final Map<String, dynamic> part;

  /// Whose sample this question comes from — the answer's only context once
  /// the report is reopened weeks later. Null for a topic-bank question, which
  /// belongs to nobody.
  final String? tutorName;

  /// Whether [part] is a topic part rather than a sample part.
  final bool fromTopicBank;

  @override
  State<SpeakingAnswerScreen> createState() => _SpeakingAnswerScreenState();
}

enum _Stage { idle, recording, review, marking, done }

class _SpeakingAnswerScreenState extends State<SpeakingAnswerScreen> {
  final _recorder = AudioRecorder();

  /// Plays back the take being reviewed, and later the marked recording the
  /// corrections seek into. One instance for both: they are the same audio,
  /// and only one of them is ever on screen.
  final _player = ap.AudioPlayer();

  /// The tutor's take, revealed only inside the report.
  ap.AudioPlayer? _samplePlayer;
  bool _samplePlaying = false;

  StreamSubscription<Amplitude>? _amplitudeSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<void>? _completeSub;
  Timer? _recordTimer;
  Timer? _pollTimer;

  _Stage _stage = _Stage.idle;
  bool _micReady = false;

  int _elapsed = 0;
  double _level = 0;

  String? _takePath;
  int _takeSeconds = 0;
  bool _takePlaying = false;
  Duration _takePosition = Duration.zero;
  Duration _takeDuration = Duration.zero;

  Map<String, dynamic>? _quota;
  Map<String, dynamic>? _attempt;
  String? _error;

  /// Set when the server itself says the free window is spent, which outranks
  /// whatever the quota fetch said a minute ago.
  bool _exhausted = false;

  int get _partNumber => (widget.part['part'] as num?)?.toInt() ?? 2;
  int get _cap => sCapForPart(_partNumber);
  int get _remainingSeconds => (_cap - _elapsed).clamp(0, _cap);

  bool get _isPlus => _quota?['is_plus'] == true;
  int? get _left => (_quota?['remaining'] as num?)?.toInt();
  bool get _blocked =>
      _exhausted || (_quota != null && !_isPlus && (_left ?? 1) <= 0);

  /// Marking is over. Derived from the attempt's own status rather than
  /// mirrored into [_stage], so the two can never disagree for a frame.
  bool get _settled {
    final status = _attempt?['status']?.toString();
    return status == 'graded' || status == 'failed';
  }

  @override
  void initState() {
    super.initState();
    _loadQuota();

    _positionSub = _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _takePosition = position);
    });
    _durationSub = _player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _takeDuration = duration);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _takePlaying = false);
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _pollTimer?.cancel();
    _amplitudeSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    _samplePlayer?.dispose();
    super.dispose();
  }

  Future<void> _loadQuota() async {
    try {
      final quota = await MockTestService.fetchSpeakingAnswerQuota();
      if (!mounted) return;
      setState(() => _quota = quota);
    } catch (_) {
      // Advisory only — the server re-checks on submit, so a failed fetch
      // leaves the pill off rather than blocking the screen.
    }
  }

  // ─── Recording ──────────────────────────────────────────────────────────

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        AppNotify.show(context, message: 'Microphone permission is required to record.');
      }
      return;
    }

    await _stopTakePlayback();
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/speaking_answer_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100),
      path: path,
    );
    if (!mounted) return;

    setState(() {
      _stage = _Stage.recording;
      _takePath = path;
      _elapsed = 0;
      _level = 0;
      _error = null;
    });

    // The exam's own limit, enforced rather than suggested — see [sPartSeconds].
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
      if (_elapsed >= _cap) _stop();
    });

    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amplitude) {
      if (!mounted) return;
      // `current` is dBFS: 0 is clipping, -45 or below is effectively silence.
      final normalised = ((amplitude.current + 45) / 45).clamp(0.0, 1.0);
      setState(() => _level = normalised);
    });
  }

  Future<void> _stop() async {
    _recordTimer?.cancel();
    _recordTimer = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    final seconds = _elapsed;
    final path = await _recorder.stop();
    if (!mounted) return;

    setState(() {
      _level = 0;
      _elapsed = 0;
    });

    if (path == null || seconds < 1) {
      setState(() {
        _stage = _Stage.idle;
        _takePath = null;
        _error = 'That was too short to keep. Try again.';
      });
      return;
    }

    final bytes = await File(path).length();
    if (bytes < _minRecordingBytes) {
      try {
        await File(path).delete();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _takePath = null;
        _error = 'That recording came out empty. Check your microphone and try again '
            '(on a simulator, make sure an input is configured).';
      });
      return;
    }

    setState(() {
      _takePath = path;
      _takeSeconds = seconds;
      _takePosition = Duration.zero;
      _takeDuration = Duration(seconds: seconds);
      _stage = _Stage.review;
    });
  }

  Future<void> _discard() async {
    await _stopTakePlayback();
    if (!mounted) return;
    setState(() {
      _takePath = null;
      _takeSeconds = 0;
      _stage = _Stage.idle;
      _error = null;
    });
  }

  Future<void> _stopTakePlayback() async {
    await _player.stop();
    if (mounted) setState(() => _takePlaying = false);
  }

  Future<void> _toggleTakePlayback() async {
    final path = _takePath;
    if (path == null) return;
    if (_takePlaying) {
      await _player.pause();
      if (mounted) setState(() => _takePlaying = false);
      return;
    }
    if (_player.state == ap.PlayerState.paused) {
      await _player.resume();
    } else {
      await _player.play(ap.DeviceFileSource(path));
    }
    if (mounted) setState(() => _takePlaying = true);
  }

  // ─── Submit and poll ────────────────────────────────────────────────────

  Future<void> _submit() async {
    final path = _takePath;
    final partId = (widget.part['id'] as num?)?.toInt();
    if (path == null || partId == null || _blocked) return;

    await _stopTakePlayback();
    if (!mounted) return;
    setState(() {
      _stage = _Stage.marking;
      _error = null;
    });

    try {
      final attempt = widget.fromTopicBank
          ? await MockTestService.submitSpeakingTopicAnswer(
              partId: partId,
              audio: File(path),
              durationSeconds: _takeSeconds,
            )
          : await MockTestService.submitSpeakingAnswer(
              partId: partId,
              audio: File(path),
              durationSeconds: _takeSeconds,
            );
      if (!mounted) return;
      setState(() => _attempt = attempt);
      _startPolling();
    } on ApiException catch (e) {
      if (!mounted) return;
      // 429 is the spent free window and 403 a sample beyond it; both mean the
      // same thing to the student and both route to the Plus upsell.
      final upsell = e.statusCode == 429 || e.statusCode == 403;
      setState(() {
        _stage = _Stage.review;
        _exhausted = upsell;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.review;
        _error = 'We could not send that recording. Check your connection and try again.';
      });
    }
  }

  /// Re-reads the attempt until it stops working.
  ///
  /// A failed poll is not a failed attempt — the marking continues on the
  /// server — so a network blip costs one tick and the next one picks the
  /// result up.
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (timer) async {
      final id = (_attempt?['id'] as num?)?.toInt();
      if (id == null) {
        timer.cancel();
        return;
      }
      try {
        final fresh = await MockTestService.fetchSpeakingAttempt(id);
        if (!mounted) return;
        setState(() => _attempt = fresh);
        if (_settled) {
          timer.cancel();
          setState(() => _stage = _Stage.done);
          await _prepareMarkedAudio();
        }
      } catch (_) {
        // Keep polling.
      }
    });
  }

  /// Loads the recording the report seeks into.
  ///
  /// The server's copy rather than the local file: it is the audio the
  /// timings were measured against, and the local temp file does not survive
  /// the app being cleared.
  Future<void> _prepareMarkedAudio() async {
    final url = _attempt?['audio_url']?.toString();
    if (url == null || url.isEmpty) return;
    try {
      await _player.setSourceUrl(url);
    } catch (_) {
      // The report still reads; it just loses its player.
    }
  }

  Future<void> _seekMarked(double seconds) async {
    try {
      await _player.seek(Duration(milliseconds: (seconds * 1000).round()));
      await _player.resume();
      if (mounted) setState(() => _takePlaying = true);
    } catch (_) {}
  }

  Future<void> _toggleSamplePlayback() async {
    final url = widget.part['audio_url']?.toString();
    if (url == null || url.isEmpty) return;

    final player = _samplePlayer ??= ap.AudioPlayer()
      ..onPlayerComplete.listen((_) {
        if (mounted) setState(() => _samplePlaying = false);
      });

    if (_samplePlaying) {
      await player.pause();
      if (mounted) setState(() => _samplePlaying = false);
      return;
    }
    // Their answer and yours talking over each other helps nobody.
    await _player.pause();
    if (mounted) setState(() => _takePlaying = false);

    if (player.state == ap.PlayerState.paused) {
      await player.resume();
    } else {
      await player.play(ap.UrlSource(url));
    }
    if (mounted) setState(() => _samplePlaying = true);
  }

  void _openPlus() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlusSubscriptionScreen()));
  }

  void _openHistory() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SpeakingAttemptsScreen()));
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.wr.page,
      appBar: mtAppBar(context, title: 'Your Answer'),
      body: switch (_stage) {
        _Stage.marking => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              SpeakingGradingProgress(
                status: _attempt?['status']?.toString(),
                onOpenHistory: _openHistory,
              ),
            ],
          ),
        _Stage.done => _buildResult(),
        _ => _buildRecorder(),
      },
    );
  }

  // ─── Result ─────────────────────────────────────────────────────────────

  Widget _buildResult() {
    final attempt = _attempt!;
    if (attempt['status']?.toString() == 'failed') return _buildFailed(attempt);

    final sampleUrl = widget.part['audio_url']?.toString();
    final hasPlayer = (attempt['audio_url']?.toString() ?? '').isNotEmpty;

    return SpeakingReportView(
      attempt: attempt,
      onHear: hasPlayer ? _seekMarked : null,
      header: hasPlayer ? _buildMarkedPlayer() : null,
      footer: Column(
        children: [
          if (sampleUrl != null && sampleUrl.isNotEmpty && widget.tutorName != null) ...[
            _CompareCard(
              tutorName: widget.tutorName!,
              playing: _samplePlaying,
              onToggle: _toggleSamplePlayback,
            ),
            const SizedBox(height: 14),
          ],
          MtPrimaryButton(
            label: 'Answer Another Question',
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(height: 10),
          _SecondaryButton(
            label: 'All Your Answers',
            icon: Symbols.history_rounded,
            onPressed: _openHistory,
          ),
        ],
      ),
    );
  }

  Widget _buildFailed(Map<String, dynamic> attempt) {
    final wr = context.wr;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: wr.bad.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(Symbols.error_rounded, size: 32, color: wr.bad),
            ),
            const SizedBox(height: 16),
            Text(
              'We could not mark that answer',
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 17, fontWeight: FontWeight.w800, color: wr.text),
            ),
            const SizedBox(height: 8),
            Text(
              (attempt['error_message']?.toString() ?? '').trim().isNotEmpty
                  ? attempt['error_message'].toString()
                  : 'Please record it and send it again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, height: 1.5, color: wr.muted),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 220,
              child: MtPrimaryButton(
                label: 'Record Again',
                onPressed: () {
                  setState(() {
                    _attempt = null;
                    _stage = _Stage.idle;
                    _takePath = null;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The marked recording, above the report so a correction's "Hear it" has
  /// somewhere visible to seek to.
  Widget _buildMarkedPlayer() {
    final wr = context.wr;
    final total = _takeDuration.inMilliseconds > 0
        ? _takeDuration
        : Duration(seconds: (_attempt?['duration_seconds'] as num?)?.toInt() ?? 0);
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_takePosition.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: wCardDecoration(context),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              if (_takePlaying) {
                await _player.pause();
                if (mounted) setState(() => _takePlaying = false);
              } else {
                await _player.resume();
                if (mounted) setState(() => _takePlaying = true);
              }
            },
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: wr.accent, shape: BoxShape.circle),
              child: Icon(
                _takePlaying ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
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
                  '${sClock(_takePosition.inSeconds)} / ${sClock(total.inSeconds)}',
                  style: TextStyle(fontFamily: 'SF Pro', fontSize: 11.5, color: wr.faint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Recorder ───────────────────────────────────────────────────────────

  Widget _buildRecorder() {
    final wr = context.wr;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _QuestionCard(part: widget.part, tutorName: widget.tutorName),
        if (_quota != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: WTag(
              icon: _isPlus ? Symbols.workspace_premium_rounded : Symbols.auto_awesome_rounded,
              label: _isPlus
                  ? 'Linka Plus — unlimited marking'
                  : '${_left ?? 0} of ${_quota!['limit'] ?? 0} free markings left',
              background: _blocked ? wr.bad.withValues(alpha: 0.12) : wr.soft,
              foreground: _blocked ? wr.bad : wr.muted,
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: wr.bad.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _error!,
              style: TextStyle(
                  fontFamily: 'SF Pro', fontSize: 13, height: 1.45, fontWeight: FontWeight.w600, color: wr.bad),
            ),
          ),
        ],

        // Recording is gated on hearing yourself once. The failure it catches
        // is silent and expensive: a muted headset or the wrong input costs a
        // student one of their free markings for a file with nothing in it.
        if (_stage == _Stage.idle) ...[
          const SizedBox(height: 14),
          _MicCheck(
            passed: _micReady,
            onPassed: () => setState(() => _micReady = true),
            onRecheck: () => setState(() => _micReady = false),
          ),
        ],

        if (_stage == _Stage.recording) ...[
          const SizedBox(height: 14),
          _RecordingCard(
            remaining: _remainingSeconds,
            cap: _cap,
            level: _level,
            onStop: _stop,
          ),
        ],

        if (_stage == _Stage.review && _takePath != null) ...[
          const SizedBox(height: 14),
          _ReviewCard(
            seconds: _takeSeconds,
            playing: _takePlaying,
            position: _takePosition,
            duration: _takeDuration,
            onTogglePlay: _toggleTakePlayback,
            blocked: _blocked,
            onSubmit: _submit,
            onDiscard: _discard,
            onUpgrade: _openPlus,
          ),
        ],

        if (_stage == _Stage.idle) ...[
          const SizedBox(height: 16),
          if (_blocked)
            MtPrimaryButton(label: 'See Linka Plus', onPressed: _openPlus)
          else
            MtPrimaryButton(
              label: 'Start Recording',
              onPressed: _micReady ? _start : null,
            ),
          if (!_micReady && !_blocked) ...[
            const SizedBox(height: 8),
            Text(
              'Check your microphone first — it takes five seconds.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, color: wr.faint),
            ),
          ],
          if (_blocked) ...[
            const SizedBox(height: 8),
            Text(
              'You have used your free AI markings. Linka Plus makes them unlimited.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, height: 1.45, color: wr.faint),
            ),
          ],
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

/// The question, exactly as the sample's part asks it.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.part, required this.tutorName});
  final Map<String, dynamic> part;

  /// Null when the question came from the topic bank rather than from a
  /// tutor's sample.
  final String? tutorName;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final title = part['title']?.toString().trim() ?? '';
    final question = part['question_text']?.toString().trim() ?? '';
    final number = (part['part'] as num?)?.toInt() ?? 2;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: wCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WTag(
                label: 'PART $number',
                background: wr.accent.withValues(alpha: 0.12),
                foreground: wr.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tutorName != null
                      ? 'The same question $tutorName answered'
                      : 'Straight from the IELTS topic bank',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, color: wr.faint),
                ),
              ),
            ],
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                  fontFamily: 'SF Pro', fontSize: 15, fontWeight: FontWeight.w800, color: wr.text),
            ),
          ],
          if (question.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              question,
              style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 14.5,
                  height: 1.55,
                  fontWeight: FontWeight.w600,
                  color: wr.text),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Symbols.timer_rounded, size: 14, color: wr.faint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Recording stops automatically at ${sCapForPart(number)} seconds, as the exam does.',
                  style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, height: 1.4, color: wr.faint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Record a few seconds and play them back before it matters.
///
/// The meter proves sound is arriving; the playback proves it is *your* voice
/// and loud enough to mark. The gate exists because neither a muted headset
/// nor the wrong input announces itself until the report comes back empty.
class _MicCheck extends StatefulWidget {
  const _MicCheck({required this.passed, required this.onPassed, required this.onRecheck});
  final bool passed;
  final VoidCallback onPassed;

  /// Drops the gate again. Owned by the parent because the gate is: a student
  /// who has switched headsets since passing wants the check back, and this
  /// widget cannot un-tell the screen it is ready.
  final VoidCallback onRecheck;

  @override
  State<_MicCheck> createState() => _MicCheckState();
}

/// Long enough to say a sentence and hear it back, short enough that nobody
/// minds doing it again.
const _micCheckSeconds = 5;

class _MicCheckState extends State<_MicCheck> {
  final _recorder = AudioRecorder();
  final _player = ap.AudioPlayer();
  StreamSubscription<Amplitude>? _amplitudeSub;
  StreamSubscription<void>? _completeSub;
  Timer? _timer;

  bool _testing = false;
  bool _playing = false;
  int _remaining = _micCheckSeconds;
  double _level = 0;

  /// The loudest the meter got during the take. Zero after a real take means
  /// nothing reached the microphone, which is the whole point of asking.
  double _peak = 0;
  String? _path;

  @override
  void initState() {
    super.initState();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amplitudeSub?.cancel();
    _completeSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _startTest() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        AppNotify.show(context, message: 'Microphone permission is required to record.');
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/mic_check_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100),
      path: path,
    );
    if (!mounted) return;

    setState(() {
      _testing = true;
      _remaining = _micCheckSeconds;
      _peak = 0;
      _level = 0;
      _path = null;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) _stopTest();
    });

    _amplitudeSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((amplitude) {
      if (!mounted) return;
      final normalised = ((amplitude.current + 45) / 45).clamp(0.0, 1.0);
      setState(() {
        _level = normalised;
        if (normalised > _peak) _peak = normalised;
      });
    });
  }

  Future<void> _stopTest() async {
    _timer?.cancel();
    _timer = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _level = 0;
      _path = path;
    });
  }

  Future<void> _togglePlayback() async {
    final path = _path;
    if (path == null) return;
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    if (_player.state == ap.PlayerState.paused) {
      await _player.resume();
    } else {
      await _player.play(ap.DeviceFileSource(path));
    }
    if (mounted) setState(() => _playing = true);
  }

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;

    if (widget.passed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: wCardDecoration(context),
        child: Row(
          children: [
            Icon(Symbols.check_circle_rounded, size: 18, color: wr.good),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Microphone ready',
                style: TextStyle(
                    fontFamily: 'SF Pro', fontSize: 13.5, fontWeight: FontWeight.w700, color: wr.text),
              ),
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  _path = null;
                  _peak = 0;
                });
                widget.onRecheck();
              },
              child: Text(
                'Check again',
                style: TextStyle(
                    fontFamily: 'SF Pro', fontSize: 12.5, fontWeight: FontWeight.w700, color: wr.accent),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: wCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.settings_voice_rounded, size: 18, color: wr.accent),
              const SizedBox(width: 9),
              Text(
                'Check your microphone',
                style: TextStyle(
                    fontFamily: 'SF Pro', fontSize: 14.5, fontWeight: FontWeight.w800, color: wr.text),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _testing
                ? 'Say anything — the bar should move while you talk.'
                : _path != null
                    ? 'Can you hear yourself clearly?'
                    : 'Record $_micCheckSeconds seconds and play it back before you start. '
                        'It takes a moment now and saves losing a marking to a dead microphone.',
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 13, height: 1.5, color: wr.muted),
          ),
          if (_testing) ...[
            const SizedBox(height: 14),
            _LevelBar(level: _level),
            const SizedBox(height: 8),
            Text(
              'Listening… ${_remaining}s left',
              style: TextStyle(
                  fontFamily: 'SF Pro', fontSize: 12.5, fontWeight: FontWeight.w700, color: wr.accent),
            ),
            const SizedBox(height: 12),
            _MiniButton(label: 'Stop', icon: Symbols.stop_rounded, onPressed: _stopTest),
          ] else if (_path != null) ...[
            if (_peak < 0.08) ...[
              const SizedBox(height: 12),
              Text(
                'We barely heard anything. Check that the right microphone is '
                'selected and that nothing is muted, then try again.',
                style: TextStyle(
                    fontFamily: 'SF Pro', fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w600, color: wr.bad),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                _MiniButton(
                  label: _playing ? 'Pause' : 'Play it back',
                  icon: _playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                  onPressed: _togglePlayback,
                ),
                const SizedBox(width: 8),
                _MiniButton(label: 'Try again', icon: Symbols.refresh_rounded, onPressed: _startTest),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onPassed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(color: wr.good, borderRadius: BorderRadius.circular(20)),
                    child: const Text(
                      'Sounds good',
                      style: TextStyle(
                          fontFamily: 'SF Pro', fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 14),
            _MiniButton(label: 'Start mic check', icon: Symbols.mic_rounded, onPressed: _startTest),
          ],
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(color: wr.soft, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: wr.text),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                  fontFamily: 'SF Pro', fontSize: 12.5, fontWeight: FontWeight.w700, color: wr.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// The live input level. Not decorative: it is the only proof, before the
/// playback, that anything is reaching the microphone at all.
class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.level});
  final double level;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: 8,
        color: wr.soft,
        child: AnimatedFractionallySizedBox(
          duration: const Duration(milliseconds: 120),
          alignment: Alignment.centerLeft,
          widthFactor: level.clamp(0.0, 1.0),
          child: Container(color: wr.accent),
        ),
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({
    required this.remaining,
    required this.cap,
    required this.level,
    required this.onStop,
  });

  final int remaining;
  final int cap;
  final double level;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: wCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: wr.bad, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                'Recording…',
                style: TextStyle(
                    fontFamily: 'SF Pro', fontSize: 14, fontWeight: FontWeight.w800, color: wr.bad),
              ),
              const Spacer(),
              Text(
                sClock(remaining),
                style: TextStyle(
                    fontFamily: 'SF Pro', fontSize: 24, fontWeight: FontWeight.w800, color: wr.text),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _LevelBar(level: level),
          const SizedBox(height: 8),
          Text(
            'Stops automatically at $cap seconds.',
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, color: wr.faint),
          ),
          const SizedBox(height: 16),
          MtPrimaryButton(label: 'Stop and Review', onPressed: onStop),
        ],
      ),
    );
  }
}

/// The take, before it is spent.
///
/// Listening back is not a nicety here: a marking is a finite resource for a
/// free user, and the difference between a good take and a wasted one is
/// usually audible in the first three seconds.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.seconds,
    required this.playing,
    required this.position,
    required this.duration,
    required this.onTogglePlay,
    required this.blocked,
    required this.onSubmit,
    required this.onDiscard,
    required this.onUpgrade,
  });

  final int seconds;
  final bool playing;
  final Duration position;
  final Duration duration;
  final VoidCallback onTogglePlay;
  final bool blocked;
  final VoidCallback onSubmit;
  final VoidCallback onDiscard;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    final total = duration.inMilliseconds > 0 ? duration : Duration(seconds: seconds);
    final progress =
        total.inMilliseconds == 0 ? 0.0 : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: wCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your take — ${wPlural(seconds, 'second', 'seconds')}',
            style: TextStyle(
                fontFamily: 'SF Pro', fontSize: 14.5, fontWeight: FontWeight.w800, color: wr.text),
          ),
          const SizedBox(height: 6),
          Text(
            'Listen back before you send it. Nothing is marked until you do.',
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, height: 1.45, color: wr.muted),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              GestureDetector(
                onTap: onTogglePlay,
                child: Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: wr.accent, shape: BoxShape.circle),
                  child: Icon(
                    playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
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
                      '${sClock(position.inSeconds)} / ${sClock(total.inSeconds)}',
                      style: TextStyle(fontFamily: 'SF Pro', fontSize: 11.5, color: wr.faint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (blocked)
            MtPrimaryButton(label: 'See Linka Plus', onPressed: onUpgrade)
          else
            MtPrimaryButton(label: 'Send for AI Marking', onPressed: onSubmit),
          const SizedBox(height: 10),
          _SecondaryButton(label: 'Record Again', icon: Symbols.refresh_rounded, onPressed: onDiscard),
        ],
      ),
    );
  }
}

/// The tutor's own take, offered only after the student has been marked.
class _CompareCard extends StatelessWidget {
  const _CompareCard({
    required this.tutorName,
    required this.playing,
    required this.onToggle,
  });

  final String tutorName;
  final bool playing;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: wCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Now hear how $tutorName answered it',
            style: TextStyle(
                fontFamily: 'SF Pro', fontSize: 14.5, fontWeight: FontWeight.w800, color: wr.text),
          ),
          const SizedBox(height: 6),
          Text(
            'Same question, marked answer. Listen for what they do between '
            'sentences, not just the words they choose.',
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, height: 1.45, color: wr.muted),
          ),
          const SizedBox(height: 14),
          _MiniButton(
            label: playing ? 'Pause' : 'Play the tutor’s answer',
            icon: playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
            onPressed: onToggle,
          ),
        ],
      ),
    );
  }
}

/// Outlined counterpart to [MtPrimaryButton], for the second action under a
/// card where both destinations are worth offering.
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final wr = context.wr;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: wr.text),
        label: Text(
          label,
          style: TextStyle(fontFamily: 'SF Pro', fontSize: 15, fontWeight: FontWeight.w600, color: wr.text),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: wr.line, width: 1.5),
          backgroundColor: wr.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
