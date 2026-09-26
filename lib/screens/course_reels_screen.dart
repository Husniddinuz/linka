import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/course_reel.dart';
import '../services/course_reels_resume_service.dart';
import '../services/course_reels_service.dart';
import '../theme/app_colors.dart';
import 'course_reels_feed_screen.dart';

const _languageKey = 'course_reels_language';

/// Opens the feed for [courseId], making it the student's current course.
Future<void> openCourseReel(
  BuildContext context, {
  required int courseId,
  int? lessonId,
}) {
  CourseReelsService.startCourse(courseId).catchError((_) {});
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          CourseReelsFeedScreen(courseId: courseId, initialLessonId: lessonId),
    ),
  );
}

/// Course Reels home: continue where you left off, pick a language, pick a
/// course.
class CourseReelsScreen extends StatefulWidget {
  const CourseReelsScreen({super.key});

  @override
  State<CourseReelsScreen> createState() => _CourseReelsScreenState();
}

class _CourseReelsScreenState extends State<CourseReelsScreen> {
  List<ReelLanguage> _languages = const [];
  List<ReelCourse> _courses = const [];
  ReelResume? _resume;
  String? _language;
  bool _loading = true;
  bool _loadingCourses = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      await CourseReelsResumeService.flush();
      final results = await Future.wait([
        CourseReelsService.fetchLanguages(),
        CourseReelsService.fetchResume(),
        SharedPreferences.getInstance(),
      ]);
      final languages = results[0] as List<ReelLanguage>;
      final resume = results[1] as ReelResume;
      final prefs = results[2] as SharedPreferences;
      final names = languages.map((l) => l.language).toList();
      String? pick(String? v) => v != null && names.contains(v) ? v : null;
      final language =
          pick(prefs.getString(_languageKey)) ??
          pick(resume.course?.language) ??
          (names.isEmpty ? null : names.first);
      if (!mounted) return;
      setState(() {
        _languages = languages;
        _resume = resume;
        _language = language;
      });
      await _loadCourses();
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadCourses() async {
    final language = _language;
    if (language == null) {
      setState(() => _courses = const []);
      return;
    }
    setState(() => _loadingCourses = true);
    try {
      final courses = await CourseReelsService.fetchCourses(language: language);
      if (!mounted || language != _language) return;
      setState(() => _courses = courses);
    } catch (_) {
      if (mounted) setState(() => _courses = const []);
    } finally {
      if (mounted) setState(() => _loadingCourses = false);
    }
  }

  Future<void> _selectLanguage(String language) async {
    if (language == _language) return;
    setState(() => _language = language);
    SharedPreferences.getInstance().then(
      (p) => p.setString(_languageKey, language),
    );
    await _loadCourses();
  }

  Future<void> _open(int courseId, {int? lessonId}) async {
    await openCourseReel(context, courseId: courseId, lessonId: lessonId);
    if (mounted) _load();
  }

