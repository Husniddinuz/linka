import 'dart:async';
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'profile_setup_screen.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/token_service.dart';
import '../widgets/app_notify.dart';
import '../widgets/num_key.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  final String fullPhone;
  final String verifyId;
  final String role;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.fullPhone,
    required this.verifyId,
    required this.role,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _code = '';
  int _secondsLeft = 57;
  Timer? _timer;
  late String _verifyId = widget.verifyId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _onDigit(String digit) {
    if (_code.length >= 5) return;
    setState(() => _code += digit);
    if (_code.length == 5) {
      Future.delayed(const Duration(milliseconds: 300), _submit);
    }
  }

  void _onDelete() {
    if (_code.isEmpty) return;
    setState(() => _code = _code.substring(0, _code.length - 1));
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0) return;
    try {
      final result = await AuthService.sendOtp(widget.fullPhone, userType: widget.role);
      if (!mounted) return;
      setState(() {
        _verifyId = result['verifyID'] as String;
        _secondsLeft = 57;
        _code = '';
      });
      _startTimer();
    } on AuthException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    }
  }

  Future<void> _submit() async {
    if (!mounted || _submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await AuthService.verifyOtp(
        verifyId: _verifyId,
        otpCode: _code,
      );

      await TokenService.saveTokens(
        access: result['accessToken'] as String,
        refresh: result['refreshToken'] as String,
      );

      if (!mounted) return;

      // Register FCM token with backend
      NotificationService.registerDevice();
      NotificationService.listenTokenRefresh();

      AppNotify.show(context,
        message: 'Login successful',
        type: NotifyType.success,
      );

      final user = result['user'] as Map<String, dynamic>;
      final isProfileComplete = user['isProfileComplete'] as bool? ?? false;

      if (isProfileComplete) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ProfileSetupScreen(role: widget.role),
          ),
          (route) => false,
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _code = '';
        _submitting = false;
      });
      AppNotify.show(context, message: e.message);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            color: Color(0xFF272942),
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Login',
          style: TextStyle(
            color: Color(0xFF272942),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Content area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),

                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF272942),
                          height: 1.2,
                        ),
                        children: [
                          TextSpan(text: 'Enter\nthe code'),
                          TextSpan(
                            text: '-',
                            style: TextStyle(color: Color(0xFFF5C542)),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'To confirm your phone number, send a 5-digit code to ${widget.phone}',
                      style: const TextStyle(
                        color: Color(0xFFAAAAAA),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),

                    const Spacer(),

                    // OTP digit display
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (i) {
                          final filled = i < _code.length;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              transitionBuilder: (child, anim) =>
                                  ScaleTransition(scale: anim, child: child),
                              child: filled
                                  ? Text(
                                      _code[i],
                                      key: ValueKey('d_${i}_${_code[i]}'),
                                      style: const TextStyle(
                                        fontSize: 40,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF272942),
                                      ),
                                    )
                                  : Container(
                                      key: ValueKey('dot_$i'),
                                      width: 14,
                                      height: 14,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFDDDDDD),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                            ),
                          );
                        }),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Timer / resend
                    Center(
                      child: GestureDetector(
                        onTap: _resend,
                        child: Text(
                          _secondsLeft > 0
                              ? 'If the code doesn\'t arrive, you can\nget a new one in $_secondsLeft seconds.'
                              : 'Resend code',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _secondsLeft > 0
                                ? const Color(0xFFAAAAAA)
                                : const Color(0xFF272942),
                            fontSize: 13,
                            height: 1.55,
                            decoration: _secondsLeft == 0
                                ? TextDecoration.underline
                                : null,
                          ),
                        ),
                      ),
                    ),

                    const Spacer(),
                  ],
                ),
              ),
            ),

            // Custom numpad
            NumPad(onDigit: _onDigit, onDelete: _onDelete),
          ],
        ),
      ),
    );
  }
}

