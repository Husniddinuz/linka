import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import '../services/api_service.dart';
import '../services/facebook_events_service.dart';
import '../services/podcast_playback_service.dart';
import '../services/subtitle_service.dart';

class PodcastPlayerScreen extends StatefulWidget {
  final int podcastId;
  final String? initialTitle;
  final String? initialAudioUrl;
  final String? initialSubtitleUrl;
  const PodcastPlayerScreen({
    super.key,
    required this.podcastId,
    this.initialTitle,
    this.initialAudioUrl,
    this.initialSubtitleUrl,
  });

  @override
  State<PodcastPlayerScreen> createState() => _PodcastPlayerScreenState();
}

class _PodcastPlayerScreenState extends State<PodcastPlayerScreen> {
  final _service = PodcastPlaybackService.instance;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<PlayerState>? _sleepSub;

  bool _loading = true;
  String _title = '';

  Duration _totalDuration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _muted = false;
  double _speed = 1.0;
  Timer? _sleepTimer;
  String _sleepLabel = 'Off';

  // Subtitles / transcript
  int? _subtitleLoadedFor;
  List<SubtitleCue> _cues = [];
  int _activeCue = -1;
  bool _showTranscript = false;
  bool _isScrubbing = false;
  final ScrollController _transcriptScroll = ScrollController();
  List<GlobalKey> _cueKeys = [];

