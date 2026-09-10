import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'otp_screen.dart';
import 'public_offer_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import '../widgets/num_key.dart';

class AuthScreen extends StatefulWidget {
  final String role;

  const AuthScreen({super.key, this.role = 'student'});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  String _digits = '';
  bool _accepted = true;
  bool _loading = false;
  final _publicOfferRecognizer = TapGestureRecognizer();

  bool get _isComplete => _digits.length == 9;

  String get _formattedPhone {
    final b = StringBuffer();
    for (var i = 0; i < _digits.length; i++) {
      if (i == 0) b.write('(');
      b.write(_digits[i]);
      if (i == 1) b.write(') ');
      if (i == 4) b.write(' - ');
      if (i == 6) b.write(' - ');
    }
    return b.toString();
  }

  void _onDigit(String digit) {
    if (_digits.length >= 9) return;
    setState(() => _digits += digit);
  }

  void _onDelete() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  String get _fullPhone => '+998$_digits';

  Future<void> _onGetCode() async {
    setState(() => _loading = true);
    try {
      final result = await AuthService.sendOtp(
        _fullPhone,
        userType: widget.role,
      );
      if (!mounted) return;

      // Show OTP code for testing (remove before release)
      final otpCode = result['otp_code'];
      if (otpCode != null) {
        AppNotify.show(
          context,
          message: 'DEV OTP: $otpCode',
          type: NotifyType.info,
          duration: const Duration(seconds: 5),
        );
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            destination: '+998 $_formattedPhone',
            identifier: _fullPhone,
            verifyId: result['verifyID'] as String,
            role: widget.role,
          ),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _publicOfferRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _isComplete && _accepted;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),

                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.colors.surfaceAlt,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Symbols.arrow_back_ios_new_rounded,
                            size: 18,
                            color: context.colors.textPrimary,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                            color: context.colors.textPrimary,
                          ),
                          children: [
                            const TextSpan(text: 'Welcome'),
                            TextSpan(
                              text: '!',
                              style: TextStyle(color: context.colors.accentYellow),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Phone display
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '+998 ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: _digits.isEmpty
                                    ? context.colors.textTertiary
                                    : context.colors.textPrimary,
                              ),
                            ),
                            Text(
                              _digits.isEmpty
                                  ? '(__) ___-__-__'
                                  : _formattedPhone,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: _digits.isEmpty
                                    ? context.colors.textTertiary
                                    : context.colors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Get a code button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: canSubmit && !_loading ? _onGetCode : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.brand,
                            disabledBackgroundColor: context.colors.textTertiary,
                            foregroundColor: Colors.white,
                            disabledForegroundColor: context.colors.textSecondary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Get a code',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Checkbox
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _accepted = !_accepted),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: _accepted
                                    ? context.colors.accentYellow
                                    : context.colors.surface,
                                border: Border.all(
                                  color: _accepted
                                      ? context.colors.accentYellow
                                      : context.colors.textTertiary,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: _accepted
                                  ? const Icon(
                                      Symbols.check_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.colors.textSecondary,
                                ),
                                children: [
                                  const TextSpan(
                                    text: 'By using the App, I accept the ',
                                  ),
                                  TextSpan(
                                    text: 'Public Offer',
                                    style: TextStyle(
                                      color: context.colors.textPrimary,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: _publicOfferRecognizer
                                      ..onTap = () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const PublicOfferScreen(),
                                          ),
                                        );
                                      },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Custom numpad
              NumPad(onDigit: _onDigit, onDelete: _onDelete),
            ],
          ),
        ),
      ),
    );
  }
}
