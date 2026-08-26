import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/affiliate_service.dart';
import '../services/api_service.dart';
import '../services/app_feature_service.dart';
import '../services/plus_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_colors.dart';
import 'payment_topup_screen.dart';
import '../widgets/app_notify.dart';
import '../widgets/promo_code_field.dart';
import '../widgets/skeleton.dart';

/// What to show before `/payments/plus/plans/` answers — and if it never does.
///
/// The real list is the server's; these are the same three tariffs at the
/// prices set on 2026-08-26, so a student on a bad connection sees the plans
/// rather than an empty screen. Checkout is by `plan_code`, so a stale price
/// here can only ever misprice the card, never the debit.
const _fallbackPlans = <PlusPlan>[
  PlusPlan(code: 'yearly', title: '1 Year', priceUzs: 799000, durationDays: 365),
  PlusPlan(
      code: 'quarterly',
      title: '3 Months',
      priceUzs: 219000,
      durationDays: 90),
  PlusPlan(code: 'monthly', title: '1 Month', priceUzs: 99000, durationDays: 30),
];

class PlusSubscriptionScreen extends StatefulWidget {
  const PlusSubscriptionScreen({super.key});

  @override
  State<PlusSubscriptionScreen> createState() => _PlusSubscriptionScreenState();
}

class _PlusSubscriptionScreenState extends State<PlusSubscriptionScreen> {
  int? _balance;
  bool _balanceLoading = true;

  /// Every active tariff the server offers, longest first — the best deal
  /// leads, and the ladder reads down to the cheapest commitment.
  List<PlusPlan> _plans = _fallbackPlans;

  /// Null only until the plans arrive; then the longest one.
  String? _pickedCode;

  PlusStatus? _status;
  bool _submitting = false;

  final _promoController = TextEditingController();

  /// The applied code, priced by the server against one specific plan.
  PromoQuote? _promo;

  /// Which plan that quote belongs to. A discount is a percentage of one
  /// plan's price, so switching plans invalidates it — this is what notices,
  /// rather than leaving a yearly saving displayed on a monthly total.
  String? _promoPlanCode;
  bool _promoChecking = false;
  String? _promoError;

  PlusPlan? _planByCode(String? code) {
    if (code == null) return null;
    for (final plan in _plans) {
      if (plan.code == code) return plan;
    }
    return null;
  }

  /// The tariff on the button. Falls back to the first (longest) plan, which
  /// is also what a fresh screen opens on.
  PlusPlan? get _selected => _planByCode(_pickedCode) ?? _plans.firstOrNull;

  /// The shortest plan on screen — the baseline every "save x%" is measured
  /// against, because it is the one a student would otherwise renew monthly.
  PlusPlan? get _shortest => _plans.isEmpty ? null : _plans.last;

  int get _price => _selected?.priceUzs ?? 0;
  String get _selectedCode => _selected?.code ?? '';

  /// The applied code, but only while it is still priced against the plan on
  /// screen. Kept in state across a plan switch rather than dropped: the quote
  /// belongs to one plan, the student's intent to use the code does not.
  PromoQuote? get _activePromo =>
      _promoPlanCode == _selectedCode ? _promo : null;

  /// What this purchase actually costs — the discounted total once a code is on.
  int get _payable => _activePromo?.payableUzs ?? _price;

  /// The badge on a card: what this plan saves against renewing the shortest
  /// one for the same stretch of time.
  int? _savePercent(PlusPlan plan) {
    final baseline = _shortest;
    return baseline == null ? null : plan.savePercentAgainst(baseline);
  }

  String _durationLabel(PlusPlan plan) {
    final months = plan.months;
    if (months <= 0) return 'Billed once';
    if (months == 1) return 'Billed monthly';
    if (months == 12) return 'Billed yearly';
    return 'Billed every $months months';
  }

