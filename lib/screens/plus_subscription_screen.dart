import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/affiliate_service.dart';
import '../services/api_service.dart';
import '../services/app_feature_service.dart';
import '../services/plus_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_colors.dart';
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
  PlusPlan(
    code: 'monthly',
    title: '1 Month',
    priceUzs: 99000,
    durationDays: 30,
  ),
  PlusPlan(
    code: 'quarterly',
    title: '3 Months',
    priceUzs: 219000,
    durationDays: 90,
  ),
  PlusPlan(
    code: 'yearly',
    title: '1 Year',
    priceUzs: 799000,
    durationDays: 365,
  ),
];

/// The smallest sum Paylov is asked for, matching the web's `MIN_UZS`. A
/// shortfall below it (a wallet 400 sums short) is rounded up rather than
/// refused; the few extra sums stay in the wallet.
const _minPaymentUzs = 1000;

/// How often the waiting card asks the gateway what happened, and when it
/// stops asking on its own. A bank flow that has taken fifteen minutes is one
/// the student walked away from; the manual button stays, so nothing is lost.
const _pollInterval = Duration(seconds: 4);
const _pollLimit = Duration(minutes: 15);

/// The three wallet apps Paylov exposes, in the order the web lists them.
/// [key] is the API's `payment_provider` value.
enum _Provider {
  click('click', 'assets/images/branding/click.png'),
  payme('payme', 'assets/images/branding/payme.png'),
  uzum('uzum', 'assets/images/branding/uzum.png');

  const _Provider(this.key, this.asset);
  final String key;
  final String asset;
}

class PlusSubscriptionScreen extends StatefulWidget {
  const PlusSubscriptionScreen({super.key});

  @override
  State<PlusSubscriptionScreen> createState() => _PlusSubscriptionScreenState();
}

