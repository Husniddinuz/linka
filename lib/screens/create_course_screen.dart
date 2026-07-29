import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/course.dart';
import '../services/api_service.dart';
import '../services/course_service.dart';
import '../theme/app_colors.dart';
import '../widgets/cached_avatar.dart';

/// Create a new course, or edit an existing one. In edit mode, price and dates
/// are locked once anyone has enrolled (the backend enforces this too).
class CreateCourseScreen extends StatefulWidget {
  final Course? existing;
  const CreateCourseScreen({super.key, this.existing});

  @override
  State<CreateCourseScreen> createState() => _CreateCourseScreenState();
}

class _CreateCourseScreenState extends State<CreateCourseScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _category = TextEditingController();
  final _price = TextEditingController();
  final _maxStudents = TextEditingController();
  final _schedule = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  /// False while the end date is still the one-month default, so moving the
  /// start date keeps carrying it along; true once the tutor picks their own.
  bool _endDateEdited = false;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  TutorSearchResult? _coTutor;
  File? _banner;
  bool _submitting = false;

  static TimeOfDay? _parseTime(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  /// Explains the pre-filled window: courses are one month long by default,
  /// and the tutor can shorten or extend it by picking another end date.
  String get _durationHint {
    final s = _startDate, e = _endDate;
    if (s == null || e == null) {
      return 'Courses run for one month by default — pick a start date and the '
          'end date fills in.';
    }
    final days = e.difference(s).inDays + 1;
    final label = days >= 28
        ? '${(days / 30.44).round()} month(s)'
        : (days >= 7 ? '${(days / 7).round()} week(s)' : '$days day(s)');
    return 'Runs for $label. Change the end date for a longer or shorter course.';
  }

  bool get _isEdit => widget.existing != null;
  bool get _termsLocked =>
      _isEdit && (widget.existing?.enrolledCount ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    if (c != null) {
      _title.text = c.title;
      _description.text = c.description;
      _category.text = c.category;
      _price.text = c.isFree ? '0' : c.priceUzs.round().toString();
      _maxStudents.text = c.maxStudents.toString();
      _schedule.text = c.scheduleDetails;
      _startDate = c.startDate;
      _endDate = c.endDate;
      _endDateEdited = true; // an existing course's window is the tutor's own
      _startTime = _parseTime(c.startTime);
      _endTime = _parseTime(c.endTime);
      if (c.coTutorId != null) {
        _coTutor = TutorSearchResult(
          id: c.coTutorId!,
          name: c.coTutorName ?? 'Co-tutor',
          imageUrl: c.coTutorImageUrl,
        );
      }
    }
  }

  @override
  void dispose() {
    for (final ctrl in [
      _title,
      _description,
      _category,
      _price,
      _maxStudents,
      _schedule,
    ]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBanner() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: context.colors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Symbols.photo_library_rounded,
                  color: context.colors.textPrimary),
              title: Text('Choose from gallery',
                  style: TextStyle(color: context.colors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(Symbols.photo_camera_rounded,
                  color: context.colors.textPrimary),
              title: Text('Take a photo',
                  style: TextStyle(color: context.colors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked =
        await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked != null && mounted) {
      setState(() => _banner = File(picked.path));
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _startDate : _endDate) ??
        (isStart ? now : (_startDate ?? now));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        // A course runs for one month unless the tutor says otherwise: the end
        // date trails the start until they pick one themselves — and a start
        // date moved past their choice resets it rather than going invalid.
        if (!_endDateEdited || _endDate == null || _endDate!.isBefore(picked)) {
          _endDate = _plusOneMonth(picked);
        }
      } else {
        _endDate = picked;
        _endDateEdited = true;
      }
    });
  }

  /// [day] one month later, clamped to the last day of the target month
  /// (31 Jan → 28/29 Feb), matching `apps.courses.services.add_months`.
  static DateTime _plusOneMonth(DateTime day) {
    final year = day.month == 12 ? day.year + 1 : day.year;
    final month = day.month == 12 ? 1 : day.month + 1;
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day.day < lastDayOfMonth ? day.day : lastDayOfMonth);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _startTime : _endTime) ??
          const TimeOfDay(hour: 16, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _pickCoTutor() async {
    final selected = await showModalBottomSheet<TutorSearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CoTutorPickerSheet(),
    );
    if (selected != null && mounted) setState(() => _coTutor = selected);
  }

  String? _validate() {
    if (_title.text.trim().isEmpty) return 'Please enter a title.';
    final max = int.tryParse(_maxStudents.text.trim());
    if (max == null || max < 1) return 'Max students must be at least 1.';
    final price = double.tryParse(_price.text.trim().isEmpty ? '0' : _price.text.trim());
    if (price == null || price < 0) return 'Enter a valid price (0 for free).';
    if (_startDate == null || _endDate == null) return 'Please pick start and end dates.';
    if (_endDate!.isBefore(_startDate!)) return 'End date must be after the start date.';
    if (_startTime == null || _endTime == null) {
      return 'Please set the daily session start and end times.';
    }
    if (_minutes(_endTime!) <= _minutes(_startTime!)) {
      return 'Session end time must be after the start time.';
    }
    if (_termsLocked && max < (widget.existing?.enrolledCount ?? 0)) {
      return 'Max students cannot be below the ${widget.existing?.enrolledCount} already enrolled.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final error = _validate();
    if (error != null) {
      _showSnack(error);
      return;
    }
    setState(() => _submitting = true);
    final price = double.parse(_price.text.trim().isEmpty ? '0' : _price.text.trim());
    final max = int.parse(_maxStudents.text.trim());
    try {
      if (_isEdit) {
        final fields = <String, dynamic>{
          'title': _title.text.trim(),
          'description': _description.text.trim(),
          'category': _category.text.trim(),
          'max_students': max,
          'schedule_details': _schedule.text.trim(),
        };
        // Only send locked fields when they're still editable (no enrollments).
        if (!_termsLocked) {
          fields['price_uzs'] = price.toStringAsFixed(2);
          fields['start_date'] = _fmt(_startDate!);
          fields['end_date'] = _fmt(_endDate!);
          fields['start_time'] = _fmtTime(_startTime!);
          fields['end_time'] = _fmtTime(_endTime!);
          fields['co_tutor_id'] = _coTutor?.id;
        }
        await CourseService.updateCourse(widget.existing!.id, fields);
      } else {
        await CourseService.createCourse(
          title: _title.text.trim(),
          description: _description.text.trim(),
          category: _category.text.trim(),
          priceUzs: price,
          maxStudents: max,
          startDate: _startDate!,
          endDate: _endDate!,
          startTime: _fmtTime(_startTime!),
          endTime: _fmtTime(_endTime!),
          scheduleDetails: _schedule.text.trim(),
          coTutorId: _coTutor?.id,
          banner: _banner,
        );
      }
      if (!mounted) return;
      _showSnack(_isEdit ? 'Course updated' : 'Course created');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.chevron_left, color: colors.textPrimary, size: 28),
        ),
        title: Text(
          _isEdit ? 'Edit course' : 'New course',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BannerPicker(
              file: _banner,
              existingUrl: widget.existing?.bannerUrl,
              onTap: _pickBanner,
              colors: colors,
            ),
            const SizedBox(height: 20),
            _Field(label: 'Title', controller: _title, colors: colors, hint: 'e.g. IELTS Speaking Intensive'),
            _Field(
              label: 'Description',
              controller: _description,
              colors: colors,
              hint: 'What students will learn',
              maxLines: 4,
            ),
            _Field(label: 'Category', controller: _category, colors: colors, hint: 'e.g. Speaking (optional)'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Field(
                    label: 'Price (UZS)',
                    controller: _price,
                    colors: colors,
                    hint: '0 = free',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    enabled: !_termsLocked,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _Field(
                    label: 'Max students',
                    controller: _maxStudents,
                    colors: colors,
                    hint: 'e.g. 15',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Start date',
                    value: _startDate,
                    onTap: _termsLocked ? null : () => _pickDate(isStart: true),
                    colors: colors,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _DateField(
                    label: 'End date',
                    value: _endDate,
                    onTap: _termsLocked ? null : () => _pickDate(isStart: false),
                    colors: colors,
                  ),
                ),
              ],
            ),
            if (!_termsLocked)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  _durationHint,
                  style: TextStyle(fontSize: 12, color: colors.textTertiary),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _TimeField(
                    label: 'Start time',
                    value: _startTime,
                    onTap: _termsLocked ? null : () => _pickTime(isStart: true),
                    colors: colors,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _TimeField(
                    label: 'End time',
                    value: _endTime,
                    onTap: _termsLocked ? null : () => _pickTime(isStart: false),
                    colors: colors,
                  ),
                ),
              ],
            ),
            Text(
              'The course runs at this time every day within the date range.',
              style: TextStyle(fontSize: 12, color: colors.textTertiary),
            ),
            if (_termsLocked)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  'Price, dates, times and co-tutor are locked — students have already enrolled.',
                  style: TextStyle(fontSize: 12, color: colors.textTertiary),
                ),
              ),
            const SizedBox(height: 16),
            _CoTutorField(
              coTutor: _coTutor,
              enabled: !_termsLocked,
              onPick: _pickCoTutor,
              onRemove: () => setState(() => _coTutor = null),
              colors: colors,
            ),
            const SizedBox(height: 4),
            _Field(
              label: 'Schedule details',
              controller: _schedule,
              colors: colors,
              hint: "e.g. Mon–Fri, 6pm (optional)",
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Symbols.videocam_rounded, size: 16, color: colors.textTertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Live sessions run in a Daily.co video room created automatically — no link needed.',
                      style: TextStyle(fontSize: 12, color: colors.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.textPrimary,
                  foregroundColor: colors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _submitting
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: colors.background,
                        ),
                      )
                    : Text(
                        _isEdit ? 'Save changes' : 'Create course',
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerPicker extends StatelessWidget {
  final File? file;
  final String? existingUrl;
  final VoidCallback onTap;
  final AppColors colors;
  const _BannerPicker({
    required this.file,
    required this.existingUrl,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 16 / 8,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          clipBehavior: Clip.hardEdge,
          child: file != null
              ? Image.file(file!, fit: BoxFit.cover)
              : existingUrl != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(existingUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink()),
                        _overlayHint(),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Symbols.add_photo_alternate_rounded,
                            size: 34, color: colors.textTertiary),
                        const SizedBox(height: 8),
                        Text('Add a banner (optional)',
                            style: TextStyle(
                                fontSize: 13, color: colors.textTertiary)),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _overlayHint() => Container(
        alignment: Alignment.bottomRight,
        padding: const EdgeInsets.all(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('Change',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
      );
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final AppColors colors;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  const _Field({
    required this.label,
    required this.controller,
    required this.colors,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            enabled: enabled,
            maxLines: maxLines,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: TextStyle(fontSize: 15, color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
              filled: true,
              fillColor: enabled ? colors.surfaceAlt : colors.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.textPrimary),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback? onTap;
  final AppColors colors;
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: enabled ? colors.surfaceAlt : colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Icon(Symbols.calendar_month_rounded,
                      size: 18, color: colors.textTertiary),
                  const SizedBox(width: 8),
                  Text(
                    value == null
                        ? 'Select'
                        : '${value!.day}/${value!.month}/${value!.year}',
                    style: TextStyle(
                      fontSize: 14.5,
                      color: value == null
                          ? colors.textTertiary
                          : colors.textPrimary,
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

class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final VoidCallback? onTap;
  final AppColors colors;
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final text = value == null
        ? 'Select'
        : '${value!.hour.toString().padLeft(2, '0')}:${value!.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: enabled ? colors.surfaceAlt : colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Icon(Symbols.schedule_rounded, size: 18, color: colors.textTertiary),
                  const SizedBox(width: 8),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: value == null ? colors.textTertiary : colors.textPrimary,
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

class _CoTutorField extends StatelessWidget {
  final TutorSearchResult? coTutor;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final AppColors colors;
  const _CoTutorField({
    required this.coTutor,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Co-tutor (optional)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        if (coTutor != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                CachedAvatar(imageUrl: coTutor!.imageUrl, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    coTutor!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (enabled)
                  GestureDetector(
                    onTap: onRemove,
                    child: Icon(Symbols.close_rounded, size: 20, color: colors.textTertiary),
                  ),
              ],
            ),
          )
        else
          GestureDetector(
            onTap: enabled ? onPick : null,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: enabled ? colors.surfaceAlt : colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Icon(Symbols.person_add_rounded, size: 18, color: colors.textTertiary),
                  const SizedBox(width: 8),
                  Text(
                    'Add a co-tutor',
                    style: TextStyle(fontSize: 14.5, color: colors.textTertiary),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CoTutorPickerSheet extends StatefulWidget {
  const _CoTutorPickerSheet();

  @override
  State<_CoTutorPickerSheet> createState() => _CoTutorPickerSheetState();
}

class _CoTutorPickerSheetState extends State<_CoTutorPickerSheet> {
  final _controller = TextEditingController();
  List<TutorSearchResult> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await CourseService.searchTutors(q.trim());
      if (!mounted) return;
      setState(() {
        _results = res;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _search,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search tutors by name',
                  hintStyle: TextStyle(color: colors.textTertiary),
                  prefixIcon: Icon(Icons.search, color: colors.textTertiary),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: colors.accentYellow))
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            _controller.text.trim().length < 2
                                ? 'Type a name to search'
                                : 'No tutors found',
                            style: TextStyle(color: colors.textTertiary),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final t = _results[i];
                            return ListTile(
                              leading: CachedAvatar(imageUrl: t.imageUrl, size: 40),
                              title: Text(
                                t.name,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onTap: () => Navigator.pop(context, t),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
