import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import 'screens/splash_screen.dart'; // restore for release
import 'screens/home_screen.dart';
import 'screens/role_selection_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/token_service.dart';
import 'widgets/app_notify.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('═══════════════════════════════════════');
    debugPrint('FLUTTER ERROR: ${details.exceptionAsString()}');
    debugPrint('${details.stack}');
    debugPrint('═══════════════════════════════════════');
  };

  // Global session-expired handler: any 401 that can't be recovered by
  // refreshing the token clears auth state and bounces the user to login.
  ApiService.onSessionExpired = () async {
    await TokenService.clearTokens();
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

  final isLoggedIn = await TokenService.isLoggedIn();

  // Register FCM token if already logged in
  if (isLoggedIn) {
    try {
      await NotificationService.registerDevice();
      NotificationService.listenTokenRefresh();
    } catch (e) {
      debugPrint('FCM registration skipped: $e');
    }
  }

  runApp(LinkaApp(isLoggedIn: isLoggedIn));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class LinkaApp extends StatefulWidget {
  final bool isLoggedIn;

  const LinkaApp({super.key, required this.isLoggedIn});

  @override
  State<LinkaApp> createState() => _LinkaAppState();
}

class _LinkaAppState extends State<LinkaApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() {
    // Handle link when app is already running
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      debugPrint('Deep link received: $uri');
      _handleDeepLink(uri);
    });

    // Handle link that launched the app
    return _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        debugPrint('Initial deep link: $uri');
        _handleDeepLink(uri);
      }
    });
  }

  @override
  void dispose() {
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
    // linka://tutor/123 → host=tutor, pathSegments=[123]
    final host = uri.host;
    final segments = uri.pathSegments;
    debugPrint('Deep link: host=$host, segments=$segments');

    switch (host) {
      case 'tutor':
        if (segments.isNotEmpty) {
          final tutorId = segments[0];
          debugPrint('Open tutor profile: $tutorId');
          _showDeepLinkToast('Opening tutor: $tutorId');
          // TODO: navigatorKey.currentState?.push(
          //   MaterialPageRoute(builder: (_) => TutorProfileScreen(id: tutorId)),
          // );
        }
        break;
      default:
        _showDeepLinkToast('Deep link: $uri');
        debugPrint('Unknown deep link host: $host');
    }
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
      home: widget.isLoggedIn ? const HomeScreen() : const RoleSelectionScreen(),
    );
  }
}
