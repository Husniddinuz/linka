import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ai_coach.dart';
import '../services/ai_coach_service.dart';
import '../services/api_service.dart';
import '../services/coach_socket.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import '../widgets/coach_avatar.dart';
import '../widgets/coach_pronunciation.dart';
import '../widgets/mock_test_styles.dart';

/// The server's own ceiling on one turn. Azure refuses anything over a minute,
/// so past this a turn comes back with `pronunciation: null` — losing the one
/// thing this screen exists for. The server enforces it; the screen only has
/// to be able to explain it.
const _maxTurnSeconds = 55;

/// How you answer.
///
/// `voice` is a live socket: the microphone stays open and the server decides
/// when a sentence has ended, so it behaves the same here as on the web and
/// neither client needs a voice-activity detector of its own. `text` is the
/// way in from a quiet room, a refused microphone, or a bad connection.
enum CoachMode { voice, text }

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

sealed class _Entry {
  const _Entry();
}

class _CoachEntry extends _Entry {
  const _CoachEntry({required this.text, this.audioPath});

  final String text;

  /// The reply, written to a temp file: the API sends base64 in the JSON, and
  /// a file is what the player takes.
  final String? audioPath;
}

class _StudentEntry extends _Entry {
  _StudentEntry({this.text, this.seconds = 0});

  /// What they typed, or null for a spoken turn — the server deliberately does
  /// not send back a transcript of the student's own words.
  final String? text;

  /// How long they spoke. Nothing was recorded to a file: the turn went out as
  /// it was spoken, so its length is all there is to show of it.
  final int seconds;

  bool pending = true;
  String? error;
  Pronunciation? pronunciation;
  List<Correction> corrections = const [];
}

/// Live speaking practice with an AI coach: talk, hear a reply out loud, and
/// see what the last thing you said sounded like.
///
/// A turn is one request — record, upload, get audio back — rather than the
/// WebSocket the API also offers. The socket wants raw PCM16 at 16 kHz and
/// end-of-utterance detection on the server; it buys latency this screen can
/// live without, and everything else about the conversation is identical, so
/// moving to it later changes this file and nothing else.
class AiCoachScreen extends StatefulWidget {
  const AiCoachScreen({super.key});

  @override
  State<AiCoachScreen> createState() => _AiCoachScreenState();
}

class _AiCoachScreenState extends State<AiCoachScreen> {
  final _player = ap.AudioPlayer();
  final _scroll = ScrollController();
  final _typed = TextEditingController();

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
  final List<_Entry> _entries = [];
  bool _starting = false;
  bool _sending = false;
  CoachMode _mode = CoachMode.voice;
  bool _liveOpen = false;
  /// The server has heard speech and is waiting for it to end.
  bool _hearing = false;
  /// `transcribing` or `replying`, while the coach works on the last turn.
  String? _stage;
  double _micLevel = 0;
  double _voiceLevel = 0;
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
    _scroll.dispose();
    _typed.dispose();
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

  /// The coach's last line, shown under the character: in a spoken
  /// conversation this is the part you would otherwise have to scroll for.
  String? get _lastSaid {
    for (var index = _entries.length - 1; index >= 0; index--) {
      final entry = _entries[index];
      if (entry is _CoachEntry) return entry.text;
    }
    return null;
  }

  /// What is happening, in the words the student needs.
  String get _status {
    if (_mode == CoachMode.text) return 'Type when you are ready';
    if (!_liveOpen) return 'Opening the microphone…';
    if (_voiceLevel > 0) return 'Speaking';
    if (_stage != null) return 'Working on it…';
    if (_hearing) return 'Hearing you…';
    return 'Listening — just start talking';
  }

