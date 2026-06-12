import 'package:flutter/material.dart';
import '../services/app_feature_service.dart';
import '../services/token_service.dart';
import 'home_screen.dart';
import 'role_selection_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Load remote feature flags (cached + background refresh) before any
    // gated screen renders. init() returns once the cache is read; the
    // network call continues in the background.
    await AppFeatureService.init();
    final isLoggedIn = await TokenService.isLoggedIn();
    if (!mounted) return;

    if (isLoggedIn) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      return;
    }

    // Not logged in: hold the branding splash briefly before auth flow.
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const RoleSelectionScreen(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF272942),
      body: Center(
        child: Image.asset(
          'assets/images/branding/new-logo.png',
          // Matches the native launch screen logo size (LaunchImage@3x is
          // 384px → 128pt centered) so the native→Flutter handoff is seamless.
          width: 128,
          height: 128,
        ),
      ),
    );
  }
}
