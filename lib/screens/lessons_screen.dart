import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';

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
      if (data['busy_days'] is List) {
        for (final d in data['busy_days'] as List) {
          days.add(d is int ? d : int.tryParse(d.toString()) ?? 0);
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
      final startStr = b['start_time']?.toString() ?? b['date']?.toString() ?? '';
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
                            ...dayBookings.asMap().entries.map((e) {
                              final booking = e.value;
                              final now = DateTime.now();
                              final isToday = _focusedMonth.month == now.month &&
                                  _focusedMonth.year == now.year &&
                                  _selectedDay == now.day;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _LessonCard(
                                  booking: booking,
                                  showStartButton: isToday,
                                  onStart: () {
                                    final id = booking['id'];
                                    if (id != null) _joinLesson(id is int ? id : int.parse(id.toString()));
                                  },
                                  onCancel: () {
                                    final id = booking['id'];
                                    if (id != null) _cancelBooking(id is int ? id : int.parse(id.toString()));
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
                          child: Center(
                            child: Text(
                              '$dayNum',
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: isSelected
                                    ? (hasLesson ? const Color(0xFF4CAF50) : Colors.white)
                                    : hasLesson
                                        ? const Color(0xFF4CAF50)
                                        : const Color(0xFF272942),
                              ),
                            ),
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

// ─── Lesson card ────────────────────────────────────────────────────────────────

class _LessonCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool showStartButton;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  const _LessonCard({
    required this.booking,
    this.showStartButton = false,
    required this.onStart,
    required this.onCancel,
  });

  String _formatTime(String? isoString) {
    if (isoString == null) return '--:--';
    final dt = DateTime.tryParse(isoString)?.toLocal();
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(String? startStr, String? endStr) {
    if (startStr == null || endStr == null) return '';
    final start = DateTime.tryParse(startStr);
    final end = DateTime.tryParse(endStr);
    if (start == null || end == null) return '';
    final diff = end.difference(start);
    if (diff.inHours > 0) return '${diff.inHours} h ${diff.inMinutes % 60} min';
    return '${diff.inMinutes} min';
  }

  @override
  Widget build(BuildContext context) {
    final tutor = booking['tutor'] as Map<String, dynamic>? ?? {};
    final tutorName = tutor['first_name']?.toString() ?? booking['tutor_first_name']?.toString() ?? 'Tutor';
    final tutorImage = tutor['profile_image']?.toString() ?? booking['tutor_profile_image']?.toString();
    final startTime = booking['start_time']?.toString();
    final endTime = booking['end_time']?.toString();
    final status = booking['status']?.toString() ?? '';
    final isCancelled = status == 'cancelled';

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
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0F4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: tutorImage != null && tutorImage.isNotEmpty
                        ? Image.network(
                            tutorImage,
                            width: 82,
                            height: 82,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => SvgPicture.asset(
                              'assets/images/branding/blank-avatar.svg',
                              width: 82,
                              height: 82,
                            ),
                          )
                        : SvgPicture.asset(
                            'assets/images/branding/blank-avatar.svg',
                            width: 82,
                            height: 82,
                          ),
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
                                tutorName,
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
                                    '${_formatTime(startTime)} - ${_formatTime(endTime)}',
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
                                    _formatDuration(startTime, endTime),
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
                            onTap: () => _showOptions(context),
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
            if (showStartButton && !isCancelled) ...[
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
                onCancel();
              },
            ),
          ],
        ),
      ),
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
