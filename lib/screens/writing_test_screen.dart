import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'plus_subscription_screen.dart';
import 'writing_result_screen.dart';

class WritingTestScreen extends StatefulWidget {
  const WritingTestScreen({super.key, required this.prompt});

  final Map<String, dynamic> prompt;

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

  bool get _isPlus => _quota?['is_plus'] == true;
  int? get _remaining => (_quota?['remaining'] as num?)?.toInt();
  bool get _quotaExhausted =>
      _quota != null && !_isPlus && (_remaining ?? 1) <= 0;

  void _showUpgradeDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.workspace_premium_rounded, color: MockTestColors.yellow),
            SizedBox(width: 8),
            Text(
              'Free limit reached',
              style: TextStyle(
                fontFamily: 'SF Pro',
                color: MockTestColors.navy,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: 'SF Pro',
            color: MockTestColors.grey,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Not now',
              style: TextStyle(
                fontFamily: 'SF Pro',
                color: MockTestColors.grey,
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
            child: const Text(
              'Get Plus',
              style: TextStyle(
                fontFamily: 'SF Pro',
                color: MockTestColors.navy,
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
      final result = await MockTestService.submitWriting(
        widget.prompt['id'] as int,
        _controller.text.trim(),
      );
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
    final imageUrl = widget.prompt['image_url'] as String?;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(
        context,
        title: widget.prompt['title']?.toString() ?? 'Writing task',
        actions: [
          if (_quota != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: MtPill(
                  background: _quotaExhausted
                      ? MockTestColors.redBg
                      : MockTestColors.chipBg,
                  child: Text(
                    _isPlus
                        ? 'Unlimited'
                        : '${_remaining ?? 0}/${_quota!['limit']} free left',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _quotaExhausted
                          ? MockTestColors.red
                          : MockTestColors.navy,
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
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      padding: const EdgeInsets.all(14),
                      decoration: mtSoftCard(color: MockTestColors.chipBg, radius: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (imageUrl != null && imageUrl.isNotEmpty) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: double.infinity,
                                color: Colors.white,
                                constraints: const BoxConstraints(maxHeight: 220),
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.contain,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 40),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: MockTestColors.yellow,
                                        ),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 24),
                                        child: Center(
                                          child: Text(
                                            'Could not load chart image',
                                            style: TextStyle(
                                              fontFamily: 'SF Pro',
                                              color: MockTestColors.greyLight,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Text(
                            widget.prompt['prompt_html']?.toString() ?? '',
                            style: const TextStyle(
                              fontFamily: 'SF Pro',
                              fontSize: 14,
                              height: 1.5,
                              color: MockTestColors.navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Stack(
                        children: [
                          TextField(
                            controller: _controller,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(
                              fontFamily: 'SF Pro',
                              fontSize: 14.5,
                              color: MockTestColors.navy,
                              height: 1.5,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Write your answer here…',
                              hintStyle: TextStyle(
                                fontFamily: 'SF Pro',
                                color: MockTestColors.greyLight,
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
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.keyboard_hide_rounded,
                                  size: 18,
                                  color: MockTestColors.grey,
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
                    color: belowMin ? MockTestColors.red : MockTestColors.green,
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