  CoachMood get _mood {
    // What the student is doing outranks what the coach is doing: they are the
    // one who needs to see themselves being heard.
    if (_hearing) return CoachMood.listening;
    if (_sending || _stage != null) return CoachMood.thinking;
    if (_voiceLevel > 0) return CoachMood.speaking;
    if (_mode == CoachMode.voice && _liveOpen) return CoachMood.listening;
    return CoachMood.idle;
  }

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
        _entries
          ..clear()
          ..addAll([
            if (session.greetingText.isNotEmpty)
              _CoachEntry(text: session.greetingText, audioPath: audioPath),
          ]);
        _starting = false;
      });
      // The greeting plays while the microphone opens behind it: by the time
      // the coach has finished saying hello, the conversation is live.
      unawaited(_applyMode());
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
      _entries.clear();
      _sending = false;
      _stage = null;
      _typed.clear();
    });
    if (id != null) {
      // Fire and forget: the conversation is over on this screen either way,
      // and an unclosed session on the server simply goes cold.
      unawaited(AiCoachService.endSession(id).catchError((_) {}));
      unawaited(_refreshStats());
    }
  }

  /// Sends a turn and folds the answer back into the entry it belongs to.
  ///
  /// The student's entry exists before the request does — it is what they just
  /// said — so a failure marks that entry rather than vanishing it. On a 422
  /// ("didn't catch that") the take is still there to play back, which is
  /// usually enough to see why.
  Future<void> _submit(
    _StudentEntry entry,
    Future<CoachTurn> Function() send,
  ) async {
    setState(() => _sending = true);
    _scrollToEnd();
    try {
      final turn = await send();
      final audioPath = await _writeReplyAudio(turn.replyAudio);
      if (!mounted) return;
      setState(() {
        entry.pending = false;
        entry.pronunciation = turn.pronunciation;
        entry.corrections = turn.corrections;
        _entries.add(_CoachEntry(text: turn.replyText, audioPath: audioPath));
        _sending = false;
      });
      _scrollToEnd();
      if (audioPath != null) await _playReply(audioPath);
      unawaited(_refreshStats());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        entry.pending = false;
        entry.error = _message(e);
        _sending = false;
        if (e.statusCode == 404) _sessionId = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        entry.pending = false;
        entry.error = 'That turn did not go through. Try again.';
        _sending = false;
      });
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
  /// for the corrections — they land in a card under a turn the student has
  /// already heard answered, and they do not arrive at all when the analysis
  /// found nothing.
  Future<void> _onSocketEvent(Map<String, dynamic> event) async {
    if (!mounted) return;
    switch (event['type']) {
      case 'ready':
        setState(() => _liveOpen = true);

      case 'speech_started':
        // They have started talking over the coach; stop it rather than let
        // both voices run.
        await _stopPlayback();
        if (!mounted) return;
        setState(() => _hearing = true);

      case 'speech_ended':
        setState(() {
          _hearing = false;
          _entries.add(_StudentEntry(
            seconds: ((event['ms'] as num?) ?? 0) ~/ 1000,
          ));
        });
        _scrollToEnd();

      case 'processing':
        setState(() => _stage = event['stage']?.toString());
        _syncMute();

      case 'pronunciation':
        _updateLastStudent((entry) {
          // The frame is the score with a tag on it; the card wants the score.
          entry.pronunciation = Pronunciation.fromJson(event);
        });

      case 'reply':
        final audioPath = await _writeReplyAudio(event['audio'] as String?);
        if (!mounted) return;
        setState(() {
          _stage = null;
          _updateLastStudent((entry) => entry.pending = false, rebuild: false);
          // Cleared here rather than after playback starts: between the two is
          // a window where the coach is about to speak and the microphone is
          // still open on its own voice.
          _entries.add(_CoachEntry(
            text: event['text']?.toString() ?? '',
            audioPath: audioPath,
          ));
        });
        _scrollToEnd();
        if (audioPath != null) await _playReply(audioPath);
        unawaited(_refreshStats());

      case 'corrections':
        _updateLastStudent((entry) {
          entry.corrections = ((event['items'] as List?) ?? const [])
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
        setState(() => _stage = null);
        _updateLastStudent((entry) {
          entry.pending = false;
          entry.error = 'That did not come through — say it again, a little '
              'louder.';
        });
    }
  }

  /// Applies a change to the turn the student most recently took.
  ///
  /// The score, the corrections and the failure all arrive as separate frames
  /// after it, seconds apart and in a fixed order, and every one of them
  /// belongs to that same turn — so they are folded into it by position rather
  /// than by an id the socket protocol does not carry.
  void _updateLastStudent(
    void Function(_StudentEntry entry) change, {
    bool rebuild = true,
  }) {
    for (var index = _entries.length - 1; index >= 0; index--) {
      final entry = _entries[index];
      if (entry is! _StudentEntry) continue;
      if (rebuild) {
        setState(() => change(entry));
      } else {
        change(entry);
      }
      return;
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
        // and typing still works over it.
        if (code == 4404) {
          setState(() => _sessionId = null);
          AppNotify.show(context,
              message: 'This conversation has closed. Start a new one.');
        } else {
          setState(() => _mode = CoachMode.text);
          AppNotify.show(context,
              message: 'The connection dropped. Switched you to typing.');
        }
      },
    );

    final ok = await socket.connect(sessionId);
    if (!ok) {
      await socket.dispose();
      if (!mounted) return;
      // No microphone is not a dead end: the same conversation takes typing.
      setState(() => _mode = CoachMode.text);
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

  /// Voice is the default, so the socket opens with the conversation and
  /// closes with it or with a switch to typing.
  Future<void> _applyMode() async {
    if (_sessionId == null || _mode == CoachMode.text) {
      await _disconnectVoice();
      return;
    }
    await _connectVoice(_sessionId!);
  }

  /// The microphone stops sending while the coach is working or speaking. The
  /// server already ignores input while it is busy, so this is about the meter
  /// — a level still moving while the coach thinks says the student is being
  /// heard when they are not.
  void _syncMute() {
    _socket?.setMuted(_voiceLevel > 0 || _stage != null);
  }

  Future<void> _sendTyped() async {
    final text = _typed.text.trim();
    final id = _sessionId;
    if (text.isEmpty || id == null || _sending) return;
    await _stopPlayback();
    _typed.clear();

    final entry = _StudentEntry(text: text);
    setState(() => _entries.add(entry));
    await _submit(
      entry,
      () => AiCoachService.sendTextTurn(sessionId: id, text: text),
    );
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
      _startMouth();
    } catch (_) {
      _stopMouth();
    }
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    _stopMouth();
  }

  /// The mouth, while a reply plays.
  ///
  /// The web drives this off the real amplitude through a WebAudio analyser.
  /// No Flutter audio package exposes the played samples, so this is an
  /// envelope rather than a measurement: a random walk at a speaking rhythm,
  /// which reads as talking where a still mouth reads as broken. It is honest
  /// about being a rhythm — it never claims to match a syllable.
  void _startMouth() {
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

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  // ─── Building ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: mtAppBar(
        context,
        title: 'AI Coach',
        actions: [
          if (_sessionId != null)
            TextButton(
              onPressed: _end,
              child: Text(
                'End',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontWeight: FontWeight.w700,
                  color: colors.error,
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _unavailable
              ? _CentredNote(
                  text: 'The coach is offline right now. Try again shortly.',
                )
              : _sessionId == null
                  ? _buildSetup(context)
                  : _buildRoom(context),
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
                : const Icon(Icons.mic_rounded, size: 20),
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

  Widget _buildRoom(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        _Stage(
          persona: _persona,
          accent: _accent,
          name: _chosen == null ? '' : _personaName(_chosen!),
          level: _level,
          mood: _mood,
          voiceLevel: _voiceLevel,
          // What the rings answer: the microphone while the student talks, the
          // coach's own voice while it replies — whichever is making sound.
          activity: _voiceLevel > 0
              ? _voiceLevel
              : (_mode == CoachMode.voice && _liveOpen ? _micLevel : 0),
          status: _status,
          lastSaid: _lastSaid,
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            itemCount: _entries.length + (_sending ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _entries.length) {
                return _ThinkingBubble(persona: _persona, accent: _accent);
              }
              final entry = _entries[index];
              return switch (entry) {
                _CoachEntry() => _CoachBubble(
                    entry: entry,
                    persona: _persona,
                    accent: _accent,
                    onPlay: _playReply,
                  ),
                _StudentEntry() => _StudentBubble(entry: entry),
              };
            },
          ),
        ),
        _Composer(
          mode: _mode,
          liveOpen: _liveOpen,
          hearing: _hearing,
          working: _stage != null,
          speaking: _voiceLevel > 0,
          sending: _sending,
          micLevel: _micLevel,
          controller: _typed,
          onMode: (mode) {
            if (mode == _mode) return;
            setState(() => _mode = mode);
            unawaited(_applyMode());
          },
          onDone: () => _socket?.commit(),
          onSend: _sendTyped,
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 0 : 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            _mode == CoachMode.voice
                ? 'The coach hears when you stop, so there is nothing to '
                    'press. Up to $_maxTurnSeconds seconds a turn.'
                : 'Typed turns are answered out loud, but there is no '
                    'pronunciation score without your voice.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 10.5,
              color: colors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Pieces ───────────────────────────────────────────────────────────────

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

/// The character, and what it is doing. It sits above the conversation rather
/// than beside it: this is the one thing on the screen meant to feel like a
/// person, so it gets the room to read as one.
/// The stage.
///
/// With the microphone open there is nothing to press and no take to review,
/// so the screen has one job: show that someone is listening. The character
/// gets the middle and the size to read as a person; the transcript is what
/// happened, and it goes below.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.persona,
    required this.accent,
    required this.name,
    required this.level,
    required this.mood,
    required this.voiceLevel,
    required this.activity,
    required this.status,
    required this.lastSaid,
  });

  final String persona;
  final Color accent;
  final String name;
  final String level;
  final CoachMood mood;
  final double voiceLevel;

  /// 0–1, whichever of the two voices is making sound right now.
  final double activity;
  final String status;
  final String? lastSaid;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.1,
          colors: [accent.withValues(alpha: 0.16), colors.background],
        ),
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          // Two rings on the live level. In this mode they are the whole
          // feedback loop — there is no waveform to watch and no button held
          // down to prove the microphone is on.
          SizedBox(
            width: 168,
            height: 168,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _Ring(color: accent.withValues(alpha: 0.14),
                    scale: 1 + activity * 0.28, size: 168),
                _Ring(color: accent.withValues(alpha: 0.20),
                    scale: 1 + activity * 0.14, size: 148),
                Container(
                  width: 130,
                  height: 130,
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.bottomCenter,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.26),
                    shape: BoxShape.circle,
                  ),
                  child: CoachAvatar(
                    persona: persona,
                    accent: accent,
                    mood: mood,
                    level: voiceLevel,
                    size: 126,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  level,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (mood != CoachMood.idle) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                status,
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),

          // What the coach just said, big enough to read at arm's length — the
          // spoken line is the conversation in this mode, and the transcript
          // below is the record of it.
          if (lastSaid != null && lastSaid!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              lastSaid!,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 15,
                height: 1.45,
                color: colors.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One of the stage's breathing rings.
class _Ring extends StatelessWidget {
  const _Ring({required this.color, required this.scale, required this.size});

  final Color color;
  final double scale;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      // Fast enough to track a voice, slow enough not to strobe.
      duration: const Duration(milliseconds: 120),
      scale: scale,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _CoachBubble extends StatelessWidget {
  const _CoachBubble({
    required this.entry,
    required this.persona,
    required this.accent,
    required this.onPlay,
  });

  final _CoachEntry entry;
  final String persona;
  final Color accent;
  final Future<void> Function(String path) onPlay;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BubbleAvatar(persona: persona, accent: accent),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                  ),
                  child: Text(
                    entry.text,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 14,
                      height: 1.4,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (entry.audioPath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 2),
                    child: GestureDetector(
                      onTap: () => onPlay(entry.audioPath!),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_circle_fill_rounded,
                            size: 26,
                            color: colors.accentBlue,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Play again',
                            style: TextStyle(
                              fontFamily: 'SF Pro',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: colors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentBubble extends StatelessWidget {
  const _StudentBubble({required this.entry});

  final _StudentEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: colors.brand,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: entry.text != null
                ? Text(
                    entry.text!,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 14,
                      height: 1.4,
                      color: colors.onBrand,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.graphic_eq_rounded,
                          size: 18, color: colors.onBrand),
                      const SizedBox(width: 8),
                      Text(
                        'Your turn · ${entry.seconds}s',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.onBrand,
                        ),
                      ),
                    ],
                  ),
          ),
          if (entry.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colors.errorBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  entry.error!,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.error,
                  ),
                ),
              ),
            ),
          if (entry.pronunciation != null) ...[
            const SizedBox(height: 10),
            CoachPronunciationCard(pronunciation: entry.pronunciation!),
          ] else if (!entry.pending &&
              entry.error == null &&
              entry.text == null) ...[
            const SizedBox(height: 6),
            Text(
              // Why there is no score, where it can be known. A turn that ran
              // past the limit is the one case the client can explain; saying
              // "too long" about a two-second answer is worse than saying
              // nothing.
              entry.seconds >= _maxTurnSeconds
                  ? 'No pronunciation score — that turn ran past the '
                      '$_maxTurnSeconds-second limit.'
                  : 'No pronunciation score for this turn — scoring was '
                      'unavailable.',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 10.5,
                height: 1.35,
                color: colors.textTertiary,
              ),
            ),
          ],
          if (entry.corrections.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CorrectionsCard(corrections: entry.corrections),
          ],
        ],
      ),
    );
  }
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
                      Icon(Icons.check_rounded,
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

class _BubbleAvatar extends StatelessWidget {
  const _BubbleAvatar({required this.persona, required this.accent});

  final String persona;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.bottomCenter,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        // Always idle: a column of talking heads would be a room full of
        // people shouting.
        child: CoachAvatar(persona: persona, accent: accent, size: 30),
      );
}

