import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/api_service.dart';

class MoviePlayerScreen extends StatefulWidget {
  final int movieId;
  final String? initialTitle;
  final String? initialPlaybackUrl;
  final String? initialPosterUrl;

  const MoviePlayerScreen({
    super.key,
    required this.movieId,
    this.initialTitle,
    this.initialPlaybackUrl,
    this.initialPosterUrl,
  });

  @override
  State<MoviePlayerScreen> createState() => _MoviePlayerScreenState();
}

class _MoviePlayerScreenState extends State<MoviePlayerScreen> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _initialized = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  String _title = '';
  String _description = '';

  @override
  void initState() {
    super.initState();
    _title = widget.initialTitle ?? '';
    _loadMovie();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.removeListener(_onVideoEvent);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadMovie() async {
    String? playbackUrl = widget.initialPlaybackUrl;

    if (widget.movieId != 0) {
      try {
        final data = await ApiService.get('/content/movies/${widget.movieId}/');
        if (!mounted) return;
        final movie = data['data'] as Map<String, dynamic>? ?? data;
        _title = movie['title'] as String? ?? _title;
        _description = movie['description'] as String? ?? '';
        playbackUrl = movie['playback_url'] as String? ?? playbackUrl;
      } catch (e) {
      }
    }

    if (playbackUrl == null || playbackUrl.isEmpty) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(playbackUrl));
    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.addListener(_onVideoEvent);
      await controller.play();
      setState(() {
        _controller = controller;
        _initialized = true;
        _loading = false;
      });
      _scheduleHideControls();
    } catch (e) {
      controller.dispose();
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _onVideoEvent() {
    if (!mounted) return;
    setState(() {});
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_controller?.value.isPlaying ?? false) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
      _hideControlsTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      c.play();
      _scheduleHideControls();
    }
  }

  void _seekRelative(Duration delta) {
    final c = _controller;
    if (c == null) return;
    final target = c.value.position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > c.value.duration ? c.value.duration : target);
    c.seekTo(clamped);
    setState(() => _showControls = true);
    _scheduleHideControls();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Stack(
            children: [
              // Video / loader / fallback
              Positioned.fill(child: _buildVideoArea()),

              // Top bar (close + title)
              if (_showControls)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: Colors.white, size: 26),
                        ),
                        Expanded(
                          child: Text(
                            _title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                ),

              // Center play/pause + skip controls
              if (_showControls && _initialized)
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CircleControl(
                        icon: Icons.replay_10,
                        size: 56,
                        onTap: () => _seekRelative(const Duration(seconds: -10)),
                      ),
                      const SizedBox(width: 32),
                      _CircleControl(
                        icon: (_controller?.value.isPlaying ?? false)
                            ? Icons.pause
                            : Icons.play_arrow,
                        size: 76,
                        onTap: _togglePlayPause,
                      ),
                      const SizedBox(width: 32),
                      _CircleControl(
                        icon: Icons.forward_10,
                        size: 56,
                        onTap: () => _seekRelative(const Duration(seconds: 10)),
                      ),
                    ],
                  ),
                ),

              // Bottom controls (progress + time + description)
              if (_showControls)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_initialized && _controller != null) ...[
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFFF5C542),
                              inactiveTrackColor: Colors.white24,
                              thumbColor: const Color(0xFFF5C542),
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            ),
                            child: Slider(
                              min: 0,
                              max: _controller!.value.duration.inMilliseconds
                                  .toDouble()
                                  .clamp(1, double.infinity),
                              value: _controller!.value.position.inMilliseconds
                                  .toDouble()
                                  .clamp(
                                    0,
                                    _controller!.value.duration.inMilliseconds.toDouble(),
                                  ),
                              onChanged: (v) {
                                _controller!.seekTo(Duration(milliseconds: v.toInt()));
                                _scheduleHideControls();
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _fmt(_controller!.value.position),
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                                Text(
                                  _fmt(_controller!.value.duration),
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_description.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            _description,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.4,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoArea() {
    if (_loading) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (widget.initialPosterUrl != null && widget.initialPosterUrl!.startsWith('http'))
            Image.network(
              widget.initialPosterUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          Container(color: Colors.black54),
          const Center(child: CircularProgressIndicator(color: Color(0xFFF5C542))),
        ],
      );
    }

    if (!_initialized || _controller == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.white54, size: 48),
            SizedBox(height: 12),
            Text(
              'Unable to play this movie',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: VideoPlayer(_controller!),
      ),
    );
  }
}

class _CircleControl extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _CircleControl({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.55),
      ),
    );
  }
}
