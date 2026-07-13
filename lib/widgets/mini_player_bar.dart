import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import '../screens/podcast_player_screen.dart';
import '../services/podcast_playback_service.dart';
import '../theme/app_colors.dart';

class MiniPlayerBar extends StatefulWidget {
  const MiniPlayerBar({super.key});

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar> {
  final _service = PodcastPlaybackService.instance;

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  @override
  void initState() {
    super.initState();
    _playing = _service.isPlaying;
    _position = _service.position;
    _duration = _service.duration;
    _stateSub = _service.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
    });
    _positionSub = _service.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });
    _durationSub = _service.durationStream.listen((d) {
      if (!mounted || d == null) return;
      setState(() => _duration = d);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    super.dispose();
  }

  void _openFullPlayer(PodcastTrack track) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PodcastPlayerScreen(
          podcastId: track.id,
          initialTitle: track.title,
          initialAudioUrl: track.audioUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PodcastTrack?>(
      valueListenable: _service.currentTrack,
      builder: (context, track, _) {
        if (track == null) return const SizedBox.shrink();

        final progress = _duration.inMilliseconds > 0
            ? (_position.inMilliseconds / _duration.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openFullPlayer(track),
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.brand,
                border: const Border(
                  top: BorderSide(color: Color(0xFF1B1D33), width: 0.5),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // Cover / app icon
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: track.imageUrl != null &&
                                track.imageUrl!.isNotEmpty
                            ? Image.network(
                                track.imageUrl!,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _fallbackIcon(),
                              )
                            : _fallbackIcon(),
                      ),
                      const SizedBox(width: 12),
                      // Title
                      Expanded(
                        child: Text(
                          track.title.isNotEmpty ? track.title : 'Podcast',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Play / Pause
                      IconButton(
                        onPressed: () => _service.togglePlay(),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 36),
                        icon: Icon(
                          _playing ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      // Close
                      IconButton(
                        onPressed: () => _service.stop(),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: Icon(
                          Icons.close,
                          color: Colors.white.withValues(alpha: 0.7),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Thin progress line
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        context.colors.accentYellow,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fallbackIcon() {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xFFBEBEC6),
      ),
      alignment: Alignment.center,
      child: SvgPicture.asset(
        'assets/images/buttons/podcast-black.svg',
        width: 22,
        height: 22,
      ),
    );
  }
}
