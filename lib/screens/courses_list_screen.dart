import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/course_service.dart';
import '../theme/app_colors.dart';
import '../widgets/course_card.dart';
import 'course_detail_screen.dart';

/// The course catalogue, opened from the home "Courses" banner. A single
/// scrollable column of [CourseCard]s (courses carry rich metadata — price,
/// dates, seats — that reads better full-width than in a cramped grid).
class CoursesListScreen extends StatefulWidget {
  const CoursesListScreen({super.key});

  @override
  State<CoursesListScreen> createState() => _CoursesListScreenState();
}

class _CoursesListScreenState extends State<CoursesListScreen> {
  List<Course> _courses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await CourseService.fetchCourses();
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

  Future<void> _openCourse(Course course) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CourseDetailScreen(courseId: course.id)),
    );
    // Enrollment state may have changed while inside the detail screen.
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
          icon: Icon(Icons.chevron_left, color: colors.textPrimary, size: 28),
        ),
        title: Text(
          'Courses',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.accentYellow))
          : _courses.isEmpty
              ? _EmptyState(colors: colors)
              : RefreshIndicator(
                  color: colors.textPrimary,
                  onRefresh: _load,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        itemCount: _courses.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (context, i) => CourseCard(
                          course: _courses[i],
                          accent: CourseCard.accentFor(_courses[i].id),
                          onTap: () => _openCourse(_courses[i]),
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
  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined, size: 56, color: colors.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No courses available yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Check back soon — tutors are creating new courses.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
