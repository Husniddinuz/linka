import 'package:flutter/material.dart';

import '../services/ielts_registration_service.dart';
import '../widgets/mock_test_styles.dart';
import 'ielts_profile_form_screen.dart';

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
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController(text: '+998');
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final fullName = _nameController.text.trim();
    final nameParts = fullName.split(RegExp(r'\s+'));
    final firstName = nameParts.first;
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : firstName;
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    try {
      await IeltsRegistrationService.signInOrSignUp(
        email: email,
        password: password,
        fullName: fullName,
      );
      try {
        await IeltsRegistrationService.createAccountProfile(
          email: email,
          firstName: firstName,
          lastName: lastName,
          mobileNumber: phone,
        );
      } catch (_) {
        // Non-fatal: the account-level profile may already exist for a
        // returning student — the test-taker profile below is what matters.
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IeltsProfileFormScreen(
            session: widget.session,
            email: email,
            firstName: firstName,
            lastName: lastName,
            mobileNumber: phone,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _error = 'Could not create the IDP account. Check the details and try again.';
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
              controller: _nameController,
              label: 'Full name',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            _field(
              controller: _emailController,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 14),
            _field(
              controller: _phoneController,
              label: 'Mobile number',
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().length < 9) ? 'Enter a valid phone number' : null,
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
