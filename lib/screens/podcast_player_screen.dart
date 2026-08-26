import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';

import '../services/api_service.dart';
import '../services/facebook_events_service.dart';
import '../services/podcast_playback_service.dart';
import '../services/podcast_transcript_service.dart';
import '../services/subtitle_service.dart';
import '../widgets/podcast_artwork.dart';
import 'podcasts_list_screen.dart' show formatClock, formatRemainingLabel;

/// Player surface colors. The player is deliberately dark in both themes —
/// like every other podcast app, the artwork is the subject and a dark room
/// makes the follow-along transcript easier to read.
const playerBgTop = Color(0xFF272942);
const playerBgBottom = Color(0xFF16172A);
const playerAccent = Color(0xFFF5C542);

/// Dot colors for labelled speakers, in the order they first speak.
const playerSpeakerColors = [
  Color(0xFFF5C542),
  Color(0xFF6FC3F5),
  Color(0xFF9B8CF5),
  Color(0xFF6FE0A8),
  Color(0xFFF58CA8),
];

class PodcastPlayerScreen extends StatefulWidget {
  final int podcastId;
  final String? initialTitle;
  final String? initialAudioUrl;
  final String? initialSubtitleUrl;
  final String? initialImageUrl;

  const PodcastPlayerScreen({
    super.key,
    required this.podcastId,
    this.initialTitle,
    this.initialAudioUrl,
    this.initialSubtitleUrl,
    this.initialImageUrl,
  });

  @override
  State<PodcastPlayerScreen> createState() => _PodcastPlayerScreenState();
}

