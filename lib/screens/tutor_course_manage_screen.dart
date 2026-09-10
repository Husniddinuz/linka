import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/course.dart';
import '../services/api_service.dart';
import '../services/course_service.dart';
import '../theme/app_colors.dart';
import '../widgets/cached_avatar.dart';
import 'channel_chat_screen.dart';
import 'chats_screen.dart';
import 'create_course_screen.dart';
import 'lesson_meeting_screen.dart';

/// The tutor's control panel for one of their courses: overview + roster,
/// post announcements, edit details, and cancel (which refunds all enrollees).
class TutorCourseManageScreen extends StatefulWidget {
  final int courseId;
  const TutorCourseManageScreen({super.key, required this.courseId});

  @override
  State<TutorCourseManageScreen> createState() =>
      _TutorCourseManageScreenState();
}

class _TutorCourseManageScreenState extends State<TutorCourseManageScreen> {
  Course? _course;
  List<CourseEnrollmentRow> _roster = [];
  bool _loading = true;
  final _announce = TextEditingController();
  bool _posting = false;
  bool _joining = false;

  Future<void> _join() async {
    final course = _course;
    if (course == null || _joining) return;
    setState(() => _joining = true);
    try {
      final info = await CourseService.joinSession(course.id);
      if (!mounted) return;
      if (info.roomUrl.isEmpty) {
        _showSnack('Could not get the room. Please try again.');
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LessonMeetingScreen(
            roomUrl: info.roomUrl,
            token: info.token,
            tutorName: course.tutorName,
          ),
        ),
      );
    } on SessionNotLiveException catch (e) {
      if (mounted) _showSnack(e.message);
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _announce.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final course = await CourseService.fetchCourse(widget.courseId);
      List<CourseEnrollmentRow> roster = [];
      try {
        roster = await CourseService.fetchEnrollments(widget.courseId);
      } catch (_) {
        // Roster is best-effort; keep the page usable if it fails.
      }
      if (!mounted) return;
      setState(() {
        _course = course;
        _roster = roster.where((r) => r.status == 'paid').toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _postAnnouncement() async {
    final text = _announce.text.trim();
    if (text.isEmpty || _posting) return;
    FocusScope.of(context).unfocus();
    setState(() => _posting = true);
    try {
      await CourseService.postAnnouncement(widget.courseId, text);
      _announce.clear();
      await _load();
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _edit() async {
    final course = _course;
    if (course == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CreateCourseScreen(existing: course)),
    );
    if (changed == true) _load();
  }

  Future<void> _cancel() async {
    final course = _course;
    if (course == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text('Cancel this course?',
            style: TextStyle(color: context.colors.textPrimary, fontSize: 18)),
        content: Text(
          course.enrolledCount > 0
              ? 'All ${course.enrolledCount} enrolled students will be refunded to their wallets. This cannot be undone.'
              : 'This course will be cancelled. This cannot be undone.',
          style: TextStyle(color: context.colors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep it',
                style: TextStyle(color: context.colors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancel course',
                style: TextStyle(
                    color: context.colors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await CourseService.cancelCourse(widget.courseId);
      if (!mounted) return;
      _showSnack('Course cancelled — students refunded');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
          icon: Icon(Symbols.chevron_left_rounded, color: colors.textPrimary, size: 28),
        ),
        title: Text('Manage course',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          // Only the primary tutor may edit; a co-tutor manages read-only.
          if (course != null && !course.isCancelled && course.isPrimaryTutor)
            IconButton(
              onPressed: _edit,
              icon: Icon(Symbols.edit_rounded, color: colors.textPrimary),
              tooltip: 'Edit',
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.accentYellow))
          : course == null
              ? Center(
                  child: Text('Course not available',
                      style:
                          TextStyle(color: colors.textTertiary, fontSize: 16)),
                )
              : _buildBody(course, colors),
    );
  }

  Widget _buildBody(Course course, AppColors colors) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(
          course.title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          [
            if (course.durationLabel.isNotEmpty) course.durationLabel,
            course.dateRangeLabel,
            if (course.sessionTimeLabel.isNotEmpty) course.sessionTimeLabel,
            course.priceLabel,
          ].join(' · '),
          style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
        ),
        if (course.hasCoTutor)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                CachedAvatar(imageUrl: course.coTutorImageUrl, size: 22),
                const SizedBox(width: 6),
                Text(
                  'with ${course.coTutorName ?? 'co-tutor'}',
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
              ],
            ),
          ),
        if (course.isCancelled)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.errorBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('This course is cancelled',
                  style: TextStyle(
                      color: colors.error, fontWeight: FontWeight.w600)),
            ),
          ),
        const SizedBox(height: 18),
        Row(
          children: [
            _Stat(
              value: '${course.enrolledCount}',
              label: 'Enrolled',
              colors: colors,
            ),
            _Stat(
              value: '${course.seatsLeft}',
              label: 'Seats left',
              colors: colors,
            ),
            _Stat(
              value: '${course.maxStudents}',
              label: 'Capacity',
              colors: colors,
            ),
          ],
        ),
        if (!course.isCancelled) ...[
          const SizedBox(height: 16),
          _joinButton(course, colors),
          if (course.hasChat) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _openChat(course),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: BorderSide(color: colors.border),
                foregroundColor: colors.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Symbols.forum_rounded, size: 20),
              label: const Text('Course chat',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
        const SizedBox(height: 24),
        _SectionTitle('STUDENTS', colors),
        const SizedBox(height: 8),
        if (_roster.isEmpty)
          Text('No students enrolled yet.',
              style: TextStyle(fontSize: 13.5, color: colors.textTertiary))
        else
          ..._roster.map((r) => _RosterRow(row: r, colors: colors)),
        const SizedBox(height: 24),
        _SectionTitle('ANNOUNCEMENTS', colors),
        const SizedBox(height: 8),
        if (!course.isCancelled) _announceComposer(colors),
        const SizedBox(height: 12),
        if (course.announcements.isEmpty)
          Text('No announcements yet.',
              style: TextStyle(fontSize: 13.5, color: colors.textTertiary))
        else
          ...course.announcements.map((a) => _AnnouncementRow(a: a, colors: colors)),
        const SizedBox(height: 28),
        if (!course.isCancelled && course.isPrimaryTutor)
          OutlinedButton.icon(
            onPressed: _cancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.error,
              side: BorderSide(color: colors.error.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Symbols.cancel_rounded, size: 20),
            label: const Text('Cancel course & refund students',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }

  /// The cohort's private chat. Same channel the students see — the course's
  /// tutors are members of it by virtue of teaching, not of paying.
  void _openChat(Course course) {
    final slug = course.chatChannelSlug;
    if (slug == null || slug.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelChatScreen(
          channel: ChatChannel(
            id: slug,
            name: course.title,
            emoji: '🎓',
            tileColor: context.colors.accentBlue,
            type: ChannelType.text,
          ),
        ),
      ),
    );
  }

  Widget _joinButton(Course course, AppColors colors) {
    if (course.sessionActiveNow) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton.icon(
          onPressed: _joining ? null : _join,
          style: FilledButton.styleFrom(
            backgroundColor: colors.success,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: _joining
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                )
              : const Icon(Symbols.videocam_rounded),
          label: Text(
            _joining ? 'Joining…' : 'Start / join live session',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        course.sessionTimeLabel.isNotEmpty
            ? 'Live daily at ${course.sessionTimeLabel}'
            : 'No session time set',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colors.textTertiary,
        ),
      ),
    );
  }

  Widget _announceComposer(AppColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _announce,
            maxLines: null,
            style: TextStyle(fontSize: 14.5, color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Post an update to enrolled students…',
              hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
              filled: true,
              fillColor: colors.surfaceAlt,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.textPrimary),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _posting ? null : _postAnnouncement,
            style: FilledButton.styleFrom(
              backgroundColor: colors.textPrimary,
              foregroundColor: colors.background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _posting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: colors.background),
                  )
                : const Icon(Symbols.send_rounded, size: 20),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final AppColors colors;
  const _Stat({required this.value, required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 11.5, color: colors.textTertiary)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final AppColors colors;
  const _SectionTitle(this.text, this.colors);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _RosterRow extends StatelessWidget {
  final CourseEnrollmentRow row;
  final AppColors colors;
  const _RosterRow({required this.row, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CachedAvatar(imageUrl: row.studentImageUrl, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.studentName.isEmpty ? 'Student' : row.studentName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementRow extends StatelessWidget {
  final CourseAnnouncement a;
  final AppColors colors;
  const _AnnouncementRow({required this.a, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.text,
              style: TextStyle(
                  fontSize: 14, color: colors.textPrimary, height: 1.4)),
          if (a.createdAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${a.createdAt!.day}/${a.createdAt!.month}/${a.createdAt!.year}',
                style: TextStyle(fontSize: 11, color: colors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}
