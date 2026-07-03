import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
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

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final words = _controller.text.trim().isEmpty ? 0 : _controller.text.trim().split(RegExp(r'\s+')).length;
      if (words != _wordCount) setState(() => _wordCount = words);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _minWords => (widget.prompt['min_words'] as num?)?.toInt() ?? 150;

  Future<void> _submit() async {
    if (_controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Write your essay before submitting')));
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final belowMin = _wordCount < _minWords;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: widget.prompt['title']?.toString() ?? 'Writing task'),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            padding: const EdgeInsets.all(14),
            decoration: mtSoftCard(color: MockTestColors.chipBg, radius: 14),
            child: Text(
              widget.prompt['prompt_html']?.toString() ?? '',
              style: const TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 14,
                height: 1.5,
                color: MockTestColors.navy,
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
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14.5, color: MockTestColors.navy, height: 1.5),
                  decoration: const InputDecoration(
                    hintText: 'Write your answer here…',
                    hintStyle: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.greyLight),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            ),
          ),
        ],
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
                label: 'Submit for AI grading',
                loading: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
