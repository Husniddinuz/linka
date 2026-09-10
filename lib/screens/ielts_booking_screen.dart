import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/ielts_registration_service.dart';
import '../widgets/mock_test_styles.dart';
import '../widgets/skeleton.dart';
import 'ielts_signup_screen.dart';

/// Real IELTS test date/centre search, backed directly by IDP's own booking
/// API (see [IeltsRegistrationService]) — no linka backend involved.
class IeltsBookingScreen extends StatefulWidget {
  const IeltsBookingScreen({super.key});

  @override
  State<IeltsBookingScreen> createState() => _IeltsBookingScreenState();
}

class _IeltsBookingScreenState extends State<IeltsBookingScreen> {
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<Map<String, dynamic>> _sessions = [];
  int _nextPage = 1;
  bool _hasMore = true;
  final _scrollController = ScrollController();

  // The API rejects pageSize > 10. Rather than paging through several
  // requests up front (slow — this was the "taking too much time" the
  // sessions list used to have), load one page at a time and fetch the
  // next page lazily as the user scrolls near the bottom.
  static const _pageSize = 10;
  static final _cutoff = DateTime.now().add(const Duration(days: 60));

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
      _sessions = [];
      _nextPage = 1;
      _hasMore = true;
    });
    try {
      final pageItems = await _fetchPage(1);
      setState(() {
        _sessions = pageItems;
        _nextPage = 2;
        _hasMore = pageItems.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load test dates. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final pageItems = await _fetchPage(_nextPage);
      setState(() {
        _sessions = [..._sessions, ...pageItems];
        _nextPage++;
        _hasMore = pageItems.length == _pageSize &&
            (pageItems.isEmpty || !DateTime.parse(pageItems.last['testStartUtcDatetime'] as String).isAfter(_cutoff));
        _loadingMore = false;
      });
    } catch (e) {
      setState(() => _loadingMore = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPage(int page) async {
    final result = await IeltsRegistrationService.searchLrwSessions(
      from: DateTime.now(),
      to: _cutoff,
      page: page,
      pageSize: _pageSize,
    );
    return (result['items'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: 'Book IELTS Test'),
      body: RefreshIndicator(
        onRefresh: _loadFirstPage,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const _BookingSkeleton();
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Icon(Symbols.wifi_off_rounded, color: MockTestColors.greyLight, size: 40),
          const SizedBox(height: 12),
          Center(
            child: Text(_error!, style: const TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey)),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: MtPrimaryButton(label: 'Retry', onPressed: _loadFirstPage),
          ),
        ],
      );
    }
    if (_sessions.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(
            child: Text(
              'No available test dates in the next 2 months.',
              style: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _sessions.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index >= _sessions.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator(color: MockTestColors.navy, strokeWidth: 2.2)),
          );
        }
        return _SessionCard(session: _sessions[index]);
      },
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});
  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final location = session['testLocation'] as Map<String, dynamic>;
    final fee = session['testFee'] as Map<String, dynamic>;
    final seats = session['seatAvailability'] as Map<String, dynamic>;
    final localDate = DateTime.parse(session['testStartLocalDatetime'] as String);
    final remaining = seats['remaining'] as int;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => IeltsSignupScreen(session: session)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: mtSoftCard(context, radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MtAvatar(icon: Symbols.event_rounded, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDate(localDate),
                        style: const TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: MockTestColors.navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        location['name'] as String,
                        style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13, color: MockTestColors.grey),
                      ),
                    ],
                  ),
                ),
                MtPill(
                  background: remaining <= 5 ? MockTestColors.redBg : MockTestColors.greenBg,
                  child: Text(
                    '$remaining seats',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: remaining <= 5 ? MockTestColors.red : MockTestColors.green,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24, color: MockTestColors.divider),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${session['testModule']} · ${session['testFormat']}',
                  style: const TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, color: MockTestColors.grey),
                ),
                Text(
                  '${_formatAmount(fee['totalAmount'] as num)} ${fee['currencyCodeIso3']}',
                  style: const TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MockTestColors.navy,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day} ${months[date.month - 1]} ${date.year} · $hour:$minute';
  }

  String _formatAmount(num amount) {
    final s = amount.toInt().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

/// Shown while the first page of sessions is loading — mirrors [_SessionCard]
/// so the list doesn't jump in shape once real data arrives.
class _BookingSkeleton extends StatelessWidget {
  const _BookingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => const _SessionCardSkeleton(),
    );
  }
}

class _SessionCardSkeleton extends StatelessWidget {
  const _SessionCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: mtSoftCard(context, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Skeleton(width: 44, height: 44, circle: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Skeleton(height: 15.5, width: 160, borderRadius: 5),
                    SizedBox(height: 6),
                    Skeleton(height: 13, width: 110, borderRadius: 4),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Skeleton(height: 24, width: 70, borderRadius: 20),
            ],
          ),
          const Divider(height: 24, color: MockTestColors.divider),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Skeleton(height: 12.5, width: 100, borderRadius: 4),
              Skeleton(height: 14, width: 80, borderRadius: 5),
            ],
          ),
        ],
      ),
    );
  }
}