class _PlusSubscriptionScreenState extends State<PlusSubscriptionScreen>
    with WidgetsBindingObserver {
  int? _balance;
  bool _balanceLoading = true;

  /// Every active tariff the server offers, shortest first — the price ladder
  /// climbs left to right, and the longest plan carries the recommendation.
  List<PlusPlan> _plans = _fallbackPlans;

  /// Null only until the plans arrive; then the longest one.
  String? _pickedCode;

  PlusStatus? _status;

  /// A purchase is in flight on `/payments/plus/checkout/`.
  bool _activating = false;

  final _promoController = TextEditingController();

  /// The applied code, priced by the server against one specific plan.
  PromoQuote? _promo;

  /// Which plan that quote belongs to. A discount is a percentage of one
  /// plan's price, so switching plans invalidates it — this is what notices,
  /// rather than leaving a yearly saving displayed on a monthly total.
  String? _promoPlanCode;
  bool _promoChecking = false;
  String? _promoError;

  // ─── Inline payment ───
  _Provider? _provider;

  /// A Paylov checkout is being created.
  bool _starting = false;

  /// The order handed to the bank, until it is paid or abandoned.
  int? _pendingOrderId;
  int? _pendingAmount;

  /// Kept so the page can be reopened if the bank tab was lost.
  String? _checkoutUrl;
  bool _verifying = false;
  Timer? _pollTimer;
  DateTime? _pollStartedAt;

  /// Automatic polling gave up; the manual button remains.
  bool _pollExpired = false;

  /// An inline payment has cleared. The balance on screen may lag the server
  /// by a request, and the purchase must not be blocked on a stale figure —
  /// the student has already paid.
  bool _toppedUp = false;

  PlusPlan? _planByCode(String? code) {
    if (code == null) return null;
    for (final plan in _plans) {
      if (plan.code == code) return plan;
    }
    return null;
  }

  /// The tariff on the button. Falls back to the longest plan, which is also
  /// what a fresh screen opens on.
  PlusPlan? get _selected => _planByCode(_pickedCode) ?? _longest;

  /// The shortest plan on screen — the baseline every "save x%" is measured
  /// against, because it is the one a student would otherwise renew monthly.
  PlusPlan? get _shortest => _plans.firstOrNull;
  PlusPlan? get _longest => _plans.lastOrNull;

  int get _price => _selected?.priceUzs ?? 0;
  String get _selectedCode => _selected?.code ?? '';

  /// The applied code, but only while it is still priced against the plan on
  /// screen. Kept in state across a plan switch rather than dropped: the quote
  /// belongs to one plan, the student's intent to use the code does not.
  PromoQuote? get _activePromo =>
      _promoPlanCode == _selectedCode ? _promo : null;

  /// What this purchase actually costs — the discounted total once a code is on.
  int get _payable => _activePromo?.payableUzs ?? _price;

  /// What is missing from the wallet, when something is. This is the number
  /// the student pays — not the plan price — so the payment opens on the gap
  /// rather than asking them to subtract their own balance from the total.
  /// Zero while the balance is unknown: the server refuses, we do not guess.
  int get _shortfall {
    if (_toppedUp || _balanceLoading) return 0;
    final balance = _balance;
    if (balance == null) return 0;
    return math.max(0, _payable - balance);
  }

  bool get _needsPayment => _shortfall > 0;
  bool get _paymentPending => _pendingOrderId != null;

  bool get _isAlreadyActive =>
      _status?.isActive == true && _status?.planCode == _selectedCode;

  /// The badge on a card: what this plan saves against renewing the shortest
  /// one for the same stretch of time.
  int? _savePercent(PlusPlan plan) {
    final baseline = _shortest;
    return baseline == null ? null : plan.savePercentAgainst(baseline);
  }

  /// What the same stretch of time would cost bought a month at a time — the
  /// struck-through figure on the card. A real comparison, not an invented
  /// "was" price, which is why it only appears beside a computed saving.
  int? _anchorPrice(PlusPlan plan) {
    final baseline = _shortest;
    if (baseline == null || baseline.months <= 0 || plan.months <= 0) {
      return null;
    }
    return (baseline.priceUzs * (plan.months / baseline.months)).round();
  }

  /// Per-day cost — the only figure that reads the same across three
  /// different billing periods.
  int _perDay(PlusPlan plan) {
    final days = plan.durationDays ?? 0;
    if (days <= 0) return 0;
    return (plan.priceUzs / days).round();
  }

  String _durationLabel(PlusPlan plan) {
    final days = plan.durationDays ?? 0;
    if (days <= 0) return 'One-time';
    if (days % 30 == 0) {
      final months = days ~/ 30;
      return months == 1 ? '1 month' : '$months months';
    }
    if (days == 365) return '12 months';
    return '$days days';
  }

  String _planName(PlusPlan plan) {
    final title = plan.title?.trim() ?? '';
    return title.isNotEmpty ? title : plan.code;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBalance();
    _loadPlans();
    _loadStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _promoController.dispose();
    super.dispose();
  }

  /// The student has just come back from the bank — the one moment an
  /// immediate answer matters more than the interval.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _paymentPending && !_verifying) {
      _checkPayment(manual: false);
    }
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

  Future<void> _loadPlans() async {
    try {
      final plans = await PlusService.getPlans();
      if (!mounted || plans.isEmpty) return;
      // Shortest first, and every plan the admin has switched on — a fourth
      // tariff added there should appear here without a release.
      final sorted = [...plans]
        ..sort((a, b) => (a.durationDays ?? 0).compareTo(b.durationDays ?? 0));
      setState(() {
        _plans = sorted;
        // Only if the student has not already chosen: the plans can land
        // after a tap on a fallback card, and moving the selection under
        // them would be a price changing by itself.
        _pickedCode ??= sorted.last.code;
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
      // Non-critical — the button stays enabled.
    }
  }

  /// Switching plans re-prices an applied code rather than dropping it.
  void _selectPlan(String code) {
    if (_selectedCode == code || _paymentPending || _activating) return;
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
        return 'You can’t use your own promo code.';
      default:
        return e.message;
    }
  }

  // ─── Payment ──────────────────────────────────────────────────────────────

  /// Start a Paylov payment for exactly what is missing, and hand off to the
  /// bank. The plan is bought the moment the payment clears — see
  /// [_checkPayment] — so from where the student stands this is paying for
  /// Plus, and the wallet is plumbing.
  Future<void> _startPayment() async {
    final provider = _provider;
    if (provider == null || _starting || _paymentPending) return;
    final amount = math.max(_shortfall, _minPaymentUzs);

    setState(() => _starting = true);
    try {
      final result = await WalletService.createPaylovCheckout(
        amountUzs: amount,
        provider: provider.key,
      );
      if (!mounted) return;

      final url = result.checkoutUrl;
      if (url == null || url.isEmpty) {
        AppNotify.show(
          context,
          message:
              result.message ??
              'The bank could not start this payment. Try another method.',
        );
        return;
      }

      setState(() {
        _pendingOrderId = result.orderId;
        _pendingAmount = amount;
        _checkoutUrl = url;
        _pollExpired = false;
        _pollStartedAt = DateTime.now();
      });
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(_pollInterval, (_) => _onPollTick());

      await _openCheckout(url);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    } catch (_) {
      if (!mounted) return;
      AppNotify.show(
        context,
        message: 'Could not start the payment. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _openCheckout(String url) async {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      AppNotify.show(context, message: 'Could not open the payment page.');
    }
  }

  void _onPollTick() {
    if (!_paymentPending) {
      _stopPolling();
      return;
    }
    final started = _pollStartedAt;
    if (started != null && DateTime.now().difference(started) > _pollLimit) {
      _stopPolling();
      if (mounted) setState(() => _pollExpired = true);
      return;
    }
    if (!_verifying) _checkPayment(manual: false);
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Ask the server where the order stands — which is also what credits the
  /// wallet, so this call is the end of the payment rather than a report on
  /// it. Once paid, the plan the student already chose is bought with the code
  /// they already entered: nobody pays for Plus and is then shown a button to
  /// buy Plus.
  Future<void> _checkPayment({required bool manual}) async {
    final orderId = _pendingOrderId;
    if (orderId == null || _verifying) return;
    setState(() => _verifying = true);
    try {
      final result = await WalletService.checkPaylovTransactionStatus(
        orderId: orderId,
      );
      if (!mounted) return;
      if (result.isPaid) {
        _stopPolling();
        setState(() {
          _pendingOrderId = null;
          _pendingAmount = null;
          _checkoutUrl = null;
          _toppedUp = true;
          final credited = result.balanceUzs;
          if (credited != null) {
            _balance = credited.round();
          } else {
            _balance = (_balance ?? 0) + (_pendingAmount ?? 0);
          }
        });
        await _activate();
        return;
      }
      if (manual) {
        AppNotify.show(
          context,
          message:
              result.message ??
              'Payment not confirmed yet. Please try again in a moment.',
          type: NotifyType.info,
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (manual) AppNotify.show(context, message: e.message);
    } catch (_) {
      if (!mounted) return;
      if (manual) {
        AppNotify.show(context, message: 'Could not verify the payment.');
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  /// Abandon the bank flow. The wallet is re-read rather than trusted: the
  /// payment may have gone through after all, and then the balance is enough
  /// and the button says so.
  Future<void> _cancelPayment() async {
    _stopPolling();
    setState(() {
      _pendingOrderId = null;
      _pendingAmount = null;
      _checkoutUrl = null;
      _pollExpired = false;
      _balanceLoading = true;
    });
    await _loadBalance();
  }

  /// Buy the selected plan from the wallet.
  Future<void> _activate() async {
    if (_activating) return;
    setState(() => _activating = true);
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
      // The balance may have been the problem; show the real figure.
      _loadBalance();
    } catch (_) {
      if (!mounted) return;
      AppNotify.show(
        context,
        message: 'Something went wrong. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final plusEnabled = AppFeatureService.isEnabled('plus');
    final isAlreadyActive = _isAlreadyActive;
    final busy = _paymentPending || _activating;
    final hasEnoughBalance = !_balanceLoading && !_needsPayment;

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
            child: AbsorbPointer(
              absorbing: busy,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: busy ? 0.55 : 1,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      const _PlusHero(),
                      const SizedBox(height: 24),
                      _SectionLabel('CHOOSE YOUR PLAN'),
                      _buildPlanRow(),
                      if (_shortest != null && _plans.length > 1) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Crossed-out prices are what the same period '
                          'costs on the ${_planName(_shortest!)} plan.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                      // Directly above the summary it changes: a student types
                      // a code to see what it does to the total below, and the
                      // answer is priced by the server, not guessed here.
                      if (!isAlreadyActive) ...[
                        const SizedBox(height: 18),
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
                      const SizedBox(height: 14),
                      _buildSummary(hasEnoughBalance: hasEnoughBalance),
                      // Too little in the wallet used to be a "top up" link
                      // that asked the student to work out the gap, pay it
                      // on another screen, then find their way back and start
                      // over. The payment methods sit here instead, on the
                      // exact amount missing — pick one and pay.
                      if (!isAlreadyActive && _needsPayment) ...[
                        const SizedBox(height: 18),
                        _SectionLabel('PAYMENT METHOD'),
                        for (final provider in _Provider.values) ...[
                          _ProviderCard(
                            asset: provider.asset,
                            selected: _provider == provider,
                            onTap: () => setState(() => _provider = provider),
                          ),
                          if (provider != _Provider.values.last)
                            const SizedBox(height: 8),
                        ],
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ─── Pinned CTA ───
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.of(context).padding.bottom + 12,
            ),
            child: _paymentPending
                ? _buildWaitingCard()
                : _buildCta(
                    plusEnabled: plusEnabled,
                    isAlreadyActive: isAlreadyActive,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanRow() {
    final plans = _plans;
    if (plans.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No plans are on sale right now.',
          style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
        ),
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final plan in plans) ...[
            Expanded(
              child: _PlanCard(
                name: _planName(plan),
                duration: _durationLabel(plan),
                price: plan.priceUzs,
                anchorPrice: _savePercent(plan) == null
                    ? null
                    : _anchorPrice(plan),
                perDay: _perDay(plan),
                baselinePerDay: _shortest == null || _shortest == plan
                    ? null
                    : _perDay(_shortest!),
                savePercent: _savePercent(plan),
                recommended: plan == _longest && plans.length > 1,
                selected: plan.code == _selectedCode,
                formatPrice: _formatPrice,
                onTap: () => _selectPlan(plan.code),
              ),
            ),
            if (plan != plans.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildSummary({required bool hasEnoughBalance}) {
    final colors = context.colors;
    final promo = _activePromo;
    final shortfall = _shortfall;
    return Container(
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
                const Skeleton(height: 20, width: 100, borderRadius: 6)
              else
                _Money(
                  amount: _balance ?? 0,
                  format: _formatPrice,
                  size: 15,
                  color: hasEnoughBalance ? colors.success : colors.error,
                ),
            ],
          ),
          if (promo != null) ...[
            _divider(colors),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Promo code (−${promo.discountPercent.round()}%)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  '−${_formatPrice(promo.discountAmountUzs)} UZS',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.success,
                  ),
                ),
              ],
            ),
          ],
          _divider(colors),
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
              if (promo != null) ...[
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
              _Money(
                amount: _payable,
                format: _formatPrice,
                size: 18,
                weight: FontWeight.w800,
                color: colors.textPrimary,
              ),
            ],
          ),
          if (shortfall > 0) ...[
            _divider(colors),
            Row(
              children: [
                Expanded(
                  child: Text(
                    (_balance ?? 0) > 0 ? 'To pay now' : 'To pay',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                _Money(
                  amount: math.max(shortfall, _minPaymentUzs),
                  format: _formatPrice,
                  size: 15,
                  weight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider(AppColors colors) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Container(height: 0.5, color: colors.border),
  );

  Widget _buildCta({required bool plusEnabled, required bool isAlreadyActive}) {
    final colors = context.colors;
    final payInline = _needsPayment && !isAlreadyActive;
    final enabled =
        plusEnabled &&
        !_activating &&
        !_starting &&
        !_balanceLoading &&
        !isAlreadyActive &&
        (!payInline || _provider != null);
    final spinning = _activating || _starting;

    final String label;
    if (!plusEnabled) {
      label = 'Temporarily unavailable';
    } else if (isAlreadyActive) {
      label = 'Already active';
    } else if (payInline) {
      label = 'Pay ${_formatPrice(math.max(_shortfall, _minPaymentUzs))} UZS';
    } else {
      label = 'Get PLUS';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (payInline && _provider == null && !_balanceLoading)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Choose a payment method to continue',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: !enabled
                ? null
                : payInline
                ? _startPayment
                : _activate,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.brand,
              foregroundColor: colors.onBrand,
              disabledBackgroundColor: colors.brand.withValues(alpha: 0.4),
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: spinning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.lock_rounded, size: 13, color: colors.textTertiary),
            const SizedBox(width: 4),
            Text(
              'Secure payment',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The footer while an order is out with the bank: what is happening, a
  /// manual check for a flow that is still settling, and a way out.
  Widget _buildWaitingCard() {
    final colors = context.colors;
    final amount = _pendingAmount ?? 0;

    final String title;
    final String body;
    if (_activating) {
      title = 'Activating PLUS…';
      body = 'Payment received. Switching on your plan.';
    } else if (_verifying) {
      title = 'Checking with the bank';
      body = 'Confirming your payment of ${_formatPrice(amount)} UZS.';
    } else if (_pollExpired) {
      title = 'Still waiting for payment';
      body =
          'We stopped checking automatically. If you completed the '
          'payment, check once more — nothing is lost.';
    } else {
      title = 'Waiting for payment';
      body =
          'Finish paying ${_formatPrice(amount)} UZS in the app that '
          'opened, then come back here — PLUS switches on by itself.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.brand),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _verifying || _activating
                  ? null
                  : () => _checkPayment(manual: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.brand,
                foregroundColor: colors.onBrand,
                disabledBackgroundColor: colors.brand.withValues(alpha: 0.4),
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'I have completed the payment',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (!_activating)
            Row(
              children: [
                if (_checkoutUrl != null)
                  Expanded(
                    child: TextButton(
                      onPressed: () => _openCheckout(_checkoutUrl!),
                      child: Text(
                        'Open payment page',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: TextButton(
                    onPressed: _verifying ? null : _cancelPayment,
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
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

// ─── Small pieces ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: context.colors.textTertiary,
        ),
      ),
    );
  }
}

/// An amount with a small "UZS" after it.
class _Money extends StatelessWidget {
  final int amount;
  final String Function(int) format;
  final double size;
  final FontWeight weight;
  final Color color;

  const _Money({
    required this.amount,
    required this.format,
    required this.size,
    this.weight = FontWeight.w700,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${format(amount)} ',
            style: TextStyle(fontSize: size, fontWeight: weight, color: color),
          ),
          TextSpan(
            text: 'UZS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
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
                      Expanded(
                        child: Text(
                          benefit,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
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

/// One column of the three-up plan row, laid out like the web's cards: a
/// banner strip (filled only on the recommended plan, rendered on all so the
/// bodies line up), the name, the per-day figure that makes three billing
/// periods comparable, then the real price beside what the same stretch costs
/// on the shortest plan.
class _PlanCard extends StatelessWidget {
  final String name;
  final String duration;
  final int price;
  final int? anchorPrice;
  final int perDay;
  final int? baselinePerDay;
  final int? savePercent;
  final bool recommended;
  final bool selected;
  final String Function(int) formatPrice;
  final VoidCallback onTap;

  const _PlanCard({
    required this.name,
    required this.duration,
    required this.price,
    required this.anchorPrice,
    required this.perDay,
    required this.baselinePerDay,
    required this.savePercent,
    required this.recommended,
    required this.selected,
    required this.formatPrice,
    required this.onTap,
  });

  // Fixed navy for contrast on gold in both themes.
  static const _onGold = Color(0xFF272942);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: selected
              ? colors.accentYellow.withValues(alpha: 0.08)
              : colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colors.accentYellow : colors.border,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 22,
              width: double.infinity,
              alignment: Alignment.center,
              color: recommended ? colors.brand : Colors.transparent,
              child: recommended
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Symbols.star_rounded,
                            size: 11,
                            fill: 1,
                            color: colors.accentYellow,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'RECOMMENDED',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: colors.onBrand,
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _SelectDot(selected: selected),
                      ],
                    ),
                    Text(
                      duration,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // The comparable number: per day, which is the only
                    // figure that reads the same across three periods.
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: formatPrice(perDay),
                            style: TextStyle(
                              fontSize: 21,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              color: colors.textPrimary,
                            ),
                          ),
                          TextSpan(
                            text: ' /day',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (baselinePerDay != null)
                      Text(
                        '${formatPrice(baselinePerDay!)} /day',
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.textTertiary,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: colors.textTertiary,
                        ),
                      )
                    else
                      const SizedBox(height: 13),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Container(height: 0.5, color: colors.border),
                    ),
                    if (anchorPrice != null)
                      Text(
                        formatPrice(anchorPrice!),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: colors.textTertiary,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: colors.textTertiary,
                        ),
                      )
                    else
                      const SizedBox(height: 13),
                    Text(
                      '${formatPrice(price)} UZS',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (savePercent != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accentYellow,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'SAVE $savePercent%',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: _onGold,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 19),
                  ],
                ),
              ),
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
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.accentYellow : Colors.transparent,
        border: selected ? null : Border.all(color: colors.border, width: 2),
      ),
      child: selected
          ? const Icon(
              Symbols.check_rounded,
              size: 12,
              weight: 800,
              // Fixed navy for contrast on the gold dot in both themes.
              color: Color(0xFF272942),
            )
          : null,
    );
  }
}

// ─── Payment provider card ──────────────────────────────────────────────────

class _ProviderCard extends StatelessWidget {
  final String asset;
  final bool selected;
  final VoidCallback onTap;

  const _ProviderCard({
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? colors.accentYellow.withValues(alpha: 0.06)
              : colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? colors.accentYellow : colors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Image.asset(asset, height: 26),
            const Spacer(),
            _SelectDot(selected: selected),
          ],
        ),
      ),
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
                    backgroundColor: locked ? colors.surfaceAlt : colors.brand,
                    foregroundColor: locked
                        ? colors.textPrimary
                        : colors.onBrand,
                    disabledBackgroundColor: colors.brand.withValues(
                      alpha: 0.35,
                    ),
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
                Icon(
                  Symbols.check_circle_rounded,
                  size: 16,
                  fill: 1,
                  color: colors.success,
                ),
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
