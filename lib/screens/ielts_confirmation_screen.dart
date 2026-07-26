import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/mock_test_styles.dart';

/// Shows the reservation created by `/v1/applications/register` — the
/// receipt/amount already come back on that response, so no separate
/// payment-method or receipt call is needed here. Payment itself happens
/// outside the app: the student logs into their own IDP account
/// (account.ielts.idp.com) and pays there.
class IeltsConfirmationScreen extends StatelessWidget {
  const IeltsConfirmationScreen({super.key, required this.application, required this.mobileNumber});

  final Map<String, dynamic> application;
  final String mobileNumber;

  Map<String, dynamic>? get _payment {
    final payments = application['applicationPayments'] as List?;
    if (payments == null || payments.isEmpty) return null;
    return payments.first as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    final payment = _payment;
    final receiptNumber = payment?['receiptNumber'] as String? ?? '—';
    final amount = payment?['amount'];
    final currency = payment?['currency'] as String? ?? '';
    final expiry = application['expiryDateTimeUtc'] as String?;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: 'Reservation Confirmed'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          Center(
            child: Icon(Icons.check_circle_rounded, color: MockTestColors.green, size: 56),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Seats reserved',
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 18, fontWeight: FontWeight.w700, color: MockTestColors.navy),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'The student must log into their own IDP account to pay — this '
              'app doesn\'t handle payment.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13, color: MockTestColors.grey),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: mtSoftCard(context, radius: 18),
            child: Column(
              children: [
                _row('Receipt number', receiptNumber),
                const Divider(height: 24, color: MockTestColors.divider),
                _row('Amount due', amount != null ? '$amount $currency' : '—'),
                if (expiry != null) ...[
                  const Divider(height: 24, color: MockTestColors.divider),
                  _row('Reservation expires', expiry),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          MtPrimaryButton(label: 'Send payment details to student', onPressed: () => _sendToPhone(context, receiptNumber, amount, currency)),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, color: MockTestColors.grey)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14, fontWeight: FontWeight.w600, color: MockTestColors.navy),
          ),
        ),
      ],
    );
  }

  Future<void> _sendToPhone(BuildContext context, String receiptNumber, dynamic amount, String currency) async {
    final message = 'Your IELTS test reservation is confirmed. Receipt: $receiptNumber, '
        'amount due: $amount $currency. Log into https://account.ielts.idp.com to complete payment.';
    final uri = Uri(scheme: 'sms', path: mobileNumber, queryParameters: {'body': message});
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open messages app.')),
      );
    }
  }
}
