import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/api_service.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import '../widgets/writing_grading_progress.dart';
import '../widgets/writing_report.dart';
import 'plus_subscription_screen.dart';
import 'writing_result_screen.dart';
import '../theme/app_colors.dart';

class WritingTestScreen extends StatefulWidget {
  const WritingTestScreen({super.key, required this.prompt, this.sampleId});

  final Map<String, dynamic> prompt;

  /// Set when the student is answering the task a published Writing sample
  /// answers, rather than a prompt from the practice catalogue.
  ///
  /// A sample's task has no [WritingPrompt] of its own to submit against — the
  /// server mirrors one on first use behind `/writing-samples/{id}/submit/` —
  /// so the id here routes the submission, and `prompt` is the sample's task
  /// rendered for the editor rather than a row the client could post to.
  /// Everything else (quota, grading, the result screen) is identical.
  final int? sampleId;

  @override
  State<WritingTestScreen> createState() => _WritingTestScreenState();
}

class _WritingTestScreenState extends State<WritingTestScreen> {
  final _controller = TextEditingController();
  bool _submitting = false;
  int _wordCount = 0;

  Map<String, dynamic>? _quota;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final words = _controller.text.trim().isEmpty
          ? 0
          : _controller.text.trim().split(RegExp(r'\s+')).length;
      if (words != _wordCount) setState(() => _wordCount = words);
    });
    _loadQuota();
  }

  Future<void> _loadQuota() async {
    try {
      final quota = await MockTestService.fetchWritingQuota();
      if (!mounted) return;
      setState(() => _quota = quota);
    } catch (_) {
      // Non-fatal — the button just won't show a live quota count; the
      // backend still enforces the limit on submit either way.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _minWords => (widget.prompt['min_words'] as num?)?.toInt() ?? 150;

  /// The app bar names the paper, not the question: `title` carries the whole
  /// task statement, which is a paragraph and only ever showed as an ellipsis
  /// up here. The question itself leads the task card below.
  String get _screenTitle {
    final taskNumber = (widget.prompt['task_number'] as num?)?.toInt();
    return taskNumber == null ? 'Writing task' : 'Writing Task $taskNumber';
  }

  bool get _isPlus => _quota?['is_plus'] == true;
  int? get _remaining => (_quota?['remaining'] as num?)?.toInt();
  bool get _quotaExhausted =>
      _quota != null && !_isPlus && (_remaining ?? 1) <= 0;

  void _showUpgradeDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Symbols.workspace_premium_rounded, color: context.colors.accentYellow),
            SizedBox(width: 8),
            Text(
              'Free limit reached',
              style: TextStyle(
                fontFamily: 'SF Pro',
                color: context.colors.textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontFamily: 'SF Pro',
            color: context.colors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Not now',
              style: TextStyle(
                fontFamily: 'SF Pro',
                color: context.colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PlusSubscriptionScreen(),
                ),
              );
            },
            child: Text(
              'Get Plus',
              style: TextStyle(
                fontFamily: 'SF Pro',
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write your essay before submitting')),
      );
      return;
    }
    if (_quotaExhausted) {
      _showUpgradeDialog(
        'You\'ve used your ${_quota!['limit']} free AI-graded essays. Upgrade to Plus for unlimited submissions.',
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final essay = _controller.text.trim();
      final sampleId = widget.sampleId;
      final result = sampleId != null
          ? await MockTestService.submitWritingSampleAnswer(sampleId, essay)
          : await MockTestService.submitWriting(widget.prompt['id'] as int, essay);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => WritingResultScreen(attempt: result)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (e.statusCode == 429) {
        _showUpgradeDialog(e.message);
      } else if (e.statusCode == 403) {
        // Only reachable from a sample: the free window that gates reading a
        // sample gates answering it too, so this is the Plus wall, not an error.
        _showUpgradeDialog(e.message);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Submit failed: ${e.message}')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final belowMin = _wordCount < _minWords;

    // Marking takes 30-60 seconds, so the editor gives way to the progress
    // panel rather than sitting behind a disabled button: the essay is already
    // on its way to the server, and leaving an editable field on screen only
    // invites edits that cannot reach this submission. The controller keeps
    // the draft throughout, so a failed submit drops the student back into it
    // exactly as they left it.
    if (_submitting) {
      return Scaffold(
        backgroundColor: context.wr.page,
        appBar: mtAppBar(context, title: _screenTitle),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: const [WritingGradingProgress()],
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.wr.page,
      appBar: mtAppBar(
        context,
        title: _screenTitle,
        actions: [
          if (_quota != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: MtPill(
                  background: _quotaExhausted
                      ? context.colors.errorBg
                      : context.colors.surfaceAlt,
                  child: Text(
                    _isPlus
                        ? 'Unlimited'
                        : '${_remaining ?? 0}/${_quota!['limit']} free left',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _quotaExhausted
                          ? context.colors.error
                          : context.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Cap the task card to whatever's left after reserving room for
            // the answer field, so it scrolls internally instead of
            // overflowing once the keyboard shrinks the available height.
            const minAnswerHeight = 140.0;
            final maxCardHeight =
                (constraints.maxHeight - minAnswerHeight).clamp(0.0, double.infinity);
            return Column(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxCardHeight),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: WTaskCard(prompt: widget.prompt),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: double.infinity,
                      // The sheet of paper being written on, in the same card
                      // language as the task above it.
                      decoration: wCardDecoration(context, radius: 14),
                      child: Stack(
                        children: [
                          TextField(
                            controller: _controller,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            style: TextStyle(
                              fontFamily: 'SF Pro',
                              fontSize: 14.5,
                              color: context.colors.textPrimary,
                              height: 1.5,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Write your answer here…',
                              hintStyle: TextStyle(
                                fontFamily: 'SF Pro',
                                color: context.colors.textTertiary,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.fromLTRB(16, 16, 52, 16),
                              alignLabelWithHint: true,
                            ),
                          ),
                          // The text field fills the whole box, so there's no
                          // "outside" area left to tap for dismissing the
                          // keyboard — give it an explicit close button instead.
                          Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: () => FocusScope.of(context).unfocus(),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: context.colors.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: context.colors.border),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Symbols.keyboard_hide_rounded,
                                  size: 18,
                                  color: context.colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$_wordCount words (min $_minWords)',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: belowMin ? context.colors.error : context.colors.success,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              MtPrimaryButton(
                label: _quotaExhausted
                    ? 'Upgrade to Plus to submit'
                    : 'Submit for AI grading',
                loading: _submitting,
                onPressed: _quotaExhausted
                    ? () => _showUpgradeDialog(
                        'You\'ve used your ${_quota!['limit']} free AI-graded essays. Upgrade to Plus for unlimited submissions.',
                      )
                    : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
