import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/podcast_playback_service.dart';
import '../services/subtitle_service.dart';
import 'podcast_player_screen.dart'
    show
        CueText,
        WaveformSeekBar,
        playerAccent,
        playerBgBottom,
        playerBgTop,
        playerSpeakerColors;
import 'podcasts_list_screen.dart' show formatClock, formatRemainingLabel;
import 'speaking_answer_screen.dart';
import 'tutor_profile_screen.dart';

/// A tutor's real Speaking sample answer, presented as a podcast episode:
/// dark player surface, waveform scrubber, ±15s seek, speed control and a
/// karaoke transcript that follows playback word by word.
///
/// Part 1/2/3 are kept separate (some tutors may only have 2 of the 3 parts)
/// and switch like tracks — each part has its own audio and SRT/VTT file.
///
/// Listening is only half of it: every part carries the question the tutor was
/// answering, and "Try yourself" hands the same question to the student and has
/// their answer marked (see [SpeakingAnswerScreen]). The tutor's take is
/// deliberately not replayed on that screen — answering a question straight
/// after hearing a band-8 answer to it measures recall, not speaking.
class SpeakingSampleTutorScreen extends StatefulWidget {
  const SpeakingSampleTutorScreen({super.key, required this.tutor, this.tutorId});

  final Map<String, dynamic> tutor;

  /// The tutor's catalogue id, when the caller knows it — the sample payload
  /// itself does not carry one. Null for an admin-authored sample, which has
  /// no tutor account behind it at all, and the booking offer stays off.
  final int? tutorId;

  @override
  State<SpeakingSampleTutorScreen> createState() => _SpeakingSampleTutorScreenState();
}

class _SpeakingSampleTutorScreenState extends State<SpeakingSampleTutorScreen> {
  final _player = PodcastPlaybackService.instance;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _bufferedSub;
  StreamSubscription<PlayerState>? _stateSub;

  late final List<Map<String, dynamic>> _parts =
      ((widget.tutor['parts'] as List?) ?? const []).cast<Map<String, dynamic>>();

  int _selectedPart = 0;
  bool _loadingAudio = false;
  bool _loadingSubtitles = false;

  // Transport
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  Duration _buffered = Duration.zero;
  bool _playing = false;
  bool _isScrubbing = false;
  double _speed = 1.0;

  // Transcript
  List<SubtitleCue> _cues = [];
  List<GlobalKey> _cueKeys = [];
  List<String> _speakers = [];
  int _activeCue = -1;
  int _activeWord = -1;

  /// The transcript is the point of a speaking sample, so it owns the main
  /// panel by default; the tutor's photo/band sits behind the toggle.
  bool _showTranscript = true;

  /// The question the tutor is answering stays on screen above the
  /// transcript — an answer read without its prompt is not much use. Part 1
  /// questions are long numbered lists, so it starts clamped to two lines and
  /// expands on tap.
  bool _questionExpanded = false;

