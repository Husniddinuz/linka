import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/earnings_service.dart';
import '../widgets/app_notify.dart';
import '../widgets/skeleton.dart';

class TutorEarningsScreen extends StatefulWidget {
  const TutorEarningsScreen({super.key});

  @override
  State<TutorEarningsScreen> createState() => _TutorEarningsScreenState();
}

class _TutorEarningsScreenState extends State<TutorEarningsScreen> {
  EarningsPage? _page;
  int _walletBalanceUzs = 0;
  bool _loading = true;
  String _tab = 'completed'; // 'completed' | 'pending'

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
      ]);
      if (!mounted) return;
      setState(() {
        _page = results[0] as EarningsPage;
        _walletBalanceUzs = results[1] as int;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppNotify.show(context, message: e.message);
    }
  }

  List<EarningEntry> get _filtered {
    final entries = _page?.entries ?? const <EarningEntry>[];
    return entries.where((e) => e.status == _tab).toList();
  }

  int get _balanceUzs => _walletBalanceUzs;

  int get _totalForTab =>
      _tab == 'completed'
          ? (_page?.totalCompletedUzs ?? 0)
          : (_page?.totalPendingUzs ?? 0);

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
                          balanceUzs: _balanceUzs,
                          loading: _loading,
                          onWithdraw: _onWithdraw,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            const Text(
                              'TRANSACTION HISTORY',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF272942),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () {
                                AppNotify.show(context,
                                    message: 'Filters coming soon',
                                    type: NotifyType.info);
                              },
                              child: const Icon(
                                Icons.filter_list_rounded,
                                color: Color(0xFF272942),
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _SegmentedTabs(
                          selected: _tab,
                          onChange: (t) => setState(() => _tab = t),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _TotalRow(
                          totalUzs: _totalForTab,
                          loading: _loading,
                          isCompleted: _tab == 'completed',
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_loading)
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
                      else if (_filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 32, 20, 32),
                          child: Center(
                            child: Text(
                              'No transactions yet',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFFAAAAAA),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                      else
                        _GroupedEntries(entries: _filtered),
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

  void _onWithdraw() {
    AppNotify.show(
      context,
      message: 'Withdrawals will be available soon',
      type: NotifyType.info,
    );
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
            'Earnings',
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
  final VoidCallback onWithdraw;
  const _BalanceCard({
    required this.balanceUzs,
    required this.loading,
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
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onWithdraw,
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
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
      ),
    );
  }
}

String _formatAmount(int amount) {
  final str = amount.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(str[i]);
  }
  return buffer.toString();
}

// ─── Segmented tabs ──────────────────────────────────────────────────────────

class _SegmentedTabs extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChange;
  const _SegmentedTabs({required this.selected, required this.onChange});

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
              label: 'Completed',
              active: selected == 'completed',
              onTap: () => onChange('completed'),
            ),
          ),
          Expanded(
            child: _SegButton(
              label: 'Pending',
              active: selected == 'pending',
              onTap: () => onChange('pending'),
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

// ─── Total row ───────────────────────────────────────────────────────────────

class _TotalRow extends StatelessWidget {
  final int totalUzs;
  final bool loading;
  final bool isCompleted;
  const _TotalRow({
    required this.totalUzs,
    required this.loading,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        isCompleted ? const Color(0xFF27AE60) : const Color(0xFFF5C542);

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
                const Text(
                  'Total',
                  style: TextStyle(
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
                            color: accent,
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

// ─── Grouped entries ─────────────────────────────────────────────────────────

class _GroupedEntries extends StatelessWidget {
  final List<EarningEntry> entries;
  const _GroupedEntries({required this.entries});

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
              child: _EntryRow(entry: e),
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

class _EntryRow extends StatelessWidget {
  final EarningEntry entry;
  const _EntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isCompleted = entry.status == 'completed';
    final accent =
        isCompleted ? const Color(0xFF27AE60) : const Color(0xFFF5C542);
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
          style: TextStyle(
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
