import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import '../widgets/skeleton.dart';
import 'writing_sample_screen.dart';
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

  void _openSample(_WritingSample sample) {
    // The my-endpoint returns the same shape the student viewer expects.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WritingSampleScreen(sample: sample.raw),
      ),
    );
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
              style: TextStyle(
                color: colors.error,
                fontWeight: FontWeight.w700,
              ),
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
      AppNotify.show(
        context,
        message: 'Failed to delete sample. Please try again.',
      );
    }
  }

  String get _subtitle {
    if (_loading) return 'Loading…';
    if (_samples.isEmpty) return 'Share your band-scored essays';
    final published = _samples.where((s) => s.isPublished).length;
    return '${_samples.length} sample${_samples.length == 1 ? '' : 's'}'
        ' · $published live';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvas = isDark ? colors.background : colors.surfaceAlt;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: canvas,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openUpload,
          backgroundColor: colors.brand,
          foregroundColor: colors.onBrand,
          elevation: 2,
          icon: const Icon(Symbols.add_rounded, weight: 600),
          label: const Text(
            'Add sample',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: Column(
          children: [
            _Hero(
              title: 'My writing samples',
              subtitle: _subtitle,
              watermark: Symbols.edit_note_rounded,
            ),
            Expanded(
              child: RefreshIndicator(
                color: Colors.white,
                backgroundColor: colors.brand,
                onRefresh: _load,
                child: _loading
                    ? const _ListSkeleton()
                    : _samples.isEmpty
                    ? _CenteredScrollable(
                        child: _EmptyState(onUpload: _openUpload),
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: _samples.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _SampleCard(
                          sample: _samples[i],
                          onTap: () => _openSample(_samples[i]),
                          onDelete: () => _confirmDelete(_samples[i]),
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

// ─── Hero header ────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData watermark;
  const _Hero({
    required this.title,
    required this.subtitle,
    required this.watermark,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gradientEnd = Color.lerp(colors.brand, Colors.black, 0.35)!;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.brand, gradientEnd],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -18,
            bottom: -24,
            child: Icon(
              watermark,
              size: 110,
              fill: 1,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Symbols.arrow_back_ios_new_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
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

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: const Row(
          children: [
            Skeleton(height: 42, width: 42, borderRadius: 14),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(height: 15, width: 150, borderRadius: 6),
                SizedBox(height: 8),
                Skeleton(height: 12, width: 100, borderRadius: 6),
              ],
            ),
          ],
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
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              Symbols.edit_note_rounded,
              color: colors.textTertiary,
              size: 40,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'No writing samples yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Share your own Writing Task essays so students can study a real '
            'band-scored sample.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 26),
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
                  Icon(
                    Symbols.add_rounded,
                    color: colors.onBrand,
                    size: 20,
                    weight: 600,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Add your first sample',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
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
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _SampleCard({
    required this.sample,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Symbols.edit_note_rounded,
                color: colors.textPrimary,
                size: 22,
                opticalSize: 20,
              ),
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
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Task ${sample.taskNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (sample.bandScore != null &&
                          sample.bandScore!.isNotEmpty) ...[
                        _BandBadge(band: sample.bandScore!),
                        const SizedBox(width: 8),
                      ],
                      _StatusLabel(isPublished: sample.isPublished),
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onDelete,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Symbols.delete_rounded,
                  color: colors.error,
                  size: 20,
                  opticalSize: 20,
                ),
              ),
            ),
            Icon(
              Symbols.chevron_right_rounded,
              color: colors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared bits ────────────────────────────────────────────────────────────

class _BandBadge extends StatelessWidget {
  final String band;
  const _BandBadge({required this.band});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gold = Theme.of(context).brightness == Brightness.dark
        ? colors.accentYellow
        : const Color(0xFFB8860B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.accentYellow.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.accentYellow.withValues(alpha: 0.45)),
      ),
      child: Text(
        'IELTS $band',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: gold,
          height: 1.2,
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final bool isPublished;
  const _StatusLabel({required this.isPublished});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gold = Theme.of(context).brightness == Brightness.dark
        ? colors.accentYellow
        : const Color(0xFFB8860B);
    final color = isPublished ? colors.success : gold;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          isPublished ? 'Published' : 'Not live',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
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

  /// Full server payload — same shape the student viewer expects, so the
  /// tutor can preview the sample exactly as students will see it.
  final Map<String, dynamic> raw;

  const _WritingSample({
    required this.id,
    required this.taskNumber,
    required this.title,
    this.bandScore,
    required this.isPublished,
    required this.raw,
  });

  factory _WritingSample.fromJson(Map<String, dynamic> j) {
    return _WritingSample(
      id: (j['id'] as num?)?.toInt() ?? 0,
      taskNumber: (j['task_number'] as num?)?.toInt() ?? 1,
      title: j['title']?.toString() ?? '',
      bandScore: j['band_score']?.toString(),
      isPublished: j['is_published'] as bool? ?? false,
      raw: j,
    );
  }
}
