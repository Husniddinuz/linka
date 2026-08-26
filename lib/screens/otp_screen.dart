import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';
import 'profile_setup_screen.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/token_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';

/// Which channel carried the code. Everything past "a code was sent" is the
/// same for both, so the two flows share this screen and differ only in the
/// endpoints it calls and the wording.
enum OtpChannel {
  /// Over SMS. Creates the account if the number is new.
  sms,

  /// By email. Creates the account if the address is new.
  email,
}

class OtpScreen extends StatefulWidget {
  final OtpChannel channel;

  /// What the user reads back: a formatted phone number, or an email address.
  final String destination;

  /// What a resend is addressed to: the E.164 number, or the email address.
  final String identifier;

  final String verifyId;
  final String role;

  const OtpScreen({
    super.key,
    this.channel = OtpChannel.sms,
    required this.destination,
    required this.identifier,
    required this.verifyId,
    required this.role,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _code = '';
  late int _secondsLeft = _resendSeconds;
  Timer? _timer;
  late String _verifyId = widget.verifyId;
  bool _submitting = false;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool get _isEmail => widget.channel == OtpChannel.email;

  /// Five digits whichever channel carried it — the backend issues the same
  /// length for both, so the code field is one shape.
  static const int _codeLength = 5;

  int get _resendSeconds => _isEmail ? 60 : 57;

  @override
  void initState() {
    super.initState();
    _startTimer();
    // Delay focus until the push animation finishes (~300ms)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _focusNode.requestFocus();
      });
    });
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

  void _onChanged(String value) {
    setState(() => _code = value);
    if (value.length == _codeLength) {
      Future.delayed(const Duration(milliseconds: 300), _submit);
    }
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0) return;
    try {
      final result = _isEmail
          ? await AuthService.sendEmailOtp(
              widget.identifier,
              userType: widget.role,
            )
          : await AuthService.sendOtp(
              widget.identifier,
              userType: widget.role,
            );
      if (!mounted) return;
      setState(() {
        _verifyId = result['verifyID'] as String;
        _secondsLeft = _resendSeconds;
        _code = '';
      });
      _controller.clear();
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
      final result = _isEmail
          ? await AuthService.verifyEmailOtp(
              verifyId: _verifyId,
              otpCode: _code,
            )
          : await AuthService.verifyOtp(
              verifyId: _verifyId,
              otpCode: _code,
            );

      await TokenService.saveTokens(
        access: result['accessToken'] as String,
        refresh: result['refreshToken'] as String,
      );

      if (!mounted) return;

      FocusScope.of(context).unfocus();

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
      _controller.clear();
      AppNotify.show(context, message: e.message);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: context.colors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Login',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textPrimary,
                    height: 1.2,
                  ),
                  children: [
                    const TextSpan(text: 'Enter\nthe code'),
                    TextSpan(
                      text: '-',
                      style: TextStyle(color: context.colors.accentYellow),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              Text(
                _isEmail
                    ? 'We sent a $_codeLength-digit code to ${widget.destination}'
                    : 'To confirm your phone number, send a $_codeLength-digit code to ${widget.destination}',
                style: TextStyle(
                  color: context.colors.textTertiary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),

              const Spacer(),

              // Stack: transparent TextField behind the digit dots.
              // TextField has real height so focus + keyboard work reliably.
              // Tapping anywhere on the dot row focuses the field.
              SizedBox(
                height: 60,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Invisible input captures taps and keyboard events
                    AutofillGroup(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(_codeLength),
                        ],
                        onChanged: _onChanged,
                        showCursor: false,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(
                          color: Colors.transparent,
                          fontSize: 1,
                        ),
                      ),
                    ),

                    // Digit display on top — pointer events fall through to TextField
                    IgnorePointer(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_codeLength, (i) {
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
                                      style: TextStyle(
                                        fontSize: 40,
                                        fontWeight: FontWeight.bold,
                                        color: context.colors.textPrimary,
                                      ),
                                    )
                                  : Container(
                                      key: ValueKey('dot_$i'),
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: context.colors.border,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
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
                          ? context.colors.textTertiary
                          : context.colors.textPrimary,
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
    );
  }
}
