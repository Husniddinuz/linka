import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'screens/home_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/tutor_profile_screen.dart';
import 'services/api_service.dart';
import 'services/app_feature_service.dart';
import 'services/auth_service.dart';
import 'services/facebook_events_service.dart';
import 'services/notification_service.dart';
import 'services/podcast_progress_service.dart';
import 'services/theme_service.dart';
import 'services/token_service.dart';
import 'services/update_service.dart';
import 'services/user_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_notify.dart';
import 'widgets/connectivity_wrapper.dart';
import 'widgets/update_dialog.dart';

void main() async {
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.linka.app.channel.audio',
    androidNotificationChannelName: 'Linka Podcasts',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
    // Downsample podcast artwork before decoding; full-size covers can be
    // multi-megapixel and the notification/lock screen never needs more.
    artDownscaleWidth: 384,
    artDownscaleHeight: 384,
  );
  await Firebase.initializeApp();
  await FacebookEventsService.init();
  await ThemeService.init();
  // Resume points are read synchronously from cache while building podcast
  // lists, so they have to be in memory before the first frame.
  await PodcastProgressService.load();
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

  /// Hosts that serve the Linka site and may therefore carry our deep links.
  ///
  /// `linka-ielts.com` is the current domain; `linkaapp.uz` is the previous one
  /// and stays here indefinitely. Links already shared, and the Telegram bot's
  /// replies to anyone running an older build, still point at it — dropping it
  /// would turn those into browser tabs instead of app opens.
  static const _siteHosts = {
    'linka-ielts.com',
    'www.linka-ielts.com',
    'linkaapp.uz',
    'www.linkaapp.uz',
  };

  /// Telegram login deep link: `https://<site>/tg-login?token=...` (universal
  /// link) or `linka://tg-login?token=...` (custom-scheme fallback from the
  /// landing page).
  bool _isTelegramLoginLink(Uri uri) {
    final isWeb = (uri.scheme == 'https' || uri.scheme == 'http') &&
        _siteHosts.contains(uri.host) &&
        uri.path == '/tg-login';
    final isScheme = uri.scheme == 'linka' && uri.host == 'tg-login';
    return isWeb || isScheme;
  }

  bool _telegramLoginInProgress = false;

  Future<void> _handleTelegramLogin(String token) async {
    if (_telegramLoginInProgress) return;
    _telegramLoginInProgress = true;
    try {
      final result = await AuthService.exchangeTelegramToken(token);

      await TokenService.saveTokens(
        access: result['accessToken'] as String,
        refresh: result['refreshToken'] as String,
      );

      NotificationService.registerDevice();
      NotificationService.listenTokenRefresh();

      // On cold start the link can arrive before the first frame; wait for
      // the navigator so the redirect isn't lost.
      for (var i = 0; i < 40 && navigatorKey.currentState == null; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final user = result['user'] as Map<String, dynamic>;
      final isProfileComplete = user['isProfileComplete'] as bool? ?? false;
      final role = user['role'] as String? ?? 'student';

      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        AppNotify.show(
          context,
          message: 'Login successful',
          type: NotifyType.success,
        );
      }

      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => isProfileComplete
              ? const HomeScreen()
              : ProfileSetupScreen(role: role),
        ),
        (route) => false,
      );
    } on AuthException catch (e) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        AppNotify.show(context, message: e.message, type: NotifyType.error);
      }
    } finally {
      _telegramLoginInProgress = false;
    }
  }

  void _openTutorProfile(int tutorId) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => TutorProfileScreen(tutorId: tutorId)),
    );
  }

  void _handleDeepLink(Uri uri) {
    if (_isTelegramLoginLink(uri)) {
      final token = uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        _handleTelegramLogin(token);
      }
      return;
    }

    final host = uri.host;
    final segments = uri.pathSegments;

    // Universal links: https://linka-ielts.com/tutor/<id>, ...
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        _siteHosts.contains(host)) {
      if (segments.length >= 2 && segments[0] == 'tutor') {
        final tutorId = int.tryParse(segments[1]);
        if (tutorId != null) _openTutorProfile(tutorId);
      }
      // Unknown site paths: do nothing (the page opens in the browser).
      return;
    }

    // Custom scheme: linka://tutor/<id>, ...
    switch (host) {
      case 'tutor':
        if (segments.isNotEmpty) {
          final tutorId = int.tryParse(segments[0]);
          if (tutorId != null) _openTutorProfile(tutorId);
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
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeService.isDarkNotifier,
      builder: (context, isDark, _) {
        return MaterialApp(
          title: 'Linka',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            child: ConnectivityWrapper(child: child ?? const SizedBox.shrink()),
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}
