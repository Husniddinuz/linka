import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'tutor_profile_screen.dart';
import 'home_screen.dart';

class StoryViewerScreen extends StatefulWidget {
  final int tutorId;
  final String tutorName;
  final String? tutorImage;
  final List<StoryData> stories;

  const StoryViewerScreen({
    super.key,
    required this.tutorId,
    required this.tutorName,
    this.tutorImage,
    required this.stories,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  int _currentIndex = 0;
  VideoPlayerController? _videoController;

  StoryData get _current => widget.stories[_currentIndex];

  @override
  void initState() {
    super.initState();
    _initMedia();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _initMedia() {
    _videoController?.dispose();
    _videoController = null;
    if (_current.mediaType == 'video') {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(_current.mediaFile))
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {});
          _videoController!.play();
          _videoController!.setLooping(true);
        });
    }
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.stories.length) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _currentIndex = index);
    _initMedia();
  }

  void _onTapLeft() => _goTo(_currentIndex - 1);
  void _onTapRight() => _goTo(_currentIndex + 1);

  void _onBookClass() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TutorProfileScreen(tutorId: widget.tutorId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

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
            if (widget.stories.length > 1)
              Positioned(
                top: topPadding + 8,
                left: 16,
                right: 16,
                child: Row(
                  children: List.generate(widget.stories.length, (i) {
                    return Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i <= _currentIndex
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),

            // Top bar: avatar + name + close
            Positioned(
              top: topPadding + (widget.stories.length > 1 ? 20 : 12),
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
                      child: widget.tutorImage != null && widget.tutorImage!.startsWith('http')
                          ? Image.network(
                              widget.tutorImage!,
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
                      widget.tutorName,
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
