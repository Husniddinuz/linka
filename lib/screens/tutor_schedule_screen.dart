import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import '../services/user_service.dart';
import '../widgets/app_notify.dart';
import '../widgets/skeleton.dart';

class TutorScheduleScreen extends StatefulWidget {
  const TutorScheduleScreen({super.key});

  @override
  State<TutorScheduleScreen> createState() => _TutorScheduleScreenState();
}

class _TutorScheduleScreenState extends State<TutorScheduleScreen> {
  List<Map<String, dynamic>> _slots = [];
  bool _loading = true;
  String? _error;
  int? _tutorId;

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final me = UserService.current ?? await UserService.fetchMe();
      _tutorId = me.tutorProfileId;
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _load() async {
    if (_tutorId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getList('/tutors/$_tutorId/availability/');
      dev.log('availability response: $data', name: 'schedule');
      if (!mounted) return;
      setState(() {
        _slots = data.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _deleteSlot(int id) async {
    try {
      await ApiService.delete('/tutor/availability/$id/');
      if (!mounted) return;
      setState(() => _slots.removeWhere((s) => s['id'] == id));
      AppNotify.show(context, message: 'Removed', type: NotifyType.success);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    }
  }

  Future<void> _openAddSheet() async {
    if (_tutorId == null) return;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _AddSlotSheet(tutorId: _tutorId!),
      ),
    );
    if (added == true) await _load();
  }

  // Group slots by day_of_week
  Map<int, List<Map<String, dynamic>>> get _grouped {
    final map = <int, List<Map<String, dynamic>>>{};
    for (final s in _slots) {
      final day = (s['day_of_week'] as num?)?.toInt() ?? 0;
      (map[day] ??= []).add(s);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _Header(onAdd: _openAddSheet),
            const SizedBox(height: 16),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const _LoadingSkeleton();
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _init);
    }
    if (_slots.isEmpty) return _EmptyState(onAdd: _openAddSheet);

    final grouped = _grouped;
    final sortedDays = grouped.keys.toList()..sort();

    return RefreshIndicator(
      color: const Color(0xFF272942),
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          for (final day in sortedDays) ...[
            _DayHeader(day: _days[day.clamp(0, 6)]),
            const SizedBox(height: 8),
            for (final slot in grouped[day]!) ...[
              _SlotCard(
                slot: slot,
                onDelete: () => _deleteSlot((slot['id'] as num).toInt()),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onAdd;
  const _Header({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: const Icon(
              Icons.chevron_left_rounded,
              size: 30,
              color: Color(0xFF272942),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'My schedule',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF272942),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: onAdd,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF272942),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Day section header ───────────────────────────────────────────────────────

class _DayHeader extends StatelessWidget {
  final String day;
  const _DayHeader({required this.day});

  @override
  Widget build(BuildContext context) {
    return Text(
      day,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF999999),
        letterSpacing: 0.3,
      ),
    );
  }
}

// ─── Slot card ────────────────────────────────────────────────────────────────

class _SlotCard extends StatelessWidget {
  final Map<String, dynamic> slot;
  final VoidCallback onDelete;
  const _SlotCard({required this.slot, required this.onDelete});

  // "10:00:00" → "10:00", already "10:00" passes through
  static String _trimSecs(String t) {
    final parts = t.split(':');
    if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
    return t;
  }

  // Returns ("09:00", "12:00") from "09:00-12:00" or "09:00:00-12:00:00"
  // Returns ("10:00", null) for a single time
  static (String from, String? until) _parse(String raw) {
    final idx = raw.indexOf('-');
    if (idx > 0) {
      return (_trimSecs(raw.substring(0, idx)), _trimSecs(raw.substring(idx + 1)));
    }
    return (_trimSecs(raw), null);
  }

  @override
  Widget build(BuildContext context) {
    final raw = slot['available_time'] as String? ?? '';
    final (from, until) = _parse(raw);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                _TimeBox(label: 'From', time: from),
                const SizedBox(width: 8),
                const Text(
                  '—',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFFCCCCCC),
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(width: 8),
                _TimeBox(label: 'Until', time: until ?? '—'),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _confirmDelete(context),
            behavior: HitTestBehavior.opaque,
            child: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFCCCCCC),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove slot',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF272942),
          ),
        ),
        content: const Text(
          'Remove this availability window?',
          style: TextStyle(fontSize: 14, color: Color(0xFF555555)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF999999)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Color(0xFFE74C3C)),
            ),
          ),
        ],
      ),
    );
    if (ok == true) onDelete();
  }
}

// ─── Time box label ───────────────────────────────────────────────────────────

class _TimeBox extends StatelessWidget {
  final String label;
  final String time;
  const _TimeBox({required this.label, required this.time});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: Color(0xFF999999),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          time,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF272942),
          ),
        ),
      ],
    );
  }
}

// ─── Add slot bottom sheet ────────────────────────────────────────────────────

