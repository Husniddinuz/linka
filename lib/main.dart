import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'screens/splash_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/tutor_profile_screen.dart';
import 'services/api_service.dart';
import 'services/app_feature_service.dart';
import 'services/facebook_events_service.dart';
import 'services/token_service.dart';
import 'services/update_service.dart';
import 'services/user_service.dart';
import 'widgets/app_notify.dart';
import 'widgets/connectivity_wrapper.dart';
import 'widgets/update_dialog.dart';

void main() async {
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.linka.app.channel.audio',
    androidNotificationChannelName: 'Linka Podcasts',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );
  await Firebase.initializeApp();
  await FacebookEventsService.init();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Global session-expired handler: any 401 that can't be recovered by
  // refreshing the token clears auth state and bounces the user to login.
  ApiService.onSessionExpired = () async {
    await TokenService.clearTokens();
    await UserService.clear();
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      AppNotify.show(
        context,
        message: 'Session expired. Please log in again.',
        type: NotifyType.error,
      );
    }
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  };

  runApp(const LinkaApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class LinkaApp extends StatefulWidget {
  const LinkaApp({super.key});

  @override
  State<LinkaApp> createState() => _LinkaAppState();
}

class _LinkaAppState extends State<LinkaApp> with WidgetsBindingObserver {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appLinks = AppLinks();
    _initDeepLinks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FacebookEventsService.requestTracking();
      _checkForUpdate();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh remote feature flags when the app returns to the foreground so
    // toggles flipped server-side land without a restart.
    if (state == AppLifecycleState.resumed) {
      AppFeatureService.refresh();
    }
  }

  Future<void> _initDeepLinks() {
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });

    return _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleDeepLink(uri);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    super.dispose();
  }

  void _showDeepLinkToast(String message) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    }
  }

  void _handleDeepLink(Uri uri) {
    final host = uri.host;
    final segments = uri.pathSegments;

    switch (host) {
      case 'tutor':
        if (segments.isNotEmpty) {
          final tutorId = int.tryParse(segments[0]);
          if (tutorId != null) {
            navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (_) => TutorProfileScreen(tutorId: tutorId)),
            );
          }
        }
        break;
      default:
        _showDeepLinkToast('Deep link: $uri');
    }
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (info == null) return;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await showUpdateDialog(context, info);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Linka',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF272942)),
        fontFamily: 'Inter',
      ),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: ConnectivityWrapper(child: child ?? const SizedBox.shrink()),
      ),
      home: const SplashScreen(),
    );
  }
}
