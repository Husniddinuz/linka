import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import 'speaking_sample_upload_screen.dart';

/// Tutor's own IELTS Speaking samples — list + delete. The "+ Add sample"
/// button pushes [SpeakingSampleUploadScreen] and refreshes the list when it
/// pops with `true`.
class TutorSpeakingSamplesScreen extends StatefulWidget {
  const TutorSpeakingSamplesScreen({super.key});

  @override
  State<TutorSpeakingSamplesScreen> createState() =>
      _TutorSpeakingSamplesScreenState();
}

class _TutorSpeakingSamplesScreenState
    extends State<TutorSpeakingSamplesScreen> {
  List<_SpeakingSample> _samples = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.getList('/tutor/samples/speaking/my/');
      if (!mounted) return;
      setState(() {
        _samples = list
            .map((e) => _SpeakingSample.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _samples = [];
        _loading = false;
      });
    }
  }

  Future<void> _openUpload() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SpeakingSampleUploadScreen()),
    );
    if (result == true) _load();
  }

  Future<void> _confirmDelete(_SpeakingSample sample) async {
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete speaking sample?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          'This sample and its recordings will be permanently removed. '
          'This action can\'t be undone.',
          style: TextStyle(fontSize: 14, color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: colors.error, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final previous = _samples;
    setState(() {
      _samples = _samples.where((s) => s.id != sample.id).toList();
    });
    try {
      await ApiService.delete('/tutor/samples/speaking/${sample.id}/');
    } catch (_) {
      if (!mounted) return;
      setState(() => _samples = previous);
      AppNotify.show(context,
          message: 'Failed to delete sample. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text(
          'My speaking samples',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openUpload,
        backgroundColor: colors.brand,
        foregroundColor: colors.onBrand,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add sample'),
      ),
      body: RefreshIndicator(
        color: colors.textPrimary,
        onRefresh: _load,
        child: _loading
            ? _CenteredScrollable(
                child: CircularProgressIndicator(color: colors.textPrimary),
              )
            : _samples.isEmpty
                ? _CenteredScrollable(child: _EmptyState(onUpload: _openUpload))
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _samples.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _SampleCard(
                      sample: _samples[i],
                      onDelete: () => _confirmDelete(_samples[i]),
                    ),
                  ),
      ),
    );
  }
}

// ─── Scaffolding widgets ────────────────────────────────────────────────────

class _CenteredScrollable extends StatelessWidget {
  final Widget child;
  const _CenteredScrollable({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onUpload;
  const _EmptyState({required this.onUpload});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: colors.surfaceAlt, shape: BoxShape.circle),
            child: Icon(Icons.mic_rounded, color: colors.textPrimary, size: 44),
          ),
          const SizedBox(height: 24),
          Text(
            'No speaking samples yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Record your own Speaking answers so students can hear a real '
            'band-scored sample.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: colors.textSecondary),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: onUpload,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: colors.brand,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: colors.onBrand, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Add your first sample',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.onBrand,
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

// ─── Sample card ────────────────────────────────────────────────────────────

class _SampleCard extends StatelessWidget {
  final _SpeakingSample sample;
  final VoidCallback onDelete;
  const _SampleCard({required this.sample, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final partNumbers = sample.parts.map((p) => p.part).toList()..sort();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration:
                    BoxDecoration(color: colors.surfaceAlt, shape: BoxShape.circle),
                child: Icon(Icons.mic_rounded, color: colors.textPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (sample.bandScore != null && sample.bandScore!.isNotEmpty)
                          ? 'IELTS ${sample.bandScore}'
                          : 'Speaking sample',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      partNumbers.isEmpty
                          ? 'No parts uploaded'
                          : 'Part${partNumbers.length > 1 ? 's' : ''} '
                              '${partNumbers.join(', ')}',
                      style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onDelete,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline_rounded, color: colors.error, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StatusPill(isPublished: sample.isPublished),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool isPublished;
  const _StatusPill({required this.isPublished});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = isPublished ? colors.successBg : colors.accentYellow.withValues(alpha: 0.18);
    final fg = isPublished ? colors.success : colors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        isPublished ? 'Published' : 'Pending review',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

// ─── Models ─────────────────────────────────────────────────────────────────

class _SpeakingSample {
  final int id;
  final String? bandScore;
  final bool isPublished;
  final List<_SpeakingPart> parts;

  const _SpeakingSample({
    required this.id,
    this.bandScore,
    required this.isPublished,
    required this.parts,
  });

  factory _SpeakingSample.fromJson(Map<String, dynamic> j) {
    final partsJson = (j['parts'] as List?) ?? const [];
    return _SpeakingSample(
      id: (j['id'] as num?)?.toInt() ?? 0,
      bandScore: j['band_score']?.toString(),
      isPublished: j['is_published'] as bool? ?? false,
      parts: partsJson
          .map((p) => _SpeakingPart.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}

class _SpeakingPart {
  final int id;
  final int part;
  final String title;

  const _SpeakingPart({required this.id, required this.part, required this.title});

  factory _SpeakingPart.fromJson(Map<String, dynamic> j) {
    return _SpeakingPart(
      id: (j['id'] as num?)?.toInt() ?? 0,
      part: (j['part'] as num?)?.toInt() ?? 0,
      title: j['title']?.toString() ?? '',
    );
  }
}
