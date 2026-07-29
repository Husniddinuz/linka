import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/social.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../widgets/app_notify.dart';
import 'tutor_profile_screen.dart';
import 'home_screen.dart';
import 'public_profile_screen.dart';

class StoryTutor {
  final int tutorId;

  /// The author's **user** id, for opening their public profile and for
  /// deciding whether these stories are the viewer's own. Null for Linka's
  /// stories and for tutor-feed rows, which carry a tutor profile id only.
  final int? userId;

  final String name;
  final String? image;
  final List<StoryData> stories;

  /// Whether the student can book a class with this tutor. Backend sends this
  /// via `is_enrollable`; defaults to true until the field is present.
  final bool isEnrollable;

  /// Platform-wide "Linka" story (backend sends `tutor_id: null`). These have
  /// no tutor profile image, so the avatar falls back to the Linka app logo.
  final bool isLinka;
  const StoryTutor({
    required this.tutorId,
    this.userId,
    required this.name,
    this.image,
    required this.stories,
    this.isEnrollable = true,
    this.isLinka = false,
  });
}

class StoryViewerScreen extends StatefulWidget {
  final List<StoryTutor> tutors;
  final int initialTutorIndex;
  final int initialStoryIndex;
  /// Fired when a ring is reached, with the ring itself.
  ///
  /// Passes the [StoryTutor] rather than an id because ids are no longer unique
  /// across the rail: followed accounts group under a user id and tutors under
  /// a tutor profile id, so "tutorId 0" now matches several rings.
  final void Function(StoryTutor tutor)? onTutorViewed;

  const StoryViewerScreen({
    super.key,
    required this.tutors,
    this.initialTutorIndex = 0,
    this.initialStoryIndex = 0,
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

  /// Vertical offset while the user is swiping down to dismiss.
  double _dragOffset = 0;

  // Preloaded controllers keyed by media URL.
  final Map<String, VideoPlayerController> _preloadedVideos = {};

  StoryTutor get _tutor => widget.tutors[_tutorIndex];
  StoryData get _current => _tutor.stories[_storyIndex];

  /// True while a delete is in flight, so the control cannot be double-fired.
  bool _deleting = false;

  /// Only the author can take a story down, and only the followers-only kind:
  /// tutor and Linka stories live in a different table with a different owner.
  bool get _canDeleteCurrent =>
      _current.source == StorySource.social &&
      _tutor.userId != null &&
      _tutor.userId == UserService.current?.id;

  void _openAuthorProfile() {
    final userId = _tutor.userId;
    if (userId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(
          userId: userId,
          initialName: _tutor.name.replaceAll('\n', ' '),
          initialImage: _tutor.image,
        ),
      ),
    );
  }

  /// Deleting from the player rather than only from the profile screen: this is
  /// where you are when you decide a story should come down, and sending you
  /// elsewhere to do it is how a story you regret stays up for 24 hours.
  ///
  /// Confirmed first — it is destructive, immediate, and sits next to the close
  /// button on a surface driven by taps.
  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this story?'),
        content: const Text('It will disappear for everyone right away.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await SocialService.deleteStory(_current.id);
      if (!mounted) return;
      // Closes rather than advancing: the rail behind is about to be rebuilt
      // without this story, and advancing into a stale list is how the viewer
      // ends up playing something that no longer exists.
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      AppNotify.show(context, message: 'Could not delete the story.');
    }
  }

  @override
  void initState() {
    super.initState();
    _tutorIndex = widget.initialTutorIndex;
    _storyIndex = widget.initialStoryIndex;
    _progress = AnimationController(vsync: this, duration: _imageDuration);
    _notifyTutorViewed();
    _initMedia();
  }

