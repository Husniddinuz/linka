import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
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
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
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
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _AddSlotSheet(tutorId: _tutorId!),
      ),
    );
    if (added == true) await _load();
  }

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
      backgroundColor: context.colors.surfaceAlt,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _body()),
          ],
        ),
      ),
      floatingActionButton: (_loading || _error != null || _slots.isEmpty)
          ? null
          : FloatingActionButton(
              onPressed: _openAddSheet,
              backgroundColor: context.colors.brand,
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.add_rounded, size: 28),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: context.colors.surface,
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.chevron_left_rounded, size: 28, color: context.colors.textPrimary),
            ),
          ),
          Expanded(
            child: Text(
              'My Schedule',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const _LoadingSkeleton();
    if (_error != null) return _ErrorState(message: _error!, onRetry: _init);
    if (_slots.isEmpty) return _EmptyState(onAdd: _openAddSheet);

    final grouped = _grouped;
    final sortedDays = grouped.keys.toList()..sort();

    return RefreshIndicator(
      color: context.colors.textPrimary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
        children: [
          for (final day in sortedDays) ...[
            _DaySection(
              dayName: _days[day.clamp(0, 6)],
              slots: grouped[day]!,
              onDelete: (id) => _deleteSlot(id),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

// ─── Day section ─────────────────────────────────────────────────────────────

class _DaySection extends StatelessWidget {
  final String dayName;
  final List<Map<String, dynamic>> slots;
  final void Function(int id) onDelete;

  const _DaySection({
    required this.dayName,
    required this.slots,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              dayName,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '· ${slots.length} slot${slots.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: context.colors.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < slots.length; i++) ...[
                _SlotRow(
                  slot: slots[i],
                  onDelete: () => onDelete((slots[i]['id'] as num).toInt()),
                ),
                if (i < slots.length - 1)
                  Divider(height: 1, indent: 16, endIndent: 16, color: context.colors.border),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Slot row ─────────────────────────────────────────────────────────────────

class _SlotRow extends StatelessWidget {
  final Map<String, dynamic> slot;
  final VoidCallback onDelete;
  const _SlotRow({required this.slot, required this.onDelete});

  static String _trimSecs(String t) {
    final parts = t.split(':');
    if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
    return t;
  }

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
    final rawEnd = slot['available_time_end'] as String?;
    final String from;
    final String? until;
    if (rawEnd != null && rawEnd.isNotEmpty) {
      from = _trimSecs(raw);
      until = _trimSecs(rawEnd);
    } else {
      final parsed = _parse(raw);
      from = parsed.$1;
      until = parsed.$2;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(
            Icons.access_time_rounded,
            color: context.colors.textTertiary,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      from,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Container(
                        width: 20,
                        height: 2,
                        decoration: BoxDecoration(
                          color: context.colors.textTertiary,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                    Text(
                      until ?? '—',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: until != null ? context.colors.textPrimary : context.colors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'From  ·  Until',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 11,
                    color: context.colors.textTertiary,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _confirmDelete(context),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.delete_outline_rounded,
                color: context.colors.textTertiary,
                size: 20,
              ),
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
        title: Text(
          'Remove slot?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: ctx.colors.textPrimary),
        ),
        content: Text(
          'Remove this availability window?',
          style: TextStyle(fontSize: 14, color: ctx.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: ctx.colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: TextStyle(color: ctx.colors.error)),
          ),
        ],
      ),
    );
    if (ok == true) onDelete();
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
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const _dayAbbr = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  static final _hours = List.generate(24, (i) => i.toString().padLeft(2, '0'));
  static final _minutes = ['00', '05', '10', '15', '20', '25', '30', '35', '40', '45', '50', '55'];

  int _selectedDay = 0;
  int _startHour = 9;
  int _startMinuteIdx = 0;
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
      final body = {
        'tutor': widget.tutorId,
        'day_of_week': _selectedDay,
        'available_time': _fmtTime(_startHour, _startMinuteIdx),
        'available_time_end': _fmtTime(_endHour, _endMinuteIdx),
      };
      final result = await ApiService.post('/tutor/availability/', body);
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // drag handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Add availability',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Set when you\'re available for lessons',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 13,
                color: context.colors.textTertiary,
              ),
            ),
            const SizedBox(height: 24),

            // Day picker
            Text(
              'DAY OF WEEK',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.colors.textTertiary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? context.colors.brand : context.colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(22),
                        border: selected
                            ? null
                            : Border.all(color: context.colors.border),
                      ),
                      child: Text(
                        _dayAbbr[i],
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : context.colors.textSecondary,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Time pickers
            Text(
              'TIME RANGE',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.colors.textTertiary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: context.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.colors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'FROM',
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textTertiary,
                            letterSpacing: 0.8,
                          ),
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
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                ':',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: context.colors.textPrimary,
                                ),
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
                  Column(
                    children: [
                      const SizedBox(height: 18),
                      Container(
                        width: 28,
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: context.colors.border,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'UNTIL',
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textTertiary,
                            letterSpacing: 0.8,
                          ),
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
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                ':',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: context.colors.textPrimary,
                                ),
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
            const SizedBox(height: 28),

            // Save button
            GestureDetector(
              onTap: _saving ? null : _save,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _valid ? context.colors.brand : context.colors.border,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text(
                        'Save slot',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
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
          Center(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
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
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
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
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: List.generate(3, (_) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Skeleton(height: 28, width: 100, borderRadius: 20),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: List.generate(2, (j) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      const Skeleton(height: 40, width: 40, borderRadius: 12),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Skeleton(height: 20, width: 120, borderRadius: 6),
                          SizedBox(height: 6),
                          Skeleton(height: 11, width: 70, borderRadius: 4),
                        ],
                      ),
                    ],
                  ),
                )),
              ),
            ),
          ],
        ),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.colors.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/images/icons/calendar_outline_20.svg',
                  width: 36,
                  height: 36,
                  colorFilter: ColorFilter.mode(
                    context.colors.textTertiary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No slots yet',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your available windows so students know when to book you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 14,
                color: context.colors.textTertiary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  color: context.colors.brand,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Add first slot',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
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
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.colors.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.wifi_off_rounded, color: context.colors.textTertiary, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 14,
                color: context.colors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: context.colors.brand,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
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
