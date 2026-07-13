import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import '../services/app_feature_service.dart';
import '../services/plus_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_colors.dart';
import 'payment_topup_screen.dart';
import '../widgets/app_notify.dart';
import '../widgets/skeleton.dart';

const _yearlyCode = 'yearly';
const _monthlyCode = 'monthly';
const _fallbackYearlyPrice = 240000;
const _fallbackMonthlyPrice = 30000;


class PlusSubscriptionScreen extends StatefulWidget {
  const PlusSubscriptionScreen({super.key});

  @override
  State<PlusSubscriptionScreen> createState() => _PlusSubscriptionScreenState();
}

class _PlusSubscriptionScreenState extends State<PlusSubscriptionScreen> {
  bool _isYearly = true;
  int? _balance;
  bool _balanceLoading = true;
  List<PlusPlan> _plans = const [];
  PlusStatus? _status;
  bool _submitting = false;

  PlusPlan? get _yearlyPlan => _planByCode(_yearlyCode);
  PlusPlan? get _monthlyPlan => _planByCode(_monthlyCode);

  PlusPlan? _planByCode(String code) {
    for (final plan in _plans) {
      if (plan.code == code) return plan;
    }
    return null;
  }

  int get _yearlyPrice => _yearlyPlan?.priceUzs ?? _fallbackYearlyPrice;
  int get _monthlyPrice => _monthlyPlan?.priceUzs ?? _fallbackMonthlyPrice;
  int get _price => _isYearly ? _yearlyPrice : _monthlyPrice;
  String get _selectedCode => _isYearly ? _yearlyCode : _monthlyCode;

  /// Savings on the yearly plan vs. buying the monthly plan for the same
  /// number of days. Returns null when we lack enough data to compute it,
  /// or when the yearly plan isn't cheaper.
  int? get _yearlyDiscountPercent {
    final monthly = _monthlyPlan;
    final yearly = _yearlyPlan;
    if (monthly == null || yearly == null) return null;
    final monthlyDays = monthly.durationDays ?? 30;
    final yearlyDays = yearly.durationDays ?? 365;
    if (monthlyDays <= 0 || yearlyDays <= 0 || monthly.priceUzs <= 0) {
      return null;
    }
    final equivalentMonthlyCost =
        monthly.priceUzs * (yearlyDays / monthlyDays);
    if (equivalentMonthlyCost <= 0) return null;
    final ratio = 1 - yearly.priceUzs / equivalentMonthlyCost;
    final percent = (ratio * 100).round();
    return percent > 0 ? percent : null;
  }

  String get _yearlySubtitle {
    final days = _yearlyPlan?.durationDays;
    if (days == null) return 'Billed yearly';
    if (days % 30 == 0) return '${days ~/ 30} months';
    return '$days days';
  }

  @override
  void initState() {
    super.initState();
    _loadBalance();
    _loadPlans();
    _loadStatus();
  }

  Future<void> _loadBalance() async {
    try {
      final balance = await WalletService.getBalance();
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _balanceLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _balanceLoading = false);
    }
  }

  Future<void> _onTopUp() async {
    await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const PaymentTopUpScreen()),
    );
    if (!mounted) return;
    // Re-fetch wallet balance from server after returning from top-up
    setState(() => _balanceLoading = true);
    await _loadBalance();
  }

  Future<void> _loadPlans() async {
    try {
      final plans = await PlusService.getPlans();
      if (!mounted) return;
      setState(() => _plans = plans);
    } catch (_) {
      // Fallback prices remain visible; checkout still works by plan_code.
    }
  }

  Future<void> _loadStatus() async {
    try {
      final status = await PlusService.getMyStatus();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (_) {
      // Non-critical — Connect button stays enabled.
    }
  }

  Future<void> _onConnect() async {
    if (_submitting) return;

    final price = _price;
    final balance = _balance;
    if (balance != null && balance < price) {
      AppNotify.show(
        context,
        message:
            'Not enough balance. Please top up your wallet and try again.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await PlusService.checkout(_selectedCode);
      if (!mounted) return;
      AppNotify.show(
        context,
        message: result.message ?? 'PLUS activated',
        type: NotifyType.success,
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    } catch (_) {
      if (!mounted) return;
      AppNotify.show(context, message: 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasEnoughBalance =
        !_balanceLoading && (_balance ?? 0) >= _price;
    final isAlreadyActive = _status?.isActive == true &&
        _status?.planCode == _selectedCode;
    final plusEnabled = AppFeatureService.isEnabled('plus');
    final canConnect =
        plusEnabled && !_submitting && !_balanceLoading && !isAlreadyActive;
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: colors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 8),

                  // ─── Gradient banner ───
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/branding/plus-banner.png',
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ─── Plan selection ───
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                        // Yearly option
                        GestureDetector(
                          onTap: () => setState(() => _isYearly = true),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                            child: Row(
                              children: [
                                _RadioDot(selected: _isYearly),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Per year',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: colors.textPrimary,
                                            ),
                                          ),
                                          if (_yearlyDiscountPercent != null) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: colors.error,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                '-$_yearlyDiscountPercent%',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _yearlySubtitle,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '${_formatPrice(_yearlyPrice)} ',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                      TextSpan(
                                        text: 'UZS',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w400,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Divider(height: 1, thickness: 1, color: colors.border),
                        ),

                        // Monthly option
                        GestureDetector(
                          onTap: () => setState(() => _isYearly = false),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 24),
                            child: Row(
                              children: [
                                _RadioDot(selected: !_isYearly),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Monthly',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ),
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '${_formatPrice(_monthlyPrice)} ',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                      TextSpan(
                                        text: 'UZS',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w400,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ),
                ],
              ),
            ),
          ),

          // ─── Bottom section ───
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Column(
              children: [
                // Balance & Price
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      // Balance
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Balance',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: colors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            if (_balanceLoading)
                              const Skeleton(
                                height: 20,
                                width: 100,
                                borderRadius: 6,
                              )
                            else
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '${_formatPrice(_balance ?? 0)} ',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: hasEnoughBalance
                                            ? colors.success
                                            : colors.error,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'UZS',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _onTopUp,
                              behavior: HitTestBehavior.opaque,
                              child: SvgPicture.asset(
                                'assets/images/buttons/top-up.svg',
                                width: 28,
                                height: 28,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Price
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Price',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: colors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: _formatPrice(_price),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' UZS',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Connect button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canConnect ? _onConnect : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.brand,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          colors.brand.withValues(alpha: 0.4),
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            !plusEnabled
                                ? 'Temporarily unavailable'
                                : isAlreadyActive
                                    ? 'Already active'
                                    : 'Connect',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrice(int price) {
    final str = price.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }
}

// ─── Radio dot ──────────────────────────────────────────────────────────────

class _RadioDot extends StatelessWidget {
  final bool selected;

  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? colors.accentYellow : colors.border,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accentYellow,
                ),
              ),
            )
          : null,
    );
  }
}
