import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/app_feature_service.dart';
import '../services/earnings_service.dart';
import '../widgets/app_notify.dart';
import '../widgets/skeleton.dart';

class TutorEarningsScreen extends StatefulWidget {
  const TutorEarningsScreen({super.key});

  @override
  State<TutorEarningsScreen> createState() => _TutorEarningsScreenState();
}

enum _Tab { earnings, withdrawals }

class _TutorEarningsScreenState extends State<TutorEarningsScreen> {
  EarningsPage? _earnings;
  WithdrawalsPage? _withdrawals;
  int _walletBalanceUzs = 0;
  bool _loading = true;
  bool _withdrawing = false;
  _Tab _tab = _Tab.earnings;

  DateTime? _from;
  DateTime? _to;
  String? _statusFilter;
  // null = all; 'pending' | 'completed' | 'rejected' | 'failed'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        EarningsService.fetch(page: 1, limit: 100),
        EarningsService.fetchWalletBalance(),
        EarningsService.fetchWithdrawals(
          from: _from,
          to: _to,
          status: _statusFilter,
          page: 1,
          limit: 50,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _earnings = results[0] as EarningsPage;
        _walletBalanceUzs = results[1] as int;
        _withdrawals = results[2] as WithdrawalsPage;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppNotify.show(context, message: e.message);
    }
  }

  Future<void> _reloadWithdrawals() async {
    try {
      final page = await EarningsService.fetchWithdrawals(
        from: _from,
        to: _to,
        status: _statusFilter,
        page: 1,
        limit: 50,
      );
      if (!mounted) return;
      setState(() => _withdrawals = page);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF272942),
                onRefresh: _load,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Text(
                          'MY WALLET',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF272942),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _BalanceCard(
                          balanceUzs: _walletBalanceUzs,
                          loading: _loading,
                          busy: _withdrawing,
                          onWithdraw: _onWithdraw,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _TopTabs(
                          selected: _tab,
                          onChange: (t) => setState(() => _tab = t),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_tab == _Tab.earnings)
                        _EarningsSection(
                          loading: _loading,
                          page: _earnings,
                        )
                      else
                        _WithdrawalsSection(
                          loading: _loading,
                          page: _withdrawals,
                          from: _from,
                          to: _to,
                          status: _statusFilter,
                          onOpenFilters: _openFilters,
                          onClearFilters: _hasFilters
                              ? () async {
                                  setState(() {
                                    _from = null;
                                    _to = null;
                                    _statusFilter = null;
                                  });
                                  await _reloadWithdrawals();
                                }
                              : null,
                        ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasFilters =>
      _from != null || _to != null || _statusFilter != null;

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FiltersSheet(
        from: _from,
        to: _to,
        status: _statusFilter,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _from = result.from;
      _to = result.to;
      _statusFilter = result.status;
    });
    await _reloadWithdrawals();
  }

  Future<void> _onWithdraw() async {
    if (_loading || _withdrawing) return;
    if (_walletBalanceUzs <= 0) {
      AppNotify.show(
        context,
        message: 'Wallet balance is empty',
        type: NotifyType.info,
      );
      return;
    }

    final amount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _WithdrawSheet(),
    );
    if (amount == null || amount <= 0 || !mounted) return;

    setState(() => _withdrawing = true);
    try {
      final result = await EarningsService.performWithdraw(
        amountUzs: amount.toStringAsFixed(2),
      );
      if (!mounted) return;
      setState(() {
        _walletBalanceUzs = result.walletBalanceUzs;
        _withdrawing = false;
      });
      AppNotify.show(
        context,
        message:
            'Request submitted. Accountants process payouts 1–2 times per week.',
        type: NotifyType.success,
      );
      await _reloadWithdrawals();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _withdrawing = false);
      AppNotify.show(context, message: e.message);
    }
  }
}

