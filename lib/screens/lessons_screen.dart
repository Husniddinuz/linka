import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import '../widgets/lesson_card.dart';

// ─── Screen ─────────────────────────────────────────────────────────────────────

class LessonsScreen extends StatefulWidget {
  const LessonsScreen({super.key});

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
    try {
      final data = await ApiService.get(
        '/bookings/calendar/?year=${_focusedMonth.year}&month=${_focusedMonth.month}',
      );
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
      if (mounted) setState(() => _busyDays = days);
    } on ApiException {
      if (mounted) setState(() => _busyDays = {});
    }
  }

  Future<void> _fetchBookings() async {
    setState(() => _loadingBookings = true);
    try {
      final list = await ApiService.getList('/bookings/my/');
      if (mounted) {
        setState(() {
          _bookings = list.cast<Map<String, dynamic>>();
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
    });
    _fetchCalendar();
    _fetchBookings();
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
      _selectedDay = 1;
    });
    _fetchCalendar();
    _fetchBookings();
  }

  Future<void> _cancelBooking(int bookingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Lesson'),
        content: const Text('Are you sure you want to cancel this lesson?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, cancel')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ApiService.patch('/bookings/$bookingId/cancel/');
      _fetchCalendar();
      _fetchBookings();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _joinLesson(int bookingId) async {
    try {
      final data = await ApiService.post('/bookings/$bookingId/join/', {});
      final roomUrl = data['room_url']?.toString() ?? '';
      final token = data['token']?.toString() ?? '';
      if (roomUrl.isEmpty || token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get room info')),
          );
        }
        return;
      }
      // TODO: Navigate to video call screen with roomUrl and token
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
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            // Title
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'My lessons',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF272942),
                ),
              ),
            ),

            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
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

                    // White bottom section
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: CircularProgressIndicator(color: Color(0xFF272942)),
                              ),
                            )
                          else if (dayBookings.isNotEmpty)
                            ...dayBookings.map((booking) {
                              final now = DateTime.now();
                              final isToday = _focusedMonth.month == now.month &&
                                  _focusedMonth.year == now.year &&
                                  _selectedDay == now.day;
                              final roomUrl = booking['daily_room_url']?.toString() ?? '';
                              final lesson = Lesson.fromBooking(booking);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: LessonCard(
                                  lesson: lesson,
                                  showStartButton: isToday && roomUrl.isNotEmpty,
                                  onStart: () {
                                    if (lesson.id != 0) _joinLesson(lesson.id);
                                  },
                                  onCancel: () {
                                    if (lesson.id != 0) _cancelBooking(lesson.id);
                                  },
                                ),
                              );
                            })
                          else
                            const _NoClassesCard(),

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Month navigation
          Row(
            children: [
              GestureDetector(
                onTap: onPrevMonth,
                child: const Icon(Icons.chevron_left, color: Color(0xFF272942), size: 24),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_monthNames[month]} $year',
                    style: const TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF272942),
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onNextMonth,
                child: const Icon(Icons.chevron_right, color: Color(0xFF272942), size: 24),
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
                          style: const TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFAAAAAA),
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
                            color: isSelected ? const Color(0xFF272942) : null,
                            borderRadius: BorderRadius.circular(8),
                            border: isToday && !isSelected
                                ? Border.all(color: const Color(0xFF272942), width: 1.5)
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
                                      : const Color(0xFF272942),
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
                                          : const Color(0xFF4CAF50),
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
            style: const TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6C6C6C),
            ),
          ),
          const Spacer(),
          if (() {
            final now = DateTime.now();
            return month.month == now.month && month.year == now.year && day == now.day;
          }())
            const Text(
              'Today',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2B85DB),
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
  const _NoClassesCard();

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: const Color(0xFFEEEEEE),
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
                const Text(
                  'There are no classes',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFAAAAAA),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF272942),
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
        ],
    );
  }
}
