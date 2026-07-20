import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
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

  /// Monthly-equivalent cost of the yearly plan, e.g. "≈ 20 000 UZS/mo".
  String? get _yearlyPerMonthLabel {
    final days = _yearlyPlan?.durationDays ?? 365;
    if (days <= 0) return null;
    final months = days / 30;
    if (months < 1) return null;
    final perMonth = (_yearlyPrice / months).round();
    return '≈ ${_formatPrice(perMonth)} UZS/mo';
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
            Symbols.arrow_back_ios_new_rounded,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  const _PlusHero(),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 8),
                    child: Text(
                      'CHOOSE YOUR PLAN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                  _PlanCard(
                    title: 'Yearly',
                    subtitle: _yearlySubtitle,
                    price: _yearlyPrice,
                    perMonthLabel: _yearlyPerMonthLabel,
                    badgePercent: _yearlyDiscountPercent,
                    selected: _isYearly,
                    formatPrice: _formatPrice,
                    onTap: () => setState(() => _isYearly = true),
                  ),
                  const SizedBox(height: 10),
                  _PlanCard(
                    title: 'Monthly',
                    subtitle: 'Billed monthly',
                    price: _monthlyPrice,
                    selected: !_isYearly,
                    formatPrice: _formatPrice,
                    onTap: () => setState(() => _isYearly = false),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ─── Bottom summary + CTA ───
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            'Balance',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colors.textSecondary,
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
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: hasEnoughBalance
                                          ? colors.success
                                          : colors.error,
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'UZS',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _onTopUp,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: colors.brand,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Symbols.add_rounded,
                                    size: 14,
                                    weight: 700,
                                    color: colors.onBrand,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Top up',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: colors.onBrand,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(height: 0.5, color: colors.border),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${_formatPrice(_price)} ',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                TextSpan(
                                  text: 'UZS',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (!_balanceLoading && !hasEnoughBalance) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Symbols.info_rounded,
                        size: 14,
                        color: colors.error,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Not enough balance — top up to continue',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.error,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 12),

                // Connect button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canConnect ? _onConnect : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.brand,
                      foregroundColor: colors.onBrand,
                      disabledBackgroundColor:
                          colors.brand.withValues(alpha: 0.4),
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
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
                                    : 'Get PLUS',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
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

// ─── Hero ───────────────────────────────────────────────────────────────────

class _PlusHero extends StatelessWidget {
  const _PlusHero();

  static const _benefits = [
    'Unlimited chat with tutors',
    'Webinars & debates',
    'Priority support',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gradientEnd = Color.lerp(colors.brand, Colors.black, 0.35)!;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.brand, gradientEnd],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -24,
            bottom: -30,
            child: Icon(
              Symbols.workspace_premium_rounded,
              size: 160,
              fill: 1,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          Positioned(
            top: -40,
            left: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Symbols.workspace_premium_rounded,
                      size: 22,
                      fill: 1,
                      color: colors.accentYellow,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Linka PLUS',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Everything you need to level up your English.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 16),
                for (final benefit in _benefits) ...[
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Symbols.check_rounded,
                          size: 12,
                          weight: 800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        benefit,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  if (benefit != _benefits.last) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Plan card ──────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int price;
  final String? perMonthLabel;
  final int? badgePercent;
  final bool selected;
  final String Function(int) formatPrice;
  final VoidCallback onTap;

  const _PlanCard({
    required this.title,
    required this.subtitle,
    required this.price,
    this.perMonthLabel,
    this.badgePercent,
    required this.selected,
    required this.formatPrice,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? colors.accentYellow.withValues(alpha: 0.06)
              : colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colors.accentYellow : colors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            _SelectDot(selected: selected),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (badgePercent != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.accentYellow,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'SAVE $badgePercent%',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              // Fixed navy for contrast on gold in both themes.
                              color: Color(0xFF272942),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${formatPrice(price)} ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      TextSpan(
                        text: 'UZS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (perMonthLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    perMonthLabel!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Selection dot ──────────────────────────────────────────────────────────

class _SelectDot extends StatelessWidget {
  final bool selected;

  const _SelectDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.accentYellow : Colors.transparent,
        border: selected
            ? null
            : Border.all(color: colors.border, width: 2),
      ),
      child: selected
          ? const Icon(
              Symbols.check_rounded,
              size: 14,
              weight: 800,
              // Fixed navy for contrast on the gold dot in both themes.
              color: Color(0xFF272942),
            )
          : null,
    );
  }
}
