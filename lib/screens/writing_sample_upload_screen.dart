import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';

/// Form for a tutor to submit their own IELTS Writing sample essay for
/// review, against an admin-curated topic. The tutor first picks a
/// [_WritingTopic] (which supplies the task number, prompt, and optional
/// chart/graph image) and then writes their sample essay for it. On
/// success, pops with `true` so the caller can refresh its list.
class WritingSampleUploadScreen extends StatefulWidget {
  const WritingSampleUploadScreen({super.key});

  @override
  State<WritingSampleUploadScreen> createState() =>
      _WritingSampleUploadScreenState();
}

class _WritingSampleUploadScreenState extends State<WritingSampleUploadScreen> {
  final _essayController = TextEditingController();
  final _bandController = TextEditingController();
  final _commentController = TextEditingController();

  List<_WritingTopic> _topics = [];
  bool _loadingTopics = true;
  bool _topicsFailed = false;
  _WritingTopic? _selectedTopic;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  @override
  void dispose() {
    _essayController.dispose();
    _bandController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadTopics() async {
    setState(() {
      _loadingTopics = true;
      _topicsFailed = false;
    });
    try {
      final list = await ApiService.getList('/tutor/samples/writing/topics/');
      if (!mounted) return;
      setState(() {
        _topics = list
            .map((e) => _WritingTopic.fromJson(e as Map<String, dynamic>))
            .toList();
        _loadingTopics = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _topics = [];
        _loadingTopics = false;
        _topicsFailed = true;
      });
    }
  }

  void _selectTopic(_WritingTopic topic) {
    if (_selectedTopic?.id == topic.id) return;
    setState(() => _selectedTopic = topic);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final topic = _selectedTopic;
    if (topic == null) {
      AppNotify.show(context, message: 'Please select a topic first.');
      return;
    }
    final essay = _essayController.text.trim();
    if (essay.isEmpty) {
      AppNotify.show(context, message: 'Please write or paste your sample essay.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final band = _bandController.text.trim();
      final comment = _commentController.text.trim();
      await ApiService.postMultipart(
        '/tutor/samples/writing/',
        fields: {
          'topic': topic.id.toString(),
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

  void _showTopicPicker() {
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              for (final topic in _topics)
                ListTile(
                  title: Text(
                    topic.title,
                    style: TextStyle(
                        color: colors.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Task ${topic.taskNumber}',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
                  ),
                  trailing: _selectedTopic?.id == topic.id
                      ? Icon(Icons.check_rounded, color: colors.brand)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _selectTopic(topic);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final topic = _selectedTopic;
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
              _FieldLabel('Topic'),
              const SizedBox(height: 6),
              _buildTopicPicker(colors),
              if (topic != null) ...[
                const SizedBox(height: 16),
                _buildTopicPreview(colors, topic),
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
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_submitting || topic == null) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.brand,
                    foregroundColor: colors.onBrand,
                    disabledBackgroundColor: colors.surfaceAlt,
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

  Widget _buildTopicPicker(AppColors colors) {
    if (_loadingTopics) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: colors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: colors.textPrimary),
        ),
      );
    }
    if (_topicsFailed || _topics.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: colors.errorBg, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _topicsFailed
                    ? 'Failed to load topics.'
                    : 'No writing topics are available yet.',
                style: TextStyle(fontSize: 13, color: colors.error),
              ),
            ),
            TextButton(onPressed: _loadTopics, child: const Text('Retry')),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: _submitting ? null : _showTopicPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedTopic?.title ?? 'Select a topic',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color:
                      _selectedTopic != null ? colors.textPrimary : colors.textTertiary,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicPreview(AppColors colors, _WritingTopic topic) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Task ${topic.taskNumber}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (topic.promptHtml.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              topic.promptHtml,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: colors.textSecondary),
            ),
          ],
          if (topic.imageUrl != null && topic.imageUrl!.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                topic.imageUrl!,
                width: double.infinity,
                height: 160,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return SizedBox(
                    height: 160,
                    child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: colors.textPrimary),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 100,
                  alignment: Alignment.center,
                  color: colors.surface,
                  child: Text(
                    'Could not load image',
                    style: TextStyle(fontSize: 12.5, color: colors.textTertiary),
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

// ─── Topic model ────────────────────────────────────────────────────────────

class _WritingTopic {
  final int id;
  final int taskNumber;
  final String title;
  final String promptHtml;
  final String? imageUrl;

  const _WritingTopic({
    required this.id,
    required this.taskNumber,
    required this.title,
    required this.promptHtml,
    this.imageUrl,
  });

  factory _WritingTopic.fromJson(Map<String, dynamic> j) {
    return _WritingTopic(
      id: (j['id'] as num?)?.toInt() ?? 0,
      taskNumber: (j['task_number'] as num?)?.toInt() ?? 1,
      title: j['title']?.toString() ?? '',
      promptHtml: j['prompt_html']?.toString() ?? '',
      imageUrl: j['image_url']?.toString(),
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
