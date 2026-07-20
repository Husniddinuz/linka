import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';

/// Form for a tutor to submit their own IELTS Writing sample essay,
/// against an admin-curated topic. The tutor first picks a
/// [_WritingTopic] (which supplies the task number, prompt, and optional
/// chart/graph image) and then writes their sample essay for it. The
/// sample is published immediately on submit. On success, pops with `true`
/// so the caller can refresh its list.
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

  // Mirrors the backend's essay markup (apps/mock_tests/essay_markup.py):
  // `==phrase==(note)` inline in the essay text becomes a tappable
  // highlight with an examiner note in the student-facing sample screen.
  static final _highlightPattern = RegExp(r'==(.+?)==\((.+?)\)', dotAll: true);

  List<_WritingTopic> _topics = [];
  bool _loadingTopics = true;
  bool _topicsFailed = false;
  _WritingTopic? _selectedTopic;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Rebuild so the "Highlights" list below the essay field tracks edits.
    _essayController.addListener(() => setState(() {}));
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

  Future<void> _addHighlight() async {
    final text = _essayController.text;
    final sel = _essayController.selection;
    if (!sel.isValid || sel.isCollapsed) {
      AppNotify.show(context,
          message: 'Select the part of your essay you want to highlight first.');
      return;
    }
    // Trim whitespace off the selection edges so the markup hugs the phrase.
    var start = sel.start;
    var end = sel.end;
    while (start < end && text[start].trim().isEmpty) {
      start++;
    }
    while (end > start && text[end - 1].trim().isEmpty) {
      end--;
    }
    if (start == end) {
      AppNotify.show(context,
          message: 'Select the part of your essay you want to highlight first.');
      return;
    }
    final phrase = text.substring(start, end);
    final overlapsExisting = _highlightPattern
        .allMatches(text)
        .any((m) => start < m.end && end > m.start);
    if (overlapsExisting || phrase.contains('==')) {
      AppNotify.show(context, message: 'That part already has a highlight.');
      return;
    }

    final note = await _promptForNote(phrase);
    if (note == null) return;

    final markup = '==$phrase==($note)';
    _essayController.value = TextEditingValue(
      text: text.replaceRange(start, end, markup),
      selection: TextSelection.collapsed(offset: start + markup.length),
    );
  }

  /// Bottom sheet asking for the note attached to [phrase]. Returns the
  /// sanitized note, or null if dismissed. Parentheses become brackets and
  /// `==` is stripped so the note can never break the markup delimiters.
  Future<String?> _promptForNote(String phrase) async {
    final raw = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _HighlightNoteSheet(phrase: phrase),
    );
    if (raw == null) return null;
    final note = raw
        .trim()
        .replaceAll('==', '')
        .replaceAll('(', '[')
        .replaceAll(')', ']');
    return note.isEmpty ? null : note;
  }

  void _removeHighlight(RegExpMatch match) {
    final phrase = match.group(1)!;
    _essayController.value = TextEditingValue(
      text: _essayController.text
          .replaceRange(match.start, match.end, phrase),
      selection: TextSelection.collapsed(offset: match.start + phrase.length),
    );
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
          message: 'Writing sample published!',
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
                Row(
                  children: [
                    _FieldLabel('Sample essay'),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _submitting ? null : _addHighlight,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        foregroundColor: colors.textPrimary,
                      ),
                      icon: const Icon(Icons.border_color_rounded, size: 14),
                      label: const Text(
                        'Highlight',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _essayController,
                  enabled: !_submitting,
                  minLines: 6,
                  maxLines: 14,
                  style: TextStyle(fontSize: 14, color: colors.textPrimary),
                  decoration:
                      fieldDecoration(context, hint: 'Write or paste the full essay'),
                  contextMenuBuilder: (context, editableTextState) {
                    final items = List<ContextMenuButtonItem>.of(
                        editableTextState.contextMenuButtonItems);
                    final sel = editableTextState.textEditingValue.selection;
                    if (sel.isValid && !sel.isCollapsed) {
                      items.insert(
                        0,
                        ContextMenuButtonItem(
                          label: 'Highlight',
                          onPressed: () {
                            editableTextState.hideToolbar();
                            _addHighlight();
                          },
                        ),
                      );
                    }
                    return AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: editableTextState.contextMenuAnchors,
                      buttonItems: items,
                    );
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  'Select a part of your essay, then tap Highlight to mark it '
                  'as important and add a note — students tap the highlight to '
                  'read it. It is stored as ==phrase==(note) in the text.',
                  style: TextStyle(
                      fontSize: 11.5, height: 1.4, color: colors.textTertiary),
                ),
                _buildHighlightsList(colors),
                const SizedBox(height: 16),
                _FieldLabel('Band score (optional)'),
                const SizedBox(height: 6),
                TextField(
                  controller: _bandController,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: bandScoreInputFormatters(),
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
                          'Submit',
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

  /// Current highlights parsed live from the essay text, each with its
  /// note and a remove button that unwraps the markup back to plain text.
  Widget _buildHighlightsList(AppColors colors) {
    final matches =
        _highlightPattern.allMatches(_essayController.text).toList();
    if (matches.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        _FieldLabel('Highlights'),
        const SizedBox(height: 6),
        for (final m in matches)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.group(1)!,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                          backgroundColor:
                              colors.accentYellow.withValues(alpha: 0.35),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        m.group(2)!,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: colors.textTertiary),
                  onPressed: _submitting ? null : () => _removeHighlight(m),
                ),
              ],
            ),
          ),
      ],
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

/// Content of the "Add highlight" bottom sheet. Owns its note controller so
/// it is disposed when the sheet unmounts — the sheet keeps building during
/// its exit animation after showModalBottomSheet's future resolves, so the
/// caller must not dispose the controller itself.
class _HighlightNoteSheet extends StatefulWidget {
  final String phrase;
  const _HighlightNoteSheet({required this.phrase});

  @override
  State<_HighlightNoteSheet> createState() => _HighlightNoteSheetState();
}

class _HighlightNoteSheetState extends State<_HighlightNoteSheet> {
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add highlight',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colors.accentYellow.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '"${widget.phrase}"',
                style: TextStyle(
                  fontSize: 13.5,
                  fontStyle: FontStyle.italic,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _noteController,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              style: TextStyle(fontSize: 14, color: colors.textPrimary),
              decoration:
                  fieldDecoration(context, hint: 'Why is this part important?'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _noteController,
                builder: (context, value, _) => ElevatedButton(
                  onPressed: value.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(context, value.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.brand,
                    foregroundColor: colors.onBrand,
                    disabledBackgroundColor: colors.surfaceAlt,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Add highlight',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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

/// Input formatters for an IELTS band-score field. Decimal keypads in
/// comma-decimal locales (e.g. ru/uz) offer no dot key, but the backend's
/// DecimalField only accepts a dot — so map commas to dots as typed, and
/// allow at most one separator.
List<TextInputFormatter> bandScoreInputFormatters() => [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      TextInputFormatter.withFunction((oldValue, newValue) {
        final text = newValue.text.replaceAll(',', '.');
        if ('.'.allMatches(text).length > 1) return oldValue;
        return newValue.copyWith(text: text);
      }),
    ];

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
