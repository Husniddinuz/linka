import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ai_coach.dart';
import '../services/ai_coach_service.dart';
import '../services/api_service.dart';
import '../services/coach_socket.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import '../widgets/coach_orb.dart';
import '../widgets/coach_pronunciation.dart';
import '../widgets/mock_test_styles.dart';

/// The server's own ceiling on one turn. Azure refuses anything over a minute,
/// so past this a turn comes back with `pronunciation: null` — losing the one
/// thing this screen exists for. The server enforces it; the screen only has
/// to be able to explain it.
const _maxTurnSeconds = 55;

const _levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

/// The five characters the server ships, named here.
///
/// The API sends a name and a tagline for each, but in Russian only — it is
/// one row in a database table, not a translation file. The slug is the stable
/// part, so the copy lives with the app and the payload is the fallback for a
/// character added later.
const _personaCopy = {
  'classic': ('Classic', 'Balanced, friendly teacher.'),
  'sarcastic': (
    'Sarcastic',
    'Witty and sharp. Keeps you on your toes without putting you down.'
  ),
  'strict': ('Strict', 'No slack. Every detail counts.'),
  'buddy': ('Mate', 'Just chatting. Real slang, zero pressure.'),
  'examiner': ('IELTS examiner', 'A real Speaking exam, start to finish.'),
};

const _correctionLabels = {
  'grammar': 'GRAMMAR',
  'vocabulary': 'WORD CHOICE',
  'collocation': 'COLLOCATION',
  'fluency': 'FLUENCY',
};

const _mistakeKindLabels = {
  'pronunciation_phoneme': 'Sound',
  'pronunciation_word': 'Word',
  'grammar': 'Grammar',
  'vocabulary': 'Vocabulary',
  'collocation': 'Collocation',
  'fluency': 'Fluency',
};

Color _parseHex(String value) {
  final hex = value.replaceFirst('#', '');
  final int rgb = int.tryParse(hex, radix: 16) ?? 0x2563EB;
  return Color(0xFF000000 | rgb);
}

/// What came back about the turn the student just took.
///
/// There is one of these at a time. This is a spoken conversation, not a
/// thread: the score that matters is the one for what was just said, and the
/// running record of everything else is the mistakes panel.
class _Feedback {
  Pronunciation? pronunciation;
  List<Correction> corrections = const [];

  bool get isEmpty => pronunciation == null && corrections.isEmpty;
}

/// Live speaking practice with an AI coach: talk, and hear it answer.
///
/// There was a chat here — bubbles, a text composer, a transcript that grew
/// downwards — and it was the wrong shape for what this is. A speaking lesson
/// is not a conversation you read; the transcript was a second place to look
/// while the point of the screen was happening somewhere else, and it invited
/// typing, which is the one way to use this feature that scores nothing.
///
/// So the conversation is the conversation: a dark room, a sphere of dots that
/// shows what is happening, and the coach's last line under it. What it found
/// in the last turn folds away at the bottom, for the student who wants to see
/// the marking rather than hear it.
class AiCoachScreen extends StatefulWidget {
  const AiCoachScreen({super.key});

  @override
  State<AiCoachScreen> createState() => _AiCoachScreenState();
}

class _AiCoachScreenState extends State<AiCoachScreen> {
  final _player = ap.AudioPlayer();

  StreamSubscription<void>? _completeSub;
  Timer? _mouthTimer;
  CoachSocket? _socket;

  List<CoachPersona> _personas = const [];
  CoachStats? _stats;
  bool _loading = true;
  bool _unavailable = false;

  String _persona = 'classic';
  String _level = 'B1';
  final _goal = TextEditingController();

  int? _sessionId;
  bool _starting = false;
  bool _liveOpen = false;

  /// The server has heard speech and is waiting for it to end.
  bool _hearing = false;

  /// The student has turned their own microphone off.
  bool _muted = false;

  /// `transcribing` or `replying`, while the coach works on the last turn.
  String? _stage;
  double _micLevel = 0;
  double _voiceLevel = 0;