class _PodcastPlayerScreenState extends State<PodcastPlayerScreen>
    with SingleTickerProviderStateMixin {
  final _service = PodcastPlaybackService.instance;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<PlayerState>? _sleepSub;

  bool _loading = true;
  String _title = '';
  String? _imageUrl;

  Duration _totalDuration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _buffered = Duration.zero;
  bool _playing = false;
  bool _muted = false;
  double _speed = 1.0;
  Timer? _sleepTimer;
  String _sleepLabel = 'Off';

  // Transcript
  int? _subtitleLoadedFor;
  bool _loadingSubtitles = false;
  List<SubtitleCue> _cues = [];
  List<String> _speakers = [];
  int _activeCue = -1;
  int _activeWord = -1;
  bool _showTranscript = false;
  bool _isScrubbing = false;

  /// Auto-scroll follows playback until the listener scrolls the transcript
  /// themselves; a "Jump to current" pill hands control back.
  bool _autoScroll = true;
  final ScrollController _transcriptScroll = ScrollController();
  List<GlobalKey> _cueKeys = [];

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.initialImageUrl;
    _title = widget.initialTitle ?? '';
    _bindStreams();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPodcast());
  }

  void _bindStreams() {
    _service.currentTrack.addListener(_onTrackChanged);
    _positionSub = _service.positionStream.listen((pos) {
      if (!mounted || _isScrubbing) return;
      setState(() => _position = pos);
      _updateActiveCue(pos);
    });
    _durationSub = _service.durationStream.listen((d) {
      if (!mounted || d == null) return;
      setState(() => _totalDuration = d);
    });
    _stateSub = _service.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _playing = state.playing;
        _buffered = _service.player.bufferedPosition;
      });
      if (state.playing) {
        _pulse.repeat(reverse: true);
      } else {
        _pulse.stop();
      }
    });
  }

  void _onTrackChanged() {
    final track = _service.currentTrack.value;
    if (!mounted || track == null) return;
    setState(() {
      _title = track.title;
      _imageUrl = track.imageUrl ?? _imageUrl;
      _cues = [];
      _cueKeys = [];
      _speakers = [];
      _activeCue = -1;
      _activeWord = -1;
      _subtitleLoadedFor = null;
    });
    _loadSubtitles(track.id, track.subtitleUrl, audioUrl: track.audioUrl);
  }

  Future<void> _loadPodcast() async {
    try {
      final existing = _service.currentTrack.value;
      if (existing != null && existing.id == widget.podcastId) {
        _title = existing.title;
        _imageUrl = existing.imageUrl ?? _imageUrl;
        _totalDuration = _service.duration;
        _position = _service.position;
        _playing = _service.isPlaying;
        _speed = _service.player.speed;
        _muted = _service.player.volume == 0.0;
        if (_playing) _pulse.repeat(reverse: true);
        setState(() => _loading = false);
        String? subtitleUrl =
            existing.subtitleUrl ?? widget.initialSubtitleUrl;
        if ((subtitleUrl == null || subtitleUrl.isEmpty) &&
            existing.audioUrl.isNotEmpty) {
          subtitleUrl = PodcastTranscriptService.deriveSubtitleUrl(existing.audioUrl);
        }
        _loadSubtitles(existing.id, subtitleUrl);
        return;
      }

      String? audioUrl = widget.initialAudioUrl;
      String? imageUrl = widget.initialImageUrl;
      String? subtitleUrl = widget.initialSubtitleUrl;
      _title = widget.initialTitle ?? '';

      if (audioUrl == null || audioUrl.isEmpty) {
        try {
          final data =
              await ApiService.get('/content/podcasts/${widget.podcastId}/');
          if (!mounted) return;
          final podcast = data['data'] as Map<String, dynamic>? ?? data;
          _title = podcast['title'] as String? ?? _title;
          audioUrl = podcast['audio_url'] as String?;
          imageUrl ??= podcast['image_url'] as String? ??
              podcast['cover_url'] as String?;
          subtitleUrl ??= podcast['subtitle_url'] as String?;
        } catch (_) {
          // API unavailable — use whatever initial data we have
        }
      }

      // Auto-derive subtitle URL from the audio filename when not provided
      if ((subtitleUrl == null || subtitleUrl.isEmpty) &&
          audioUrl != null && audioUrl.isNotEmpty) {
        subtitleUrl = PodcastTranscriptService.deriveSubtitleUrl(audioUrl);
      }

      debugPrint('[Podcast] audioUrl: $audioUrl');
      debugPrint('[Podcast] subtitleUrl: $subtitleUrl');

      if (audioUrl != null && audioUrl.isNotEmpty) {
        // load() picks up the stored resume point on its own.
        await _service.load(PodcastTrack(
          id: widget.podcastId,
          title: _title,
          audioUrl: audioUrl,
          imageUrl: imageUrl,
          subtitleUrl: subtitleUrl,
        ));
        _service.play();
      }

      if (!mounted) return;
      setState(() {
        _imageUrl = imageUrl ?? _imageUrl;
        _loading = false;
      });
      _loadSubtitles(widget.podcastId, subtitleUrl);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _loadSubtitles(widget.podcastId, widget.initialSubtitleUrl);
    }
  }

  /// Loads the cues for the podcast with [id]. No-op if already loaded for
  /// this podcast. Silently leaves the transcript empty on any failure.
  Future<void> _loadSubtitles(int id, String? subtitleUrl,
      {String? audioUrl}) async {
    if (_subtitleLoadedFor == id) return;
    _subtitleLoadedFor = id;
    if (mounted) setState(() => _loadingSubtitles = true);

    final cues = await PodcastTranscriptService.load(
      id,
      subtitleUrl: subtitleUrl,
      audioUrl: audioUrl,
    );
    if (!mounted || _subtitleLoadedFor != id) return;
    setState(() {
      _cues = cues;
      _cueKeys = List.generate(cues.length, (_) => GlobalKey());
      _speakers = SubtitleService.speakers(cues);
      _activeCue = -1;
      _activeWord = -1;
      _loadingSubtitles = false;
    });
    _updateActiveCue(_position);
  }

  /// Recomputes the highlighted line and word at [pos] and, when the
  /// transcript is open and following, keeps the line on screen.
  void _updateActiveCue(Duration pos) {
    if (_cues.isEmpty) return;
    final index = SubtitleService.nearestCueIndex(_cues, pos);
    final word =
        index >= 0 ? _cues[index].wordIndexAt(pos) : -1;
    if (index == _activeCue && word == _activeWord) return;
    final lineChanged = index != _activeCue;
    setState(() {
      _activeCue = index;
      _activeWord = word;
    });
    if (lineChanged && _showTranscript && _autoScroll) _scrollToActiveCue();
  }

  void _scrollToActiveCue() {
    if (_activeCue < 0 || _activeCue >= _cueKeys.length) return;
    final ctx = _cueKeys[_activeCue].currentContext;
    if (ctx == null) {
      // Item is off-screen; jump to a proportional estimate to bring it into
      // the viewport, then refine with ensureVisible on the next frame.
      if (_transcriptScroll.hasClients && _cues.isNotEmpty) {
        final max = _transcriptScroll.position.maxScrollExtent;
        _transcriptScroll.jumpTo((_activeCue / _cues.length * max).clamp(0, max));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final refined = _cueKeys[_activeCue].currentContext;
          if (refined != null) {
            Scrollable.ensureVisible(refined,
                duration: Duration.zero, alignment: 0.35);
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

  void _toggleTranscript() {
    setState(() {
      _showTranscript = !_showTranscript;
      if (_showTranscript) _autoScroll = true;
    });
    FacebookEventsService.logEvent('podcast_transcript_toggled', parameters: {
      'podcast_id': widget.podcastId,
      'visible': _showTranscript,
    });
    if (_showTranscript) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToActiveCue());
    }
  }

  @override
  void dispose() {
    // The screen can close mid-episode while audio keeps going in the mini
    // player; write the resume point now rather than waiting for the next
    // periodic save.
    _service.saveProgressNow();
    _pulse.dispose();
    _transcriptScroll.dispose();
    _service.currentTrack.removeListener(_onTrackChanged);
    _sleepTimer?.cancel();
    _sleepSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  // ─── Controls ───────────────────────────────────────────────────────────

  void _togglePlay() {
    if (_playing) {
      debugPrint('[Podcast] pause id=${widget.podcastId}');
      FacebookEventsService.logEvent('podcast_pause', parameters: {'podcast_id': widget.podcastId});
      _service.pause();
    } else {
      debugPrint('[Podcast] play id=${widget.podcastId}');
      FacebookEventsService.logEvent('podcast_play', parameters: {'podcast_id': widget.podcastId});
      _service.play();
    }
  }

  void _previousTrack() {
    debugPrint('[Podcast] previous_track id=${widget.podcastId}');
    FacebookEventsService.logEvent('podcast_previous_track', parameters: {'podcast_id': widget.podcastId});
    _service.previous();
  }

  void _nextTrack() {
    debugPrint('[Podcast] next_track id=${widget.podcastId}');
    FacebookEventsService.logEvent('podcast_next_track', parameters: {'podcast_id': widget.podcastId});
    _service.next();
  }

  void _seekForward() {
    debugPrint('[Podcast] seek_forward id=${widget.podcastId}');
    FacebookEventsService.logEvent('podcast_seek_forward', parameters: {'podcast_id': widget.podcastId});
    final newPos = _position + const Duration(seconds: 15);
    _seekTo(newPos > _totalDuration ? _totalDuration : newPos);
  }

  void _seekBackward() {
    debugPrint('[Podcast] seek_backward id=${widget.podcastId}');
    FacebookEventsService.logEvent('podcast_seek_backward', parameters: {'podcast_id': widget.podcastId});
    final newPos = _position - const Duration(seconds: 15);
    _seekTo(newPos < Duration.zero ? Duration.zero : newPos);
  }

  void _seekTo(Duration position) {
    _service.seek(position);
    setState(() => _position = position);
    _updateActiveCue(position);
    if (_showTranscript && _autoScroll) _scrollToActiveCue();
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      debugPrint('[Podcast] mute=$_muted id=${widget.podcastId}');
      FacebookEventsService.logEvent('podcast_mute_toggled', parameters: {
        'podcast_id': widget.podcastId,
        'muted': _muted,
      });
      _service.setVolume(_muted ? 0.0 : 1.0);
    });
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
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final speed in const [0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(sheetContext);
                        setState(() => _speed = speed);
                        _service.setSpeed(speed);
                        FacebookEventsService.logEvent(
                          'podcast_speed_changed',
                          parameters: {
                            'podcast_id': widget.podcastId,
                            'speed': speed,
                          },
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: _speed == speed
                              ? playerAccent
                              : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${speed == speed.roundToDouble() ? speed.toInt() : speed}x',
                          style: TextStyle(
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

  void _showSleepTimer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2E3050),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SleepTimerSheet(
        currentLabel: _sleepLabel,
        onSelected: (label, duration) {
          Navigator.pop(context);
          _sleepTimer?.cancel();
          _sleepSub?.cancel();
          if (duration == null) {
            debugPrint('[Podcast] sleep_timer=Off id=${widget.podcastId}');
            FacebookEventsService.logEvent('podcast_sleep_timer_set', parameters: {
              'podcast_id': widget.podcastId,
              'timer': 'Off',
            });
            setState(() => _sleepLabel = 'Off');
            return;
          }
          debugPrint('[Podcast] sleep_timer="$label" id=${widget.podcastId}');
          FacebookEventsService.logEvent('podcast_sleep_timer_set', parameters: {
            'podcast_id': widget.podcastId,
            'timer': label,
          });
          setState(() => _sleepLabel = label);
          if (label == 'At the end of the release') {
            _sleepSub = _service.playerStateStream.listen((state) {
              if (state.processingState == ProcessingState.completed) {
                _sleepSub?.cancel();
                _service.pause();
                if (mounted) setState(() => _sleepLabel = 'Off');
              }
            });
          } else {
            _sleepTimer = Timer(duration, () {
              _service.pause();
              if (mounted) setState(() => _sleepLabel = 'Off');
            });
          }
        },
      ),
    );
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
            child: Column(
              children: [
                _buildAppBar(),
                if (_loading)
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: playerAccent),
                    ),
                  )
                else ...[
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _showTranscript
                          ? _buildTranscriptPanel()
                          : _buildCoverPanel(),
                    ),
                  ),
                  _buildSeekBar(),
                  const SizedBox(height: 6),
                  _buildControls(),
                  const SizedBox(height: 10),
                  _buildUtilityRow(),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white, size: 30),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _showTranscript ? 'LIVE TRANSCRIPT' : 'NOW PLAYING',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loading ? null : _toggleMute,
            icon: SvgPicture.asset(
              _muted
                  ? 'assets/images/buttons/volume-off.svg'
                  : 'assets/images/buttons/volume-on.svg',
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(
                _loading ? Colors.white.withValues(alpha: 0.3) : Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Cover panel ────────────────────────────────────────────────────────

  Widget _buildCoverPanel() {
    return SingleChildScrollView(
      key: const ValueKey('cover'),
      physics: const ClampingScrollPhysics(),
      child: Column(
        children: [
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final glow = 0.18 + 0.22 * _pulse.value;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: podcastGradient(_title).first
                          .withValues(alpha: _playing ? glow : 0.12),
                      blurRadius: 44,
                      spreadRadius: _playing ? 6 : 0,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: PodcastArtwork(
              seed: _title,
              imageUrl: _imageUrl,
              size: 216,
              borderRadius: 28,
            ),
          ),
          const SizedBox(height: 26),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
          if (_speakers.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildSpeakerLegend(),
          ],
          const SizedBox(height: 20),
          _buildLiveCaption(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSpeakerLegend() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        for (var i = 0; i < _speakers.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: playerSpeakerColors[i % playerSpeakerColors.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _speakers[i],
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// The follow-along caption card: the line being spoken, word-highlighted in
  /// real time, with the neighbouring lines dimmed for context.
  Widget _buildLiveCaption() {
    if (_loadingSubtitles) {
      return _captionShell(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: playerAccent),
            ),
            const SizedBox(width: 10),
            Text(
              'Loading transcript…',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    if (_cues.isEmpty) return const SizedBox.shrink();

    final active = _activeCue >= 0 ? _cues[_activeCue] : null;
    final previous = _activeCue > 0 ? _cues[_activeCue - 1] : null;
    final next =
        _activeCue >= 0 && _activeCue + 1 < _cues.length ? _cues[_activeCue + 1] : null;

    return _captionShell(
      onTap: _toggleTranscript,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LiveDot(active: _playing),
              const SizedBox(width: 7),
              Text(
                'FOLLOWING ALONG',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                'Full transcript',
                style: TextStyle(
                  color: playerAccent.withValues(alpha: 0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: playerAccent.withValues(alpha: 0.9)),
            ],
          ),
          const SizedBox(height: 10),
          if (previous != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                previous.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.28),
                  fontSize: 13,
                ),
              ),
            ),
          if (active != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (active.speaker != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 3,
                      height: 16,
                      decoration: BoxDecoration(
                        color: _colorForSpeaker(active.speaker!),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: CueText(
                    cue: active,
                    activeWord: _activeWord,
                    fontSize: 16.5,
                    spokenColor: Colors.white,
                    currentColor: playerAccent,
                    upcomingColor: Colors.white.withValues(alpha: 0.42),
                  ),
                ),
              ],
            ),
          if (next != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                next.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.28),
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _captionShell({required Widget child, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: child,
        ),
      ),
    );
  }

  Color _colorForSpeaker(String speaker) {
    final index = _speakers.indexOf(speaker);
    return playerSpeakerColors[(index < 0 ? 0 : index) % playerSpeakerColors.length];
  }

  // ─── Transcript panel ───────────────────────────────────────────────────

  Widget _buildTranscriptPanel() {
    return Stack(
      key: const ValueKey('transcript'),
      children: [
        NotificationListener<UserScrollNotification>(
          // A deliberate drag means the listener is browsing — stop yanking
          // the view back to the spoken line until they ask for it.
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle && _autoScroll) {
              setState(() => _autoScroll = false);
            }
            return false;
          },
          child: ListView.builder(
            controller: _transcriptScroll,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            itemCount: _cues.length,
            itemBuilder: (context, i) {
              final cue = _cues[i];
              final isActive = i == _activeCue;
              final isSpoken = i < _activeCue;
              final showSpeaker = cue.speaker != null &&
                  (i == 0 || _cues[i - 1].speaker != cue.speaker);

              return Padding(
                key: _cueKeys[i],
                padding: EdgeInsets.only(top: showSpeaker && i > 0 ? 16 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showSpeaker)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
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
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        _seekTo(cue.start);
                        if (!_service.isPlaying) _service.play();
                        setState(() => _autoScroll = true);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
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
                              : Colors.white.withValues(
                                  alpha: isSpoken ? 0.55 : 0.38),
                          currentColor: isActive
                              ? playerAccent
                              : Colors.white.withValues(alpha: 0.55),
                          upcomingColor: isActive
                              ? Colors.white.withValues(alpha: 0.45)
                              : Colors.white.withValues(
                                  alpha: isSpoken ? 0.55 : 0.38),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
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
                      Icon(Icons.vertical_align_center_rounded,
                          size: 15, color: playerBgTop),
                      SizedBox(width: 6),
                      Text(
                        'Jump to current',
                        style: TextStyle(
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

  // ─── Transport ──────────────────────────────────────────────────────────

  Widget _buildSeekBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          WaveformSeekBar(
            seed: _title,
            position: _position,
            duration: _totalDuration,
            buffered: _buffered,
            onScrubStart: () => setState(() => _isScrubbing = true),
            onScrubUpdate: (pos) {
              setState(() => _position = pos);
              _updateActiveCue(pos);
            },
            onScrubEnd: (pos) {
              setState(() => _isScrubbing = false);
              _seekTo(pos);
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatClock(_position),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (_totalDuration > Duration.zero)
                Text(
                  formatRemainingLabel(_totalDuration - _position),
                  style: TextStyle(
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _service.hasPrevious ? _previousTrack : null,
            icon: Icon(
              Icons.skip_previous_rounded,
              size: 30,
              color: _service.hasPrevious
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.25),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _seekBackward,
            tooltip: 'Back 15 seconds',
            icon: SvgPicture.asset(
              'assets/images/branding/video-back.svg',
              width: 30,
              height: 30,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _togglePlay,
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
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: playerBgTop,
                size: 36,
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: _seekForward,
            tooltip: 'Forward 15 seconds',
            icon: SvgPicture.asset(
              'assets/images/branding/video-front.svg',
              width: 30,
              height: 30,
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _service.hasNext ? _nextTrack : null,
            icon: Icon(
              Icons.skip_next_rounded,
              size: 30,
              color: _service.hasNext
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.25),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUtilityRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _utilityButton(
            onTap: _showSleepTimer,
            active: _sleepLabel != 'Off',
            child: SvgPicture.asset(
              'assets/images/buttons/moon.svg',
              width: 16,
              height: 16,
              colorFilter: ColorFilter.mode(
                _sleepLabel != 'Off'
                    ? playerBgTop
                    : Colors.white.withValues(alpha: 0.75),
                BlendMode.srcIn,
              ),
            ),
            label: _sleepLabel == 'Off' ? 'Sleep' : _sleepLabel,
          ),
          _utilityButton(
            onTap: _cues.isEmpty ? null : _toggleTranscript,
            active: _showTranscript,
            child: Icon(
              Icons.closed_caption_rounded,
              size: 17,
              color: _showTranscript
                  ? playerBgTop
                  : Colors.white.withValues(
                      alpha: _cues.isEmpty ? 0.25 : 0.75),
            ),
            label: _cues.isEmpty ? 'No transcript' : 'Transcript',
            dimmed: _cues.isEmpty,
          ),
          _utilityButton(
            onTap: _showSpeedSheet,
            active: _speed != 1.0,
            child: Text(
              '${_speed == _speed.roundToDouble() ? _speed.toInt() : _speed}x',
              style: TextStyle(
                color: _speed != 1.0
                    ? playerBgTop
                    : Colors.white.withValues(alpha: 0.75),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            label: 'Speed',
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
    bool dimmed = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
              color: Colors.white
                  .withValues(alpha: dimmed ? 0.3 : (active ? 0.9 : 0.55)),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Word-level caption text ──────────────────────────────────────────────

/// A transcript line rendered word by word so the one currently being spoken
/// can be picked out.
///
/// [activeWord] is the index inside [SubtitleCue.words] being spoken right
/// now, or -1 when this line isn't the active one — then every word is drawn
/// in [upcomingColor].
class CueText extends StatelessWidget {
  final SubtitleCue cue;
  final int activeWord;
  final double fontSize;
  final Color spokenColor;
  final Color currentColor;
  final Color upcomingColor;
  final bool bold;

  const CueText({
    super.key,
    required this.cue,
    required this.activeWord,
    required this.fontSize,
    required this.spokenColor,
    required this.currentColor,
    required this.upcomingColor,
    this.bold = true,
  });

  @override
  Widget build(BuildContext context) {
    final words = cue.words;
    if (words.isEmpty || activeWord < 0) {
      return Text(
        cue.text,
        style: TextStyle(
          color: upcomingColor,
          fontSize: fontSize,
          height: 1.45,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < words.length; i++)
            TextSpan(
              text: i == words.length - 1 ? words[i].text : '${words[i].text} ',
              style: TextStyle(
                color: i < activeWord
                    ? spokenColor
                    : i == activeWord
                        ? currentColor
                        : upcomingColor,
                fontWeight:
                    i == activeWord && bold ? FontWeight.w800 : null,
              ),
            ),
        ],
      ),
      style: TextStyle(
        fontSize: fontSize,
        height: 1.45,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}

/// Pulsing red dot — the "this is happening right now" marker on the caption.
class _LiveDot extends StatefulWidget {
  final bool active;
  const _LiveDot({required this.active});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_LiveDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active) {
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final alpha = widget.active ? 0.45 + 0.55 * _controller.value : 0.35;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B6B).withValues(alpha: alpha),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

// ─── Waveform scrubber ────────────────────────────────────────────────────

/// Seek bar drawn as a waveform.
///
/// The audio isn't analysed — decoding a whole episode client-side just to
/// draw it would be wasteful — so the bar heights come from a hash of the
/// episode title. They're stable per episode and read as "audio" while the
/// played/buffered/remaining split carries the real information.
class WaveformSeekBar extends StatefulWidget {
  final String seed;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final VoidCallback onScrubStart;
  final ValueChanged<Duration> onScrubUpdate;
  final ValueChanged<Duration> onScrubEnd;

  const WaveformSeekBar({
    super.key,
    required this.seed,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
  });

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar> {
  static const _barCount = 56;
  static const _height = 40.0;

  late List<double> _bars = _generateBars(widget.seed);
  double? _dragFraction;

  @override
  void didUpdateWidget(WaveformSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed) _bars = _generateBars(widget.seed);
  }

  /// Deterministic pseudo-random heights (a small LCG over the seed hash) with
  /// a gentle envelope so the shape tapers at both ends like a real clip.
  static List<double> _generateBars(String seed) {
    var state = 0;
    for (final unit in seed.codeUnits) {
      state = (state * 31 + unit) & 0x7fffffff;
    }
    if (state == 0) state = 12345;
    return List.generate(_barCount, (i) {
      state = (1103515245 * state + 12345) & 0x7fffffff;
      final noise = (state % 1000) / 1000;
      final envelope = math.sin(math.pi * (i + 0.5) / _barCount);
      return (0.25 + 0.75 * noise) * (0.45 + 0.55 * envelope);
    });
  }

  double get _fraction {
    if (_dragFraction != null) return _dragFraction!;
    if (widget.duration.inMilliseconds <= 0) return 0;
    return (widget.position.inMilliseconds / widget.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  double get _bufferedFraction {
    if (widget.duration.inMilliseconds <= 0) return 0;
    return (widget.buffered.inMilliseconds / widget.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  Duration _positionFor(double fraction) => Duration(
        milliseconds:
            (widget.duration.inMilliseconds * fraction.clamp(0.0, 1.0)).round(),
      );

  @override
  Widget build(BuildContext context) {
    final enabled = widget.duration > Duration.zero;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void update(double dx) {
          final fraction = (dx / width).clamp(0.0, 1.0);
          setState(() => _dragFraction = fraction);
          widget.onScrubUpdate(_positionFor(fraction));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: enabled
              ? (details) {
                  widget.onScrubStart();
                  update(details.localPosition.dx);
                }
              : null,
          onHorizontalDragUpdate:
              enabled ? (details) => update(details.localPosition.dx) : null,
          onHorizontalDragEnd: enabled
              ? (_) {
                  final fraction = _dragFraction ?? _fraction;
                  setState(() => _dragFraction = null);
                  widget.onScrubEnd(_positionFor(fraction));
                }
              : null,
          onTapDown: enabled
              ? (details) {
                  final fraction =
                      (details.localPosition.dx / width).clamp(0.0, 1.0);
                  widget.onScrubEnd(_positionFor(fraction));
                }
              : null,
          child: SizedBox(
            height: _height,
            width: double.infinity,
            child: CustomPaint(
              painter: _WaveformPainter(
                bars: _bars,
                progress: _fraction,
                buffered: _bufferedFraction,
                playedColor: playerAccent,
                bufferedColor: Colors.white.withValues(alpha: 0.38),
                remainingColor: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final double buffered;
  final Color playedColor;
  final Color bufferedColor;
  final Color remainingColor;

  const _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.buffered,
    required this.playedColor,
    required this.bufferedColor,
    required this.remainingColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final slot = size.width / bars.length;
    final barWidth = math.max(2.0, slot * 0.5);
    final centerY = size.height / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < bars.length; i++) {
      final fraction = (i + 0.5) / bars.length;
      paint.color = fraction <= progress
          ? playedColor
          : fraction <= buffered
              ? bufferedColor
              : remainingColor;
      final barHeight = math.max(3.0, bars[i] * size.height);
      final left = i * slot + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, centerY - barHeight / 2, barWidth, barHeight),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }

    // Playhead
    final x = (progress.clamp(0.0, 1.0)) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(math.min(x, size.width - 3), 0, 3, size.height),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.buffered != buffered ||
      !identical(oldDelegate.bars, bars);
}

// ─── Sleep timer bottom sheet ─────────────────────────────────────────────

class _SleepTimerSheet extends StatelessWidget {
  final String currentLabel;
  final void Function(String label, Duration? duration) onSelected;

  const _SleepTimerSheet({required this.currentLabel, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final options = <_SleepOption>[
      _SleepOption('At the end of the release', const Duration(hours: 99)),
      _SleepOption('1 hour', const Duration(hours: 1)),
      _SleepOption('30 min', const Duration(minutes: 30)),
      _SleepOption('15 min', const Duration(minutes: 15)),
      _SleepOption('5 min', const Duration(minutes: 5)),
      _SleepOption('Off', null),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Row(
                children: [
                  Text(
                    'Sleep timer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            ...options.map((opt) {
              final selected = currentLabel == opt.label;
              return InkWell(
                onTap: () => onSelected(opt.label, opt.duration),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          opt.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? playerAccent
                                : Colors.white.withValues(alpha: 0.5),
                            width: 2,
                          ),
                        ),
                        child: selected
                            ? const Center(
                                child: SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: playerAccent,
                                    ),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _SleepOption {
  final String label;
  final Duration? duration;
  const _SleepOption(this.label, this.duration);
}