  @override
  void initState() {
    super.initState();
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
      setState(() => _playing = state.playing);
    });
  }

  void _onTrackChanged() {
    final track = _service.currentTrack.value;
    if (!mounted || track == null) return;
    setState(() {
      _title = track.title;
      _cues = [];
      _cueKeys = [];
      _activeCue = -1;
      _subtitleLoadedFor = null;
    });
    _loadSubtitles(track.id, track.subtitleUrl, audioUrl: track.audioUrl);
  }

  Future<void> _loadPodcast() async {
    try {
      final existing = _service.currentTrack.value;
      if (existing != null && existing.id == widget.podcastId) {
        _title = existing.title;
        _totalDuration = _service.duration;
        _position = _service.position;
        _playing = _service.isPlaying;
        _speed = _service.player.speed;
        _muted = _service.player.volume == 0.0;
        setState(() => _loading = false);
        String? subtitleUrl =
            existing.subtitleUrl ?? widget.initialSubtitleUrl;
        if ((subtitleUrl == null || subtitleUrl.isEmpty) &&
            existing.audioUrl.isNotEmpty) {
          subtitleUrl = _resolveSubtitleUrl(existing.audioUrl);
        }
        _loadSubtitles(existing.id, subtitleUrl);
        return;
      }

      String? audioUrl = widget.initialAudioUrl;
      String? imageUrl;
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
          imageUrl = podcast['image_url'] as String? ??
              podcast['cover_url'] as String?;
          subtitleUrl ??= podcast['subtitle_url'] as String?;
        } catch (_) {
          // API unavailable — use whatever initial data we have
        }
      }

      // Auto-derive subtitle URL from the audio filename when not provided
      if ((subtitleUrl == null || subtitleUrl.isEmpty) &&
          audioUrl != null && audioUrl.isNotEmpty) {
        subtitleUrl = _resolveSubtitleUrl(audioUrl);
      }

      debugPrint('[Podcast] audioUrl: $audioUrl');
      debugPrint('[Podcast] subtitleUrl: $subtitleUrl');

      if (audioUrl != null && audioUrl.isNotEmpty) {
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
      setState(() => _loading = false);
      _loadSubtitles(widget.podcastId, subtitleUrl);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _loadSubtitles(widget.podcastId, widget.initialSubtitleUrl);
    }
  }

  /// Derives the subtitle URL from [audioUrl] by inserting `srt/` after
  /// `podcasts/` in the path and replacing the audio extension with `.srt`.
  /// e.g. `.../podcasts/audio.mp3` → `.../podcasts/srt/audio.srt`
  String? _resolveSubtitleUrl(String audioUrl) {
    final withSubdir = audioUrl.replaceFirst('podcasts/', 'podcasts/srt/');
    final srtUrl = withSubdir.replaceFirst(
      RegExp(r'\.(mp3|m4a|wav|aac|ogg)$', caseSensitive: false),
      '.srt',
    );
    if (srtUrl == audioUrl) {
      debugPrint('[Subtitle] URL did not match expected pattern: $audioUrl');
      return null;
    }
    debugPrint('[Subtitle] resolved: $srtUrl');
    return srtUrl;
  }

  /// Resolves [subtitleUrl] (fetching the podcast detail if it's unknown) and
  /// loads the WebVTT cues for the podcast with [id]. No-op if already loaded
  /// for this podcast. Silently leaves the transcript empty on any failure.
  Future<void> _loadSubtitles(int id, String? subtitleUrl, {String? audioUrl}) async {
    if (_subtitleLoadedFor == id) return;
    _subtitleLoadedFor = id;

    var url = subtitleUrl;
    if (url == null || url.isEmpty) {
      try {
        final data = await ApiService.get('/content/podcasts/$id/');
        final podcast = data['data'] as Map<String, dynamic>? ?? data;
        url = podcast['subtitle_url'] as String?;
      } catch (_) {
        url = null;
      }
    }
    if ((url == null || url.isEmpty) && audioUrl != null && audioUrl.isNotEmpty) {
      url = _resolveSubtitleUrl(audioUrl);
    }

    final cues = await SubtitleService.fetchCues(url);
    if (!mounted || _subtitleLoadedFor != id) return;
    setState(() {
      _cues = cues;
      _cueKeys = List.generate(cues.length, (_) => GlobalKey());
      _activeCue = -1;
      if (cues.isEmpty) {
        _showTranscript = false;
      } else {
        _showTranscript = true;
      }
    });
    _updateActiveCue(_position);
  }

  /// Recomputes which cue is active at [pos] and, when the transcript panel is
  /// open, scrolls it into view.
  void _updateActiveCue(Duration pos) {
    if (_cues.isEmpty) return;
    final index = SubtitleService.activeCueIndex(_cues, pos);
    if (index == _activeCue) return;
    setState(() => _activeCue = index);
    if (_showTranscript) _scrollToActiveCue();
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
                duration: Duration.zero, alignment: 0.4);
          }
        });
      }
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      duration: _isScrubbing ? Duration.zero : const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.4,
    );
  }

  void _toggleTranscript() {
    setState(() => _showTranscript = !_showTranscript);
    if (_showTranscript) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToActiveCue());
    }
  }

  @override
  void dispose() {
    _transcriptScroll.dispose();
    _service.currentTrack.removeListener(_onTrackChanged);
    _sleepTimer?.cancel();
    _sleepSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

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
    _service.seek(newPos > _totalDuration ? _totalDuration : newPos);
  }

  void _seekBackward() {
    debugPrint('[Podcast] seek_backward id=${widget.podcastId}');
    FacebookEventsService.logEvent('podcast_seek_backward', parameters: {'podcast_id': widget.podcastId});
    final newPos = _position - const Duration(seconds: 15);
    _service.seek(newPos < Duration.zero ? Duration.zero : newPos);
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

  void _cycleSpeed() {
    setState(() {
      _speed = _speed == 1.0 ? 1.5 : _speed == 1.5 ? 2.0 : 1.0;
      debugPrint('[Podcast] speed=$_speed id=${widget.podcastId}');
      FacebookEventsService.logEvent('podcast_speed_changed', parameters: {
        'podcast_id': widget.podcastId,
        'speed': _speed,
      });
      _service.setSpeed(_speed);
    });
  }

  void _showSleepTimer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF3A3C56),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatRemaining(Duration total, Duration pos) {
    final remaining = total - pos;
    if (remaining.isNegative) return '0:00';
    return '-${_formatDuration(remaining)}';
  }

  Widget _buildTranscriptPanel() {
    return Expanded(
      child: ListView.builder(
        controller: _transcriptScroll,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        itemCount: _cues.length,
        itemBuilder: (context, i) {
          final cue = _cues[i];
          final isActive = i == _activeCue;
          return Padding(
            key: _cueKeys[i],
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _service.seek(cue.start);
                if (!_service.isPlaying) _service.play();
              },
              child: Text(
                cue.text,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.4),
                  fontSize: isActive ? 19 : 17,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  height: 1.4,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
      backgroundColor: const Color(0xFF272942),
      body: SafeArea(
        child: Column(
              children: [
                  // App bar (always visible)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
                        ),
                        const Expanded(
                          child: Text(
                            'Podcasts',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_cues.isNotEmpty)
                          IconButton(
                            onPressed: _toggleTranscript,
                            tooltip: 'Transcript',
                            icon: Icon(
                              _showTranscript
                                  ? Icons.closed_caption
                                  : Icons.closed_caption_off_outlined,
                              color: _showTranscript
                                  ? const Color(0xFFF5C542)
                                  : Colors.white,
                              size: 26,
                            ),
                          ),
                        IconButton(
                          onPressed: _loading ? null : _toggleMute,
                          icon: SvgPicture.asset(
                            _muted
                                ? 'assets/images/buttons/volume-off.svg'
                                : 'assets/images/buttons/volume-on.svg',
                            width: 24,
                            height: 24,
                            colorFilter: ColorFilter.mode(
                              _loading
                                  ? Colors.white.withValues(alpha: 0.3)
                                  : Colors.white,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_loading)
                    const Expanded(
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFF5C542),
                        ),
                      ),
                    )
                  else ...[

                  // Podcast image + title — or transcript when toggled on
                  if (_showTranscript)
                    _buildTranscriptPanel()
                  else
                    Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 180,
                          height: 200,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.bottomCenter,
                            children: [
                              // Circle icon
                              Container(
                                width: 150,
                                height: 150,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFBEBEC6),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: SvgPicture.asset(
                                    'assets/images/buttons/podcast-black.svg',
                                    width: 60,
                                    height: 60,
                                  ),
                                ),
                              ),
                              // Umbrella SVG above the circle
                              Positioned(
                                top: -5,
                                child: SvgPicture.asset(
                                  'assets/images/branding/meeting-umbrella.svg',
                                  width: 160,
                                  colorFilter: ColorFilter.mode(
                                    Colors.white.withValues(alpha: 0.25),
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            _title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (_activeCue >= 0 && _activeCue < _cues.length) ...[
                          const SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _cues[_activeCue].text,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Controls
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        // Moon (left)
                        GestureDetector(
                          onTap: _showSleepTimer,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: SvgPicture.asset(
                              'assets/images/buttons/moon.svg',
                              width: 18,
                              height: 18,
                              colorFilter: ColorFilter.mode(
                                _sleepLabel != 'Off'
                                    ? const Color(0xFFF5C542)
                                    : Colors.white.withValues(alpha: 0.7),
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Previous track
                        IconButton(
                          onPressed: _service.hasPrevious ? _previousTrack : null,
                          icon: Icon(
                            Icons.skip_previous_rounded,
                            size: 28,
                            color: _service.hasPrevious
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        // Rewind
                        IconButton(
                          onPressed: _seekBackward,
                          icon: SvgPicture.asset(
                            'assets/images/branding/video-back.svg',
                            width: 28,
                            height: 28,
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Play / Pause
                        GestureDetector(
                          onTap: _togglePlay,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _playing ? Icons.pause : Icons.play_arrow,
                              color: const Color(0xFF272942),
                              size: 32,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Forward
                        IconButton(
                          onPressed: _seekForward,
                          icon: SvgPicture.asset(
                            'assets/images/branding/video-front.svg',
                            width: 28,
                            height: 28,
                          ),
                        ),
                        // Next track
                        IconButton(
                          onPressed: _service.hasNext ? _nextTrack : null,
                          icon: Icon(
                            Icons.skip_next_rounded,
                            size: 28,
                            color: _service.hasNext
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        const Spacer(),
                        // Speed (right)
                        GestureDetector(
                          onTap: _cycleSpeed,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _speed == 1.0 ? '1x' : _speed == 1.5 ? '1.5x' : '2x',
                              style: TextStyle(
                                color: _speed != 1.0 ? const Color(0xFFF5C542) : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Progress bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                            thumbColor: Colors.white,
                            overlayColor: Colors.white.withValues(alpha: 0.15),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                          ),
                          child: Slider(
                            value: _totalDuration.inMilliseconds > 0
                                ? _position.inMilliseconds.toDouble().clamp(0, _totalDuration.inMilliseconds.toDouble())
                                : 0,
                            max: _totalDuration.inMilliseconds > 0
                                ? _totalDuration.inMilliseconds.toDouble()
                                : 1,
                            onChangeStart: (_) => setState(() => _isScrubbing = true),
                            onChangeEnd: (v) {
                              setState(() => _isScrubbing = false);
                              _service.seek(Duration(milliseconds: v.toInt()));
                            },
                            onChanged: (v) {
                              final pos = Duration(milliseconds: v.toInt());
                              setState(() => _position = pos);
                              _updateActiveCue(pos);
                            },
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(_position),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _formatRemaining(_totalDuration, _position),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  ],
                ],
              ),
      ),
    ),
    );
  }
}

// ─── Sleep timer bottom sheet ─────────────────────────────────────────────────

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
          children: options.map((opt) {
            final selected = currentLabel == opt.label;
            return InkWell(
              onTap: () => onSelected(opt.label, opt.duration),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
                          color: selected ? const Color(0xFFF5C542) : Colors.white.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? Center(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFFF5C542),
                                ),
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
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