// ─── Top bar ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final VoidCallback onBack;
  const _TopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBack,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  color: Color(0xFF272942),
                ),
              ),
            ),
          ),
          const Text(
            'Income',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFF272942),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Balance card ────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final int balanceUzs;
  final bool loading;
  final bool busy;
  final VoidCallback onWithdraw;
  const _BalanceCard({
    required this.balanceUzs,
    required this.loading,
    required this.busy,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF272942),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available balance',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          if (loading)
            Container(
              width: 180,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
            )
          else
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _formatAmount(balanceUzs),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                  TextSpan(
                    text: '  UZS',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          if (AppFeatureService.isEnabled('withdraw')) ...[
            const SizedBox(height: 20),
            GestureDetector(
              onTap: busy ? null : onWithdraw,
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Color(0xFF272942),
                          ),
                        )
                      : const Text(
                          'Withdraw',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF272942),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatAmount(num amount) {
  final str = amount.toInt().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(str[i]);
  }
  return buffer.toString();
}

// ─── Top tabs: Earnings | Withdrawals ────────────────────────────────────────

class _TopTabs extends StatelessWidget {
  final _Tab selected;
  final ValueChanged<_Tab> onChange;
  const _TopTabs({required this.selected, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegButton(
              label: 'Earnings',
              active: selected == _Tab.earnings,
              onTap: () => onChange(_Tab.earnings),
            ),
          ),
          Expanded(
            child: _SegButton(
              label: 'Withdrawals',
              active: selected == _Tab.withdrawals,
              onTap: () => onChange(_Tab.withdrawals),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SegButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF272942) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : const Color(0xFF272942),
          ),
        ),
      ),
    );
  }
}

// ─── Earnings section ────────────────────────────────────────────────────────

class _EarningsSection extends StatelessWidget {
  final bool loading;
  final EarningsPage? page;
  const _EarningsSection({required this.loading, required this.page});

  @override
  Widget build(BuildContext context) {
    final entries = page?.entries ?? const <EarningEntry>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _TotalRow(
            label: 'Total earned',
            totalUzs: page?.totalCompletedUzs ?? 0,
            loading: loading,
            color: const Color(0xFF27AE60),
          ),
        ),
        const SizedBox(height: 16),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Skeleton(height: 64, borderRadius: 12),
                SizedBox(height: 10),
                Skeleton(height: 64, borderRadius: 12),
                SizedBox(height: 10),
                Skeleton(height: 64, borderRadius: 12),
              ],
            ),
          )
        else if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 32, 20, 32),
            child: Center(
              child: Text(
                'No earnings yet',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFFAAAAAA),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
        else
          _GroupedEarnings(entries: entries),
      ],
    );
  }
}

// ─── Withdrawals section ─────────────────────────────────────────────────────

class _WithdrawalsSection extends StatelessWidget {
  final bool loading;
  final WithdrawalsPage? page;
  final DateTime? from;
  final DateTime? to;
  final String? status;
  final VoidCallback onOpenFilters;
  final VoidCallback? onClearFilters;
  const _WithdrawalsSection({
    required this.loading,
    required this.page,
    required this.from,
    required this.to,
    required this.status,
    required this.onOpenFilters,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final entries = page?.entries ?? const <WithdrawalEntry>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _WithdrawSummaryCard(
            loading: loading,
            page: page,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _FilterBar(
            from: from,
            to: to,
            status: status,
            onTap: onOpenFilters,
            onClear: onClearFilters,
          ),
        ),
        const SizedBox(height: 12),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Skeleton(height: 64, borderRadius: 12),
                SizedBox(height: 10),
                Skeleton(height: 64, borderRadius: 12),
                SizedBox(height: 10),
                Skeleton(height: 64, borderRadius: 12),
              ],
            ),
          )
        else if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 32, 20, 32),
            child: Center(
              child: Text(
                'No withdrawals yet',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFFAAAAAA),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
        else
          for (final w in entries)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _WithdrawalRow(entry: w),
            ),
      ],
    );
  }
}

class _WithdrawSummaryCard extends StatelessWidget {
  final bool loading;
  final WithdrawalsPage? page;
  const _WithdrawSummaryCard({required this.loading, required this.page});

  @override
  Widget build(BuildContext context) {
    final payout = page?.payoutTotalUzs ?? 0;
    final commission = page?.commissionTotalUzs ?? 0;
    final completedCount = page?.completedCount ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total withdrawn',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF999999),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          if (loading)
            const Skeleton(height: 22, width: 140, borderRadius: 6)
          else
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${_formatAmount(payout)} ',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF272942),
                    ),
                  ),
                  TextSpan(
                    text: 'UZS  ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                  TextSpan(
                    text: '($completedCount payouts)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF999999),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          if (commission > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Commission: ${_formatAmount(commission)} UZS',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF999999),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final DateTime? from;
  final DateTime? to;
  final String? status;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _FilterBar({
    required this.from,
    required this.to,
    required this.status,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasAny = from != null || to != null || status != null;
    final label = hasAny ? _summarize() : 'Filter';
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_list_rounded,
                    size: 18,
                    color: Color(0xFF272942),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF272942),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: Color(0xFF272942),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (onClear != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClear,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF272942),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _summarize() {
    final parts = <String>[];
    if (from != null && to != null) {
      parts.add('${_fmtShort(from!)} – ${_fmtShort(to!)}');
    } else if (from != null) {
      parts.add('from ${_fmtShort(from!)}');
    } else if (to != null) {
      parts.add('to ${_fmtShort(to!)}');
    }
    if (status != null) parts.add(_capitalize(status!));
    return parts.join(' · ');
  }

  static String _fmtShort(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month]}';
  }

  static String _capitalize(String v) =>
      v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}';
}

