import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../screens/podcast_player_screen.dart';
import '../services/podcast_playback_service.dart';
import '../services/podcast_transcript_service.dart';
import '../services/subtitle_service.dart';
import '../theme/app_colors.dart';
import 'podcast_artwork.dart';

/// Persistent playback bar shown above the bottom navigation.
///
/// Beyond transport controls it doubles as a live caption strip: when the
/// episode has a transcript, the line currently being spoken scrolls through
/// under the title so the listener can keep reading along after leaving the
/// player screen.
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

  int? _cuesLoadedFor;
  List<SubtitleCue> _cues = [];
  int _activeCue = -1;

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
      _updateActiveCue(pos);
    });
    _durationSub = _service.durationStream.listen((d) {
      if (!mounted || d == null) return;
      setState(() => _duration = d);
    });
    _service.currentTrack.addListener(_onTrackChanged);
    _onTrackChanged();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _service.currentTrack.removeListener(_onTrackChanged);
    super.dispose();
  }

  void _onTrackChanged() {
    final track = _service.currentTrack.value;
    if (track == null || track.id == _cuesLoadedFor) return;
    _cuesLoadedFor = track.id;
    setState(() {
      _cues = [];
      _activeCue = -1;
    });
    PodcastTranscriptService.load(
      track.id,
      subtitleUrl: track.subtitleUrl,
      audioUrl: track.audioUrl,
    ).then((cues) {
      if (!mounted || _cuesLoadedFor != track.id) return;
      setState(() => _cues = cues);
      _updateActiveCue(_position);
    });
  }

  void _updateActiveCue(Duration position) {
    if (_cues.isEmpty) return;
    final index = SubtitleService.nearestCueIndex(_cues, position);
    if (index == _activeCue) return;
    setState(() => _activeCue = index);
  }

  void _openFullPlayer(PodcastTrack track) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PodcastPlayerScreen(
          podcastId: track.id,
          initialTitle: track.title,
          initialAudioUrl: track.audioUrl,
          initialSubtitleUrl: track.subtitleUrl,
          initialImageUrl: track.imageUrl,
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
        final caption =
            _activeCue >= 0 && _activeCue < _cues.length ? _cues[_activeCue] : null;

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
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      PodcastArtwork(
                        seed: track.title,
                        imageUrl: track.imageUrl,
                        size: 42,
                        borderRadius: 10,
                        playing: _playing,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.title.isNotEmpty ? track.title : 'Podcast',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (caption != null) ...[
                              const SizedBox(height: 2),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Text(
                                  caption.speaker != null
                                      ? '${caption.speaker}: ${caption.text}'
                                      : caption.text,
                                  key: ValueKey(_activeCue),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.65),
                                    fontSize: 11.5,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _service.togglePlay(),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 36),
                        icon: Icon(
                          _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
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
}
