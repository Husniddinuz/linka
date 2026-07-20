import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/course.dart';
import '../services/api_service.dart';
import '../services/course_service.dart';
import '../theme/app_colors.dart';

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
  final _link = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  File? _banner;
  bool _submitting = false;

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
      _link.text = c.sharedLink;
      _startDate = c.startDate;
      _endDate = c.endDate;
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
      _link,
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
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  String? _validate() {
    if (_title.text.trim().isEmpty) return 'Please enter a title.';
    final max = int.tryParse(_maxStudents.text.trim());
    if (max == null || max < 1) return 'Max students must be at least 1.';
    final price = double.tryParse(_price.text.trim().isEmpty ? '0' : _price.text.trim());
    if (price == null || price < 0) return 'Enter a valid price (0 for free).';
    if (_startDate == null || _endDate == null) return 'Please pick start and end dates.';
    if (_endDate!.isBefore(_startDate!)) return 'End date must be after the start date.';
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
          'shared_link': _link.text.trim(),
        };
        // Only send locked fields when they're still editable (no enrollments).
        if (!_termsLocked) {
          fields['price_uzs'] = price.toStringAsFixed(2);
          fields['start_date'] = _fmt(_startDate!);
          fields['end_date'] = _fmt(_endDate!);
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
          scheduleDetails: _schedule.text.trim(),
          sharedLink: _link.text.trim(),
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
            if (_termsLocked)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  'Price and dates are locked — students have already enrolled.',
                  style: TextStyle(fontSize: 12, color: colors.textTertiary),
                ),
              ),
            const SizedBox(height: 4),
            _Field(
              label: 'Schedule details',
              controller: _schedule,
              colors: colors,
              hint: "e.g. Mon–Fri, 6pm (optional)",
            ),
            _Field(
              label: 'Meeting / group link',
              controller: _link,
              colors: colors,
              hint: 'Telegram / Zoom link — shown to enrolled students',
              keyboardType: TextInputType.url,
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
