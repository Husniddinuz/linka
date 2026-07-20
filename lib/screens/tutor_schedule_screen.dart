import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
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

  Future<void> _openAddSheet({int initialDay = 0}) async {
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
        child: _AddSlotSheet(tutorId: _tutorId!, initialDay: initialDay),
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

  String get _subtitle {
    if (_loading) return 'Loading…';
    if (_slots.isEmpty) return 'Set your weekly availability';
    final days = _grouped.keys.length;
    final total = _slots.fold<int>(0, (sum, s) {
      final d = _SlotTime.of(s).durationMinutes;
      return sum + (d ?? 0);
    });
    final hours = _fmtMinutes(total);
    return hours == null
        ? '${_slots.length} slot${_slots.length == 1 ? '' : 's'} · '
            '$days day${days == 1 ? '' : 's'}'
        : '$hours per week · $days day${days == 1 ? '' : 's'}';
  }

  static String? _fmtMinutes(int minutes) {
    if (minutes <= 0) return null;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvas = isDark ? colors.background : colors.surfaceAlt;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: canvas,
        floatingActionButton: (_loading || _error != null)
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _openAddSheet(
                    initialDay: DateTime.now().weekday - 1),
                backgroundColor: colors.brand,
                foregroundColor: colors.onBrand,
                elevation: 2,
                icon: const Icon(Symbols.add_rounded, weight: 600),
                label: const Text(
                  'Add slot',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
        body: Column(
          children: [
            _Hero(subtitle: _subtitle),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const _LoadingSkeleton();
    if (_error != null) return _ErrorState(message: _error!, onRetry: _init);

    final grouped = _grouped;
    final today = DateTime.now().weekday - 1;

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: context.colors.brand,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          if (_slots.isEmpty) ...[
            const _FirstRunHint(),
            const SizedBox(height: 14),
          ],
          for (int day = 0; day < 7; day++) ...[
            _DayCard(
              dayName: _days[day],
              isToday: day == today,
              slots: grouped[day] ?? const [],
              totalLabel: _fmtMinutes(
                (grouped[day] ?? const []).fold<int>(
                  0,
                  (sum, s) => sum + (_SlotTime.of(s).durationMinutes ?? 0),
                ),
              ),
              onAdd: () => _openAddSheet(initialDay: day),
              onDelete: _deleteSlot,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

// ─── Hero header ────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  final String subtitle;
  const _Hero({required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gradientEnd = Color.lerp(colors.brand, Colors.black, 0.35)!;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.brand, gradientEnd],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -26,
            child: Icon(
              Symbols.calendar_month_rounded,
              size: 110,
              fill: 1,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Symbols.arrow_back_ios_new_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'My schedule',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── First-run hint ─────────────────────────────────────────────────────────

class _FirstRunHint extends StatelessWidget {
  const _FirstRunHint();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.accentYellow.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.accentYellow.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Symbols.lightbulb_rounded,
            size: 20,
            fill: 1,
            color: Theme.of(context).brightness == Brightness.dark
                ? colors.accentYellow
                : const Color(0xFFB8860B),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Add your available windows so students know when to book you. '
              'Tap + on any day to get started.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Slot time parsing ──────────────────────────────────────────────────────

class _SlotTime {
  final String from;
  final String? until;
  const _SlotTime(this.from, this.until);

  static String _trimSecs(String t) {
    final parts = t.split(':');
    if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
    return t;
  }

  factory _SlotTime.of(Map<String, dynamic> slot) {
    final raw = slot['available_time'] as String? ?? '';
    final rawEnd = slot['available_time_end'] as String?;
    if (rawEnd != null && rawEnd.isNotEmpty) {
      return _SlotTime(_trimSecs(raw), _trimSecs(rawEnd));
    }
    // Legacy rows encode "HH:MM-HH:MM" in a single field.
    final idx = raw.indexOf('-');
    if (idx > 0) {
      return _SlotTime(
        _trimSecs(raw.substring(0, idx)),
        _trimSecs(raw.substring(idx + 1)),
      );
    }
    return _SlotTime(_trimSecs(raw), null);
  }

  static int? _toMinutes(String? t) {
    if (t == null) return null;
    final parts = t.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  int? get durationMinutes {
    final start = _toMinutes(from);
    final end = _toMinutes(until);
    if (start == null || end == null || end <= start) return null;
    return end - start;
  }

  String? get durationLabel {
    final d = durationMinutes;
    if (d == null) return null;
    final h = d ~/ 60;
    final m = d % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}

// ─── Day card ───────────────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  final String dayName;
  final bool isToday;
  final List<Map<String, dynamic>> slots;
  final String? totalLabel;
  final VoidCallback onAdd;
  final void Function(int id) onDelete;

  const _DayCard({
    required this.dayName,
    required this.isToday,
    required this.slots,
    required this.totalLabel,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Day header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                Text(
                  dayName,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                if (isToday) ...[
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.accentYellow,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      'TODAY',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        // Fixed navy for contrast on gold in both themes.
                        color: Color(0xFF272942),
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (totalLabel != null) ...[
                  Text(
                    totalLabel!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                GestureDetector(
                  onTap: onAdd,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Symbols.add_rounded,
                      size: 18,
                      weight: 600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (slots.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Not available',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textTertiary,
                  ),
                ),
              ),
            )
          else ...[
            Divider(height: 1, color: colors.border),
            for (int i = 0; i < slots.length; i++) ...[
              _SlotRow(
                slot: slots[i],
                onDelete: () => onDelete((slots[i]['id'] as num).toInt()),
              ),
              if (i < slots.length - 1)
                Divider(
                    height: 1,
                    indent: 14,
                    endIndent: 14,
                    color: colors.border),
            ],
          ],
        ],
      ),
    );
  }
}

// ─── Slot row ───────────────────────────────────────────────────────────────

class _SlotRow extends StatelessWidget {
  final Map<String, dynamic> slot;
  final VoidCallback onDelete;
  const _SlotRow({required this.slot, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final time = _SlotTime.of(slot);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Icon(
            Symbols.schedule_rounded,
            color: colors.textTertiary,
            size: 16,
            opticalSize: 20,
          ),
          const SizedBox(width: 10),
          Text(
            time.until != null ? '${time.from} – ${time.until}' : time.from,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
          if (time.durationLabel != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                time.durationLabel!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                  height: 1.3,
                ),
              ),
            ),
          ],
          const Spacer(),
          GestureDetector(
            onTap: () => _confirmDelete(context),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Symbols.delete_rounded,
                color: colors.textTertiary,
                size: 18,
                opticalSize: 20,
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
        backgroundColor: ctx.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Remove slot?',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: ctx.colors.textPrimary),
        ),
        content: Text(
          'Remove this availability window?',
          style: TextStyle(fontSize: 14, color: ctx.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: ctx.colors.textSecondary)),
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
  final int initialDay;
  const _AddSlotSheet({required this.tutorId, this.initialDay = 0});

  @override
  State<_AddSlotSheet> createState() => _AddSlotSheetState();
}

class _AddSlotSheetState extends State<_AddSlotSheet> {
  static const _dayAbbr = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  static final _hours = List.generate(24, (i) => i.toString().padLeft(2, '0'));
  static final _minutes = [
    '00', '05', '10', '15', '20', '25', '30', '35', '40', '45', '50', '55',
  ];

  late int _selectedDay = widget.initialDay.clamp(0, 6);
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

  int get _durationMins {
    final startMins = _startHour * 60 + int.parse(_minutes[_startMinuteIdx]);
    final endMins = _endHour * 60 + int.parse(_minutes[_endMinuteIdx]);
    return endMins - startMins;
  }

  bool get _valid => _durationMins > 0;

  String get _durationLabel {
    final d = _durationMins;
    if (d <= 0) return 'End time must be after start time';
    final h = d ~/ 60;
    final m = d % 60;
    final label = h == 0
        ? '${m}m'
        : m == 0
            ? '${h}h'
            : '${h}h ${m}m';
    return 'Duration: $label';
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
      await ApiService.post('/tutor/availability/', body);
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
    final colors = context.colors;
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
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Add availability',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Set when you\'re available for lessons',
              style: TextStyle(
                fontSize: 13,
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(height: 24),

            // Day picker
            Text(
              'DAY OF WEEK',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.textTertiary,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _dayAbbr.length,
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
                        color: selected ? colors.brand : colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(22),
                        border: selected
                            ? null
                            : Border.all(color: colors.border),
                      ),
                      child: Text(
                        _dayAbbr[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? colors.onBrand
                              : colors.textSecondary,
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
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.textTertiary,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'FROM',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: colors.textTertiary,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _DrumPicker(
                              items: _hours,
                              controller: _startHourCtrl,
                              onChanged: (i) =>
                                  setState(() => _startHour = i),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                ':',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            _DrumPicker(
                              items: _minutes,
                              controller: _startMinCtrl,
                              onChanged: (i) =>
                                  setState(() => _startMinuteIdx = i),
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
                          color: colors.border,
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
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: colors.textTertiary,
                            letterSpacing: 1.0,
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                ':',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            _DrumPicker(
                              items: _minutes,
                              controller: _endMinCtrl,
                              onChanged: (i) =>
                                  setState(() => _endMinuteIdx = i),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Live duration preview
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _valid ? Symbols.timelapse_rounded : Symbols.error_rounded,
                  size: 14,
                  color: _valid ? colors.textTertiary : colors.error,
                ),
                const SizedBox(width: 5),
                Text(
                  _durationLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _valid ? colors.textSecondary : colors.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Save button
            GestureDetector(
              onTap: _saving ? null : _save,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _valid ? colors.brand : colors.border,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(
                        'Save slot',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color:
                              _valid ? colors.onBrand : colors.textSecondary,
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
    final colors = context.colors;
    return SizedBox(
      width: 52,
      height: 120,
      child: Stack(
        children: [
          Center(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.05),
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
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
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
    final colors = context.colors;
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: const Row(
          children: [
            Skeleton(height: 15, width: 90, borderRadius: 6),
            Spacer(),
            Skeleton(height: 30, width: 30, borderRadius: 10),
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
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: colors.border),
              ),
              child: Icon(Symbols.wifi_off_rounded,
                  color: colors.textTertiary, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.brand,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.onBrand,
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
