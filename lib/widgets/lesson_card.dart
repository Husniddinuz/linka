import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class Lesson {
  final int id;
  final String tutorName;
  final String? tutorImage;
  final String timeRange;
  final String duration;
  final String status;

  const Lesson({
    required this.id,
    required this.tutorName,
    this.tutorImage,
    required this.timeRange,
    required this.duration,
    required this.status,
  });

  bool get isCancelled => status == 'cancelled';

  factory Lesson.fromBooking(Map<String, dynamic> booking) {
    final tutor = booking['tutor'] as Map<String, dynamic>? ?? {};
    final firstName = tutor['first_name'] as String? ?? booking['tutor_first_name'] as String? ?? '';
    final lastName = tutor['last_name'] as String? ?? booking['tutor_last_name'] as String? ?? '';
    final startAt = DateTime.tryParse(
      booking['start_at'] as String? ?? booking['start_time'] as String? ?? '',
    );
    final endAt = DateTime.tryParse(
      booking['end_at'] as String? ?? booking['end_time'] as String? ?? '',
    );

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

    return Lesson(
      id: booking['id'] as int? ?? 0,
      tutorName: '$firstName $lastName'.trim(),
      tutorImage: (tutor['profile_image'] as String?) ?? booking['tutor_profile_image'] as String?,
      timeRange: timeRange,
      duration: durationLabel,
      status: booking['status'] as String? ?? '',
    );
  }
}

class LessonCard extends StatelessWidget {
  final Lesson lesson;
  final bool showStartButton;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;

  const LessonCard({
    super.key,
    required this.lesson,
    this.showStartButton = false,
    this.onStart,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isCancelled = lesson.isCancelled;

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
                  child: lesson.tutorImage != null && lesson.tutorImage!.startsWith('http')
                      ? Image.network(
                          lesson.tutorImage!,
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
                                lesson.tutorName,
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
                                    lesson.timeRange,
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
                                    lesson.duration,
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
                        if (!isCancelled)
                          GestureDetector(
                            onTap: onCancel != null ? () => _showOptions(context) : null,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
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
            if (showStartButton && !isCancelled && onStart != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onStart,
                child: Container(
                  width: double.infinity,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF272942),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text(
                      'Start the lesson',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                  ),
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
          ],
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    final cancel = onCancel;
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
}