  /// Auto-scroll follows playback until the student scrolls the transcript
  /// themselves; a "Jump to current" pill hands control back.
  bool _autoScroll = true;
  final ScrollController _transcriptScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _positionSub = _player.positionStream.listen(_onPosition);
    _durationSub = _player.durationStream.listen((duration) {
      if (!mounted || duration == null) return;
      setState(() => _totalDuration = duration);
    });
    _bufferedSub = _player.player.bufferedPositionStream.listen((buffered) {
      if (!mounted) return;
      setState(() => _buffered = buffered);
    });
    _stateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
    });
    if (_parts.isNotEmpty) _loadPart(0);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferedSub?.cancel();
    _stateSub?.cancel();
    _transcriptScroll.dispose();
    _player.stop();
    super.dispose();
  }

  // ─── Loading ────────────────────────────────────────────────────────────

  Future<void> _loadPart(int index) async {
    final part = _parts[index];
    setState(() {
      _selectedPart = index;
      _cues = [];
      _cueKeys = [];
      _speakers = [];
      _activeCue = -1;
      _activeWord = -1;
      _autoScroll = true;
      _questionExpanded = false;
      _position = Duration.zero;
      _totalDuration = Duration.zero;
      _buffered = Duration.zero;
      _loadingAudio = true;
      _loadingSubtitles = true;
    });
    if (_transcriptScroll.hasClients) _transcriptScroll.jumpTo(0);

    final audioUrl = part['audio_url'] as String?;
    if (audioUrl != null && audioUrl.isNotEmpty) {
      final gen = _player.beginLoad();
      final duration = await _player.loadAdHoc(
        'speaking-tutor-${widget.tutor['id']}-part${part['part']}',
        Uri.parse(audioUrl),
        title: part['title']?.toString() ?? '',
        generation: gen,
      );
      // Bail if another part — or another screen entirely, e.g. Mock Test
      // Listening — won the race while this one was fetching, so we don't
      // resurrect this part's audio out from under whatever the user moved on
      // to. A stale *part* also means a newer _loadPart owns the state below.
      if (!mounted || _selectedPart != index) return;
      final stillOurs = _player.isCurrent(gen);
      setState(() {
        _loadingAudio = false;
        if (stillOurs) _totalDuration = duration ?? Duration.zero;
      });
      if (stillOurs) {
        await _player.setSpeed(_speed);
        _player.play();
      }
    } else {
      setState(() => _loadingAudio = false);
    }

    final cues = await SubtitleService.fetchCues(part['subtitle_url'] as String?);
    if (!mounted || _selectedPart != index) return;
    setState(() {
      _cues = cues;
      _cueKeys = List.generate(cues.length, (_) => GlobalKey());
      _speakers = SubtitleService.speakers(cues);
      _loadingSubtitles = false;
    });
    _onPosition(_player.position);
  }

  // ─── Transcript sync ────────────────────────────────────────────────────

  /// Recomputes the highlighted line and word at [pos] and, while the
  /// transcript is following, keeps the spoken line on screen.
  void _onPosition(Duration pos) {
    if (!mounted || _isScrubbing) return;
    final index = _cues.isEmpty ? -1 : SubtitleService.nearestCueIndex(_cues, pos);
    final word = index >= 0 ? _cues[index].wordIndexAt(pos) : -1;
    if (pos == _position && index == _activeCue && word == _activeWord) return;
    final lineChanged = index != _activeCue;
    setState(() {
      _position = pos;
      _activeCue = index;
      _activeWord = word;
    });
    if (lineChanged && _showTranscript && _autoScroll) _scrollToActiveCue();
  }

  void _scrollToActiveCue() {
    if (_activeCue < 0 || _activeCue >= _cueKeys.length) return;
    final ctx = _cueKeys[_activeCue].currentContext;
    if (ctx == null) {
      // Item is off-screen, so it has no context to scroll to; jump to a
      // proportional estimate to bring it into the viewport, then refine with
      // ensureVisible once it has been laid out.
      if (_transcriptScroll.hasClients && _cues.isNotEmpty) {
        final max = _transcriptScroll.position.maxScrollExtent;
        _transcriptScroll.jumpTo((_activeCue / _cues.length * max).clamp(0, max));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _activeCue < 0 || _activeCue >= _cueKeys.length) return;
          final refined = _cueKeys[_activeCue].currentContext;
          if (refined != null) {
            Scrollable.ensureVisible(refined, duration: Duration.zero, alignment: 0.35);
          }
        });
      }
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      duration: _isScrubbing ? Duration.zero : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.35,
    );
  }

  // ─── Transport ──────────────────────────────────────────────────────────

  void _togglePlay() => _player.togglePlay();

  void _seekTo(Duration position) {
    final clamped = position < Duration.zero
        ? Duration.zero
        : (_totalDuration > Duration.zero && position > _totalDuration
            ? _totalDuration
            : position);
    _player.seek(clamped);
    _onPosition(clamped);
    if (_showTranscript && _autoScroll) _scrollToActiveCue();
  }

  void _seekBy(Duration delta) => _seekTo(_position + delta);

  void _toggleTranscript() {
    setState(() {
      _showTranscript = !_showTranscript;
      if (_showTranscript) _autoScroll = true;
    });
    if (_showTranscript) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToActiveCue();
      });
    }
  }

  void _showSpeedSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2E3050),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Playback speed',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Slow it down to catch every linking word.',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final speed in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(sheetContext);
                        setState(() => _speed = speed);
                        _player.setSpeed(speed);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: _speed == speed
                              ? playerAccent
                              : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _speedLabel(speed),
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            color: _speed == speed ? playerBgTop : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _speedLabel(double speed) =>
      '${speed == speed.roundToDouble() ? speed.toInt() : speed}x';

  Color _colorForSpeaker(String speaker) {
    final index = _speakers.indexOf(speaker);
    return playerSpeakerColors[(index < 0 ? 0 : index) % playerSpeakerColors.length];
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: playerBgTop,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [playerBgTop, playerBgBottom],
            ),
          ),
          child: SafeArea(
            child: _parts.isEmpty
                ? Column(
                    children: [
                      _buildAppBar(),
                      Expanded(
                        child: Center(
                          child: Text(
                            'No sample parts yet',
                            style: TextStyle(
                              fontFamily: 'SF Pro',
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _buildAppBar(),
                      _buildPartTabs(),
                      _buildQuestionCard(),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: _showTranscript
                              ? _buildTranscriptPanel()
                              : _buildTutorPanel(),
                        ),
                      ),
                      _buildSeekBar(),
                      const SizedBox(height: 4),
                      _buildControls(),
                      const SizedBox(height: 6),
                      _buildUtilityRow(),
                      const SizedBox(height: 12),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final band = widget.tutor['band_score']?.toString();
    final title = widget.tutor['topic_title']?.toString() ??
        widget.tutor['tutor_name']?.toString() ??
        '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Symbols.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _showTranscript ? 'LIVE TRANSCRIPT' : 'THE TUTOR',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'SF Pro',
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 48,
            child: band == null
                ? null
                : Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: playerAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        band,
                        style: const TextStyle(
                          fontFamily: 'SF Pro',
                          color: playerBgTop,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Part 1/2/3 switch like tracks in a queue.
  Widget _buildPartTabs() {
    if (_parts.length < 2) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Row(
        children: [
          for (var i = 0; i < _parts.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: i == _selectedPart ? null : () => _loadPart(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == _selectedPart
                        ? playerAccent
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    'Part ${_parts[i]['part']}',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: i == _selectedPart
                          ? playerBgTop
                          : Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Question card ──────────────────────────────────────────────────────

  /// The prompt being answered, pinned above the transcript. Collapsed it
  /// costs two lines; expanded it is capped at a third of the screen and
  /// scrolls internally, so a ten-question Part 1 list can't push the
  /// transcript off screen.
  Widget _buildQuestionCard() {
    final part = _parts[_selectedPart];
    final question = part['question_text']?.toString().trim() ?? '';
    if (question.isEmpty) return const SizedBox.shrink();

    final body = Text(
      question,
      maxLines: _questionExpanded ? null : 2,
      overflow: _questionExpanded ? null : TextOverflow.ellipsis,
      style: const TextStyle(
        fontFamily: 'SF Pro',
        color: Colors.white,
        fontSize: 13.5,
        height: 1.45,
        fontWeight: FontWeight.w600,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: GestureDetector(
        onTap: () => setState(() => _questionExpanded = !_questionExpanded),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'PART ${part['part']} QUESTION',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _questionExpanded
                          ? Symbols.keyboard_arrow_up_rounded
                          : Symbols.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_questionExpanded)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.32,
                    ),
                    child: SingleChildScrollView(child: body),
                  )
                else
                  body,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Tutor panel ────────────────────────────────────────────────────────

  Widget _buildTutorPanel() {
    final tutor = widget.tutor;
    final imageUrl = tutor['tutor_image_url'] as String?;
    final name = tutor['tutor_name']?.toString() ?? '';
    final band = tutor['band_score']?.toString();

    return SingleChildScrollView(
      key: const ValueKey('tutor'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              width: 168,
              height: 168,
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const _AvatarFallback(),
                    )
                  : const _AvatarFallback(),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'SF Pro',
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (band != null) ...[
            const SizedBox(height: 6),
            Text(
              'IELTS Speaking $band',
              style: TextStyle(
                fontFamily: 'SF Pro',
                color: playerAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          // A student listening to someone for ten minutes has already formed
          // an opinion about how they teach. The offer belongs here, beside
          // the face and the band, rather than back in the tutors directory.
          if (widget.tutorId != null) ...[
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                _player.pause();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TutorProfileScreen(tutorId: widget.tutorId!),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: BoxDecoration(
                  color: playerAccent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Symbols.event_available_rounded, size: 16, color: playerBgTop),
                    const SizedBox(width: 7),
                    Text(
                      name.isEmpty ? 'Book a lesson' : 'Book a lesson with $name',
                      style: const TextStyle(
                        fontFamily: 'SF Pro',
                        color: playerBgTop,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Transcript panel ───────────────────────────────────────────────────

  Widget _buildTranscriptPanel() {
    if (_loadingSubtitles) {
      return const Center(
        key: ValueKey('transcript-loading'),
        child: CircularProgressIndicator(color: playerAccent),
      );
    }
    if (_cues.isEmpty) {
      return Center(
        key: const ValueKey('transcript-empty'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No transcript for this part yet.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'SF Pro',
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Stack(
      key: const ValueKey('transcript'),
      children: [
        NotificationListener<UserScrollNotification>(
          // A deliberate drag means the student is browsing the answer — stop
          // yanking the view back to the spoken line until they ask for it.
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle && _autoScroll) {
              setState(() => _autoScroll = false);
            }
            return false;
          },
          child: ListView.builder(
            controller: _transcriptScroll,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            itemCount: _cues.length,
            itemBuilder: (context, i) {
              final cue = _cues[i];
              final isActive = i == _activeCue;
              final isSpoken = i < _activeCue;
              final showSpeaker =
                  cue.speaker != null && (i == 0 || _cues[i - 1].speaker != cue.speaker);

              return Padding(
                key: _cueKeys[i],
                padding: EdgeInsets.only(top: showSpeaker && i > 0 ? 16 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showSpeaker)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, left: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _colorForSpeaker(cue.speaker!),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              cue.speaker!,
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                color: _colorForSpeaker(cue.speaker!),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatClock(cue.start),
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      // Tapping a line jumps playback to it — and takes the
                      // transcript out of browse mode, since the student just
                      // told us where they want to be.
                      onTap: () {
                        setState(() => _autoScroll = true);
                        _seekTo(cue.start);
                        if (!_player.isPlaying) _player.play();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CueText(
                          cue: cue,
                          activeWord: isActive ? _activeWord : -1,
                          fontSize: isActive ? 18 : 16,
                          spokenColor: isActive
                              ? Colors.white
                              : Colors.white.withValues(alpha: isSpoken ? 0.55 : 0.38),
                          currentColor: isActive
                              ? playerAccent
                              : Colors.white.withValues(alpha: 0.55),
                          upcomingColor: isActive
                              ? Colors.white.withValues(alpha: 0.45)
                              : Colors.white.withValues(alpha: isSpoken ? 0.55 : 0.38),
                          bold: isActive,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (!_autoScroll)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  setState(() => _autoScroll = true);
                  _scrollToActiveCue();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: playerAccent,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Symbols.vertical_align_center_rounded, size: 15, color: playerBgTop),
                      SizedBox(width: 6),
                      Text(
                        'Jump to current',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          color: playerBgTop,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Transport UI ───────────────────────────────────────────────────────

  Widget _buildSeekBar() {
    final part = _parts[_selectedPart];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          WaveformSeekBar(
            seed: 'speaking-${widget.tutor['id']}-${part['part']}',
            position: _position,
            duration: _totalDuration,
            buffered: _buffered,
            onScrubStart: () => setState(() => _isScrubbing = true),
            onScrubUpdate: (pos) {
              setState(() => _position = pos);
              final index = _cues.isEmpty ? -1 : SubtitleService.nearestCueIndex(_cues, pos);
              if (index == _activeCue) return;
              setState(() {
                _activeCue = index;
                _activeWord = index >= 0 ? _cues[index].wordIndexAt(pos) : -1;
              });
              if (_showTranscript && _autoScroll) _scrollToActiveCue();
            },
            onScrubEnd: (pos) {
              setState(() => _isScrubbing = false);
              _seekTo(pos);
            },
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatClock(_position),
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (_totalDuration > Duration.zero)
                Text(
                  formatRemainingLabel(_totalDuration - _position),
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => _seekBy(const Duration(seconds: -15)),
          tooltip: 'Back 15 seconds',
          icon: SvgPicture.asset('assets/images/branding/video-back.svg', width: 30, height: 30),
        ),
        const SizedBox(width: 14),
        GestureDetector(
          onTap: _loadingAudio ? null : _togglePlay,
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: _loadingAudio
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: playerBgTop),
                  )
                : Icon(
                    _playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                    color: playerBgTop,
                    size: 36,
                  ),
          ),
        ),
        const SizedBox(width: 14),
        IconButton(
          onPressed: () => _seekBy(const Duration(seconds: 15)),
          tooltip: 'Forward 15 seconds',
          icon: SvgPicture.asset('assets/images/branding/video-front.svg', width: 30, height: 30),
        ),
      ],
    );
  }

  /// Hands the current part's question to the student.
  ///
  /// The player keeps running otherwise, and coming back to a tutor's answer
  /// mid-sentence after recording your own is the wrong thing to walk into —
  /// so playback pauses on the way out.
  void _openAnswerScreen() {
    final part = _parts[_selectedPart];
    if ((part['id'] as num?) == null) return;
    _player.pause();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SpeakingAnswerScreen(
          part: part,
          tutorName: widget.tutor['tutor_name']?.toString() ?? 'this tutor',
        ),
      ),
    );
  }

  Widget _buildUtilityRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _utilityButton(
            onTap: _toggleTranscript,
            active: _showTranscript,
            label: _showTranscript ? 'Transcript' : 'Tutor',
            child: Icon(
              _showTranscript
                  ? Symbols.closed_caption_rounded
                  : Symbols.person_rounded,
              size: 17,
              color: _showTranscript ? playerBgTop : Colors.white.withValues(alpha: 0.75),
            ),
          ),
          // The point of the screen, once the answer has been studied: the
          // same question, recorded by the student and marked. Prominent
          // rather than tucked into an overflow — a reference recording that
          // never turns into practice is just a podcast.
          _utilityButton(
            onTap: _openAnswerScreen,
            active: true,
            label: 'Try yourself',
            child: const Icon(Symbols.mic_rounded, size: 17, color: playerBgTop),
          ),
          _utilityButton(
            onTap: _showSpeedSheet,
            active: _speed != 1.0,
            label: 'Speed',
            child: Text(
              _speedLabel(_speed),
              style: TextStyle(
                fontFamily: 'SF Pro',
                color: _speed != 1.0 ? playerBgTop : Colors.white.withValues(alpha: 0.75),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _utilityButton({
    required VoidCallback? onTap,
    required bool active,
    required Widget child,
    required String label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? playerAccent : Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: child,
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'SF Pro',
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.1),
      alignment: Alignment.center,
      child: Icon(Symbols.person_rounded, color: Colors.white.withValues(alpha: 0.5), size: 56),
    );
  }
}