/// The coach thinking, drawn where its answer will appear rather than as a
/// spinner over the composer.
class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble({required this.persona, required this.accent});

  final String persona;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          _BubbleAvatar(persona: persona, accent: accent),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: SizedBox(
              width: 30,
              height: 8,
              child: _TypingDots(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});

  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var dot = 0; dot < 3; dot++)
            Opacity(
              opacity: 0.35 +
                  0.65 *
                      (0.5 +
                          0.5 *
                              math.sin(
                                (_controller.value * 2 * math.pi) -
                                    dot * 0.9,
                              )),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// How you answer, and what is happening while you do.
///
/// Two modes rather than a microphone button next to a text field: a live
/// conversation and a written one are different things to be in, and the
/// screen should say which one you are in.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.mode,
    required this.liveOpen,
    required this.hearing,
    required this.working,
    required this.speaking,
    required this.sending,
    required this.micLevel,
    required this.controller,
    required this.onMode,
    required this.onDone,
    required this.onSend,
  });

  final CoachMode mode;
  final bool liveOpen;
  final bool hearing;
  final bool working;
  final bool speaking;
  final bool sending;
  final double micLevel;
  final TextEditingController controller;
  final ValueChanged<CoachMode> onMode;
  final VoidCallback onDone;
  final VoidCallback onSend;

  String get _status {
    if (!liveOpen) return 'Opening the microphone…';
    if (speaking) return 'Speaking';
    if (working) return 'Working on it…';
    if (hearing) return 'Hearing you…';
    return 'Listening — just start talking';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        8 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _ModeSwitch(mode: mode, onMode: onMode),
              const SizedBox(width: 12),
              if (mode == CoachMode.voice)
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _status,
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // The meter is the proof the microphone is live. A
                            // flat one here is a dead input, visible before a
                            // whole answer has been spoken into it.
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: liveOpen ? micLevel.clamp(0.0, 1.0) : 0,
                                minHeight: 4,
                                backgroundColor: colors.surfaceAlt,
                                valueColor:
                                    AlwaysStoppedAnimation(colors.success),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // The silence detector works on loudness, so a noisy
                      // room needs a way to say "I have finished".
                      TextButton(
                        onPressed: hearing ? onDone : null,
                        style: TextButton.styleFrom(
                          foregroundColor: colors.textSecondary,
                          disabledForegroundColor: colors.textTertiary
                              .withValues(alpha: 0.5),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text(
                          "I'm done",
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          enabled: !sending,
                          maxLength: 1000,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => onSend(),
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 14,
                            color: colors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            isDense: true,
                            hintText: 'Type your answer…',
                            hintStyle: TextStyle(
                              fontFamily: 'SF Pro',
                              fontSize: 14,
                              color: colors.textTertiary,
                            ),
                            filled: true,
                            fillColor: colors.surfaceAlt,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: sending ? null : onSend,
                        icon: Icon(Icons.send_rounded, color: colors.brand),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onMode});

  final CoachMode mode;
  final ValueChanged<CoachMode> onMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in CoachMode.values)
            GestureDetector(
              onTap: () => onMode(option),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: option == mode ? colors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      option == CoachMode.voice
                          ? Icons.mic_rounded
                          : Icons.keyboard_alt_outlined,
                      size: 14,
                      color: option == mode
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      option == CoachMode.voice ? 'Voice' : 'Text',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: option == mode
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
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
                Icon(Icons.auto_awesome_rounded,
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
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.bottomCenter,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: CoachAvatar(
                persona: persona.slug,
                accent: accent,
                size: 48,
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
              Icon(Icons.check_circle_rounded, size: 20, color: accent),
          ],
        ),
      ),
    );
  }
}
