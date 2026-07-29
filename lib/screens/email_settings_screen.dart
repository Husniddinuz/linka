import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/auth_service.dart';
import '../services/token_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';

/// Linking an email address to the signed-in account, so it can also be used
/// to sign in.
///
/// Two steps by design: the address is typed here, but nothing is stored until
/// the code mailed to it comes back. That is what makes email login safe —
/// an account only gains a second way in through an inbox its owner has just
/// demonstrably read.
///
/// The phone number is never touched, so removing the email can lock nobody
/// out.
class EmailSettingsScreen extends StatefulWidget {
  const EmailSettingsScreen({super.key});

  @override
  State<EmailSettingsScreen> createState() => _EmailSettingsScreenState();
}

class _EmailSettingsScreenState extends State<EmailSettingsScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();

  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  String? _linked = UserService.current?.email;
  String? _verifyId;
  String _pendingAddress = '';
  bool _busy = false;

  bool get _awaitingCode => _verifyId != null;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<String?> _token() async => TokenService.getAccessToken();

  /// Re-reads `/users/me/` so the rest of the app sees the change without a
  /// restart — [UserService.current] is what the profile screen renders from.
  Future<void> _refreshMe() async {
    try {
      await UserService.fetchMe();
    } catch (_) {
      // The link itself already succeeded; a failed refresh is not worth an
      // error the user can act on, and the next fetch will pick it up.
    }
  }

  Future<void> _send() async {
    final email = _emailController.text.trim();
    if (!_emailRe.hasMatch(email) || _busy) return;

    setState(() => _busy = true);
    try {
      final token = await _token();
      if (token == null) throw const AuthException('Please log in again');

      final result = await AuthService.addEmail(email: email, accessToken: token);
      if (!mounted) return;
      setState(() {
        _verifyId = result['verifyID'] as String;
        _pendingAddress = email;
      });
      _codeController.clear();
    } on AuthException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    } catch (_) {
      if (!mounted) return;
      AppNotify.show(context, message: 'Connection problem. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final code = _codeController.text.trim();
    final verifyId = _verifyId;
    if (verifyId == null || code.length < 4 || _busy) return;

    setState(() => _busy = true);
    try {
      final token = await _token();
      if (token == null) throw const AuthException('Please log in again');

      final email = await AuthService.confirmEmail(
        verifyId: verifyId,
        otpCode: code,
        accessToken: token,
      );
      await _refreshMe();
      if (!mounted) return;
      setState(() {
        _linked = email.isEmpty ? _pendingAddress : email;
        _verifyId = null;
      });
      _emailController.clear();
      _codeController.clear();
      AppNotify.show(
        context,
        message: 'Email linked. You can now sign in with it.',
        type: NotifyType.success,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    } catch (_) {
      if (!mounted) return;
      AppNotify.show(context, message: 'Connection problem. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final token = await _token();
      if (token == null) throw const AuthException('Please log in again');

      await AuthService.removeEmail(accessToken: token);
      await _refreshMe();
      if (!mounted) return;
      setState(() => _linked = null);
      AppNotify.show(context, message: 'Email removed from your account.');
    } on AuthException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    } catch (_) {
      if (!mounted) return;
      AppNotify.show(context, message: 'Connection problem. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: colors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Email sign-in',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add an email address and you can sign in with it as well as '
                'your phone number. Your phone stays the main identity of the '
                'account.',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              if (_linked != null && !_awaitingCode) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.check_circle_rounded,
                        size: 20,
                        fill: 1,
                        color: colors.success,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _linked!,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _remove,
                        child: Text(
                          'Remove',
                          style: TextStyle(
                            color: colors.error,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              if (!_awaitingCode) ...[
                Text(
                  _linked == null
                      ? 'Email address'
                      : 'Replace with a different address',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.go,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.email],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _send(),
                  style: TextStyle(color: colors.textPrimary, fontSize: 16),
                  decoration: _fieldDecoration(colors, 'you@example.com'),
                ),
                const SizedBox(height: 16),
                _primaryButton(
                  colors,
                  label: 'Send code',
                  enabled: _emailRe.hasMatch(_emailController.text.trim()),
                  onPressed: _send,
                ),
              ] else ...[
                Text(
                  'We sent a 6-digit code to $_pendingAddress. Enter it to '
                  'finish linking.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: 6,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _confirm(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: _fieldDecoration(colors, '••••••')
                      .copyWith(counterText: ''),
                ),
                const SizedBox(height: 16),
                _primaryButton(
                  colors,
                  label: 'Confirm',
                  enabled: _codeController.text.trim().length >= 4,
                  onPressed: _confirm,
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _verifyId = null),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(AppColors colors, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: colors.textTertiary,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      filled: true,
      fillColor: colors.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _primaryButton(
    AppColors colors, {
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: enabled && !_busy ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.brand,
          disabledBackgroundColor: colors.border,
          foregroundColor: colors.onBrand,
          disabledForegroundColor: colors.textTertiary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        child: _busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onBrand,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
