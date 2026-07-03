import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
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
      appBar: AppBar(title: Text(widget.prompt['title']?.toString() ?? 'Writing task')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              widget.prompt['prompt_html']?.toString() ?? '',
              style: const TextStyle(fontSize: 14.5, height: 1.5),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'Write your answer here…',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_wordCount words (min $_minWords)',
                    style: TextStyle(color: belowMin ? Colors.red : Colors.grey.shade700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Submit for AI grading'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
