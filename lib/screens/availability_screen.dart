import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'booking_page_screen.dart';

class AvailabilityScreen extends StatefulWidget {
  final int tutorId;
  final String tutorName;
  final String tutorImage;
  final String experience;
  final double ieltsScore;
  final List<Map<String, dynamic>> lessonPrices;

  const AvailabilityScreen({
    super.key,
    required this.tutorId,
    required this.tutorName,
    required this.tutorImage,
    required this.experience,
    required this.ieltsScore,
    required this.lessonPrices,
  });

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  late DateTime _focusedMonth;
  DateTime? _selectedDate;
  String? _selectedWindow;
  int _selectedDurationIndex = 0;

  static const _dayHeaders = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
  static const _monthNames = [
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];
  static const _dayOfWeekNames = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY',
  ];

  // Available time windows (these would come from tutor schedule API when available)
  static const _windows = [
    '10:00 - 11:00',
    '11:00 - 11:30',
    '12:00 - 12:40',
    '17:10 - 18:00',
    '22:20 - 23:00',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _selectedDate = now;
  }

  int get _selectedDurationMinutes {
    if (widget.lessonPrices.isEmpty) return 30;
    final p = widget.lessonPrices[_selectedDurationIndex];
    return p['duration_minutes'] as int? ?? 30;
  }

  int get _selectedPrice {
    if (widget.lessonPrices.isEmpty) return 0;
    final p = widget.lessonPrices[_selectedDurationIndex];
    final priceStr = p['price']?.toString() ?? '0';
    return double.tryParse(priceStr)?.toInt() ?? 0;
  }

  // Compute start/end from selected window
  String? get _startTime {
    if (_selectedWindow == null) return null;
    return _selectedWindow!.split(' - ')[0];
  }

  String? get _endTime {
    if (_startTime == null) return null;
    final parts = _startTime!.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final totalMin = h * 60 + m + _selectedDurationMinutes;
    final endH = (totalMin ~/ 60) % 24;
    final endM = totalMin % 60;
    return '${endH.toString().padLeft(2, '0')}:${endM.toString().padLeft(2, '0')}';
  }

  bool get _canProceed => _selectedDate != null && _selectedWindow != null;

  bool _isWindowPast(String window) {
    final date = _selectedDate;
    if (date == null) return false;
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    if (!isToday) return false;
    final parts = window.split(' - ')[0].split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final start = DateTime(date.year, date.month, date.day, h, m);
    return !start.isAfter(now);
  }

  void _showTimePicker() {
    if (_selectedWindow == null) return;
    final parts = _startTime!.split(':');
    int hour = int.parse(parts[0]);
    int minute = int.parse(parts[1]);

    final hours = List.generate(24, (i) => i);
    final minutes = List.generate(12, (i) => i * 5);

    int hourIndex = hours.indexOf(hour);
    int minuteIndex = minutes.indexOf((minute ~/ 5) * 5);
    if (minuteIndex < 0) minuteIndex = 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: 280,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                children: [
                  // Hours
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: hourIndex),
                      itemExtent: 40,
                      onSelectedItemChanged: (i) => hour = hours[i],
                      children: hours.map((h) => Center(
                        child: Text(
                          h.toString().padLeft(2, '0'),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                        ),
                      )).toList(),
                    ),
                  ),
                  // Minutes
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: minuteIndex),
                      itemExtent: 40,
                      onSelectedItemChanged: (i) => minute = minutes[i],
                      children: minutes.map((m) => Center(
                        child: Text(
                          m.toString().padLeft(2, '0'),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                        ),
                      )).toList(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final newStart = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
                    final endMin = hour * 60 + minute + _selectedDurationMinutes;
                    final endH = (endMin ~/ 60) % 24;
                    final endM = endMin % 60;
                    final newEnd = '${endH.toString().padLeft(2, '0')}:${endM.toString().padLeft(2, '0')}';
                    setState(() {
                      _selectedWindow = '$newStart - $newEnd';
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF272942),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Confirm', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onNext() {
    if (!_canProceed) return;
    final parts = _startTime!.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final startAt = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      h, m,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingPageScreen(
          tutorId: widget.tutorId,
          tutorName: widget.tutorName,
          tutorImage: widget.tutorImage,
          experience: widget.experience,
          ieltsScore: widget.ieltsScore,
          startAt: startAt,
          durationMinutes: _selectedDurationMinutes,
          price: _selectedPrice,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // App bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.chevron_left_rounded, size: 30, color: Color(0xFF272942)),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Availability',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF272942),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 30),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _buildCalendar(),
                    const SizedBox(height: 24),
                    _buildSelectedDateLabel(),
                    const SizedBox(height: 20),
                    _buildWindowsSection(),
                    const SizedBox(height: 24),
                    _buildDurationSection(),
                    const SizedBox(height: 24),
                    _buildTimeSection(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // Bottom buttons
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF272942),
                        side: const BorderSide(color: Color(0xFF272942), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _canProceed ? _onNext : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _canProceed ? const Color(0xFF272942) : const Color(0xFFDDDDDD),
                        foregroundColor: _canProceed ? Colors.white : const Color(0xFF6C6C6C),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Calendar ──────────────────────────────────────────────────────────────

  Widget _buildCalendar() {
    final year = _focusedMonth.year;
    final month = _focusedMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday % 7; // Sunday = 0
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        children: [
          // Month header
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() {
                  _focusedMonth = DateTime(year, month - 1);
                }),
                child: const Icon(Icons.chevron_left, color: Color(0xFF272942), size: 24),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_monthNames[month - 1]} $year',
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
                onTap: () => setState(() {
                  _focusedMonth = DateTime(year, month + 1);
                }),
                child: const Icon(Icons.chevron_right, color: Color(0xFF272942), size: 24),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Day headers
          Row(
            children: _dayHeaders.map((d) => Expanded(
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
            )).toList(),
          ),
          const SizedBox(height: 8),
          // Day grid
          ...List.generate(6, (week) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: List.generate(7, (weekday) {
                  final dayNum = week * 7 + weekday - firstWeekday + 1;
                  if (dayNum < 1 || dayNum > daysInMonth) {
                    return const Expanded(child: SizedBox(height: 36));
                  }
                  final date = DateTime(year, month, dayNum);
                  final isPast = date.isBefore(today);
                  final isSelected = _selectedDate != null &&
                      _selectedDate!.year == year &&
                      _selectedDate!.month == month &&
                      _selectedDate!.day == dayNum;
                  final isToday = date == today;

                  return Expanded(
                    child: GestureDetector(
                      onTap: isPast ? null : () => setState(() {
                        _selectedDate = date;
                        _selectedWindow = null;
                      }),
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
                                color: isPast
                                    ? const Color(0xFFCCCCCC)
                                    : isSelected
                                        ? Colors.white
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

  // ── Selected date label ───────────────────────────────────────────────────

  Widget _buildSelectedDateLabel() {
    if (_selectedDate == null) return const SizedBox.shrink();
    final d = _selectedDate!;
    final label = '${d.day} ${_monthNames[d.month - 1]}, ${_dayOfWeekNames[d.weekday - 1]}';
    return Text(
      label,
      style: const TextStyle(
        fontFamily: 'SF Pro',
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Color(0xFF272942),
      ),
    );
  }

  // ── Windows section ───────────────────────────────────────────────────────

  Widget _buildWindowsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Windows',
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF272942),
          ),
        ),
        const SizedBox(height: 12),
        Builder(builder: (_) {
          final visible = _windows.where((w) => !_isWindowPast(w)).toList();
          if (visible.isEmpty) {
            return const Text(
              'No available windows for this day',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 14,
                color: Color(0xFF9E9E9E),
              ),
            );
          }
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: visible.map((w) {
              final selected = w == _selectedWindow;
              return GestureDetector(
                onTap: () => setState(() => _selectedWindow = w),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF272942) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: selected ? const Color(0xFF272942) : const Color(0xFFDDDDDD),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    w,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: selected ? Colors.white : const Color(0xFF272942),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  // ── Duration section ──────────────────────────────────────────────────────

  Widget _buildDurationSection() {
    if (widget.lessonPrices.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Lesson duration',
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF272942),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: List.generate(widget.lessonPrices.length, (i) {
            final p = widget.lessonPrices[i];
            final mins = p['duration_minutes'] as int? ?? 0;
            final selected = i == _selectedDurationIndex;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedDurationIndex = i;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF272942) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: selected ? const Color(0xFF272942) : const Color(0xFFDDDDDD),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  '$mins min',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: selected ? Colors.white : const Color(0xFF272942),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ── Time section ──────────────────────────────────────────────────────────

  Widget _buildTimeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Time',
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF272942),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Start
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Start',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _showTimePicker,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _startTime ?? '--:--',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _startTime != null
                              ? const Color(0xFF272942)
                              : const Color(0xFFAAAAAA),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // End
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'End',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _endTime ?? '--:--',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _endTime != null
                            ? const Color(0xFF272942)
                            : const Color(0xFFAAAAAA),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
