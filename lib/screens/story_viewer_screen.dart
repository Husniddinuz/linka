import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'tutor_profile_screen.dart';
import 'home_screen.dart';

class StoryTutor {
  final int tutorId;
  final String name;
  final String? image;
  final List<StoryData> stories;
  const StoryTutor({
    required this.tutorId,
    required this.name,
    this.image,
    required this.stories,
  });
}

class StoryViewerScreen extends StatefulWidget {
  final List<StoryTutor> tutors;
  final int initialTutorIndex;
  final void Function(int tutorId)? onTutorViewed;

  const StoryViewerScreen({
    super.key,
    required this.tutors,
    this.initialTutorIndex = 0,
    this.onTutorViewed,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _imageDuration = Duration(seconds: 15);

  late int _tutorIndex;
  int _storyIndex = 0;
  VideoPlayerController? _videoController;
  late final AnimationController _progress;

  StoryTutor get _tutor => widget.tutors[_tutorIndex];
  StoryData get _current => _tutor.stories[_storyIndex];

  @override
  void initState() {
    super.initState();
    _tutorIndex = widget.initialTutorIndex;
    _progress = AnimationController(vsync: this, duration: _imageDuration);
    _notifyTutorViewed();
    _initMedia();
  }

  @override
  void dispose() {
    _progress.dispose();
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    super.dispose();
  }

  void _notifyTutorViewed() {
    widget.onTutorViewed?.call(_tutor.tutorId);
  }

  void _initMedia() {
    _progress.stop();
    _progress.value = 0;
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _videoController = null;

    if (_current.mediaType == 'video') {
      final controller = VideoPlayerController.networkUrl(Uri.parse(_current.mediaFile));
      _videoController = controller;
      controller.initialize().then((_) {
        if (!mounted || _videoController != controller) return;
        setState(() {});
        _progress.duration = controller.value.duration == Duration.zero
            ? _imageDuration
            : controller.value.duration;
        controller.play();
        controller.addListener(_onVideoTick);
      });
    } else {
      _progress.duration = _imageDuration;
      _progress.forward(from: 0).whenCompleteOrCancel(() {
        if (!mounted) return;
        if (_progress.status == AnimationStatus.completed) _advance();
      });
    }
  }

  void _onVideoTick() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    if (duration <= Duration.zero) return;
    final ratio = controller.value.position.inMilliseconds / duration.inMilliseconds;
    _progress.value = ratio.clamp(0.0, 1.0);
    if (controller.value.position >= duration) {
      controller.removeListener(_onVideoTick);
      _advance();
    }
  }

  void _advance() {
    if (_storyIndex + 1 < _tutor.stories.length) {
      setState(() => _storyIndex++);
      _initMedia();
    } else if (_tutorIndex + 1 < widget.tutors.length) {
      setState(() {
        _tutorIndex++;
        _storyIndex = 0;
      });
      _notifyTutorViewed();
      _initMedia();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _goBack() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _initMedia();
    } else if (_tutorIndex > 0) {
      setState(() {
        _tutorIndex--;
        _storyIndex = widget.tutors[_tutorIndex].stories.length - 1;
      });
      _notifyTutorViewed();
      _initMedia();
    }
  }

  void _onTapLeft() => _goBack();
  void _onTapRight() => _advance();

  void _onBookClass() {
    final id = _tutor.tutorId;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TutorProfileScreen(tutorId: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final stories = _tutor.stories;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (details) {
          final dx = details.globalPosition.dx;
          final width = MediaQuery.of(context).size.width;
          if (dx < width / 3) {
            _onTapLeft();
          } else if (dx > width * 2 / 3) {
            _onTapRight();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Story content
            if (_current.mediaType == 'video' && _videoController != null)
              _videoController!.value.isInitialized
                  ? FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _videoController!.value.size.width,
                        height: _videoController!.value.size.height,
                        child: VideoPlayer(_videoController!),
                      ),
                    )
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
            else
              Image.network(
                _current.mediaFile,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                ),
              ),

            // Top gradient
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 160,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
              ),
            ),

            // Bottom gradient
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 300,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
              ),
            ),

            // Progress indicators
            Positioned(
              top: topPadding + 8,
              left: 16,
              right: 16,
              child: AnimatedBuilder(
                animation: _progress,
                builder: (_, _) => Row(
                  children: List.generate(stories.length, (i) {
                    final double value;
                    if (i < _storyIndex) {
                      value = 1;
                    } else if (i == _storyIndex) {
                      value = _progress.value;
                    } else {
                      value = 0;
                    }
                    return Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: value,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),

            // Top bar: avatar + name + close
            Positioned(
              top: topPadding + 20,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  // Avatar — center crop for 2:3 aspect ratio
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: ClipOval(
                      child: _tutor.image != null && _tutor.image!.startsWith('http')
                          ? Image.network(
                              _tutor.image!,
                              fit: BoxFit.cover,
                              width: 40,
                              height: 40,
                              alignment: Alignment.topCenter,
                              errorBuilder: (_, _, _) => Container(
                                color: const Color(0xFF444444),
                                child: const Icon(Icons.person, color: Colors.white54, size: 20),
                              ),
                            )
                          : Container(
                              color: const Color(0xFF444444),
                              child: const Icon(Icons.person, color: Colors.white54, size: 20),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Name
                  Expanded(
                    child: Text(
                      _tutor.name,
                      style: const TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Close
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom: description + Book a class
            Positioned(
              bottom: bottomPadding + 16,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Description
                  if (_current.description != null && _current.description!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _current.description!,
                        style: const TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 14,
                          color: Color(0xFF272942),
                          height: 1.5,
                        ),
                      ),
                    ),

                  // Book a class button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _onBookClass,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF272942),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Book a class',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF272942),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
