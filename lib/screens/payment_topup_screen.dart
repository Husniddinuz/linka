import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/wallet_service.dart';
import '../widgets/app_notify.dart';

enum PaymentMethod { click, payme, uzum }

extension on PaymentMethod {
  String get apiValue {
    switch (this) {
      case PaymentMethod.click:
        return 'click';
      case PaymentMethod.payme:
        return 'payme';
      case PaymentMethod.uzum:
        return 'uzum';
    }
  }
}

class PaymentTopUpScreen extends StatefulWidget {
  const PaymentTopUpScreen({super.key});

  @override
  State<PaymentTopUpScreen> createState() => _PaymentTopUpScreenState();
}

class _PaymentTopUpScreenState extends State<PaymentTopUpScreen>
    with WidgetsBindingObserver {
  PaymentMethod? _selected;
  final TextEditingController _amountController = TextEditingController();
  bool _submitting = false;
  // Set after we hand the user off to an external payment app/page. When
  // the app comes back to the foreground we'll finalize and pop.
  int? _awaitingAmount;
  int? _pendingOrderId;
  bool _finalizing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amountController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _pendingOrderId != null &&
        !_finalizing) {
      _finalize();
    }
  }

  Future<void> _finalize() async {
    final orderId = _pendingOrderId;
    if (orderId == null) return;
    setState(() => _finalizing = true);
    try {
      final result = await WalletService.checkPaylovTransactionStatus(
        orderId: orderId,
      );
      if (!mounted) return;
      if (result.isPaid) {
        final amount = _awaitingAmount;
        _pendingOrderId = null;
        _awaitingAmount = null;
        Navigator.pop(context, amount);
        return;
      }
      // Not yet paid — keep the screen open so the user can retry the
      // finalize check (e.g. if the bank flow is still settling).
      AppNotify.show(
        context,
        message: result.message ??
            'Payment not confirmed yet. Please try again in a moment.',
        type: NotifyType.info,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message, type: NotifyType.error);
    } catch (_) {
      if (!mounted) return;
      AppNotify.show(
        context,
        message: 'Could not verify payment',
        type: NotifyType.error,
      );
    } finally {
      if (mounted) setState(() => _finalizing = false);
    }
  }

  Widget _buildWaitingView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF272942)),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _finalizing ? 'Verifying payment.' : 'Waiting for payment.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF272942),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _finalizing
                ? 'Checking the payment status with the bank.'
                : 'Complete the payment in your bank app, then return here.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF888888),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _finalizing ? null : _finalize,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF272942),
                disabledBackgroundColor: const Color(0xFFCCCCCC),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _finalizing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'I have completed the payment',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _finalizing
                ? null
                : () {
                    setState(() {
                      _awaitingAmount = null;
                      _pendingOrderId = null;
                    });
                  },
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF888888),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int? get _amount {
    final raw = _amountController.text.replaceAll(' ', '');
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  bool get _canSubmit =>
      !_submitting &&
      _selected != null &&
      (_amount ?? 0) >= 1;

  Future<void> _onTopUp() async {
    if (!_canSubmit) return;
    final amount = _amount!;
    final provider = _selected!.apiValue;

    setState(() => _submitting = true);
    try {
      final result = await WalletService.createPaylovCheckout(
        amountUzs: amount,
        provider: provider,
      );
      if (!mounted) return;

      final url = result.checkoutUrl;
      if (url == null || url.isEmpty) {
        AppNotify.show(
          context,
          message: result.message ?? 'No checkout URL returned',
          type: NotifyType.error,
        );
        return;
      }

      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (!launched) {
        AppNotify.show(
          context,
          message: 'Could not open payment page',
          type: NotifyType.error,
        );
        return;
      }
      // Don't pop yet — wait until the user comes back to the app from the
      // external payment flow (handled in didChangeAppLifecycleState).
      setState(() {
        _awaitingAmount = amount;
        _pendingOrderId = result.orderId;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message, type: NotifyType.error);
    } catch (_) {
      if (!mounted) return;
      AppNotify.show(
        context,
        message: 'Failed to start payment',
        type: NotifyType.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF272942), size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Payment',
          style: TextStyle(
            color: Color(0xFF272942),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _awaitingAmount != null ? _buildWaitingView() : Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'AMOUNT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF888888),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE8E8E8)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amountController,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF272942),
                            ),
                            decoration: const InputDecoration(
                              hintText: '0',
                              hintStyle: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFCCCCCC),
                              ),
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const Text(
                          'UZS',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF999999),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'PAYMENT METHOD',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF888888),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Click
                  _PaymentMethodCard(
                    isSelected: _selected == PaymentMethod.click,
                    onTap: () => setState(() => _selected = PaymentMethod.click),
                    child: Image.asset(
                      'assets/images/branding/click.png',
                      height: 28,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Payme
                  _PaymentMethodCard(
                    isSelected: _selected == PaymentMethod.payme,
                    onTap: () => setState(() => _selected = PaymentMethod.payme),
                    child: Image.asset(
                      'assets/images/branding/payme.png',
                      height: 28,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Uzum Bank
                  _PaymentMethodCard(
                    isSelected: _selected == PaymentMethod.uzum,
                    onTap: () => setState(() => _selected = PaymentMethod.uzum),
                    child: Image.asset(
                      'assets/images/branding/uzum.png',
                      height: 28,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Info text
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F6F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Color(0xFF6C9BD1)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Select from the options to go to the bank app and top up your wallet.',
                            style: TextStyle(fontSize: 13, color: Color(0xFF888888)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Top up button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _canSubmit ? _onTopUp : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF272942),
                  disabledBackgroundColor: const Color(0xFFCCCCCC),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Top up',
                        style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}

// ─── Payment method card ────────────────────────────────────────────────────

class _PaymentMethodCard extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final Widget child;

  const _PaymentMethodCard({
    required this.isSelected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF8C00) : const Color(0xFFE8E8E8),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            child,
            const Spacer(),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFFFF8C00) : const Color(0xFFCCCCCC),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFF8C00),
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
