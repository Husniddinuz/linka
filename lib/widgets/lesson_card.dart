import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';

class Lesson {
  final int id;
  final int? tutorId;
  final String participantName;
  final String? participantImage;
  final String timeRange;
  final String duration;
  final String status;
  final DateTime? startAt;
  final String dailyRoomUrl;
  final bool rated;

  const Lesson({
    required this.id,
    this.tutorId,
    required this.participantName,
    this.participantImage,
    required this.timeRange,
    required this.duration,
    required this.status,
    this.startAt,
    this.dailyRoomUrl = '',
    this.rated = false,
  });

  bool get isCancelled => status == 'cancelled';
  bool get isFinished => status == 'finished';

  factory Lesson.fromBooking(
    Map<String, dynamic> booking, {
    bool viewerIsTutor = false,
  }) {
    final party = (viewerIsTutor
            ? booking['student'] as Map<String, dynamic>?
            : booking['tutor'] as Map<String, dynamic>?) ??
        {};
    final firstName = party['first_name'] as String? ??
        booking[viewerIsTutor ? 'student_first_name' : 'tutor_first_name'] as String? ??
        '';
    final lastName = party['last_name'] as String? ??
        booking[viewerIsTutor ? 'student_last_name' : 'tutor_last_name'] as String? ??
        '';
    final profileImage = (party['profile_image'] as String?) ??
        booking[viewerIsTutor ? 'student_profile_image' : 'tutor_profile_image'] as String?;
    final startAt = DateTime.tryParse(
      booking['start_at'] as String? ?? booking['start_time'] as String? ?? '',
    );
    final endAt = DateTime.tryParse(
      booking['end_at'] as String? ?? booking['end_time'] as String? ?? '',
    );
    final localStartAt = startAt?.toLocal();

    final durationRaw = booking['duration_minutes'];
    final durationFromField = durationRaw is int
        ? durationRaw
        : int.tryParse(durationRaw?.toString() ?? '') ?? 0;
    final durationMin = durationFromField > 0
        ? durationFromField
        : (startAt != null && endAt != null
            ? endAt.difference(startAt).inMinutes
            : 0);

    String timeRange = '';
    if (startAt != null) {
      final localStart = startAt.toLocal();
      final localEnd = (endAt ?? startAt.add(Duration(minutes: durationMin))).toLocal();
      timeRange =
          '${localStart.hour.toString().padLeft(2, '0')}:${localStart.minute.toString().padLeft(2, '0')}'
          ' - '
          '${localEnd.hour.toString().padLeft(2, '0')}:${localEnd.minute.toString().padLeft(2, '0')}';
    }

    String durationLabel = '';
    if (durationMin >= 60) {
      durationLabel = '${durationMin ~/ 60} h ${durationMin % 60} min';
    } else if (durationMin > 0) {
      durationLabel = '$durationMin min';
    }

    final tutorMap = booking['tutor'] as Map<String, dynamic>?;
    final tutorId = tutorMap?['id'] as int? ?? booking['tutor_id'] as int?;

    return Lesson(
      id: booking['id'] as int? ?? 0,
      tutorId: viewerIsTutor ? null : tutorId,
      participantName: '$firstName $lastName'.trim(),
      participantImage: profileImage,
      timeRange: timeRange,
      duration: durationLabel,
      status: booking['status'] as String? ?? '',
      startAt: localStartAt,
      dailyRoomUrl: booking['daily_room_url']?.toString() ?? '',
      rated: booking['rated'] as bool? ?? false,
    );
  }
}

class LessonCard extends StatefulWidget {
  final Lesson lesson;
  final bool showStartButton;
  final bool showCopyLink;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onRated;

  const LessonCard({
    super.key,
    required this.lesson,
    this.showStartButton = false,
    this.showCopyLink = false,
    this.onStart,
    this.onCancel,
    this.onRated,
  });

  @override
  State<LessonCard> createState() => _LessonCardState();
}

