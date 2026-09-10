import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/lesson_card.dart';
import 'lesson_meeting_screen.dart';

// ─── Screen ─────────────────────────────────────────────────────────────────────

class LessonsScreen extends StatefulWidget {
  final VoidCallback? onFindTutor;
  const LessonsScreen({super.key, this.onFindTutor});

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _selectedDay = DateTime.now().day;

  // Calendar data from API
  Set<int> _busyDays = {};
  List<Map<String, dynamic>> _bookings = [];
  bool _loadingBookings = true;

  @override
  void initState() {
    super.initState();
    _fetchCalendar();
    _fetchBookings();
  }

  Future<void> _fetchCalendar() async {
    final url =
        '/bookings/calendar/?year=${_focusedMonth.year}&month=${_focusedMonth.month}';
    try {
      final data = await ApiService.get(url);
      final days = <int>{};
      final raw = data['busy_dates'] ?? data['busy_days'];
      if (raw is List) {
        for (final d in raw) {
          if (d is int) {
            days.add(d);
            continue;
          }
          final s = d.toString();
          final asInt = int.tryParse(s);
          if (asInt != null) {
            days.add(asInt);
            continue;
          }
          final parsed = DateTime.tryParse(s);
          if (parsed != null &&
              parsed.year == _focusedMonth.year &&
              parsed.month == _focusedMonth.month) {
            days.add(parsed.day);
          }
        }
      }
      if (mounted) {
        setState(() => _busyDays = days);
      }
    } on ApiException {
      if (mounted) setState(() => _busyDays = {});
    }
  }