  Future<void> _openSaved() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SavedReelsScreen()),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Symbols.arrow_back_rounded, color: c.textPrimary),
        ),
        title: Text(
          'Course Reels',
          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Saved lessons',
            onPressed: _openSaved,
            icon: Icon(Symbols.bookmark_rounded, color: c.textPrimary),
          ),
        ],
      ),
      body: _body(c),
    );
  }

  Widget _body(AppColors c) {
    if (_loading && _languages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return Center(
        child: TextButton(
          onPressed: _load,
          child: const Text('Couldn\'t load courses — retry'),
        ),
      );
    }
    if (_languages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No courses yet — check back soon.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, fontSize: 15),
          ),
        ),
      );
    }
    final resume = _resume;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          if (resume?.course != null) ...[
            ReelContinueCard(
              course: resume!.course!,
              lesson: resume.lesson,
              onTap: () =>
                  _open(resume.course!.id, lessonId: resume.lesson?.id),
            ),
            const SizedBox(height: 28),
          ],
          Text(
            'LANGUAGE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: c.textTertiary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in _languages)
                ChoiceChip(
                  label: Text(l.language),
                  selected: l.language == _language,
                  onSelected: (_) => _selectLanguage(l.language),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: l.language == _language ? c.onBrand : c.textPrimary,
                  ),
                  selectedColor: c.brand,
                  backgroundColor: c.surfaceAlt,
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'COURSES',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: c.textTertiary,
            ),
          ),
          const SizedBox(height: 10),
          if (_loadingCourses && _courses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_courses.isEmpty)
            Text(
              'No courses in this language yet.',
              style: TextStyle(color: c.textSecondary),
            )
          else
            for (final course in _courses) ...[
              _CourseTile(course: course, onTap: () => _open(course.id)),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

/// "Continue" card — used here and on the home screen.
class ReelContinueCard extends StatelessWidget {
  const ReelContinueCard({
    super.key,
    required this.course,
    required this.lesson,
    required this.onTap,
  });

  final ReelCourse course;
  final ReelLesson? lesson;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = lesson;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E8E4E), Color(0xFF27AE60), Color(0xFF45C77A)],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'CONTINUE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      course.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (l != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        l.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: course.completedFraction,
                        minHeight: 6,
                        color: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${course.completedCount} of ${course.lessonsCount} lessons completed',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Symbols.play_arrow_rounded,
                  fill: 1,
                  size: 32,
                  color: Color(0xFF27AE60),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({required this.course, required this.onTap});

  final ReelCourse course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 84,
                  child: course.coverUrl != null
                      ? Image.network(
                          course.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _coverFallback(c),
                        )
                      : _coverFallback(c),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        '${course.lessonsCount} lessons',
                        if (course.level.isNotEmpty) course.level,
                      ].join(' · '),
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: course.completedFraction,
                              minHeight: 6,
                              color: c.success,
                              backgroundColor: c.surfaceAlt,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          course.started
                              ? '${course.completedCount}/${course.lessonsCount}'
                              : 'Start',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: course.started ? c.textSecondary : c.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverFallback(AppColors c) => Container(
    color: c.surfaceAlt,
    alignment: Alignment.center,
    child: Icon(Symbols.play_circle_rounded, color: c.textTertiary, size: 28),
  );
}

/// Lessons the student bookmarked from the feed.
class SavedReelsScreen extends StatefulWidget {
  const SavedReelsScreen({super.key});

  @override
  State<SavedReelsScreen> createState() => _SavedReelsScreenState();
}

class _SavedReelsScreenState extends State<SavedReelsScreen> {
  List<ReelLesson>? _lessons;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final lessons = await CourseReelsService.fetchSaved();
      if (mounted) setState(() => _lessons = lessons);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Plays the saved lessons one after another, starting at [lessonId].
  Future<void> _play({int? lessonId}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourseReelsFeedScreen.saved(initialLessonId: lessonId),
      ),
    );
    // Lessons may have been unsaved in the feed.
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lessons = _lessons;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Symbols.arrow_back_rounded, color: c.textPrimary),
        ),
        title: Text(
          'Saved lessons',
          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (lessons != null && lessons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _play,
                icon: const Icon(Symbols.play_arrow_rounded),
                label: const Text(
                  'Play all',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      body: _failed
          ? Center(
              child: TextButton(
                onPressed: _load,
                child: const Text('Couldn\'t load — retry'),
              ),
            )
          : lessons == null
          ? const Center(child: CircularProgressIndicator())
          : lessons.isEmpty
          ? Center(
              child: Text(
                'Tap the bookmark on a lesson to keep it here.',
                style: TextStyle(color: c.textSecondary),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: lessons.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final lesson = lessons[i];
                  return ListTile(
                    onTap: () => _play(lessonId: lesson.id),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: c.border),
                    ),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 44,
                        height: 58,
                        child: lesson.posterUrl != null
                            ? Image.network(
                                lesson.posterUrl!,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: c.surfaceAlt,
                                child: Icon(
                                  Symbols.play_arrow_rounded,
                                  color: c.textTertiary,
                                ),
                              ),
                      ),
                    ),
                    title: Text(
                      lesson.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      lesson.courseTitle,
                      style: TextStyle(color: c.textSecondary),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Home-screen entry for students who haven't started a course yet.
class ReelsPromoBanner extends StatelessWidget {
  const ReelsPromoBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 132,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF272942), Color(0xFF3D4A8A), Color(0xFF5B7FD4)],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'COURSE REELS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Learn in short videos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Swipe, practise, and track every lesson',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Symbols.swipe_up_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
