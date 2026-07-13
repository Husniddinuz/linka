import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';

/// Form for a tutor to submit their own IELTS Writing sample (Task 1 or 2)
/// for review. On success, pops with `true` so the caller can refresh its
/// list.
class WritingSampleUploadScreen extends StatefulWidget {
  const WritingSampleUploadScreen({super.key});

  @override
  State<WritingSampleUploadScreen> createState() =>
      _WritingSampleUploadScreenState();
}

class _WritingSampleUploadScreenState extends State<WritingSampleUploadScreen> {
  int _taskNumber = 1;
  final _titleController = TextEditingController();
  final _promptController = TextEditingController();
  final _essayController = TextEditingController();
  final _bandController = TextEditingController();
  final _commentController = TextEditingController();
  File? _chartImage;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _promptController.dispose();
    _essayController.dispose();
    _bandController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickChartImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 85);
    if (file == null || !mounted) return;
    setState(() => _chartImage = File(file.path));
  }

  void _showImageSourceSheet() {
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: colors.textPrimary),
              title: Text('Choose from gallery',
                  style: TextStyle(color: colors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _pickChartImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(Icons.camera_alt_outlined, color: colors.textPrimary),
              title:
                  Text('Take a photo', style: TextStyle(color: colors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _pickChartImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final title = _titleController.text.trim();
    final prompt = _promptController.text.trim();
    final essay = _essayController.text.trim();
    if (title.isEmpty || prompt.isEmpty || essay.isEmpty) {
      AppNotify.show(context,
          message: 'Please fill in the title, prompt, and sample essay.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final band = _bandController.text.trim();
      final comment = _commentController.text.trim();
      await ApiService.postMultipart(
        '/tutor/samples/writing/',
        files: {
          if (_taskNumber == 1 && _chartImage != null)
            'chart_image': _chartImage!,
        },
        fields: {
          'task_number': _taskNumber.toString(),
          'title': title,
          'prompt_html': prompt,
          'sample_essay_html': essay,
          if (band.isNotEmpty) 'band_score': band,
          if (comment.isNotEmpty) 'examiner_comment': comment,
        },
      );

      if (!mounted) return;
      AppNotify.show(context,
          message: 'Writing sample submitted for review!',
          type: NotifyType.success);
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _handleBack() {
    if (_submitting) {
      AppNotify.show(context,
          message: 'Submitting — please keep the app open');
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope(
      canPop: !_submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_submitting) return;
        AppNotify.show(context,
            message: 'Submitting — please keep the app open');
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: colors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            iconTheme: IconThemeData(color: colors.textPrimary),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
              onPressed: _handleBack,
            ),
            title: Text(
              'New writing sample',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _FieldLabel('Task'),
              const SizedBox(height: 8),
              _buildTaskSelector(colors),
              const SizedBox(height: 20),
              _FieldLabel('Title'),
              const SizedBox(height: 6),
              TextField(
                controller: _titleController,
                enabled: !_submitting,
                style: TextStyle(fontSize: 14, color: colors.textPrimary),
                decoration: fieldDecoration(context,
                    hint: 'e.g. Line graph: internet usage by age group'),
              ),
              const SizedBox(height: 16),
              _FieldLabel('Prompt'),
              const SizedBox(height: 6),
              TextField(
                controller: _promptController,
                enabled: !_submitting,
                minLines: 3,
                maxLines: 6,
                style: TextStyle(fontSize: 14, color: colors.textPrimary),
                decoration:
                    fieldDecoration(context, hint: 'Enter the exact task prompt'),
              ),
              const SizedBox(height: 16),
              _FieldLabel('Sample essay'),
              const SizedBox(height: 6),
              TextField(
                controller: _essayController,
                enabled: !_submitting,
                minLines: 6,
                maxLines: 14,
                style: TextStyle(fontSize: 14, color: colors.textPrimary),
                decoration:
                    fieldDecoration(context, hint: 'Write or paste the full essay'),
              ),
              if (_taskNumber == 1) ...[
                const SizedBox(height: 16),
                _FieldLabel('Chart image (optional)'),
                const SizedBox(height: 6),
                _buildChartPicker(colors),
              ],
              const SizedBox(height: 16),
              _FieldLabel('Band score (optional)'),
              const SizedBox(height: 6),
              TextField(
                controller: _bandController,
                enabled: !_submitting,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(fontSize: 14, color: colors.textPrimary),
                decoration: fieldDecoration(context, hint: 'e.g. 7.5'),
              ),
              const SizedBox(height: 16),
              _FieldLabel('Examiner comment (optional)'),
              const SizedBox(height: 6),
              TextField(
                controller: _commentController,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                style: TextStyle(fontSize: 14, color: colors.textPrimary),
                decoration: fieldDecoration(context,
                    hint: 'Overall feedback for this essay'),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.brand,
                    foregroundColor: colors.onBrand,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape:
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: colors.onBrand),
                        )
                      : const Text(
                          'Submit for review',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskSelector(AppColors colors) {
    return Row(
      children: [
        for (final task in [1, 2]) ...[
          if (task > 1) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: _submitting
                  ? null
                  : () => setState(() {
                        _taskNumber = task;
                        if (task != 1) _chartImage = null;
                      }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _taskNumber == task ? colors.brand : colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Task $task',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _taskNumber == task ? colors.onBrand : colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildChartPicker(AppColors colors) {
    final image = _chartImage;
    if (image == null) {
      return GestureDetector(
        onTap: _submitting ? null : _showImageSourceSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.image_outlined, color: colors.textPrimary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Add chart image',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colors.surfaceAlt,
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Image.file(image, width: double.infinity, height: 160, fit: BoxFit.cover),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: _submitting ? null : _showImageSourceSheet,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('Change',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: GestureDetector(
              onTap: _submitting ? null : () => setState(() => _chartImage = null),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared field styling ───────────────────────────────────────────────────

InputDecoration fieldDecoration(BuildContext context, {String? hint}) {
  final colors = context.colors;
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
    filled: true,
    fillColor: colors.surfaceAlt,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colors.brand, width: 1.5),
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: context.colors.textSecondary,
      ),
    );
  }
}
