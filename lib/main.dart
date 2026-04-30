import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/splash_screen.dart';
import 'screens/role_selection_screen.dart';
import 'services/api_service.dart';
import 'services/token_service.dart';
import 'services/update_service.dart';
import 'services/user_service.dart';
import 'widgets/app_notify.dart';
import 'widgets/connectivity_wrapper.dart';
import 'widgets/update_dialog.dart';

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

class _LinkaAppState extends State<LinkaApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _initDeepLinks();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _initDeepLinks() {
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      debugPrint('Deep link received: $uri');
      _handleDeepLink(uri);
    });

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