  /// The coach's last line, which in a spoken room is the whole transcript
  /// anyone needs on screen.
  String _said = '';
  _Feedback? _feedback;

  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _load();
    _completeSub = _player.onPlayerComplete.listen((_) => _stopMouth());
  }

  @override
  void dispose() {
    _mouthTimer?.cancel();
    _completeSub?.cancel();
    unawaited(_socket?.dispose());
    _player.dispose();
    _goal.dispose();
    super.dispose();
  }

  // ─── Loading ────────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        AiCoachService.fetchPersonas(),
        AiCoachService.fetchModels(),
        AiCoachService.fetchStats().catchError((_) => const CoachStats(
              active: 0,
              resolved: 0,
              top: <TrackedMistake>[],
            )),
      ]);
      if (!mounted) return;
      final personas = results[0] as List<CoachPersona>;
      final models = results[1] as List<String>;
      setState(() {
        _personas = personas;
        _stats = results[2] as CoachStats;
        // An empty model list means no LLM key is configured upstream and
        // every session call would answer 503. Saying so beats a start button
        // that cannot start anything.
        _unavailable = personas.isEmpty || models.isEmpty;
        _persona = personas.isNotEmpty ? personas.first.slug : 'classic';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _unavailable = true;
      });
    }
  }

  Future<void> _refreshStats() async {
    try {
      final stats = await AiCoachService.fetchStats();
      if (!mounted) return;
      setState(() => _stats = stats);
    } catch (_) {
      // The panel keeping its previous reading beats an error over a
      // conversation that is going fine.
    }
  }

  // ─── The conversation ───────────────────────────────────────────────────

  CoachPersona? get _chosen {
    for (final persona in _personas) {
      if (persona.slug == _persona) return persona;
    }
    return _personas.isEmpty ? null : _personas.first;
  }

  Color get _accent =>
      _chosen == null ? const Color(0xFF2563EB) : _parseHex(_chosen!.color);

  String _personaName(CoachPersona persona) =>
      _personaCopy[persona.slug]?.$1 ?? persona.name;

  String _personaTagline(CoachPersona persona) =>
      _personaCopy[persona.slug]?.$2 ?? persona.tagline;

  /// What is happening, in the words the student needs.
  String get _status {
    if (_muted) return 'Microphone off';
    if (!_liveOpen) return 'Opening the microphone…';
    if (_voiceLevel > 0) return 'Speaking';
    if (_stage != null) return 'Working on it…';
    if (_hearing) return 'Hearing you…';
    return 'Listening — just start talking';
  }

  /// What the sphere is doing. What the student is doing outranks what the
  /// coach is doing: they are the one who needs to see themselves being heard.
  CoachMood get _mood {
    if (_hearing) return CoachMood.listening;
    if (_stage != null) return CoachMood.thinking;
    if (_voiceLevel > 0) return CoachMood.speaking;
    if (_liveOpen && !_muted) return CoachMood.listening;
    return CoachMood.idle;
  }

  /// What the sphere answers to: the microphone while the student talks, the
  /// coach's own voice while it replies — whichever is making sound.
  double get _activity => _voiceLevel > 0
      ? _voiceLevel
      : (_liveOpen && !_muted ? _micLevel : 0);

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      final session = await AiCoachService.startSession(
        persona: _persona,
        level: _level,
        goal: _goal.text.trim(),
      );
      final audioPath = await _writeReplyAudio(session.greetingAudio);
      if (!mounted) return;
      setState(() {
        _sessionId = session.id;
        _said = session.greetingText;
        _feedback = null;
        _muted = false;
        _starting = false;
      });
      // The greeting plays while the microphone opens behind it: by the time
      // the coach has finished saying hello, the conversation is live.
      unawaited(_connectVoice(session.id));
      if (audioPath != null) await _playReply(audioPath);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      AppNotify.show(context, message: _message(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _starting = false);
      AppNotify.show(context, message: 'That did not go through. Try again.');
    }
  }

  Future<void> _end() async {
    final id = _sessionId;
    await _stopPlayback();
    await _disconnectVoice();
    if (!mounted) return;
    setState(() {
      _sessionId = null;
      _said = '';
      _feedback = null;
      _stage = null;
      _muted = false;
    });
    if (id != null) {
      // Fire and forget: the conversation is over on this screen either way,
      // and an unclosed session on the server simply goes cold.
      unawaited(AiCoachService.endSession(id).catchError((_) {}));
      unawaited(_refreshStats());
    }
  }

  String _message(ApiException e) => switch (e.statusCode) {
        422 => 'That did not come through — say it again, a little louder.',
        400 => 'That recording could not be read.',
        404 => 'This conversation has closed. Start a new one.',
        502 => 'The coach cannot be reached right now.',
        503 => 'The coach is not set up on the server yet.',
        _ => 'That turn did not go through. Try again.',
      };

  // ─── The live conversation ──────────────────────────────────────────────

  /// Turns one socket frame into what the screen shows.
  ///
  /// The order the server sends these in is deliberate and worth keeping in
  /// mind: `reply` arrives before `corrections`, because the analysis takes
  /// about six seconds against the reply's one and a half. Nothing here waits
  /// for the corrections — they land under a turn the student has already
  /// heard answered, and they do not arrive at all when the analysis found
  /// nothing.
  Future<void> _onSocketEvent(Map<String, dynamic> event) async {
    if (!mounted) return;
    switch (event['type']) {
      case 'ready':
        setState(() => _liveOpen = true);

      case 'speech_started':
        // They have started talking over the coach; stop it rather than let
        // both voices run — its tail would come back through the microphone
        // as if they had said it.
        await _stopPlayback();
        if (!mounted) return;
        setState(() => _hearing = true);

      case 'speech_ended':
        // A new turn is in flight, so the marking of the last one is history.
        setState(() {
          _hearing = false;
          _feedback = null;
        });

      case 'processing':
        setState(() => _stage = event['stage']?.toString());
        _syncMute();

      case 'pronunciation':
        setState(() {
          // The frame is the score with a tag on it; the card wants the score.
          (_feedback ??= _Feedback()).pronunciation =
              Pronunciation.fromJson(event);
        });

      case 'reply':
        final audioPath = await _writeReplyAudio(event['audio'] as String?);
        if (!mounted) return;
        setState(() {
          _stage = null;
          _said = event['text']?.toString() ?? '';
        });
        if (audioPath != null) await _playReply(audioPath);
        unawaited(_refreshStats());

      case 'corrections':
        setState(() {
          (_feedback ??= _Feedback()).corrections =
              ((event['items'] as List?) ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .map(Correction.fromJson)
                  .toList();
        });
        unawaited(_refreshStats());

      case 'cancelled':
        setState(() => _hearing = false);

      case 'error':
        // The message is Russian prose from the server and belongs in a log,
        // not in front of a student reading the app in Uzbek.
        setState(() {
          _stage = null;
          _hearing = false;
        });
        AppNotify.show(context,
            message: 'That did not come through — say it again, a little '
                'louder.');
    }
  }

  Future<void> _connectVoice(int sessionId) async {
    if (_socket != null) return;
    final socket = CoachSocket(
      onEvent: (event) => unawaited(_onSocketEvent(event)),
      onLevel: (level) {
        if (mounted) setState(() => _micLevel = level);
      },
      onClosed: (code) {
        if (!mounted) return;
        _socket = null;
        setState(() {
          _liveOpen = false;
          _hearing = false;
          _stage = null;
        });
        // 4404 is a conversation that has ended and 4401 a token that has;
        // both mean this screen cannot go on. Anything else is the network,
        // and the student can open the microphone again.
        if (code == 4404) {
          setState(() => _sessionId = null);
          AppNotify.show(context,
              message: 'This conversation has closed. Start a new one.');
        } else {
          AppNotify.show(context,
              message: 'The connection dropped. Tap to reconnect.');
        }
      },
    );

    final ok = await socket.connect(sessionId);
    if (!ok) {
      await socket.dispose();
      if (!mounted) return;
      AppNotify.show(context,
          message: 'Microphone permission is required to talk to the coach.');
      return;
    }
    if (!mounted) {
      await socket.dispose();
      return;
    }
    _socket = socket;
  }

  Future<void> _disconnectVoice() async {
    final socket = _socket;
    _socket = null;
    await socket?.dispose();
    if (!mounted) return;
    setState(() {
      _liveOpen = false;
      _hearing = false;
      _micLevel = 0;
    });
  }

  /// Opens the microphone again after a drop, or after the student refused the
  /// permission and changed their mind.
  Future<void> _reconnect() async {
    final id = _sessionId;
    if (id == null || _socket != null) return;
    await _connectVoice(id);
  }

  /// The microphone stops sending while the coach is working or speaking, or
  /// while the student has muted it. The server already ignores input while it
  /// is busy, so this is about the meter — a level still moving while the
  /// coach thinks says the student is being heard when they are not.
  void _syncMute() {
    _socket?.setMuted(_muted || _voiceLevel > 0 || _stage != null);
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _syncMute();
  }

  /// The reply arrives as base64 in the JSON — generated per turn and never
  /// stored, so there is nothing to link to. It goes to a temp file because
  /// that is what the player reads, and the OS clears the directory for us.
  Future<String?> _writeReplyAudio(String? base64Audio) async {
    if (base64Audio == null || base64Audio.isEmpty) return null;
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/ai_coach_reply_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      await file.writeAsBytes(base64Decode(base64Audio));
      return file.path;
    } catch (_) {
      // No audio is a reply that can still be read.
      return null;
    }
  }

  Future<void> _playReply(String path) async {
    try {
      await _player.play(ap.DeviceFileSource(path));
      _startVoiceMeter();
    } catch (_) {
      _stopMouth();
    }
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    _stopMouth();
  }

  /// The sphere's amplitude while a reply plays.
  ///
  /// The web drives this off the real samples through a WebAudio analyser. No
  /// Flutter audio package exposes them, so this is an envelope rather than a
  /// measurement: a random walk at a speaking rhythm, which reads as talking
  /// where a still sphere reads as broken. It is honest about being a rhythm —
  /// it never claims to match a syllable.
  void _startVoiceMeter() {
    _mouthTimer?.cancel();
    _syncMute();
    _mouthTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!mounted) return;
      setState(() {
        final target = 0.15 + _random.nextDouble() * 0.7;
        _voiceLevel = _voiceLevel + (target - _voiceLevel) * 0.55;
      });
    });
  }

  void _stopMouth() {
    _mouthTimer?.cancel();
    _mouthTimer = null;
    if (!mounted) return;
    setState(() => _voiceLevel = 0);
    _syncMute();
  }

  // ─── Building ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final talking = _sessionId != null;
    return Scaffold(
      backgroundColor: talking ? colors.coachStage : colors.background,
      // The room has no app bar: it is a dark stage with its own controls, the
      // way a call is, and a title bar above it is furniture from the rest of
      // the app.
      appBar: talking ? null : mtAppBar(context, title: 'AI Coach'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _unavailable
              ? _CentredNote(
                  text: 'The coach is offline right now. Try again shortly.',
                )
              : talking
                  ? _buildRoom(context)
                  : _buildSetup(context),
    );
  }

  Widget _buildSetup(BuildContext context) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          'Talk to a coach that answers out loud, scores how you said it '
          'sound by sound, and remembers what you keep getting wrong.',
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 13.5,
            height: 1.45,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 18),

        // The coach, before a word is said. It gathers itself out of the dark
        // on the way in, and picking a different character recolours it —
        // which is the only preview of "who am I talking to" that means
        // anything when the character is a voice.
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 180,
            color: colors.coachStage,
            child: CoachOrb(accent: _accent),
          ),
        ),
        const SizedBox(height: 18),

        Text(
          'PICK WHO YOU ARE TALKING TO',
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: 10),
        for (final persona in _personas) ...[
          _PersonaCard(
            persona: persona,
            name: _personaName(persona),
            tagline: _personaTagline(persona),
            selected: persona.slug == _persona,
            onTap: () => setState(() => _persona = persona.slug),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        Text(
          'YOUR LEVEL',
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final level in _levels)
              GestureDetector(
                onTap: () => setState(() => _level = level),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: level == _level ? colors.brand : colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    level,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: level == _level
                          ? colors.onBrand
                          : colors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _goal,
          maxLength: 120,
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 14,
            color: colors.textPrimary,
          ),
          decoration: InputDecoration(
            counterText: '',
            labelText: 'What are you working towards? (optional)',
            labelStyle: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 13,
              color: colors.textTertiary,
            ),
            hintText: 'IELTS 7.0, a job interview, small talk…',
            hintStyle: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 13,
              color: colors.textTertiary,
            ),
            filled: true,
            fillColor: colors.surfaceAlt,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _starting ? null : _start,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.brand,
              foregroundColor: colors.onBrand,
              disabledBackgroundColor: colors.brand.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            icon: _starting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(colors.onBrand),
                    ),
                  )
                : const Icon(Symbols.mic_rounded, size: 20),
            label: Text(
              _starting ? 'Starting…' : 'Start talking',
              style: const TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        if ((_stats?.top.isNotEmpty ?? false)) ...[
          const SizedBox(height: 28),
          _MistakesCard(stats: _stats!),
        ],
      ],
    );
  }

  /// The room.
  ///
  /// A dark stage whatever the app's theme is: the sphere is drawn in light,
  /// and light needs somewhere dark to be seen. There is nothing to press on
  /// it but mute, end, and "I'm done" for a room too noisy for the silence
  /// detector.
  Widget _buildRoom(BuildContext context) {
    final colors = context.colors;
    final accent = _accent;
    final feedback = _feedback;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.35),
            radius: 1.1,
            colors: [
              Color.alphaBlend(accent.withValues(alpha: 0.28), colors.coachStage),
              colors.coachStage,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
                child: Row(
                  children: [
                    Text(
                      _chosen == null ? '' : _personaName(_chosen!),
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: colors.coachGlow,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.32),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _level,
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.coachGlow,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _toggleMute,
                      tooltip: _muted ? 'Turn the microphone on' : 'Mute',
                      icon: Icon(
                        _muted ? Symbols.mic_off_rounded : Symbols.mic_rounded,
                        color: _muted
                            ? colors.error
                            : colors.coachGlow.withValues(alpha: 0.8),
                        size: 22,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _end,
                      style: TextButton.styleFrom(
                        backgroundColor: colors.error,
                        foregroundColor: colors.onBrand,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      icon: const Icon(Symbols.call_end_rounded, size: 16),
                      label: const Text(
                        'End',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: CoachOrb(
                  mood: _mood,
                  level: _activity,
                  accent: accent,
                ),
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_mood != CoachMood.idle) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _muted ? colors.error : accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    _status,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.coachGlow.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),

              // What the coach just said. In a spoken room this is the whole
              // transcript worth having on screen — and it is a caption, not a
              // chat: it is replaced, never stacked.
              if (_said.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    child: Text(
                      _said,
                      key: ValueKey(_said),
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 15,
                        height: 1.45,
                        color: colors.coachGlow,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 14),

              // The meter is the proof the microphone is live. A flat one here
              // is a dead input, visible before a whole answer has been spoken
              // into it.
              SizedBox(
                width: 160,
                height: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _liveOpen && !_muted ? _micLevel.clamp(0.0, 1.0) : 0,
                    backgroundColor: colors.coachGlow.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(colors.success),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (!_liveOpen)
                // The socket is not open: either it is still opening, or it
                // dropped and this is the way back in.
                TextButton(
                  onPressed: _reconnect,
                  child: Text(
                    'Open the microphone',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: colors.coachGlow,
                    ),
                  ),
                )
              else
                // The silence detector works on loudness, so a noisy room
                // needs a way to say "I have finished".
                OutlinedButton(
                  onPressed: _hearing ? () => _socket?.commit() : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.coachGlow,
                    disabledForegroundColor:
                        colors.coachGlow.withValues(alpha: 0.3),
                    side: BorderSide(
                      color: colors.coachGlow
                          .withValues(alpha: _hearing ? 0.35 : 0.12),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text(
                    "I'm done",
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 8),
                child: Text(
                  'The coach hears when you stop, so there is nothing to '
                  'press. Up to $_maxTurnSeconds seconds a turn.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 10.5,
                    color: colors.coachGlow.withValues(alpha: 0.5),
                  ),
                ),
              ),

              // The marking for the turn just taken, folded away. One turn at
              // a time, replacing itself: the running record of what the
              // student keeps getting wrong is the panel on the way in.
              if (feedback != null && !feedback.isEmpty)
                _LastTurnCard(feedback: feedback),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Pieces ───────────────────────────────────────────────────────────────

/// What the coach found in the last turn, shut by default.
///
/// In a spoken lesson the marking is something you look at between sentences,
/// not while one is being said — so it opens on a tap and takes at most half
/// the screen when it does.
class _LastTurnCard extends StatefulWidget {
  const _LastTurnCard({required this.feedback});

  final _Feedback feedback;

  @override
  State<_LastTurnCard> createState() => _LastTurnCardState();
}

class _LastTurnCardState extends State<_LastTurnCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pronunciation = widget.feedback.pronunciation;
    final corrections = widget.feedback.corrections;
    final band = pronunciation == null
        ? null
        : pronunciation.overall < 60
            ? 'A listener would notice'
            : pronunciation.overall < 80
                ? 'Understandable, not clean'
                : 'Clear';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Text(
                    'YOUR LAST TURN',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (pronunciation != null)
                    Text(
                      '${pronunciation.overall.round()} · $band',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  if (corrections.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        corrections.length == 1
                            ? '1 fix'
                            : '${corrections.length} fixes',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    _open
                        ? Symbols.keyboard_arrow_down_rounded
                        : Symbols.keyboard_arrow_up_rounded,
                    color: colors.textTertiary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.42,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: [
                    if (pronunciation != null)
                      CoachPronunciationCard(pronunciation: pronunciation),
                    if (corrections.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _CorrectionsCard(corrections: corrections),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CentredNote extends StatelessWidget {
  const _CentredNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 13.5,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      );
}


class _CorrectionsCard extends StatelessWidget {
  const _CorrectionsCard({required this.corrections});

  final List<Correction> corrections;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Text(
              '${corrections.length} ${corrections.length == 1 ? 'FIX' : 'FIXES'}',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: colors.textTertiary,
              ),
            ),
          ),
          for (final correction in corrections)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _correctionLabels[correction.type] ?? 'FIX',
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          correction.rule,
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    correction.original,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12.5,
                      color: colors.textTertiary,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: colors.error,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Symbols.check_rounded,
                          size: 14, color: colors.success),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          correction.corrected,
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: colors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (correction.explanation.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      correction.explanation,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 12,
                        height: 1.4,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}


class _MistakesCard extends StatelessWidget {
  const _MistakesCard({required this.stats});

  final CoachStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final top = stats.top.take(6).toList();
    final busiest = top.isEmpty ? 1 : top.first.occurrences;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Icon(Symbols.auto_awesome_rounded,
                    size: 16, color: colors.accentBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'What we are working on',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (stats.resolved > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.successBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${stats.resolved} cleared',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: colors.success,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (final mistake in top)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          mistake.key,
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '${mistake.occurrences}×',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _mistakeKindLabels[mistake.kind] ?? mistake.kind,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Relative to the busiest entry, not a fixed scale: what
                  // matters is which one to fix first, and nine occurrences
                  // means nothing on its own.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: (mistake.occurrences / busiest).clamp(0.08, 1.0),
                      minHeight: 4,
                      backgroundColor: colors.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation(colors.accentBlue),
                    ),
                  ),
                  if (mistake.correction.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      mistake.correction,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 11.5,
                        height: 1.35,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}


class _PersonaCard extends StatelessWidget {
  const _PersonaCard({
    required this.persona,
    required this.name,
    required this.tagline,
    required this.selected,
    required this.onTap,
  });

  final CoachPersona persona;
  final String name;
  final String tagline;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = _parseHex(persona.color);
    final filled = math.max(1, (persona.strictness * 5).round());

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? accent : colors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                persona.emoji,
                style: const TextStyle(fontSize: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      for (var dot = 0; dot < 5; dot++)
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: dot < filled ? accent : colors.border,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tagline,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      height: 1.35,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Symbols.check_circle_rounded, size: 20, color: accent),
          ],
        ),
      ),
    );
  }
}
