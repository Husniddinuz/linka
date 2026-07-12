import 'package:flutter/material.dart';

import '../services/ielts_registration_service.dart';
import '../widgets/mock_test_styles.dart';
import 'ielts_profile_form_screen.dart';
import 'ielts_resume_upload_screen.dart';

/// First step of the real IELTS registration flow: creates (or signs into)
/// the candidate's own IDP "One Account". This has to be a real account the
/// student can later log into themselves — that's how they'll check status
/// and pay, since payment is handled outside the app.
class IeltsSignupScreen extends StatefulWidget {
  const IeltsSignupScreen({super.key, required this.session});

  final Map<String, dynamic> session;

  @override
  State<IeltsSignupScreen> createState() => _IeltsSignupScreenState();
}

class _IeltsSignupScreenState extends State<IeltsSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      // Full name and mobile number aren't collected here — same as the IDP
      // website, they're asked for on the candidate profile step right after
      // sign-in, not during account creation.
      await IeltsRegistrationService.signInOrSignUp(
        email: email,
        password: password,
        fullName: email,
      );

      try {
        // Provisions the test-taker profile that the next screen's
        // `getUserProfile()` depends on — confirmed live: for a genuinely
        // new account, skipping this makes that call 404 (only worked in
        // earlier testing because the test account already had one from a
        // prior session). "Unknown" mirrors IDP's own frontend, which uses
        // that exact literal for fields not yet collected. Non-fatal: for a
        // returning student the account profile already exists and this
        // 500s harmlessly — the test-taker profile update in the wizard is
        // what carries the real name/mobile.
        await IeltsRegistrationService.createAccountProfile(
          email: email,
          firstName: 'Unknown',
          lastName: 'Unknown',
          mobileNumber: 'Unknown',
        );
      } catch (_) {}

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IeltsProfileFormScreen(
            session: widget.session,
            email: email,
          ),
        ),
      );
    } catch (e) {
      // TODO: temporary — surfaces the real error for debugging, revert to
      // plain user-facing copy once the flow is confirmed stable.
      setState(() {
        _error = 'Could not create the IDP account: $e';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: 'Your IELTS Account'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const Text(
              'This creates your real IDP IELTS account — the same one you\'ll '
              'use to check your booking status and complete payment.',
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, color: MockTestColors.grey),
            ),
            const SizedBox(height: 20),
            _field(
              controller: _emailController,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 14),
            _field(
              controller: _passwordController,
              label: 'Password',
              obscureText: true,
              validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
            ),
            const SizedBox(height: 8),
            const Text(
              'Make sure the student knows this password — they\'ll need it to '
              'sign into account.ielts.idp.com themselves.',
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, color: MockTestColors.greyLight),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13, color: MockTestColors.red)),
            ],
            const SizedBox(height: 24),
            MtPrimaryButton(label: 'Continue', loading: _submitting, onPressed: _submit),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const IeltsResumeUploadScreen()),
                ),
                child: const Text(
                  'Resume an existing application (dev)',
                  style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, color: MockTestColors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    bool obscureText = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(fontFamily: 'SF Pro', fontSize: 15, color: MockTestColors.navy),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey),
        filled: true,
        fillColor: MockTestColors.softBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
