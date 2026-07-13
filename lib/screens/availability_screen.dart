import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
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
  Map<String, dynamic>? _selectedSlot;
  int _selectedDurationIndex = 0;

  List<Map<String, dynamic>> _slots = [];
  bool _isLoadingSlots = false;

  static const _dayHeaders = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
  static const _monthNames = [
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];
  static const _dayOfWeekNames = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _selectedDate = now;
    _fetchSlots();
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

  Future<void> _fetchSlots() async {
    final date = _selectedDate;
    if (date == null) return;

    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final duration = _selectedDurationMinutes;

    setState(() {
      _isLoadingSlots = true;
      _selectedSlot = null;
    });

    try {
      final data = await ApiService.get(
        '/tutors/${widget.tutorId}/availability/?date=$dateStr&duration=$duration',
      );
      if (!mounted) return;
      final rawSlots = data['slots'] as List<dynamic>? ?? [];
      setState(() {
        _slots = rawSlots
            .cast<Map<String, dynamic>>()
            .where((s) => s['is_past'] != true && s['is_booked'] != true)
            .toList();
        _isLoadingSlots = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _slots = [];
        _isLoadingSlots = false;
      });
    }
  }

  String? _formatTime(String? isoString) {
    if (isoString == null) return null;
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return null;
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String? get _startTime => _formatTime(_selectedSlot?['start_at'] as String?);
  String? get _endTime => _formatTime(_selectedSlot?['end_at'] as String?);

  bool get _canProceed => _selectedDate != null && _selectedSlot != null;

  void _onNext() {
    if (!_canProceed) return;
    final startAt = DateTime.parse(_selectedSlot!['start_at'] as String).toLocal();

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
      backgroundColor: context.colors.background,
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
                    child: Icon(Icons.chevron_left_rounded, size: 30, color: context.colors.textPrimary),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Availability',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
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
                    _buildDurationSection(),
                    const SizedBox(height: 24),
                    _buildSlotsSection(),
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
                        foregroundColor: context.colors.textPrimary,
                        side: BorderSide(color: context.colors.textPrimary, width: 1.5),
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
                        backgroundColor: _canProceed ? context.colors.brand : context.colors.border,
                        foregroundColor: _canProceed ? Colors.white : context.colors.textSecondary,
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
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
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
                child: Icon(Icons.chevron_left, color: context.colors.textPrimary, size: 24),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_monthNames[month - 1]} $year',
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
                onTap: () => setState(() {
                  _focusedMonth = DateTime(year, month + 1);
                }),
                child: Icon(Icons.chevron_right, color: context.colors.textPrimary, size: 24),
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
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textTertiary,
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
                      onTap: isPast ? null : () {
                        setState(() => _selectedDate = date);
                        _fetchSlots();
                      },
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
              onTap: () {
                setState(() => _selectedDurationIndex = i);
                _fetchSlots();
              },
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

  // ── Slots section ─────────────────────────────────────────────────────────

  Widget _buildSlotsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Available slots',
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF272942),
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoadingSlots)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF272942),
              ),
            ),
          )
        else if (_slots.isEmpty)
          const Text(
            'No available slots for this day',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 14,
              color: Color(0xFF9E9E9E),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _slots.map((slot) {
              final start = _formatTime(slot['start_at'] as String?);
              final end = _formatTime(slot['end_at'] as String?);
              final label = '$start - $end';
              final selected = _selectedSlot == slot;
              return GestureDetector(
                onTap: () => setState(() => _selectedSlot = slot),
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
                    label,
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
                  Container(
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
