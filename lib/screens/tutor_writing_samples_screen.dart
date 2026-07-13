import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import 'writing_sample_upload_screen.dart';

/// Tutor's own IELTS Writing samples — list + delete. The "+ Add sample"
/// button pushes [WritingSampleUploadScreen] and refreshes the list when it
/// pops with `true`.
class TutorWritingSamplesScreen extends StatefulWidget {
  const TutorWritingSamplesScreen({super.key});

  @override
  State<TutorWritingSamplesScreen> createState() =>
      _TutorWritingSamplesScreenState();
}

class _TutorWritingSamplesScreenState extends State<TutorWritingSamplesScreen> {
  List<_WritingSample> _samples = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.getList('/tutor/samples/writing/my/');
      if (!mounted) return;
      setState(() {
        _samples = list
            .map((e) => _WritingSample.fromJson(e as Map<String, dynamic>))
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
      MaterialPageRoute(builder: (_) => const WritingSampleUploadScreen()),
    );
    if (result == true) _load();
  }

  Future<void> _confirmDelete(_WritingSample sample) async {
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete writing sample?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          'This sample will be permanently removed. This action can\'t be '
          'undone.',
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
      await ApiService.delete('/tutor/samples/writing/${sample.id}/');
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
          'My writing samples',
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
            child: Icon(Icons.article_outlined, color: colors.textPrimary, size: 44),
          ),
          const SizedBox(height: 24),
          Text(
            'No writing samples yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Share your own Writing Task essays so students can study a real '
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
  final _WritingSample sample;
  final VoidCallback onDelete;
  const _SampleCard({required this.sample, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
                child: Icon(Icons.article_outlined, color: colors.textPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sample.title.isNotEmpty ? sample.title : 'Writing sample',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Task ${sample.taskNumber}'
                      '${(sample.bandScore != null && sample.bandScore!.isNotEmpty) ? ' · IELTS ${sample.bandScore}' : ''}',
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

// ─── Model ──────────────────────────────────────────────────────────────────

class _WritingSample {
  final int id;
  final int taskNumber;
  final String title;
  final String? bandScore;
  final bool isPublished;

  const _WritingSample({
    required this.id,
    required this.taskNumber,
    required this.title,
    this.bandScore,
    required this.isPublished,
  });

  factory _WritingSample.fromJson(Map<String, dynamic> j) {
    return _WritingSample(
      id: (j['id'] as num?)?.toInt() ?? 0,
      taskNumber: (j['task_number'] as num?)?.toInt() ?? 1,
      title: j['title']?.toString() ?? '',
      bandScore: j['band_score']?.toString(),
      isPublished: j['is_published'] as bool? ?? false,
    );
  }
}
