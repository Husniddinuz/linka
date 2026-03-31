import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// ─── Data model ─────────────────────────────────────────────────────────────────

class _LessonItem {
  final String tutorName;
  final String image;
  final String timeRange;
  final String duration;
  const _LessonItem(this.tutorName, this.image, this.timeRange, this.duration);
}

// ─── Screen ─────────────────────────────────────────────────────────────────────

class LessonsScreen extends StatefulWidget {
  const LessonsScreen({super.key});

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  DateTime _focusedMonth = DateTime(2026, 3);
  int _selectedDay = 15;

  // Days that have lessons per month (year-month -> days)
  static final _lessonDaysByMonth = {
    '2026-2': {17, 19, 26},
    '2026-3': {3, 10, 15, 22},
  };

  // Mock lessons for selected day
  static const _lessons = [
    _LessonItem('Azizbek', 'assets/images/tutors/azizbek.png', '21:00 - 0:00', '20 min'),
    _LessonItem('Azizbek', 'assets/images/tutors/azizbek.png', '0:00 - 0:30', '30 min'),
  ];

  void _prevMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
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
                        lessonDays: _lessonDaysByMonth['${_focusedMonth.year}-${_focusedMonth.month}'] ?? {},
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

                          // Lesson cards or no classes
                          if ((_lessonDaysByMonth['${_focusedMonth.year}-${_focusedMonth.month}'] ?? {}).contains(_selectedDay))
                            ..._lessons.asMap().entries.map((e) {
                              final now = DateTime.now();
                              final isToday = _focusedMonth.month == now.month && _focusedMonth.year == now.year && _selectedDay == now.day;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _LessonCard(lesson: e.value, showStartButton: isToday && e.key == 0),
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
  final _LessonItem lesson;
  final bool showStartButton;
  const _LessonCard({required this.lesson, this.showStartButton = false});

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  child: Image.asset(
                    lesson.image,
                    width: 82,
                    height: 82,
                    fit: BoxFit.cover,
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
                      Padding(
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
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (showStartButton) ...[
            const SizedBox(height: 8),
            Container(
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
          ],
        ],
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