  @override
  void dispose() {
    _progress.dispose();
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    for (final ctrl in _preloadedVideos.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _preloadNext() {
    if (!mounted) return;
    final nextStories = <StoryData>[];
    if (_storyIndex + 1 < _tutor.stories.length) {
      nextStories.add(_tutor.stories[_storyIndex + 1]);
    }
    if (_tutorIndex + 1 < widget.tutors.length) {
      nextStories.add(widget.tutors[_tutorIndex + 1].stories.first);
    }
    for (final story in nextStories) {
      if (story.mediaType == 'video') {
        if (!_preloadedVideos.containsKey(story.mediaFile)) {
          final ctrl = VideoPlayerController.networkUrl(
            Uri.parse(story.mediaFile),
          );
          _preloadedVideos[story.mediaFile] = ctrl;
          ctrl.initialize();
        }
      } else {
        precacheImage(NetworkImage(story.mediaFile), context);
      }
    }
  }

  void _notifyTutorViewed() {
    widget.onTutorViewed?.call(_tutor);
  }

  void _initMedia() {
    _progress.stop();
    _progress.value = 0;
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _videoController = null;

    if (_current.mediaType == 'video') {
      final url = _current.mediaFile;
      final preloaded = _preloadedVideos.remove(url);
      final controller =
          preloaded ?? VideoPlayerController.networkUrl(Uri.parse(url));
      _videoController = controller;

      void startPlaying() {
        _progress.duration = controller.value.duration == Duration.zero
            ? _imageDuration
            : controller.value.duration;
        controller.play();
        controller.addListener(_onVideoTick);
      }

      if (preloaded != null && preloaded.value.isInitialized) {
        setState(() {});
        startPlaying();
      } else {
        controller.initialize().then((_) {
          if (!mounted || _videoController != controller) return;
          setState(() {});
          startPlaying();
        });
      }
    } else {
      _progress.duration = _imageDuration;
      _progress.forward(from: 0).whenCompleteOrCancel(() {
        if (!mounted) return;
        if (_progress.status == AnimationStatus.completed) _advance();
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _preloadNext();
    });
  }

  void _onVideoTick() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    if (duration <= Duration.zero) return;
    final ratio =
        controller.value.position.inMilliseconds / duration.inMilliseconds;
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

  void _pause() {
    _progress.stop();
    _videoController?.pause();
  }

  void _resume() {
    if (_videoController != null) {
      _videoController!.play();
    } else if (_progress.status != AnimationStatus.completed) {
      _progress.forward().whenCompleteOrCancel(() {
        if (!mounted) return;
        if (_progress.status == AnimationStatus.completed) _advance();
      });
    }
  }

  void _onVerticalDragStart(DragStartDetails details) => _pause();

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final next = _dragOffset + details.delta.dy;
    setState(() => _dragOffset = next < 0 ? 0 : next);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 120 || velocity > 700) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _dragOffset = 0);
    _resume();
  }

  void _onBookClass() {
    final id = _tutor.tutorId;
    Navigator.of(context).pop();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => TutorProfileScreen(tutorId: id)));
  }

  /// Header avatar: Linka logo for platform stories, the tutor's profile photo
  /// otherwise, falling back to a person icon.
  Widget _buildAvatar() {
    if (_tutor.isLinka) {
      return Container(
        width: 40,
        height: 40,
        color: Colors.white,
        padding: const EdgeInsets.all(6),
        child: Image.asset(
          'assets/images/branding/new-logo.png',
          fit: BoxFit.contain,
        ),
      );
    }
    final hasImage = _tutor.image != null && _tutor.image!.startsWith('http');
    if (hasImage) {
      return Image.network(
        _tutor.image!,
        fit: BoxFit.cover,
        width: 40,
        height: 40,
        alignment: Alignment.topCenter,
        errorBuilder: (_, _, _) => _avatarFallback(),
      );
    }
    return _avatarFallback();
  }

  Widget _avatarFallback() => Container(
    color: const Color(0xFF444444),
    child: const Icon(Icons.person, color: Colors.white54, size: 20),
  );

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final stories = _tutor.stories;

    final screenHeight = MediaQuery.of(context).size.height;
    final dragProgress = (_dragOffset / screenHeight).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1 - dragProgress * 0.6),
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
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_dragOffset > 0 ? 16 : 0),
            child: Stack(
              fit: StackFit.expand,
              children: [
            // Story content
            if (_current.mediaType == 'video' && _videoController != null)
              _videoController!.value.isInitialized
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
                      ),
                    )
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
            else
              Center(
                child: Image.network(
                  _current.mediaFile,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
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
                  // Avatar and name open the author's public profile — a ring
                  // names somebody with an account, and this is the way to it.
                  // Linka and tutor-feed rows carry no user id and stay inert.
                  GestureDetector(
                    onTap: _tutor.userId == null ? null : _openAuthorProfile,
                    behavior: HitTestBehavior.opaque,
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
                          child: ClipOval(child: _buildAvatar()),
                        ),
                        const SizedBox(width: 10),
                      ],
                    ),
                  ),
                  // Name
                  Expanded(
                    child: GestureDetector(
                      onTap: _tutor.userId == null ? null : _openAuthorProfile,
                      behavior: HitTestBehavior.opaque,
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
                  ),
                  // Delete — only your own social stories. A tutor story comes
                  // down from the tutor's own Stories tab, and Linka's are not
                  // yours at all.
                  if (_canDeleteCurrent) ...[
                    GestureDetector(
                      onTap: _deleting ? null : _confirmDelete,
                      child: Container(
                        width: 36,
                        height: 36,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
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
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 22,
                      ),
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
                  if (_current.description != null &&
                      _current.description!.isNotEmpty)
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

                  // Book a class button — only when the tutor is enrollable
                  if (_tutor.isEnrollable)
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
        ),
      ),
    );
  }
}
