import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'plus_subscription_screen.dart';
import 'writing_sample_screen.dart';
import '../theme/app_colors.dart';

const int _freeSamplesPerTask = 3;
const double _cardWidth = 172;
const double _cardHeight = 220;
// Fixed accent triad for the card placeholders — these identify the card kind
// (Task 1 / Task 2 / tutor) rather than following the surface theme, so they
// stay constant in dark mode like the other two always have.
const Color _task1Accent = Color(0xFF2F6FED);
const Color _task2Accent = Color(0xFF8B5CF6);
const Color _tutorAccent = Color(0xFF27AE60);

/// Tutors with at least one published Writing sample — read-only reference
/// content, no submission/grading. Tapping a tutor drills into their
/// submitted topics (see [WritingSampleTutorTopicsScreen]), shown as plain
/// Task 1/2 topic lists. Non-Plus users can open only the first
/// [_freeSamplesPerTask] samples of each task; the rest stay visible but
/// locked, and tapping one opens the Plus subscription screen.
class WritingSamplesListScreen extends StatefulWidget {
  const WritingSamplesListScreen({super.key});

  @override
  State<WritingSamplesListScreen> createState() => _WritingSamplesListScreenState();
}

class _WritingSamplesListScreenState extends State<WritingSamplesListScreen> {
  final Future<List<Map<String, dynamic>>> _future = MockTestService.fetchWritingSampleTutors();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: mtAppBar(context, title: 'Writing Samples'),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.accentYellow));
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'SF Pro', color: context.colors.textSecondary, fontSize: 14),
                ),
              ),
            );
          }
          final tutors = snapshot.data ?? const [];
          if (tutors.isEmpty) {
            return Center(
              child: Text(
                'No writing samples yet',
                style: TextStyle(fontFamily: 'SF Pro', color: context.colors.textSecondary, fontSize: 14),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: _cardWidth / _cardHeight,
            ),
            itemCount: tutors.length,
            itemBuilder: (context, i) {
              final tutor = tutors[i];
              final tutorId = (tutor['tutor_id'] as num?)?.toInt();
              final tutorName = tutor['tutor_name']?.toString() ?? '';
              final tutorImageUrl = tutor['tutor_image_url'] as String?;
              final sampleCount = (tutor['sample_count'] as num?)?.toInt() ?? 0;
              final writingScore = (tutor['tutor_writing_score'] as num?)?.toString();

              return _TutorCard(
                tutorName: tutorName,
                tutorImageUrl: tutorImageUrl,
                sampleCount: sampleCount,
                writingScore: writingScore,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WritingSampleTutorTopicsScreen(
                      tutorId: tutorId,
                      tutorName: tutorName,
                      tutorImageUrl: tutorImageUrl,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One tutor's submitted Writing topics — a simple Task 1/2 list with the
/// same Plus paywall rules, scoped to a single tutor.
class WritingSampleTutorTopicsScreen extends StatefulWidget {
  const WritingSampleTutorTopicsScreen({
    super.key,
    required this.tutorId,
    required this.tutorName,
    required this.tutorImageUrl,
  });

  final int? tutorId;
  final String tutorName;
  final String? tutorImageUrl;

  @override
  State<WritingSampleTutorTopicsScreen> createState() => _WritingSampleTutorTopicsScreenState();
}

class _WritingSampleTutorTopicsScreenState extends State<WritingSampleTutorTopicsScreen> {
  late final Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = MockTestService.fetchWritingSamples(
      tutorId: widget.tutorId,
      tutorName: widget.tutorId == null ? widget.tutorName : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: mtAppBar(context, title: widget.tutorName),
      body: _TutorWritingSamplesBody(future: _future),
    );
  }
}

/// Shared Task 1/2 list body (with the Plus paywall gate) for one tutor's
/// Writing samples — fed by whichever [future] the caller resolves
/// (currently always a single tutor's topics via [WritingSampleTutorTopicsScreen]).
class _TutorWritingSamplesBody extends StatefulWidget {
  const _TutorWritingSamplesBody({required this.future});
  final Future<List<Map<String, dynamic>>> future;

  @override
  State<_TutorWritingSamplesBody> createState() => _TutorWritingSamplesBodyState();
}

class _TutorWritingSamplesBodyState extends State<_TutorWritingSamplesBody> {
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    _checkPlusStatus();
  }

  Future<void> _checkPlusStatus() async {
    final locked = await mtCheckContentLocked();
    if (!mounted) return;
    setState(() => _isLocked = locked);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: widget.future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator(color: context.colors.accentYellow));
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Failed to load: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'SF Pro', color: context.colors.textSecondary, fontSize: 14),
              ),
            ),
          );
        }
        final samples = snapshot.data ?? const [];
        final task1 = samples.where((s) => s['task_number'] == 1).toList();
        final task2 = samples.where((s) => s['task_number'] == 2).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              'Study real, examiner-scored essays — tap a topic, then tap a highlight for the tutor\'s note.',
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13, height: 1.4, color: context.colors.textSecondary),
            ),
            const SizedBox(height: 20),
            _TaskSection(
              label: 'TASK 1',
              icon: Icons.bar_chart_rounded,
              accent: _task1Accent,
              samples: task1,
              isLocked: _isLocked,
            ),
            const SizedBox(height: 24),
            _TaskSection(
              label: 'TASK 2',
              icon: Icons.edit_note_rounded,
              accent: _task2Accent,
              samples: task2,
              isLocked: _isLocked,
            ),
          ],
        );
      },
    );
  }
}