class _LessonCardState extends State<LessonCard> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  static const _windowMinutes = 120;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  @override
  void didUpdateWidget(LessonCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lesson.startAt != widget.lesson.startAt) {
      _updateRemaining();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateRemaining() {
    final startAt = widget.lesson.startAt;
    if (startAt == null) {
      if (mounted) setState(() => _remaining = Duration.zero);
      return;
    }
    final diff = startAt.difference(DateTime.now());
    if (mounted) setState(() => _remaining = diff > Duration.zero ? diff : Duration.zero);
  }

  bool get _canStart =>
      widget.lesson.startAt == null ||
      _remaining <= const Duration(minutes: _windowMinutes);

  String get _countdownLabel {
    final total = _remaining.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _showOptions(BuildContext context) {
    final cancel = widget.onCancel;
    if (cancel == null) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cancel_outlined, color: Colors.red),
              title: const Text('Cancel lesson'),
              onTap: () {
                Navigator.pop(ctx);
                cancel();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRateSheet(BuildContext context) async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _RateSheet(
          bookingId: widget.lesson.id,
          tutorId: widget.lesson.tutorId,
          participantName: widget.lesson.participantName,
          participantImageUrl: widget.lesson.participantImage,
        ),
      ),
    );
    if (submitted == true) widget.onRated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isCancelled = widget.lesson.isCancelled;
    final isFinished = widget.lesson.isFinished;
    final isUpcoming = widget.lesson.startAt == null ||
        widget.lesson.startAt!.isAfter(DateTime.now());

    return Opacity(
      opacity: isCancelled ? 0.5 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F6F6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: widget.lesson.participantImage != null &&
                          widget.lesson.participantImage!.startsWith('http')
                      ? Image.network(
                          widget.lesson.participantImage!,
                          width: 82,
                          height: 82,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Image.asset(
                            'assets/images/tutors/tutor.png',
                            width: 82,
                            height: 82,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Image.asset(
                          'assets/images/tutors/tutor.png',
                          width: 82,
                          height: 82,
                          fit: BoxFit.cover,
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 82,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                widget.lesson.participantName,
                                style: const TextStyle(
                                  fontFamily: 'SF Pro',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF272942),
                                  height: 1.0,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  SvgPicture.asset(
                                    'assets/images/icons/recent_outline_20.svg',
                                    width: 15,
                                    height: 15,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    widget.lesson.timeRange,
                                    style: const TextStyle(
                                      fontFamily: 'SF Pro',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF6C6C6C),
                                      height: 1.0,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  SvgPicture.asset(
                                    'assets/images/icons/tabler_hourglass-high.svg',
                                    width: 15,
                                    height: 15,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    widget.lesson.duration,
                                    style: const TextStyle(
                                      fontFamily: 'SF Pro',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF6C6C6C),
                                      height: 1.0,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (!isCancelled && isUpcoming)
                          GestureDetector(
                            onTap: widget.onCancel != null
                                ? () => _showOptions(context)
                                : null,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(
                                  3,
                                  (i) => Padding(
                                    padding: EdgeInsets.only(top: i == 0 ? 0 : 3),
                                    child: Container(
                                      width: 4,
                                      height: 4,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF272942),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (widget.showStartButton && !isCancelled && !isFinished && widget.onStart != null) ...[
              const SizedBox(height: 8),
              if (_canStart)
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.onStart,
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: const Color(0xFF272942),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _LiveDot(),
                              const SizedBox(width: 8),
                              const Text(
                                'Join the lesson',
                                style: TextStyle(
                                  fontFamily: 'SF Pro',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (widget.showCopyLink && widget.lesson.dailyRoomUrl.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: widget.lesson.dailyRoomUrl),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Link copied'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F2F4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.link_rounded,
                            size: 22,
                            color: Color(0xFF272942),
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              else
                Container(
                  width: double.infinity,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 16,
                        color: Color(0xFF6C6C6C),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Starts in $_countdownLabel',
                        style: const TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6C6C6C),
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (isCancelled) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text(
                    'Cancelled',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFAAAAAA),
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ],
            if (isFinished) ...[
              const SizedBox(height: 8),
              if (!widget.lesson.rated)
                GestureDetector(
                  onTap: () => _openRateSheet(context),
                  child: Container(
                    width: double.infinity,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5C542),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text(
                        'Rate the lesson',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF272942),
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF7EE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 15,
                          color: Color(0xFF27AE60),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Review submitted',
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF27AE60),
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RateSheet extends StatefulWidget {
  final int bookingId;
  final int? tutorId;
  final String participantName;
  final String? participantImageUrl;

  const _RateSheet({
    required this.bookingId,
    this.tutorId,
    required this.participantName,
    this.participantImageUrl,
  });

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  int _rating = 5;
  final TextEditingController _commentController = TextEditingController();
  bool _saving = false;
  String? _error;

  static const _labels = ['Terrible', 'Bad', 'Okay', 'Good', 'Excellent'];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) {
      setState(() => _error = 'Please share your experience');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = {
      'booking_id': widget.bookingId,
      if (widget.tutorId != null) 'tutor': widget.tutorId,
      'rating': _rating,
      'comment': comment,
    };
    dev.log('submitting review: $payload', name: 'RateSheet');
    try {
      await ApiService.post('/reviews/', payload);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      dev.log('review error [${e.statusCode}]: ${e.message}', name: 'RateSheet');
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } catch (e) {
      dev.log('review unexpected error: $e', name: 'RateSheet');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.participantImageUrl;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: imageUrl != null && imageUrl.startsWith('http')
                      ? Image.network(
                          imageUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                            width: 44,
                            height: 44,
                            child: ColoredBox(color: Color(0xFFEEEEEE)),
                          ),
                        )
                      : Container(
                          width: 44,
                          height: 44,
                          color: const Color(0xFFEEEEEE),
                        ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.participantName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF272942),
                      ),
                    ),
                    const Text(
                      'Rate this lesson',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFFAAAAAA),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF272942).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final filled = i < _rating;
                      return GestureDetector(
                        onTap: () => setState(() => _rating = i + 1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            filled
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 40,
                            color: filled
                                ? const Color(0xFFF5C542)
                                : const Color(0xFFDDDDDD),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _labels[(_rating - 1).clamp(0, 4)],
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF272942),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentController,
              minLines: 3,
              maxLines: 5,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF272942),
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText: 'Share your experience...',
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFFBBBBBB),
                ),
                filled: true,
                fillColor: const Color(0xFFF5F5F7),
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFE74C3C),
                ),
              ),
            ],
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _saving ? null : _submit,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _saving
                      ? const Color(0xFF272942).withValues(alpha: 0.5)
                      : const Color(0xFF272942),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit review',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFFE53935),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
