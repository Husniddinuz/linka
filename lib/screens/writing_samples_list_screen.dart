import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'plus_subscription_screen.dart';
import 'writing_sample_screen.dart';

const int _freeSamplesPerTask = 2;
const double _cardWidth = 172;
const double _cardHeight = 220;
const Color _task1Accent = Color(0xFF2F6FED);
const Color _task2Accent = Color(0xFF8B5CF6);
const Color _tutorAccent = MockTestColors.green;

/// Tutors with at least one published Writing sample — read-only reference
/// content, no submission/grading. Tapping a tutor drills into their
/// submitted topics (see [WritingSampleTutorTopicsScreen]), shown as
/// swipeable, photo-led Task 1/2 carousels. Non-Plus users see the first
/// [_freeSamplesPerTask] samples of each task normally; the rest sit behind
/// a blurred teaser card.
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
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: 'Writing Samples'),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: MockTestColors.yellow));
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey, fontSize: 14),
                ),
              ),
            );
          }
          final tutors = snapshot.data ?? const [];
          if (tutors.isEmpty) {
            return const Center(
              child: Text(
                'No writing samples yet',
                style: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey, fontSize: 14),
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

/// One tutor's submitted Writing topics — same Task 1/2 carousel + Plus
/// paywall presentation as the old flat list, just scoped to a single tutor.
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
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: widget.tutorName),
      body: _TutorWritingSamplesBody(future: _future),
    );
  }
}

/// Shared Task 1/2 carousel body (with the Plus paywall gate) for one
/// tutor's Writing samples — fed by whichever [future] the caller resolves
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
          return const Center(child: CircularProgressIndicator(color: MockTestColors.yellow));
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Failed to load: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey, fontSize: 14),
              ),
            ),
          );
        }
        final samples = snapshot.data ?? const [];
        final task1 = samples.where((s) => s['task_number'] == 1).toList();
        final task2 = samples.where((s) => s['task_number'] == 2).toList();
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Study real, examiner-scored essays — tap a card, then tap a highlight for the tutor\'s note.',
                style: TextStyle(fontFamily: 'SF Pro', fontSize: 13, height: 1.4, color: MockTestColors.grey),
              ),
            ),
            const SizedBox(height: 20),
            _TaskCarousel(
              label: 'TASK 1',
              icon: Icons.bar_chart_rounded,
              accent: _task1Accent,
              samples: task1,
              isLocked: _isLocked,
            ),
            const SizedBox(height: 26),
            _TaskCarousel(
              label: 'TASK 2',
              icon: Icons.edit_note_rounded,
              accent: _task2Accent,
              samples: task2,
              isLocked: _isLocked,
            ),
            const SizedBox(height: 8),
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
                  background: MockTestColors.yellow,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Text(
                    'IELTS $writingScore',
                    style: const TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: MockTestColors.navy,
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

class _TaskCarousel extends StatelessWidget {
  const _TaskCarousel({
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
    final locked = isLocked && samples.length > _freeSamplesPerTask;
    final visible = locked ? samples.sublist(0, _freeSamplesPerTask) : samples;
    final hidden = locked ? samples.sublist(_freeSamplesPerTask) : const <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: MockTestColors.greyLight,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${samples.length} essays',
                style: const TextStyle(fontFamily: 'SF Pro', fontSize: 12, color: MockTestColors.greyLight),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: _cardHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: visible.length + (locked ? 1 : 0),
            itemBuilder: (context, i) {
              final isLast = i == visible.length;
              return Padding(
                padding: EdgeInsets.only(right: isLast ? 0 : 12),
                child: isLast
                    ? _LockedCard(accent: accent, hiddenCount: hidden.length, previewImageUrl: hidden.first['tutor_image_url'] as String?)
                    : _EssayCard(sample: visible[i], accent: accent),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EssayCard extends StatelessWidget {
  const _EssayCard({required this.sample, required this.accent});
  final Map<String, dynamic> sample;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final title = sample['title']?.toString() ?? '';
    final tutorName = sample['tutor_name']?.toString() ?? '';
    final tutorImageUrl = sample['tutor_image_url'] as String?;
    final band = sample['band_score']?.toString();
    final highlightCount = ((sample['annotations'] as List?) ?? const []).length;

    return _Pressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WritingSampleScreen(sample: sample)),
      ),
      child: SizedBox(
        width: _cardWidth,
        height: _cardHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (tutorImageUrl != null && tutorImageUrl.isNotEmpty)
                Image.network(
                  tutorImageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _CardPlaceholder(accent: accent),
                )
              else
                _CardPlaceholder(accent: accent),
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
              if (band != null)
                Positioned(
                  top: 10,
                  right: 10,
                  child: MtPill(
                    background: MockTestColors.yellow,
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    child: Text(
                      'Band $band',
                      style: const TextStyle(fontFamily: 'SF Pro', fontSize: 11, fontWeight: FontWeight.w800, color: MockTestColors.navy),
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
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white, height: 1.25),
                    ),
                    if (tutorName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        tutorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'SF Pro', fontSize: 11.5, color: Colors.white70),
                      ),
                    ],
                    if (highlightCount > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lightbulb_rounded, color: Colors.white70, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            '$highlightCount highlight${highlightCount == 1 ? '' : 's'}',
                            style: const TextStyle(fontFamily: 'SF Pro', fontSize: 11, color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
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

class _LockedCard extends StatelessWidget {
  const _LockedCard({required this.accent, required this.hiddenCount, required this.previewImageUrl});
  final Color accent;
  final int hiddenCount;
  final String? previewImageUrl;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PlusSubscriptionScreen()),
      ),
      child: SizedBox(
        width: _cardWidth,
        height: _cardHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (previewImageUrl != null && previewImageUrl!.isNotEmpty)
                Image.network(
                  previewImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _CardPlaceholder(accent: accent),
                )
              else
                _CardPlaceholder(accent: accent),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(color: Colors.black.withValues(alpha: 0.45)),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.workspace_premium_rounded, color: MockTestColors.yellow, size: 26),
                    const SizedBox(height: 8),
                    Text(
                      '+$hiddenCount more',
                      style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(color: MockTestColors.yellow, borderRadius: BorderRadius.circular(20)),
                      child: const Text(
                        'Get Plus',
                        style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, fontWeight: FontWeight.w700, color: MockTestColors.navy),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps [child] with a light tactile press animation (scale down + haptic
/// tick on tap) so the carousel feels responsive to touch, not just tappable.
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