/// Big photo-led tutor card — same visual language as [_EssayCard] (full-bleed
/// photo, bottom gradient, name overlaid) so picking a tutor feels like the
/// same browsing experience as picking a topic afterward.
class _TutorCard extends StatelessWidget {
  const _TutorCard({
    required this.tutorName,
    required this.tutorImageUrl,
    required this.sampleCount,
    required this.writingScore,
    required this.onTap,
  });
  final String tutorName;
  final String? tutorImageUrl;
  final int sampleCount;
  final String? writingScore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (tutorImageUrl != null && tutorImageUrl!.isNotEmpty)
              Image.network(
                tutorImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const _CardPlaceholder(accent: _tutorAccent),
              )
            else
              const _CardPlaceholder(accent: _tutorAccent),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.4, 1],
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                ),
              ),
            ),
            // The tutor's own IELTS Writing score (their credential) — not
            // to be confused with an individual sample's band_score.
            if (writingScore != null)
              Positioned(
                top: 10,
                right: 10,
                child: MtPill(
                  background: context.colors.accentYellow,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Text(
                    'IELTS $writingScore',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tutorName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white, height: 1.25),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$sampleCount topic${sampleCount == 1 ? '' : 's'}',
                    style: const TextStyle(fontFamily: 'SF Pro', fontSize: 11.5, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One task's topics as a plain vertical list: section header, then a simple
/// row per sample. For non-Plus users, rows beyond [_freeSamplesPerTask]
/// render locked and route to the Plus subscription screen on tap.
class _TaskSection extends StatelessWidget {
  const _TaskSection({
    required this.label,
    required this.icon,
    required this.accent,
    required this.samples,
    required this.isLocked,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final List<Map<String, dynamic>> samples;
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: accent, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: context.colors.textTertiary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${samples.length} essays',
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, color: context.colors.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // The backend is the source of truth ('locked' items arrive with
        // their essay/annotations stripped); the index check is a fallback
        // for backends that predate server-side gating.
        for (var i = 0; i < samples.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _EssayRow(
              sample: samples[i],
              accent: accent,
              icon: icon,
              locked: samples[i]['locked'] == true || (isLocked && i >= _freeSamplesPerTask),
            ),
          ),
      ],
    );
  }
}

/// Simple list row for one submitted topic: tinted task icon, title,
/// highlight count, band pill — no tutor photo (the tutor was already
/// chosen on the previous screen). When [locked], the row dims, shows a
/// lock instead of a chevron, and tapping it opens the Plus subscription
/// screen instead of the sample.
class _EssayRow extends StatelessWidget {
  const _EssayRow({required this.sample, required this.accent, required this.icon, required this.locked});
  final Map<String, dynamic> sample;
  final Color accent;
  final IconData icon;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final title = sample['title']?.toString() ?? '';
    final band = sample['band_score']?.toString();
    final highlightCount = ((sample['annotations'] as List?) ?? const []).length;

    return _Pressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              locked ? const PlusSubscriptionScreen() : WritingSampleScreen(sample: sample),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: mtSoftCard(context),
        child: Opacity(
          opacity: locked ? 0.55 : 1,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isNotEmpty ? title : 'Writing sample',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    if (locked) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Linka Plus',
                        style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, color: context.colors.textSecondary),
                      ),
                    ] else if (highlightCount > 0) ...[
                      const SizedBox(height: 3),
                      Text(
                        '$highlightCount highlight${highlightCount == 1 ? '' : 's'}',
                        style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, color: context.colors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (band != null) ...[
                const SizedBox(width: 8),
                MtPill(
                  background: context.colors.accentYellow,
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  child: Text(
                    'Band $band',
                    style: TextStyle(fontFamily: 'SF Pro', fontSize: 11, fontWeight: FontWeight.w800, color: context.colors.textPrimary),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                locked ? Icons.lock_rounded : Icons.chevron_right_rounded,
                color: context.colors.textTertiary,
                size: locked ? 18 : 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardPlaceholder extends StatelessWidget {
  const _CardPlaceholder({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.9), accent.withValues(alpha: 0.55)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.auto_stories_rounded, color: Colors.white70, size: 40),
      ),
    );
  }
}

/// Wraps [child] with a light tactile press animation (scale down + haptic
/// tick on tap) so the list feels responsive to touch, not just tappable.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
