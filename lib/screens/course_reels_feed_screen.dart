import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/course_reel.dart';
import '../services/course_reels_resume_service.dart';
import '../services/course_reels_service.dart';
import '../services/screen_security_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import '../widgets/reel_comments_sheet.dart';
import '../widgets/reel_progress_markers.dart';
import 'course_reels_map_screen.dart';
import 'reel_practice_screen.dart';

/// Share of a video that has to play before the lesson counts as watched.
/// Mirrors `WATCHED_THRESHOLD` in the backend.
const double _watchedThreshold = 0.9;

/// TikTok-style vertical feed of one course's lessons.
///
/// Opens at [initialLessonId] (or wherever the student left off) and seeks to
/// the saved position. The current, previous and next videos are kept
/// initialised so a swipe starts playing immediately; everything further away
/// is disposed.
class CourseReelsFeedScreen extends StatefulWidget {
  const CourseReelsFeedScreen({
    super.key,
    required this.courseId,
    this.initialLessonId,
  });

  final int courseId;
  final int? initialLessonId;

  @override
  State<CourseReelsFeedScreen> createState() => _CourseReelsFeedScreenState();
}

class _CourseReelsFeedScreenState extends State<CourseReelsFeedScreen>
    with WidgetsBindingObserver {
  ReelCourse? _course;
  List<ReelLesson> _lessons = const [];
  bool _loading = true;
  String? _error;

  PageController? _pageController;
  int _index = 0;

  final Map<int, VideoPlayerController> _controllers = {};
  final Set<int> _failed = {};

  /// Seek target for a lesson that hasn't finished initialising yet.
  final Map<int, Duration> _pendingSeek = {};

  /// True while the student paused on purpose; a swipe clears it.
  bool _userPaused = false;

  /// True while a pushed screen or sheet covers the feed.
  bool _covered = false;

  int _lastRecordMs = 0;

  /// In-flight refresh of the lessons' signed video links.
  Future<void>? _refreshingUrls;

  /// Lessons whose player already failed once on a fresh link.
  final Set<int> _retriedWithFreshUrl = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    ScreenSecurityService.protect();
    ScreenSecurityService.captured.addListener(_onCaptureChanged);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordCurrent(force: true);
    CourseReelsResumeService.flush();
    for (final c in _controllers.values) {
      c.removeListener(_onTick);
      c.dispose();
    }
    _pageController?.dispose();
    ScreenSecurityService.captured.removeListener(_onCaptureChanged);
    ScreenSecurityService.release();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final current = _controllers[_index];
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _recordCurrent(force: true);
      current?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _playIfAllowed(_index);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Anything a previous session couldn't send goes first, so the course
      // we fetch already reflects it.
      await CourseReelsResumeService.flush();
      final course = await CourseReelsService.fetchCourse(widget.courseId);
      if (!mounted) return;
      // Units of a section the student hasn't bought come without a video;
      // the course path is where they get unlocked.
      final lessons = course.lessons.where((l) => !l.locked).toList();
      final start = _startIndex(course, lessons);
      if (lessons.isNotEmpty) {
        final lesson = lessons[start];
        final seconds = CourseReelsResumeService.positionFor(
          lesson.id,
          lesson.progress.positionSeconds,
        );
        final duration = lesson.progress.durationSeconds;
        // A video that was nearly over restarts rather than resuming on
        // its last frame.
        if (seconds > 1 && (duration <= 0 || seconds < duration - 2)) {
          _pendingSeek[start] = Duration(
            milliseconds: (seconds * 1000).round(),
          );
        }
      }
      setState(() {
        _course = course;
        _lessons = lessons;
        _index = start;
        _pageController = PageController(initialPage: start);
        _loading = false;
      });
      if (lessons.isNotEmpty) _activate(start);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn\'t load this course. Check your connection.';
      });
    }
  }

  int _startIndex(ReelCourse course, List<ReelLesson> lessons) {
    int indexOf(int? id) =>
        id == null ? -1 : lessons.indexWhere((l) => l.id == id);
    for (final id in [
      widget.initialLessonId,
      CourseReelsResumeService.unsyncedLessonIn(course.id),
      course.lastLessonId,
    ]) {
      final i = indexOf(id);
      if (i >= 0) return i;
    }
    final firstOpen = lessons.indexWhere((l) => !l.progress.watched);
    return firstOpen >= 0 ? firstOpen : 0;
  }

  // --- Playback -----------------------------------------------------------

  VideoPlayerController? _controllerFor(int i) {
    if (i < 0 || i >= _lessons.length) return null;
    final existing = _controllers[i];
    if (existing != null) return existing;
    final lesson = _lessons[i];
    if (lesson.videoUrlExpiring) {
      // The signed link is (nearly) dead — get new ones, then try again.
      _refreshVideoUrls().then((_) {
        if (mounted && !_lessons[i].videoUrlExpiring) _activate(_index);
      });
      return null;
    }
    final url = lesson.videoUrl;
    if (url == null) {
      _failed.add(i);
      return null;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controllers[i] = controller;
    controller.setLooping(true);
    controller
        .initialize()
        .then((_) async {
          if (!mounted || _controllers[i] != controller) return;
          final seek = _pendingSeek.remove(i);
          if (seek != null) await controller.seekTo(seek);
          if (!mounted) return;
          setState(() {});
          if (i == _index) _playIfAllowed(i);
        })
        .catchError((_) {
          if (!mounted || _controllers[i] != controller) return;
          // A signed link can die early (clock skew, a replaced video): fetch
          // fresh links once before giving up on this lesson.
          if (_lessons[i].videoUrlExpiresAt != null &&
              _retriedWithFreshUrl.add(i)) {
            _dropController(i);
            _refreshVideoUrls().then((_) {
              if (mounted) _activate(_index);
            });
            return;
          }
          setState(() => _failed.add(i));
        });
    return controller;
  }

  void _dropController(int i) {
    final c = _controllers.remove(i);
    c?.removeListener(_onTick);
    c?.dispose();
  }

  /// Re-fetches the course for new signed video links. Calls coalesce.
  Future<void> _refreshVideoUrls() {
    return _refreshingUrls ??= () async {
      try {
        final fresh = await CourseReelsService.fetchCourse(widget.courseId);
        final byId = {for (final l in fresh.lessons) l.id: l};
        for (final lesson in _lessons) {
          final f = byId[lesson.id];
          if (f == null) continue;
          lesson
            ..videoUrl = f.videoUrl
            ..videoUrlExpiresAt = f.videoUrlExpiresAt;
        }
      } catch (_) {
        // Offline: the retry button tries again.
      } finally {
        _refreshingUrls = null;
      }
    }();
  }

  void _activate(int i) {
    for (final entry in _controllers.entries) {
      if (entry.key != i) entry.value.pause();
    }
    // Keep a window of three players; the rest are disposed.
    final keep = {i - 1, i, i + 1};
    for (final key in _controllers.keys.toList()) {
      if (!keep.contains(key)) {
        final c = _controllers.remove(key)!;
        c.removeListener(_onTick);
        c.dispose();
      }
    }
    final current = _controllerFor(i);
    current?.removeListener(_onTick);
    current?.addListener(_onTick);
    _controllerFor(i + 1);
    _controllerFor(i - 1);
    _playIfAllowed(i);
  }

  void _playIfAllowed(int i) {
    final c = _controllers[i];
    if (c == null || !c.value.isInitialized) return;
    if (_userPaused || _covered || i != _index) return;
    if (ScreenSecurityService.captured.value) return;
    c.play();
  }

  /// iOS screen recording/mirroring started or stopped: hide and pause the
  /// video while it's on, resume when it ends.
  void _onCaptureChanged() {
    if (!mounted) return;
    if (ScreenSecurityService.captured.value) {
      _recordCurrent(force: true);
      for (final c in _controllers.values) {
        c.pause();
      }
    } else {
      _playIfAllowed(_index);
    }
    setState(() {});
  }

  void _onPageChanged(int i) {
    _recordCurrent(force: true);
    setState(() {
      _index = i;
      _userPaused = false;
    });
    if (i < _lessons.length) {
      _activate(i);
    } else {
      // The end-of-course page — nothing plays.
      for (final c in _controllers.values) {
        c.pause();
      }
    }
  }

  void _onTick() {
    _recordCurrent();
  }

  /// Saves the current position locally (and queues it for the server).
  /// Throttled to once a second unless [force]d.
  void _recordCurrent({bool force = false}) {
    if (_index >= _lessons.length) return;
    final c = _controllers[_index];
    if (c == null || !c.value.isInitialized) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastRecordMs < 1000) return;
    _lastRecordMs = now;

    final lesson = _lessons[_index];
    final position = c.value.position.inMilliseconds / 1000;
    final duration = c.value.duration.inMilliseconds / 1000;
    final reachedEnd = duration > 0 && position >= duration * _watchedThreshold;
    CourseReelsResumeService.record(
      courseId: widget.courseId,
      lessonId: lesson.id,
      positionSeconds: position,
      durationSeconds: duration,
      completed: reachedEnd,
    );
    if (reachedEnd && !lesson.progress.watched && mounted) {
      setState(() {
        lesson.progress = lesson.progress.markWatched(
          practiceRequired: lesson.practiceRequired,
        );
      });
    }
  }

  void _togglePlay() {
    final c = _controllers[_index];
    if (c == null || !c.value.isInitialized) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _userPaused = true;
        _recordCurrent(force: true);
      } else {
        _userPaused = false;
        c.play();
      }
    });
  }

  Future<void> _retry(int i) async {
    _dropController(i);
    setState(() => _failed.remove(i));
    await _refreshVideoUrls();
    if (mounted) _activate(_index);
  }

  /// Pauses for a pushed screen/sheet and resumes afterwards.
  Future<T?> _covering<T>(Future<T?> Function() open) async {
    _covered = true;
    _recordCurrent(force: true);
    _controllers[_index]?.pause();
    try {
      return await open();
    } finally {
      _covered = false;
      if (mounted) _playIfAllowed(_index);
    }
  }

  // --- Actions ------------------------------------------------------------

  Future<void> _toggleLike(ReelLesson lesson) async {
    HapticFeedback.lightImpact();
    final want = !lesson.liked;
    setState(() {
      lesson.liked = want;
      lesson.likeCount = (lesson.likeCount + (want ? 1 : -1)).clamp(0, 1 << 30);
    });
    try {
      final (liked, count) = await CourseReelsService.setLiked(lesson.id, want);
      if (!mounted) return;
      setState(() {
        lesson.liked = liked;
        lesson.likeCount = count;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        lesson.liked = !want;
        lesson.likeCount = (lesson.likeCount + (want ? -1 : 1)).clamp(
          0,
          1 << 30,
        );
      });
      AppNotify.show(context, message: 'Couldn\'t update like');
    }
  }

  Future<void> _toggleSave(ReelLesson lesson) async {
    HapticFeedback.lightImpact();
    final want = !lesson.saved;
    setState(() => lesson.saved = want);
    try {
      final saved = await CourseReelsService.setSaved(lesson.id, want);
      if (!mounted) return;
      setState(() => lesson.saved = saved);
      AppNotify.show(
        context,
        message: saved ? 'Saved' : 'Removed from saved',
        type: NotifyType.success,
        duration: const Duration(milliseconds: 1400),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => lesson.saved = !want);
      AppNotify.show(context, message: 'Couldn\'t update saved');
    }
  }

  Future<void> _openComments(ReelLesson lesson) async {
    await _covering<void>(() => showReelCommentsSheet(context, lesson: lesson));
    if (mounted) setState(() {});
  }

  Future<void> _openPractice(ReelLesson lesson) async {
    await _covering<void>(
      () => Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => ReelPracticeScreen(lesson: lesson)),
      ),
    );
    // The practice screen wrote the new progress onto the lesson.
    if (mounted) setState(() {});
  }

  Future<void> _openMap() async {
    final course = _course;
    if (course == null) return;
    final target = await _covering<int>(
      () => Navigator.push<int>(
        context,
        MaterialPageRoute(
          builder: (_) => CourseReelsMapScreen(
            course: course,
            lessons: _lessons,
            currentIndex: _index.clamp(0, _lessons.length - 1),
          ),
        ),
      ),
    );
    if (!mounted) return;
    // The map may have opened practice; redraw its markers here too.
    setState(() {});
    if (target != null && target != _index) {
      _pageController?.jumpToPage(target);
    }
  }

  // --- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(child: _body()),
            if (ScreenSecurityService.captured.value)
              const Positioned.fill(child: _CaptureShield()),
            _TopBar(
              title: _course?.title ?? '',
              subtitle: _lessons.isEmpty || _index >= _lessons.length
                  ? ''
                  : 'Lesson ${_index + 1} of ${_lessons.length}',
              onBack: () => Navigator.pop(context),
              onMap: _course == null || _lessons.isEmpty ? null : _openMap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return _Message(
        icon: Symbols.wifi_off_rounded,
        text: _error!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }
    if (_lessons.isEmpty) {
      return const _Message(
        icon: Symbols.movie_rounded,
        text: 'No lessons in this course yet.',
      );
    }
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: _lessons.length + 1,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, i) {
        if (i == _lessons.length) {
          return _EndPage(
            completed: _lessons.where((l) => l.progress.completed).length,
            total: _lessons.length,
            onMap: _openMap,
          );
        }
        final lesson = _lessons[i];
        return _ReelPage(
          lesson: lesson,
          number: i + 1,
          controller: _controllers[i],
          failed: _failed.contains(i),
          onTap: _togglePlay,
          onRetry: () => _retry(i),
          onLike: () => _toggleLike(lesson),
          onComment: () => _openComments(lesson),
          onSave: () => _toggleSave(lesson),
          onPractice: lesson.hasPractice ? () => _openPractice(lesson) : null,
        );
      },
    );
  }
}