  Future<void> _fetchBookings() async {
    setState(() => _loadingBookings = true);
    try {
      final list = await ApiService.getList('/bookings/my/');
      final bookings = list.cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _bookings = bookings;
          _loadingBookings = false;
        });
      }
    } on ApiException {
      if (mounted) setState(() { _bookings = []; _loadingBookings = false; });
    }
  }

  List<Map<String, dynamic>> get _selectedDayBookings {
    final selectedDate = DateTime(_focusedMonth.year, _focusedMonth.month, _selectedDay);
    return _bookings.where((b) {
      final status = (b['status'] ?? '').toString();
      if (status == 'pending' || status == 'cancelled') return false;
      final startStr = b['start_at']?.toString() ??
          b['start_time']?.toString() ??
          b['date']?.toString() ?? '';
      if (startStr.isEmpty) return false;
      final parsed = DateTime.tryParse(startStr);
      if (parsed == null) return false;
      final local = parsed.toLocal();
      return local.year == selectedDate.year &&
          local.month == selectedDate.month &&
          local.day == selectedDate.day;
    }).toList();
  }

  void _prevMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
      _selectedDay = 1;
      _busyDays = {};
    });
    _fetchCalendar();
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
      _selectedDay = 1;
      _busyDays = {};
    });
    _fetchCalendar();
  }

  Future<void> _cancelBooking(int bookingId) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CancelLessonSheet(),
    );
    if (reason == null) return;

    try {
      await ApiService.patch('/bookings/$bookingId/cancel/', {'reason': reason});
      _fetchCalendar();
      _fetchBookings();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _joinLesson(int bookingId, {String tutorName = 'Tutor'}) async {
    try {
      final data = await ApiService.post('/bookings/$bookingId/join/', {});
      final payload = (data['data'] is Map<String, dynamic>)
          ? data['data'] as Map<String, dynamic>
          : data;
      final roomUrl = (payload['joinUrl'] ??
              payload['join_url'] ??
              payload['room_url'] ??
              payload['daily_room_url'] ??
              payload['roomUrl'] ??
              '')
          .toString();
      final token = (payload['token'] ??
              payload['daily_token'] ??
              payload['meeting_token'] ??
              payload['daily_meeting_token'] ??
              '')
          .toString();
      if (roomUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get room info')),
          );
        }
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LessonMeetingScreen(
            roomUrl: roomUrl,
            token: token,
            tutorName: tutorName,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayBookings = _selectedDayBookings;

    return Scaffold(
      backgroundColor: context.colors.surfaceAlt,
      body: SafeArea(
        child: Column(
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'My lessons',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
            ),

            // Scrollable content
            Expanded(
              child: RefreshIndicator(
                color: context.colors.textPrimary,
                onRefresh: () async {
                  await Future.wait([_fetchCalendar(), _fetchBookings()]);
                },
                child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // Calendar card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _CalendarCard(
                        focusedMonth: _focusedMonth,
                        selectedDay: _selectedDay,
                        lessonDays: _busyDays,
                        onPrevMonth: _prevMonth,
                        onNextMonth: _nextMonth,
                        onDayTap: (day) => setState(() => _selectedDay = day),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Surface bottom section
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Date header
                          _DateHeader(
                            month: _focusedMonth,
                            day: _selectedDay,
                          ),

                          const SizedBox(height: 16),

                          // Loading / Lesson cards / No classes
                          if (_loadingBookings)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: CircularProgressIndicator(color: context.colors.textPrimary),
                              ),
                            )
                          else if (dayBookings.isNotEmpty)
                            ...dayBookings.map((booking) {
                              final roomUrl = booking['daily_room_url']?.toString() ?? '';
                              final lesson = Lesson.fromBooking(booking);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: LessonCard(
                                  lesson: lesson,
                                  showStartButton: roomUrl.isNotEmpty,
                                  onStart: () {
                                    if (lesson.id != 0) {
                                      _joinLesson(lesson.id, tutorName: lesson.participantName);
                                    }
                                  },
                                  onCancel: () {
                                    if (lesson.id != 0) _cancelBooking(lesson.id);
                                  },
                                  onRated: _fetchBookings,
                                ),
                              );
                            })
                          else
                            _NoClassesCard(onFindTutor: widget.onFindTutor),

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ],
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

// ─── Calendar card ──────────────────────────────────────────────────────────────

class _CalendarCard extends StatelessWidget {
  final DateTime focusedMonth;
  final int selectedDay;
  final Set<int> lessonDays;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final void Function(int) onDayTap;

  const _CalendarCard({
    required this.focusedMonth,
    required this.selectedDay,
    required this.lessonDays,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onDayTap,
  });

  static const _dayHeaders = ['SAN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

  static const _monthNames = [
    '', 'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];

  @override
  Widget build(BuildContext context) {
    final year = focusedMonth.year;
    final month = focusedMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday % 7; // 0=Sun

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Month navigation
          Row(
            children: [
              GestureDetector(
                onTap: onPrevMonth,
                child: Icon(Symbols.chevron_left_rounded, color: context.colors.textPrimary, size: 24),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_monthNames[month]} $year',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onNextMonth,
                child: Icon(Symbols.chevron_right_rounded, color: context.colors.textPrimary, size: 24),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Day headers
          Row(
            children: _dayHeaders
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textTertiary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),

          const SizedBox(height: 12),

          // Calendar grid
          ...List.generate(6, (week) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: List.generate(7, (weekday) {
                  final dayNum = week * 7 + weekday - firstWeekday + 1;
                  if (dayNum < 1 || dayNum > daysInMonth) {
                    return const Expanded(child: SizedBox());
                  }

                  final isSelected = dayNum == selectedDay;
                  final hasLesson = lessonDays.contains(dayNum);
                  final now = DateTime.now();
                  final isToday = dayNum == now.day && month == now.month && year == now.year;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onDayTap(dayNum),
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected ? context.colors.brand : null,
                            borderRadius: BorderRadius.circular(8),
                            border: isToday && !isSelected
                                ? Border.all(color: context.colors.brand, width: 1.5)
                                : null,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Text(
                                '$dayNum',
                                style: TextStyle(
                                  fontFamily: 'SF Pro',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: isSelected
                                      ? Colors.white
                                      : context.colors.textPrimary,
                                ),
                              ),
                              if (hasLesson)
                                Positioned(
                                  bottom: 4,
                                  child: Container(
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.white
                                          : context.colors.success,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Date header ────────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final DateTime month;
  final int day;
  const _DateHeader({required this.month, required this.day});

  static const _monthNames = [
    '', 'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];

  static const _weekdays = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY',
  ];

  @override
  Widget build(BuildContext context) {
    final date = DateTime(month.year, month.month, day);
    final weekday = _weekdays[date.weekday - 1];

    return Row(
        children: [
          Text(
            '$day ${_monthNames[month.month]}, $weekday',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.colors.textSecondary,
            ),
          ),
          const Spacer(),
          if (() {
            final now = DateTime.now();
            return month.month == now.month && month.year == now.year && day == now.day;
          }())
            Text(
              'Today',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.colors.accentBlue,
                height: 1.0,
                letterSpacing: 0,
              ),
            ),
        ],
    );
  }
}

// ─── No classes card ────────────────────────────────────────────────────────────

class _NoClassesCard extends StatelessWidget {
  final VoidCallback? onFindTutor;
  const _NoClassesCard({this.onFindTutor});

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: context.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                SvgPicture.asset(
                  'assets/images/icons/block_outline_20.svg',
                  width: 32,
                  height: 32,
                ),
                const SizedBox(height: 12),
                Text(
                  'There are no classes',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onFindTutor,
            child: Container(
              width: double.infinity,
              height: 46,
              decoration: BoxDecoration(
                color: context.colors.brand,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'Find a tutor',
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
    );
  }
}

// ─── Cancel lesson bottom sheet ─────────────────────────────────────────────────

class CancelLessonSheet extends StatefulWidget {
  const CancelLessonSheet({super.key});

  @override
  State<CancelLessonSheet> createState() => _CancelLessonSheetState();
}

class _CancelLessonSheetState extends State<CancelLessonSheet> {
  final _controller = TextEditingController();
  bool _showError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: context.colors.errorBg,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                Symbols.warning_amber_rounded,
                color: context.colors.error,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Cancel Lesson?',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.colors.errorBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.error.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Symbols.info_rounded, color: context.colors.error, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your payment will NOT be refunded.\nThe lesson fee has already been charged and cancellations are non-reversible.',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.colors.error,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reason for cancellation',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                onChanged: (_) => setState(() => _showError = false),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Please explain why you are cancelling…',
                  hintStyle: TextStyle(fontSize: 13, color: context.colors.textTertiary),
                  filled: true,
                  fillColor: context.colors.surfaceAlt,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: _showError
                        ? BorderSide(color: context.colors.error, width: 1.5)
                        : BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.colors.brand, width: 1.5),
                  ),
                ),
              ),
              if (_showError) ...[
                const SizedBox(height: 4),
                Text(
                  'A reason is required to cancel.',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: context.colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Keep lesson',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _confirm,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: context.colors.error,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'Yes, cancel',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
