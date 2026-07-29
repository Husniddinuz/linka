import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'otp_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';

/// Signing in with an email address.
///
/// The counterpart to [AuthScreen], and deliberately a separate screen rather
/// than a tab inside it: the phone screen is built around a custom numeric
/// keypad that fills the lower half, which an email field has no use for.
///
/// This route can only sign you *in*. Accounts are created by phone, and the
/// address has to be confirmed from My Profile first — so the copy below says
/// as much, otherwise the only feedback a new user gets is a code that never
/// arrives.
class EmailAuthScreen extends StatefulWidget {
  final String role;

  const EmailAuthScreen({super.key, this.role = 'student'});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;

  /// Loose on purpose — the server owns the real rule. This only decides when
  /// the button lights up; rejecting a valid-but-unusual address here would be
  /// worse than letting the server answer.
  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  String get _email => _controller.text.trim();

  bool get _isComplete => _emailRe.hasMatch(_email);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _focusNode.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _onGetCode() async {
    if (!_isComplete || _loading) return;
    setState(() => _loading = true);
    final email = _email;
    try {
      final result = await AuthService.sendEmailOtp(
        email,
        userType: widget.role,
      );
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            channel: OtpChannel.email,
            destination: email,
            identifier: email,
            verifyId: result['verifyID'] as String,
            role: widget.role,
          ),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    } catch (_) {
      // AuthService talks to `http` directly, so a dropped connection arrives
      // as a SocketException rather than an AuthException.
      if (!mounted) return;
      AppNotify.show(
        context,
        message: 'Connection problem. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        Icons.arrow_back_ios_rounded,
                        color: colors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                        height: 1.2,
                      ),
                      children: [
                        const TextSpan(text: 'Sign in with\nemail'),
                        TextSpan(
                          text: '-',
                          style: TextStyle(color: colors.accentYellow),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Enter the address linked to your Linka account and we will '
                    'email you a 6-digit code.',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 32),

                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.go,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.email],
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _onGetCode(),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: 'you@example.com',
                      hintStyle: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                      ),
                      filled: true,
                      fillColor: colors.surfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isComplete && !_loading ? _onGetCode : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.brand,
                        disabledBackgroundColor: colors.border,
                        foregroundColor: colors.onBrand,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: _loading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onBrand,
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

                  const SizedBox(height: 20),

                  Text(
                    'Email sign-in works once you have added your address in My '
                    'Profile. New accounts still start with a phone number.',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