  /// Monthly-equivalent cost, e.g. "≈ 66 583 UZS/mo" — the only figure that
  /// reads the same across three different billing periods.
  String? _perMonthLabel(PlusPlan plan) {
    final months = plan.months;
    if (months <= 1) return null;
    return '≈ ${_formatPrice((plan.priceUzs / months).round())} UZS/mo';
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
      if (!mounted || plans.isEmpty) return;
      // Longest first, and every plan the admin has switched on — a fourth
      // tariff added there should appear here without a release.
      final sorted = [...plans]..sort(
          (a, b) => (b.durationDays ?? 0).compareTo(a.durationDays ?? 0),
        );
      setState(() {
        _plans = sorted;
        // Only if the student has not already chosen: the plans can land
        // after a tap on a fallback card, and moving the selection under
        // them would be a price changing by itself.
        _pickedCode ??= sorted.first.code;
      });
    } catch (_) {
      // The fallback tariffs stay on screen; checkout is by plan_code, so a
      // stale price here cannot become a wrong debit.
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

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  /// Switching plans re-prices an applied code rather than dropping it.
  void _selectPlan(String code) {
    if (_selectedCode == code) return;
    setState(() => _pickedCode = code);
    final promo = _promo;
    if (promo != null) _applyPromo(promo.code);
  }

  /// Price a code against the selected plan on the server and hold the answer.
  ///
  /// Never computed here: the discount is a percentage the admin can set per
  /// code, so a client that assumed 10% would quote the wrong total to exactly
  /// the students whose tutor negotiated something else.
  Future<void> _applyPromo(String raw) async {
    final code = AffiliateService.normalizeCode(raw);
    if (code.isEmpty || _promoChecking) return;

    final planCode = _selectedCode;
    setState(() {
      _promoChecking = true;
      _promoError = null;
    });
    try {
      final quote = await PlusService.checkPromo(
        planCode: planCode,
        promoCode: code,
      );
      if (!mounted) return;
      setState(() {
        _promo = quote;
        _promoPlanCode = planCode;
        _promoController.text = quote.code;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _promo = null;
        _promoPlanCode = null;
        _promoError = _promoMessage(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _promo = null;
        _promoPlanCode = null;
        _promoError = 'Could not check this code. Try again.';
      });
    } finally {
      if (mounted) setState(() => _promoChecking = false);
    }
  }

  void _clearPromo() {
    setState(() {
      _promo = null;
      _promoPlanCode = null;
      _promoError = null;
      _promoController.clear();
    });
  }

  /// The refusal, in a sentence. The server sends a stable reason code beside
  /// its own English `detail`; the codes are worded for this screen and the
  /// detail is the fallback for a reason this build has not heard of.
  String _promoMessage(ApiException e) {
    switch (e.errorCode) {
      case 'invalid_code':
        return 'Enter a valid promo code.';
      case 'unknown_code':
        return 'No such promo code.';
      case 'inactive_code':
        return 'This promo code is no longer active.';
      case 'own_code':
        return 'You can\u2019t use your own promo code.';
      default:
        return e.message;
    }
  }

  Future<void> _onConnect() async {
    if (_submitting) return;

    final price = _payable;
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
      final result = await PlusService.checkout(
        _selectedCode,
        promoCode: _activePromo?.code,
      );
      if (!mounted) return;
      AppNotify.show(
        context,
        message: result.message ?? 'PLUS activated',
        type: NotifyType.success,
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      // A code can go stale between the quote and the purchase — the tutor
      // deactivates it, an admin suspends the account. That is reported on the
      // promo field, where it can be cleared and the plan bought at full
      // price, rather than as a failed checkout.
      if (e.data?['promo_error'] is String) {
        setState(() {
          _promo = null;
          _promoPlanCode = null;
          _promoError = _promoMessage(e);
        });
        return;
      }
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
        !_balanceLoading && (_balance ?? 0) >= _payable;
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
                  for (final plan in _plans) ...[
                    _PlanCard(
                      title: plan.title?.trim().isNotEmpty == true
                          ? plan.title!.trim()
                          : plan.code,
                      subtitle: _durationLabel(plan),
                      price: plan.priceUzs,
                      perMonthLabel: _perMonthLabel(plan),
                      badgePercent: _savePercent(plan),
                      selected: plan.code == _selectedCode,
                      formatPrice: _formatPrice,
                      onTap: () => _selectPlan(plan.code),
                    ),
                    if (plan != _plans.last) const SizedBox(height: 10),
                  ],
                  // Directly above the summary it changes: a student types a
                  // code to see what it does to the total below, and the
                  // answer is priced by the server, not guessed here. It sits
                  // in the scrolling half rather than the pinned footer so the
                  // keyboard has somewhere to push it.
                  if (!isAlreadyActive) ...[
                    const SizedBox(height: 14),
                    _PromoField(
                      controller: _promoController,
                      applied: _activePromo,
                      checking: _promoChecking,
                      error: _promoError,
                      onApply: () => _applyPromo(_promoController.text),
                      onRemove: _clearPromo,
                      onChanged: () {
                        if (_promoError != null) {
                          setState(() => _promoError = null);
                        }
                      },
                    ),
                  ],
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
                      if (_activePromo != null) ...[
                        const SizedBox(height: 12),
                        Container(height: 0.5, color: colors.border),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Promo code '
                                '(\u2212${_activePromo!.discountPercent.round()}%)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                            Text(
                              '\u2212${_formatPrice(_activePromo!.discountAmountUzs)} UZS',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: colors.success,
                              ),
                            ),
                          ],
                        ),
                      ],
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
                          if (_activePromo != null) ...[
                            Text(
                              '${_formatPrice(_price)} UZS',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: colors.textTertiary,
                                decoration: TextDecoration.lineThrough,
                                decorationColor: colors.textTertiary,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${_formatPrice(_payable)} ',
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

// ─── Promo code field ───────────────────────────────────────────────────────

/// The tutor's promo code, entered by the student who was given it.
///
/// One field, one button: the button applies the code and — once the server
/// has priced it — removes it again, because a code that is on is a thing to
/// take off rather than a second control to find.
class _PromoField extends StatelessWidget {
  final TextEditingController controller;
  final PromoQuote? applied;
  final bool checking;
  final String? error;
  final VoidCallback onApply;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _PromoField({
    required this.controller,
    required this.applied,
    required this.checking,
    required this.error,
    required this.onApply,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final promo = applied;
    final locked = promo != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: locked ? colors.success.withValues(alpha: 0.5) : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PROMO CODE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PromoCodeField(
                  controller: controller,
                  hintText: 'e.g. ALIYA472',
                  enabled: !locked && !checking,
                  onChanged: (_) => onChanged(),
                  onSubmitted: onApply,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 44,
                child: TextButton(
                  onPressed: checking ? null : (locked ? onRemove : onApply),
                  style: TextButton.styleFrom(
                    backgroundColor:
                        locked ? colors.surfaceAlt : colors.brand,
                    foregroundColor: locked ? colors.textPrimary : colors.onBrand,
                    disabledBackgroundColor:
                        colors.brand.withValues(alpha: 0.35),
                    disabledForegroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          locked ? 'Remove' : 'Apply',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
          if (promo != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Symbols.check_circle_rounded,
                    size: 16, fill: 1, color: colors.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    promo.tutorName.isNotEmpty
                        ? '${promo.discountPercent.round()}% off, thanks to '
                            '${promo.tutorName}'
                        : '${promo.discountPercent.round()}% off applied',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colors.success,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Symbols.error_rounded, size: 16, color: colors.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colors.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
