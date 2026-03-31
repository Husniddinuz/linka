import 'package:flutter/material.dart';
import '../services/prefs_service.dart';
import 'role_selection_screen.dart';

class _Slide {
  final String title;
  final String subtitle;
  final String? imagePath;

  const _Slide({required this.title, required this.subtitle, this.imagePath});
}

const _slides = [
  _Slide(
    title: 'Book\na lesson.',
    subtitle: 'Book a lesson at your preferred time',
    imagePath: 'assets/images/onboarding/book-lesson.png',
  ),
  _Slide(
    title: 'Find\na tutor.',
    subtitle: 'Tell him what you want him to help with',
    imagePath: 'assets/images/onboarding/find-tutor.png',
  ),
  _Slide(
    title: 'Make\na schedule.',
    subtitle: 'Choose a time that is convenient for you',
    imagePath: 'assets/images/onboarding/make-schedule.png',
  ),
  _Slide(
    title: 'Find\nstudents.',
    subtitle: 'Advertise your services to students',
    imagePath: 'assets/images/onboarding/find-students.png',
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

    return Scaffold(
      backgroundColor: Colors.white,
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
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: Color(0xFFAAAAAA),
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
                          color: active
                              ? const Color(0xFFF5C542)
                              : const Color(0xFFDDDDDD),
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
                        color: const Color(0xFF272942),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        // Image — full screen width, no horizontal padding
        SizedBox(
          height: 320,
          width: double.infinity,
          child: slide.imagePath != null
              ? Image.asset(
                  slide.imagePath!,
                  fit: BoxFit.fitHeight,
                  alignment: Alignment.centerRight,
                )
              : Container(color: const Color(0xFFF2F2F2)),
        ),

        const SizedBox(height: 28),

        // Title with yellow dot
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.bold,
                color: Color(0xFF272942),
                height: 1.2,
              ),
              children: [
                TextSpan(text: titleWithoutDot),
                if (hasDot)
                  const TextSpan(
                    text: '.',
                    style: TextStyle(color: Color(0xFFF5C542)),
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
            style: const TextStyle(
              color: Color(0xFFAAAAAA),
              fontSize: 15,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}