class _WithdrawalRow extends StatelessWidget {
  final WithdrawalEntry entry;
  const _WithdrawalRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(entry.status);
    final icon = _statusIcon(entry.status);
    return GestureDetector(
      onTap: () => _showDetails(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F6F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDateTime(entry.createdAt),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF272942),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _statusLabel(entry.status) +
                        (entry.paylovPaymentId != null
                            ? ' · #${entry.paylovPaymentId}'
                            : ''),
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${_formatAmount(entry.requestedAmountUzs)} UZS',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF272942),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _WithdrawalDetailsSheet(entry: entry),
    );
  }

  static Color _statusColor(String s) {
    switch (s) {
      case 'completed':
        return const Color(0xFF27AE60);
      case 'rejected':
        return const Color(0xFFE74C3C);
      case 'failed':
        return const Color(0xFFE67E22);
      case 'pending':
      default:
        return const Color(0xFFF5C542);
    }
  }

  static IconData _statusIcon(String s) {
    switch (s) {
      case 'completed':
        return Icons.check_rounded;
      case 'rejected':
        return Icons.close_rounded;
      case 'failed':
        return Icons.error_outline_rounded;
      case 'pending':
      default:
        return Icons.hourglass_empty_rounded;
    }
  }

  static String _statusLabel(String s) {
    if (s.isEmpty) return '—';
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }
}

String _formatDateTime(DateTime? d) {
  if (d == null) return '—';
  const months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month]} $hh:$mm';
}

// ─── Total row (earnings) ────────────────────────────────────────────────────

class _TotalRow extends StatelessWidget {
  final String label;
  final int totalUzs;
  final bool loading;
  final Color color;
  const _TotalRow({
    required this.label,
    required this.totalUzs,
    required this.loading,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF999999),
                  ),
                ),
                const SizedBox(height: 4),
                if (loading)
                  const Skeleton(height: 22, width: 120, borderRadius: 6)
                else
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '+${_formatAmount(totalUzs)} ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                        const TextSpan(
                          text: 'UZS',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF999999),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E5E7)),
            ),
            child: const Icon(
              Icons.arrow_downward_rounded,
              size: 18,
              color: Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grouped earnings ────────────────────────────────────────────────────────

class _GroupedEarnings extends StatelessWidget {
  final List<EarningEntry> entries;
  const _GroupedEarnings({required this.entries});

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDate(entries);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              _formatDateHeader(g.date),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF272942),
                letterSpacing: 0.5,
              ),
            ),
          ),
          for (final e in g.entries)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _EarningRow(entry: e),
            ),
        ],
      ],
    );
  }

  List<_DateGroup> _groupByDate(List<EarningEntry> items) {
    final map = <String, _DateGroup>{};
    for (final e in items) {
      final d = e.occurredAt;
      if (d == null) continue;
      final key = '${d.year}-${d.month}-${d.day}';
      map.putIfAbsent(key, () => _DateGroup(DateTime(d.year, d.month, d.day)))
          .entries
          .add(e);
    }
    final list = map.values.toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  static const _monthNames = [
    '', 'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];
  static const _weekdays = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY',
  ];
  String _formatDateHeader(DateTime d) =>
      '${d.day} ${_monthNames[d.month]}, ${_weekdays[d.weekday - 1]}';
}

class _DateGroup {
  final DateTime date;
  final List<EarningEntry> entries = [];
  _DateGroup(this.date);
}

class _EarningRow extends StatelessWidget {
  final EarningEntry entry;
  const _EarningRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF27AE60);
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: entry.studentImage != null &&
                  entry.studentImage!.startsWith('http')
              ? Image.network(
                  entry.studentImage!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _AvatarFallback(),
                )
              : const _AvatarFallback(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.studentName.isEmpty ? 'Student' : entry.studentName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF272942),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                entry.timeRange ?? '',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF999999),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Text(
          '+${_formatAmount(entry.amountUzs)} UZS',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
      ],
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      color: const Color(0xFFE0E0E0),
      child: const Icon(Icons.person, color: Color(0xFFAAAAAA), size: 22),
    );
  }
}