/// Covers the video while iOS reports the screen as recorded or mirrored.
class _CaptureShield extends StatelessWidget {
  const _CaptureShield();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          color: Colors.black.withValues(alpha: 0.7),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.screen_record_rounded,
                size: 48,
                color: Colors.white,
              ),
              SizedBox(height: 14),
              Text(
                'Video hidden while your screen is being recorded or shared',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Stop recording to keep watching.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onMap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback? onMap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 16),
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(
                    Symbols.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                if (onMap != null)
                  TextButton.icon(
                    onPressed: onMap,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Symbols.route_rounded, size: 18),
                    label: const Text(
                      'Map',
                      style: TextStyle(fontWeight: FontWeight.w700),
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

class _ReelPage extends StatelessWidget {
  const _ReelPage({
    required this.lesson,
    required this.number,
    required this.controller,
    required this.failed,
    required this.onTap,
    required this.onRetry,
    required this.onLike,
    required this.onComment,
    required this.onSave,
    required this.onPractice,
  });

  final ReelLesson lesson;
  final int number;
  final VideoPlayerController? controller;
  final bool failed;
  final VoidCallback onTap;
  final VoidCallback onRetry;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onSave;
  final VoidCallback? onPractice;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (lesson.posterUrl != null)
          Image.network(
            lesson.posterUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        if (c != null)
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (context, value, _) {
              if (!value.isInitialized) {
                return failed
                    ? const SizedBox.shrink()
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
              }
              return FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: value.size.width,
                  height: value.size.height,
                  child: VideoPlayer(c),
                ),
              );
            },
          ),
        if (failed)
          _Message(
            icon: Symbols.error_rounded,
            text: 'This video couldn\'t be played.',
            actionLabel: 'Retry',
            onAction: onRetry,
          ),
        // Tap anywhere to pause/play.
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onTap,
          child: c == null
              ? const SizedBox.expand()
              : ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: c,
                  builder: (context, value, _) => AnimatedOpacity(
                    opacity: value.isInitialized && !value.isPlaying ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Symbols.play_arrow_rounded,
                          fill: 1,
                          size: 44,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        // Bottom scrim so white text stays readable on bright video.
        IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 320,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 10, 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _Caption(lesson: lesson, number: number),
                    ),
                    const SizedBox(width: 8),
                    _ActionRail(
                      lesson: lesson,
                      onLike: onLike,
                      onComment: onComment,
                      onSave: onSave,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _PracticeButton(lesson: lesson, onTap: onPractice),
                ),
                const SizedBox(height: 12),
                if (c != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: VideoProgressIndicator(
                        c,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        colors: VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white.withValues(alpha: 0.35),
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.lesson, required this.number});

  final ReelLesson lesson;
  final int number;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'LESSON $number',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ReelProgressMarkers(
              progress: lesson.progress,
              practiceRequired: lesson.practiceRequired,
              size: 18,
              onDark: true,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          lesson.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        if (lesson.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            lesson.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionRail extends StatelessWidget {
  const _ActionRail({
    required this.lesson,
    required this.onLike,
    required this.onComment,
    required this.onSave,
  });

  final ReelLesson lesson;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailButton(
          icon: Symbols.favorite_rounded,
          filled: lesson.liked,
          color: lesson.liked ? const Color(0xFFFF4D67) : Colors.white,
          label: _compact(lesson.likeCount),
          semantic: lesson.liked ? 'Unlike' : 'Like',
          onTap: onLike,
        ),
        const SizedBox(height: 16),
        _RailButton(
          icon: Symbols.chat_bubble_rounded,
          label: _compact(lesson.commentCount),
          semantic: 'Comments',
          onTap: onComment,
        ),
        const SizedBox(height: 16),
        _RailButton(
          icon: Symbols.bookmark_rounded,
          filled: lesson.saved,
          color: lesson.saved ? context.colors.accentYellow : Colors.white,
          label: lesson.saved ? 'Saved' : 'Save',
          semantic: lesson.saved ? 'Remove from saved' : 'Save',
          onTap: onSave,
        ),
      ],
    );
  }

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.semantic,
    required this.onTap,
    this.filled = false,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final String semantic;
  final VoidCallback onTap;
  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantic,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 56,
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.32),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, fill: filled ? 1 : 0, size: 26, color: color),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PracticeButton extends StatelessWidget {
  const _PracticeButton({required this.lesson, required this.onTap});

  final ReelLesson lesson;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final green = context.colors.success;
    final done = lesson.progress.practiceCompleted;
    final enabled = onTap != null;
    final label = !enabled
        ? 'No practice for this lesson'
        : done
        ? 'Practice again'
        : 'Practice · ${lesson.exerciseCount} '
              '${lesson.exerciseCount == 1 ? 'task' : 'tasks'}';
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.14),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        icon: Icon(
          done ? Symbols.task_alt_rounded : Symbols.edit_note_rounded,
          size: 22,
        ),
        label: Text(label),
      ),
    );
  }
}

class _EndPage extends StatelessWidget {
  const _EndPage({
    required this.completed,
    required this.total,
    required this.onMap,
  });

  final int completed;
  final int total;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) {
    final allDone = completed == total;
    return Container(
      color: context.colors.coachStage,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            allDone ? Symbols.emoji_events_rounded : Symbols.flag_rounded,
            size: 64,
            color: context.colors.accentYellow,
          ),
          const SizedBox(height: 16),
          Text(
            allDone ? 'Course complete!' : 'You reached the last lesson',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            allDone
                ? 'Every lesson watched and practised.'
                : '$completed of $total lessons completed. '
                      'Finish the practice to turn every lesson green.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onMap,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: context.colors.coachStage,
              minimumSize: const Size(200, 48),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Symbols.route_rounded),
            label: const Text(
              'Open progress map',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.white70),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  shape: const StadiumBorder(),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
