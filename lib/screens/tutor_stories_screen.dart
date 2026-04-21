import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';
import '../services/api_service.dart';
import 'story_upload_screen.dart';

/// Tutor's own stories — shown as a 3-column grid with an "Add new story"
/// button at the top.
class TutorStoriesScreen extends StatefulWidget {
  const TutorStoriesScreen({super.key});

  @override
  State<TutorStoriesScreen> createState() => _TutorStoriesScreenState();
}

class _TutorStoriesScreenState extends State<TutorStoriesScreen> {
  List<_MyStory> _stories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.getList('/tutor/stories/my/');
      if (!mounted) return;
      setState(() {
        _stories = list
            .map((e) => _MyStory.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stories = [];
        _loading = false;
      });
    }
  }

  Future<void> _openUpload() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const StoryUploadScreen()),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'My stories',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF272942),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: _AddStoryButton(onTap: _openUpload),
            ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF272942),
                onRefresh: _load,
                child: _loading
                    ? const _GridSkeleton()
                    : _stories.isEmpty
                        ? const _EmptyGrid()
                        : _StoryGrid(stories: _stories),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add story button ────────────────────────────────────────────────────────

class _AddStoryButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddStoryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF272942),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Color(0xFFF5C542),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded,
                  color: Color(0xFF272942), size: 22),
            ),
            const SizedBox(width: 12),
            const Text(
              'Add new story',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            SvgPicture.asset(
              'assets/images/icons/story_active.svg',
              width: 22,
              height: 22,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Grids ───────────────────────────────────────────────────────────────────

class _StoryGrid extends StatelessWidget {
  final List<_MyStory> stories;
  const _StoryGrid({required this.stories});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.7,
      ),
      itemCount: stories.length,
      itemBuilder: (_, i) => _StoryTile(story: stories[i]),
    );
  }
}

class _StoryTile extends StatelessWidget {
  final _MyStory story;
  const _StoryTile({required this.story});

  @override
  Widget build(BuildContext context) {
    final hasUrl =
        story.mediaFile != null && story.mediaFile!.startsWith('http');
    final isVideo = story.mediaType == 'video';
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!hasUrl)
            const _TilePlaceholder()
          else if (isVideo)
            _VideoThumb(url: story.mediaFile!)
          else
            Image.network(
              story.mediaFile!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _TilePlaceholder(),
            ),
          if (isVideo)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoThumb extends StatefulWidget {
  final String url;
  const _VideoThumb({required this.url});

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      // Seek to 0 ensures the first frame is decoded and shown.
      await controller.seekTo(Duration.zero);
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const _TilePlaceholder();
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Container(color: const Color(0xFFEFEFF2));
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: c.value.size.width,
        height: c.value.size.height,
        child: VideoPlayer(c),
      ),
    );
  }
}

class _TilePlaceholder extends StatelessWidget {
  const _TilePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEFEFF2),
      child: const Icon(
        Icons.image_outlined,
        color: Color(0xFFAAAAAA),
        size: 28,
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.7,
      ),
      itemCount: 9,
      itemBuilder: (_, _) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _EmptyGrid extends StatelessWidget {
  const _EmptyGrid();

  @override
  Widget build(BuildContext context) {
    // 3x3 empty placeholder tiles so layout matches the loaded state.
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.7,
      ),
      itemCount: 9,
      itemBuilder: (_, _) => const _TilePlaceholder(),
    );
  }
}

// ─── Model ───────────────────────────────────────────────────────────────────

class _MyStory {
  final int id;
  final String? mediaFile;
  final String mediaType;
  final String? description;

  const _MyStory({
    required this.id,
    this.mediaFile,
    required this.mediaType,
    this.description,
  });

  factory _MyStory.fromJson(Map<String, dynamic> j) {
    return _MyStory(
      id: (j['id'] as num?)?.toInt() ?? 0,
      mediaFile: j['media_file'] as String?,
      mediaType: (j['media_type'] as String?) ?? 'photo',
      description: j['description'] as String?,
    );
  }
}