class _AddSlotSheet extends StatefulWidget {
  final int tutorId;
  const _AddSlotSheet({required this.tutorId});

  @override
  State<_AddSlotSheet> createState() => _AddSlotSheetState();
}

class _AddSlotSheetState extends State<_AddSlotSheet> {
  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  static final _hours = List.generate(24, (i) => i.toString().padLeft(2, '0'));
  static final _minutes = ['00', '05', '10', '15', '20', '25', '30', '35', '40', '45', '50', '55'];

  int _selectedDay = 0;
  int _startHour = 9;
  int _startMinuteIdx = 0; // index into _minutes
  int _endHour = 12;
  int _endMinuteIdx = 0;
  bool _saving = false;

  late final FixedExtentScrollController _startHourCtrl;
  late final FixedExtentScrollController _startMinCtrl;
  late final FixedExtentScrollController _endHourCtrl;
  late final FixedExtentScrollController _endMinCtrl;

  @override
  void initState() {
    super.initState();
    _startHourCtrl = FixedExtentScrollController(initialItem: _startHour);
    _startMinCtrl = FixedExtentScrollController(initialItem: _startMinuteIdx);
    _endHourCtrl = FixedExtentScrollController(initialItem: _endHour);
    _endMinCtrl = FixedExtentScrollController(initialItem: _endMinuteIdx);
  }

  @override
  void dispose() {
    _startHourCtrl.dispose();
    _startMinCtrl.dispose();
    _endHourCtrl.dispose();
    _endMinCtrl.dispose();
    super.dispose();
  }

  String _fmtTime(int hour, int minuteIdx) =>
      '${hour.toString().padLeft(2, '0')}:${_minutes[minuteIdx]}:00';

  bool get _valid {
    final startMins = _startHour * 60 + int.parse(_minutes[_startMinuteIdx]);
    final endMins = _endHour * 60 + int.parse(_minutes[_endMinuteIdx]);
    return endMins > startMins;
  }

  Future<void> _save() async {
    if (!_valid) {
      AppNotify.show(context, message: 'End time must be after start time');
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService.post('/tutor/availability/', {
        'tutor': widget.tutorId,
        'day_of_week': _selectedDay,
        'available_time': '${_fmtTime(_startHour, _startMinuteIdx)}-${_fmtTime(_endHour, _endMinuteIdx)}',
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Add availability window',
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700,
                color: Color(0xFF272942),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Day of week',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF999999)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _days.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final selected = _selectedDay == i;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedDay = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF272942) : const Color(0xFFF2F2F2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _days[i].substring(0, 3),
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : const Color(0xFF272942),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            // Drum pickers: From ——— Until
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'From',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF999999)),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _DrumPicker(
                              items: _hours,
                              controller: _startHourCtrl,
                              onChanged: (i) => setState(() => _startHour = i),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                ':',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF272942)),
                              ),
                            ),
                            _DrumPicker(
                              items: _minutes,
                              controller: _startMinCtrl,
                              onChanged: (i) => setState(() => _startMinuteIdx = i),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Text(
                      '—',
                      style: TextStyle(fontSize: 20, color: Color(0xFFCCCCCC), fontWeight: FontWeight.w300),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Until',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF999999)),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _DrumPicker(
                              items: _hours,
                              controller: _endHourCtrl,
                              onChanged: (i) => setState(() => _endHour = i),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                ':',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF272942)),
                              ),
                            ),
                            _DrumPicker(
                              items: _minutes,
                              controller: _endMinCtrl,
                              onChanged: (i) => setState(() => _endMinuteIdx = i),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _saving ? null : _save,
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF272942),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Add window',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Drum picker ──────────────────────────────────────────────────────────────

class _DrumPicker extends StatelessWidget {
  final List<String> items;
  final FixedExtentScrollController controller;
  final ValueChanged<int> onChanged;

  const _DrumPicker({
    required this.items,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 120,
      child: Stack(
        children: [
          // highlight band behind selected item
          Center(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: 40,
            perspective: 0.003,
            diameterRatio: 2.2,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: onChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: items.length,
              builder: (_, i) => Center(
                child: Text(
                  items[i],
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF272942),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// ─── Loading skeleton ─────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: List.generate(4, (i) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(height: 14, width: 80, borderRadius: 6),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Skeleton(height: 20, width: 20, borderRadius: 4),
                SizedBox(width: 12),
                Skeleton(height: 16, width: 140, borderRadius: 6),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      )),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/images/icons/calendar_outline_20.svg',
            width: 48,
            height: 48,
            colorFilter: const ColorFilter.mode(
              Color(0xFFCCCCCC),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No availability windows',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFF272942),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Add windows so students know when you\'re available.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Color(0xFF999999),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
              decoration: BoxDecoration(
                color: const Color(0xFF272942),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Add window',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Error state ──────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF999999)),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF272942),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
