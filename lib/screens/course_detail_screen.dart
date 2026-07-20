import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/course.dart';
import '../services/api_service.dart';
import '../services/course_service.dart';
import '../theme/app_colors.dart';
import '../widgets/cached_avatar.dart';
import '../widgets/course_card.dart';
import 'payment_topup_screen.dart';

/// A live-cohort course: banner, price/dates/seats, description, and the
/// enroll action. Once enrolled (or for the owning tutor) it also reveals the
/// "course room" — the tutor's shared link + announcements.
class CourseDetailScreen extends StatefulWidget {
  final int courseId;
  const CourseDetailScreen({super.key, required this.courseId});

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  Course? _course;
  bool _loading = true;
  bool _enrolling = false;

  Color get _accent => CourseCard.accentFor(widget.courseId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final course = await CourseService.fetchCourse(widget.courseId);
      if (!mounted) return;
      setState(() {
        _course = course;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _enroll() async {
    final course = _course;
    if (course == null || _enrolling) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text('Enroll in this course?',
            style: TextStyle(color: context.colors.textPrimary, fontSize: 18)),
        content: Text(
          course.isFree
              ? 'You will get a seat in "${course.title}".'
              : '${course.priceLabel} will be charged from your wallet for a seat in "${course.title}".',
          style: TextStyle(color: context.colors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: context.colors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(course.isFree ? 'Enroll' : 'Pay & enroll',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _enrolling = true);
    try {
      await CourseService.enroll(course.id);
      if (!mounted) return;
      _showSnack('Enrolled — see you in class!');
      await _load();
    } on InsufficientBalanceException {
      if (!mounted) return;
      await _promptTopUp();
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }

  Future<void> _promptTopUp() async {
    final goTopUp = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text('Not enough balance',
            style: TextStyle(color: context.colors.textPrimary, fontSize: 18)),
        content: Text(
          'Your wallet balance is too low to enroll. Top up your wallet and try again.',
          style: TextStyle(color: context.colors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Later',
                style: TextStyle(color: context.colors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Top up',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (goTopUp != true || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PaymentTopUpScreen()),
    );
    if (mounted) _load();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _showSnack('Could not open the link');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final course = _course;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.chevron_left, color: colors.textPrimary, size: 28),
        ),
        title: Text('Course',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.accentYellow))
          : course == null
              ? Center(
                  child: Text('Course not available',
                      style: TextStyle(color: colors.textTertiary, fontSize: 16)),
                )
              : _buildBody(course, colors),
      bottomNavigationBar: (course == null || _loading)
          ? null
          : _buildCta(course, colors),
    );
  }

  Widget _buildBody(Course course, AppColors colors) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CoverBand(course: course, accent: _accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (course.category.isNotEmpty) ...[
                      _Chip(label: course.category.toUpperCase(), accent: _accent),
                      const SizedBox(width: 8),
                    ],
                    _Chip(
                      label: course.priceLabel,
                      accent: colors.success,
                      filled: true,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  course.title,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    CachedAvatar(imageUrl: course.tutorImageUrl, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        course.tutorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _InfoRow(
                  icon: Symbols.calendar_month_rounded,
                  label: course.dateRangeLabel,
                  colors: colors,
                ),
                if (course.scheduleDetails.isNotEmpty)
                  _InfoRow(
                    icon: Symbols.schedule_rounded,
                    label: course.scheduleDetails,
                    colors: colors,
                  ),
                _InfoRow(
                  icon: Symbols.group_rounded,
                  label: course.isFull
                      ? 'Sold out (${course.maxStudents} seats)'
                      : '${course.seatsLeft} of ${course.maxStudents} seats left',
                  colors: colors,
                  emphasize: course.isFull,
                ),
                if (course.description.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    course.description,
                    style: TextStyle(
                      fontSize: 15,
                      color: colors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                ],
                if (course.isEnrolled || course.isOwner) ...[
                  const SizedBox(height: 24),
                  _RoomSection(
                    course: course,
                    colors: colors,
                    onOpenLink: _openLink,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCta(Course course, AppColors colors) {
    // Owners manage from "My Courses"; here they just see the room above.
    if (course.isOwner) return const SizedBox.shrink();

    String? disabledLabel;
    if (course.isCancelled) {
      disabledLabel = 'This course was cancelled';
    } else if (course.isEnrolled) {
      disabledLabel = "You're enrolled";
    } else if (course.isFull) {
      disabledLabel = 'Sold out';
    } else if (!course.enrollmentOpen) {
      disabledLabel = 'Enrollment closed';
    }

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        height: 52,
        child: disabledLabel != null
            ? _DisabledButton(
                label: disabledLabel,
                enrolled: course.isEnrolled,
                colors: colors,
              )
            : FilledButton(
                onPressed: _enrolling ? null : _enroll,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.textPrimary,
                  foregroundColor: colors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _enrolling
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: colors.background,
                        ),
                      )
                    : Text(
                        course.isFree
                            ? 'Enroll for free'
                            : 'Enroll · ${course.priceLabel}',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
      ),
    );
  }
}

// ─── Pieces ──────────────────────────────────────────────────────────────────

class _CoverBand extends StatelessWidget {
  final Course course;
  final Color accent;
  const _CoverBand({required this.course, required this.accent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, Color.lerp(accent, Colors.black, 0.32)!],
              ),
            ),
          ),
          Positioned(
            top: -30,
            right: -30,
            child: _circle(150, Colors.white.withValues(alpha: 0.10)),
          ),
          if (course.bannerUrl != null)
            Image.network(
              course.bannerUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          if (course.bannerUrl == null)
            const Center(
              child: Icon(Symbols.school_rounded, size: 52, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _circle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final Color accent;
  final bool filled;
  const _Chip({required this.label, required this.accent, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? accent : accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: filled ? Colors.white : accent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppColors colors;
  final bool emphasize;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.colors,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final color = emphasize ? colors.error : colors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomSection extends StatelessWidget {
  final Course course;
  final AppColors colors;
  final void Function(String url) onOpenLink;
  const _RoomSection({
    required this.course,
    required this.colors,
    required this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.meeting_room_rounded, size: 20, color: colors.textPrimary),
              const SizedBox(width: 8),
              Text(
                'Course room',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (course.sharedLink.isNotEmpty)
            GestureDetector(
              onTap: () => onOpenLink(course.sharedLink),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Icon(Symbols.link_rounded, size: 18, color: colors.accentBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        course.sharedLink,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: colors.accentBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Symbols.open_in_new_rounded, size: 16, color: colors.textTertiary),
                  ],
                ),
              ),
            )
          else
            Text(
              'The tutor will share a join link here.',
              style: TextStyle(fontSize: 13, color: colors.textTertiary),
            ),
          const SizedBox(height: 16),
          Text(
            'ANNOUNCEMENTS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          if (course.announcements.isEmpty)
            Text(
              'No announcements yet.',
              style: TextStyle(fontSize: 13, color: colors.textTertiary),
            )
          else
            ...course.announcements.map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.text,
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    if (a.createdAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${a.createdAt!.day}/${a.createdAt!.month}/${a.createdAt!.year}',
                          style: TextStyle(fontSize: 11, color: colors.textTertiary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DisabledButton extends StatelessWidget {
  final String label;
  final bool enrolled;
  final AppColors colors;
  const _DisabledButton({
    required this.label,
    required this.enrolled,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final bg = enrolled ? colors.successBg : colors.surfaceAlt;
    final fg = enrolled ? colors.success : colors.textTertiary;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (enrolled) ...[
            Icon(Symbols.check_circle_rounded, size: 18, color: fg),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}
