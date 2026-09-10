import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/course.dart';
import '../services/course_service.dart';
import '../theme/app_colors.dart';
import '../widgets/course_card.dart';
import 'create_course_screen.dart';
import 'tutor_course_manage_screen.dart';

/// A tutor's own courses (any state), reached from the profile tab. Create new
/// ones with the FAB; tap one to manage it (roster, announcements, cancel).
class TutorMyCoursesScreen extends StatefulWidget {
  const TutorMyCoursesScreen({super.key});

  @override
  State<TutorMyCoursesScreen> createState() => _TutorMyCoursesScreenState();
}

class _TutorMyCoursesScreenState extends State<TutorMyCoursesScreen> {
  List<Course> _courses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await CourseService.fetchMyCourses();
      if (!mounted) return;
      setState(() {
        _courses = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateCourseScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _manage(Course course) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TutorCourseManageScreen(courseId: course.id),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Symbols.chevron_left_rounded, color: colors.textPrimary, size: 28),
        ),
        title: Text(
          'My Courses',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: colors.textPrimary,
        foregroundColor: colors.background,
        icon: const Icon(Symbols.add_rounded),
        label: const Text('Create course'),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.accentYellow))
          : _courses.isEmpty
              ? _EmptyState(colors: colors, onCreate: _create)
              : RefreshIndicator(
                  color: colors.textPrimary,
                  onRefresh: _load,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        itemCount: _courses.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (context, i) => CourseCard(
                          course: _courses[i],
                          accent: CourseCard.accentFor(_courses[i].id),
                          tutorView: true,
                          onTap: () => _manage(_courses[i]),
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AppColors colors;
  final VoidCallback onCreate;
  const _EmptyState({required this.colors, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.school_rounded, size: 56, color: colors.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No courses yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Create your first course — set a price, dates and seat limit, and students can enroll.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: colors.textTertiary),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                backgroundColor: colors.textPrimary,
                foregroundColor: colors.background,
              ),
              child: const Text('Create course'),
            ),
          ],
        ),
      ),
    );
  }
}
