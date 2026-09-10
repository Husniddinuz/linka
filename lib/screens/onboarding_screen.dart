import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/prefs_service.dart';
import '../theme/app_colors.dart';
import 'role_selection_screen.dart';

/// A small label that floats beside a feature slide's artwork.
class _Chip {
  final IconData icon;
  final String label;

  const _Chip(this.icon, this.label);
}

/// One intro page.
///
/// A slide is drawn either from an illustration ([imagePath]) or, for the
/// features that shipped after the illustrations were commissioned, from
/// [icon] over a [gradient] — the same colours those features wear on the
/// home screen, so the tiles are recognisable once the user gets there.
class _Slide {
  final String title;
  final String subtitle;
  final String? imagePath;
  final IconData? icon;
  final List<Color>? gradient;
  final List<_Chip> chips;

  const _Slide({
    required this.title,
    required this.subtitle,
    this.imagePath,
    this.icon,
    this.gradient,
    this.chips = const [],
  });
}

const _slides = [
  _Slide(
    title: 'Find\na tutor.',
    subtitle: 'Browse verified IELTS tutors, read their reviews and pick the '
        'one who fits you.',
    imagePath: 'assets/images/onboarding/find-tutor.png',
  ),
  _Slide(
    title: 'Book\na lesson.',
    subtitle: 'Choose a time that suits you and meet 1:1, right inside the app.',
    imagePath: 'assets/images/onboarding/book-lesson.png',
  ),
  _Slide(
    title: 'Take a\nmock IELTS.',
    subtitle: 'Full Reading, Listening, Writing and Speaking tests, sat under '
        'real exam timing.',
    icon: Symbols.assignment_rounded,
    gradient: [Color(0xFF34C759), Color(0xFF1F8A3D)],
    chips: [
      _Chip(Symbols.timer_rounded, '60:00'),
      _Chip(Symbols.workspace_premium_rounded, 'Band 7.5'),
    ],
  ),
  _Slide(
    title: 'Practise\nwith AI.',
    subtitle: 'Speak with the AI coach whenever you like, and have your '
        'writing and speaking marked in minutes.',
    icon: Symbols.auto_awesome_rounded,
    gradient: [Color(0xFF8A7EF0), Color(0xFF5F4FC7)],
    chips: [
      _Chip(Symbols.mic_rounded, 'Live speaking'),
      _Chip(Symbols.edit_rounded, 'Instant feedback'),
    ],
  ),
  _Slide(
    title: 'Track\nyour band.',
    subtitle: 'Every attempt, score and correction in one place, so you can '
        'see the progress you are making.',
    icon: Symbols.trending_up_rounded,
    gradient: [Color(0xFFFF9500), Color(0xFFCC6D00)],
    chips: [
      _Chip(Symbols.history_rounded, 'Every attempt'),
      _Chip(Symbols.insights_rounded, '+0.5 band'),
    ],
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;
  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The illustrations are multi-megabyte PNGs; decoding one on the frame it
    // is swiped into shows a blank slide first. Warm them up front instead.
    if (_precached) return;
    _precached = true;
    for (final slide in _slides) {
      final path = slide.imagePath;
      if (path != null) precacheImage(AssetImage(path), context);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await PrefsService.setOnboardingCompleted();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const RoleSelectionScreen(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _slides.length - 1;
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 16),
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

            // Slides
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _slides.length,
                itemBuilder: (_, i) => _SlidePage(slide: _slides[i]),
              ),
            ),

            // Bottom bar
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Dots
                  Row(
                    children: List.generate(_slides.length, (i) {
                      final active = i == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(right: 6),
                        width: active ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active ? colors.accentYellow : colors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),

                  // Next / Start button
                  GestureDetector(
                    onTap: _next,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: colors.brand,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        isLast ? 'Start' : 'Next',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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

class _SlidePage extends StatelessWidget {
  final _Slide slide;

  const _SlidePage({required this.slide});

  @override
  Widget build(BuildContext context) {
    final titleWithoutDot = slide.title.endsWith('.')
        ? slide.title.substring(0, slide.title.length - 1)
        : slide.title;
    final hasDot = slide.title.endsWith('.');
    final colors = context.colors;

    // Small phones and large text settings leave far less than the 320pt the
    // artwork wants: give it a share of whatever height there is, and let the
    // copy scroll if even that is not enough.
    return LayoutBuilder(
      builder: (context, constraints) {
        final artHeight = (constraints.maxHeight * 0.52).clamp(176.0, 320.0);

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // Artwork — full screen width, no horizontal padding
              SizedBox(
                height: artHeight,
                width: double.infinity,
                child: slide.imagePath != null
                    ? Image.asset(
                        slide.imagePath!,
                        fit: BoxFit.fitHeight,
                        alignment: Alignment.centerRight,
                      )
                    : _FeatureArt(slide: slide),
              ),

              const SizedBox(height: 28),

              // Title with yellow dot
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                      height: 1.2,
                    ),
                    children: [
                      TextSpan(text: titleWithoutDot),
                      if (hasDot)
                        TextSpan(
                          text: '.',
                          style: TextStyle(color: colors.accentYellow),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Subtitle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  slide.subtitle,
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 15,
                    height: 1.55,
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// Artwork for the slides that have no illustration: one big feature tile in
/// the feature's own colours, with two labels floating off its left edge —
/// the illustrations sit right-of-centre too, so the composition matches.
class _FeatureArt extends StatelessWidget {
  final _Slide slide;

  const _FeatureArt({required this.slide});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gradient = slide.gradient ?? [colors.brand, colors.brand];

    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 32),
      child: Row(
        children: [
          // Floating labels
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < slide.chips.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  Padding(
                    // Stagger them so they read as scattered, not stacked.
                    padding: EdgeInsets.only(left: i.isOdd ? 20 : 0),
                    child: _ChipLabel(chip: slide.chips[i]),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Feature tile
          Container(
            width: 176,
            height: 176,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: gradient.last.withValues(alpha: 0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Icon(slide.icon, size: 76, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ChipLabel extends StatelessWidget {
  final _Chip chip;

  const _ChipLabel({required this.chip});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(chip.icon, size: 16, color: colors.textPrimary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              chip.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