// ─── Withdraw sheet (presets + custom amount) ────────────────────────────────

class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet();

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  WithdrawOptions? _options;
  bool _loading = true;
  String? _loadError;
  bool _submitting = false;

  int? _selectedPreset; // UZS amount of selected preset, null if custom
  final TextEditingController _amountCtrl = TextEditingController();
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _loadOptions();
    _amountCtrl.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final opts = await EarningsService.fetchWithdrawOptions();
      if (!mounted) return;
      setState(() {
        _options = opts;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    }
  }

  void _onAmountChanged() {
    // Typing in the custom field clears any preset selection.
    if (_amountCtrl.text.isNotEmpty && _selectedPreset != null) {
      setState(() => _selectedPreset = null);
    }
    if (_amountError != null) setState(() => _amountError = null);
  }

  int _customAmount() {
    final raw = _amountCtrl.text.replaceAll(' ', '').trim();
    if (raw.isEmpty) return 0;
    return int.tryParse(raw) ?? 0;
  }

  int _effectiveAmount() => _selectedPreset ?? _customAmount();

  void _submit() {
    final opts = _options;
    if (opts == null) return;
    final amount = _effectiveAmount();
    if (amount <= 0) {
      setState(() => _amountError = 'Enter an amount');
      return;
    }
    if (amount > opts.maxAmountUzs) {
      setState(() => _amountError =
          'Maximum is ${_formatAmount(opts.maxAmountUzs)} UZS');
      return;
    }
    setState(() => _submitting = true);
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E5E7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Withdraw',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF272942),
                ),
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Color(0xFF272942),
                      ),
                    ),
                  ),
                )
              else if (_loadError != null)
                _ErrorBox(message: _loadError!, onRetry: _loadOptions)
              else
                _buildBody(_options!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(WithdrawOptions opts) {
    final disabled = !opts.partnerIdConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BalanceRow(balanceUzs: opts.walletBalanceUzs),
        const SizedBox(height: 14),
        if (!opts.partnerIdConfigured)
          const _ErrorBox(
            message:
                'Your payout account is not configured yet. Please contact admin to set it up.',
          )
        else ...[
          if (opts.presets.isNotEmpty) ...[
            const _SectionLabel(label: 'QUICK AMOUNTS'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in opts.presets)
                  _PresetChip(
                    amountUzs: p.amountUzs,
                    selected: _selectedPreset == p.amountUzs,
                    enabled: p.available,
                    onTap: () {
                      setState(() {
                        _selectedPreset = p.amountUzs;
                        _amountCtrl.clear();
                        _amountError = null;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          const _SectionLabel(label: 'CUSTOM AMOUNT (UZS)'),
          const SizedBox(height: 8),
          _AmountInput(
            controller: _amountCtrl,
            hint: 'Up to ${_formatAmount(opts.maxAmountUzs)}',
            error: _amountError,
          ),
          const SizedBox(height: 12),
          if (opts.payoutScheduleNote.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 16,
                    color: Color(0xFF8A6D00),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      opts.payoutScheduleNote,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8A6D00),
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _SheetButton(
                label: 'Cancel',
                filled: false,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SheetButton(
                label: _submitting ? 'Submitting…' : 'Submit',
                filled: true,
                onTap: (disabled || _submitting) ? () {} : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BalanceRow extends StatelessWidget {
  final int balanceUzs;
  const _BalanceRow({required this.balanceUzs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Text(
            'Available',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF999999),
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${_formatAmount(balanceUzs)} ',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF272942),
                  ),
                ),
                const TextSpan(
                  text: 'UZS',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF999999),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF999999),
        letterSpacing: 0.6,
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final int amountUzs;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _PresetChip({
    required this.amountUzs,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = selected
        ? const Color(0xFF272942)
        : (enabled ? const Color(0xFFF2F2F4) : const Color(0xFFF6F6F8));
    final Color fg = selected
        ? Colors.white
        : (enabled ? const Color(0xFF272942) : const Color(0xFFBDBDBD));
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            '${_formatAmount(amountUzs)} UZS',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _AmountInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String? error;
  const _AmountInput({
    required this.controller,
    required this.hint,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F6F8),
            borderRadius: BorderRadius.circular(10),
            border: error == null
                ? null
                : Border.all(color: const Color(0xFFE74C3C)),
          ),
          alignment: Alignment.center,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF272942),
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              hintText: hint,
              hintStyle: const TextStyle(
                fontSize: 14,
                color: Color(0xFF999999),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFE74C3C),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _ErrorBox({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFFC0392B),
              height: 1.35,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onRetry,
              behavior: HitTestBehavior.opaque,
              child: const Text(
                'Retry',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF272942),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _SheetButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: filled ? const Color(0xFF272942) : const Color(0xFFF2F2F4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : const Color(0xFF272942),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Withdrawal details sheet ────────────────────────────────────────────────

class _WithdrawalDetailsSheet extends StatelessWidget {
  final WithdrawalEntry entry;
  const _WithdrawalDetailsSheet({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E5E7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Withdrawal #${entry.id}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF272942),
              ),
            ),
            const SizedBox(height: 12),
            _kv('Status',
                _WithdrawalRow._statusLabel(entry.status),
                color: _WithdrawalRow._statusColor(entry.status)),
            _kv('Requested',
                '${_formatAmount(entry.requestedAmountUzs)} UZS'),
            if (entry.commissionAmountUzs > 0)
              _kv('Commission',
                  '${_formatAmount(entry.commissionAmountUzs)} UZS'),
            _kv('Payout', '${_formatAmount(entry.payoutAmountUzs)} UZS'),
            if (entry.paylovPaymentId != null)
              _kv('Paylov payment', '#${entry.paylovPaymentId}'),
            if (entry.linkaOrderId != null)
              _kv('Order', '#${entry.linkaOrderId}'),
            if (entry.paylovSplitRef.isNotEmpty)
              _kv('Split ref', entry.paylovSplitRef),
            _kv('Created', _formatDateTime(entry.createdAt)),
            if (entry.processedAt != null)
              _kv('Processed', _formatDateTime(entry.processedAt)),
            if (entry.accountantNote.isNotEmpty ||
                entry.failReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDECEC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  entry.accountantNote.isNotEmpty
                      ? entry.accountantNote
                      : entry.failReason,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFC0392B),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF999999),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color ?? const Color(0xFF272942),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Filters sheet ───────────────────────────────────────────────────────────

class _FilterResult {
  final DateTime? from;
  final DateTime? to;
  final String? status;
  const _FilterResult({this.from, this.to, this.status});
}

class _FiltersSheet extends StatefulWidget {
  final DateTime? from;
  final DateTime? to;
  final String? status;
  const _FiltersSheet({
    required this.from,
    required this.to,
    required this.status,
  });

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late DateTime? _from = widget.from;
  late DateTime? _to = widget.to;
  late String? _status = widget.status;

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = (isFrom ? _from : _to) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF272942)),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E5E7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Filter withdrawals',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF272942),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'DATE RANGE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF999999),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'From',
                    value: _from,
                    onTap: () => _pickDate(isFrom: true),
                    onClear: _from == null
                        ? null
                        : () => setState(() => _from = null),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateField(
                    label: 'To',
                    value: _to,
                    onTap: () => _pickDate(isFrom: false),
                    onClear:
                        _to == null ? null : () => setState(() => _to = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'STATUS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF999999),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                  label: 'All',
                  active: _status == null,
                  onTap: () => setState(() => _status = null),
                ),
                _StatusChip(
                  label: 'Completed',
                  active: _status == 'completed',
                  onTap: () => setState(() => _status = 'completed'),
                ),
                _StatusChip(
                  label: 'Pending',
                  active: _status == 'pending',
                  onTap: () => setState(() => _status = 'pending'),
                ),
                _StatusChip(
                  label: 'Rejected',
                  active: _status == 'rejected',
                  onTap: () => setState(() => _status = 'rejected'),
                ),
                _StatusChip(
                  label: 'Failed',
                  active: _status == 'failed',
                  onTap: () => setState(() => _status = 'failed'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: 'Reset',
                    filled: false,
                    onTap: () {
                      setState(() {
                        _from = null;
                        _to = null;
                        _status = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SheetButton(
                    label: 'Apply',
                    filled: true,
                    onTap: () => Navigator.of(context).pop(
                      _FilterResult(from: _from, to: _to, status: _status),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F6F8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 16,
              color: Colors.black.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value == null
                    ? label
                    : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: value == null
                      ? const Color(0xFF999999)
                      : const Color(0xFF272942),
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                behavior: HitTestBehavior.opaque,
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Color(0xFF999999),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _StatusChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF272942) : const Color(0xFFF2F2F4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : const Color(0xFF272942),
            ),
          ),
        ),
      ),
    );
  }
}
