import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_colors.dart';
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

/// Pops with the topped-up amount once the bank confirms it, or null.
class PaymentTopUpScreen extends StatefulWidget {
  const PaymentTopUpScreen({super.key, this.initialAmount, this.purpose});

  /// Prefills the amount, e.g. exactly what a purchase is short by.
  final int? initialAmount;

  /// One line above the amount saying what the money is for.
  final String? purpose;

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
    final amount = widget.initialAmount;
    if (amount != null && amount > 0) _amountController.text = '$amount';
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
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(context.colors.textPrimary),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _finalizing ? 'Verifying payment.' : 'Waiting for payment.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _finalizing
                ? 'Checking the payment status with the bank.'
                : 'Complete the payment in your bank app, then return here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textSecondary,
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
                backgroundColor: context.colors.brand,
                disabledBackgroundColor: context.colors.border,
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
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
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
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Symbols.chevron_left_rounded, color: context.colors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'Payment',
          style: TextStyle(
            color: context.colors.textPrimary,
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
                  if (widget.purpose != null) ...[
                    Text(
                      widget.purpose!,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: context.colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    'AMOUNT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textSecondary,
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
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.colors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amountController,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textTertiary,
                              ),
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        Text(
                          'UZS',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'PAYMENT METHOD',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textSecondary,
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
                      color: context.colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Symbols.info_rounded, size: 18, color: context.colors.accentBlue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Select from the options to go to the bank app and top up your wallet.',
                            style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
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
                  backgroundColor: context.colors.brand,
                  disabledBackgroundColor: context.colors.border,
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
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF8C00) : context.colors.border,
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
                  color: isSelected ? const Color(0xFFFF8C00) : context.colors.border,
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
