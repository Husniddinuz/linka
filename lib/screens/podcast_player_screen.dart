import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import '../services/api_service.dart';

class PodcastPlayerScreen extends StatefulWidget {
  final int podcastId;
  final String? initialTitle;
  final String? initialAudioUrl;
  const PodcastPlayerScreen({
    super.key,
    required this.podcastId,
    this.initialTitle,
    this.initialAudioUrl,
  });

  @override
  State<PodcastPlayerScreen> createState() => _PodcastPlayerScreenState();
}

class _PodcastPlayerScreenState extends State<PodcastPlayerScreen> {
  final AudioPlayer _player = AudioPlayer();

  bool _loading = true;
  String _title = '';

  Duration _totalDuration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _muted = false;
  double _speed = 1.0;
  Timer? _sleepTimer;
  String _sleepLabel = 'Off';

  @override
  void initState() {
    super.initState();
    _loadPodcast();
  }

  Future<void> _loadPodcast() async {
    try {
      String? audioUrl = widget.initialAudioUrl;
      _title = widget.initialTitle ?? '';

      if (audioUrl == null || audioUrl.isEmpty) {
        final data = await ApiService.get('/content/podcasts/${widget.podcastId}/');
        if (!mounted) return;
        final podcast = data['data'] as Map<String, dynamic>? ?? data;
        _title = podcast['title'] as String? ?? '';
        audioUrl = podcast['audio_url'] as String?;
      }

      if (audioUrl != null && audioUrl.isNotEmpty) {
        final duration = await _player.setUrl(audioUrl);
        if (duration != null) {
          _totalDuration = duration;
        }
      }

      _player.positionStream.listen((pos) {
        if (!mounted) return;
        setState(() => _position = pos);
      });

      _player.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() {
          _playing = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _playing = false;
            _position = Duration.zero;
            _player.seek(Duration.zero);
            _player.pause();
          }
        });
      });

      _player.durationStream.listen((d) {
        if (!mounted || d == null) return;
        setState(() => _totalDuration = d);
      });

      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_playing) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  void _seekForward() {
    final newPos = _position + const Duration(seconds: 15);
    _player.seek(newPos > _totalDuration ? _totalDuration : newPos);
  }

  void _seekBackward() {
    final newPos = _position - const Duration(seconds: 15);
    _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      _player.setVolume(_muted ? 0.0 : 1.0);
    });
  }

  void _cycleSpeed() {
    setState(() {
      _speed = _speed == 1.0 ? 1.5 : _speed == 1.5 ? 2.0 : 1.0;
      _player.setSpeed(_speed);
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
          if (duration == null) {
            setState(() => _sleepLabel = 'Off');
            return;
          }
          setState(() => _sleepLabel = label);
          if (label == 'At the end of the release') {
            // Pause when current track ends
            late final StreamSubscription<PlayerState> sub;
            sub = _player.playerStateStream.listen((state) {
              if (state.processingState == ProcessingState.completed) {
                sub.cancel();
                _player.pause();
                if (mounted) setState(() => _sleepLabel = 'Off');
              }
            });
          } else {
            _sleepTimer = Timer(duration, () {
              _player.pause();
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

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
      backgroundColor: const Color(0xFF272942),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFF5C542)))
            : Column(
                children: [
                  // App bar
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
                        IconButton(
                          onPressed: _toggleMute,
                          icon: SvgPicture.asset(
                            _muted
                                ? 'assets/images/buttons/volume-off.svg'
                                : 'assets/images/buttons/volume-on.svg',
                            width: 24,
                            height: 24,
                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Podcast image + title
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
                        // Rewind
                        IconButton(
                          onPressed: _seekBackward,
                          icon: SvgPicture.asset(
                            'assets/images/branding/video-back.svg',
                            width: 28,
                            height: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
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
                        const SizedBox(width: 12),
                        // Forward
                        IconButton(
                          onPressed: _seekForward,
                          icon: SvgPicture.asset(
                            'assets/images/branding/video-front.svg',
                            width: 28,
                            height: 28,
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
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
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
                            onChanged: (v) {
                              _player.seek(Duration(milliseconds: v.toInt()));
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
