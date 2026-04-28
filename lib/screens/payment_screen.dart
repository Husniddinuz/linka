import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/booking_service.dart';
import '../services/wallet_service.dart';
import '../widgets/app_notify.dart';
import '../widgets/skeleton.dart';
import 'payment_topup_screen.dart';
import 'payment_success_screen.dart';

class PaymentScreen extends StatefulWidget {
  final int? tutorId;
  final DateTime? startAt;
  final int? durationMinutes;
  final String tutorName;
  final String tutorImage;
  final String experience;
  final String ieltsScore;
  final String lessonDate;
  final String timeRange;
  final String duration;
  final String goal;
  final int totalAmount;

  const PaymentScreen({
    super.key,
    this.tutorId,
    this.startAt,
    this.durationMinutes,
    this.tutorName = 'Azizbek Karimov',
    this.tutorImage = 'assets/images/tutors/azizbek.png',
    this.experience = '+13 yrs',
    this.ieltsScore = '8.0',
    this.lessonDate = '17 feb. 2026',
    this.timeRange = '21:00 - 21:20',
    this.duration = '20 min',
    this.goal =
        'My goal for this lesson is to improve my vocabulary and pronunciation. I want to speak more clearly and confidently in different situations. I expect interactive tasks, useful examples, and detailed feedback to help me correct mistakes and develop my English skills.',
    this.totalAmount = 100000,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  int _balance = 0;
  bool _balanceLoading = true;
  bool _paying = false;

  bool get _canPay =>
      _balance >= widget.totalAmount &&
      widget.tutorId != null &&
      widget.startAt != null &&
      widget.durationMinutes != null;

  @override
  void initState() {
    super.initState();
    _loadBalance();
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

  String _formatAmount(int amount) {
    final str = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  void _onTopUp() async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const PaymentTopUpScreen()),
    );
    if (result != null) {
      // Re-fetch the wallet balance from server after top-up
      await _loadBalance();
    }
  }

  Future<void> _onPay() async {
    if (!_canPay || _paying) return;
    setState(() => _paying = true);
    try {
      final bookingId = await BookingService.createBooking(
        tutorId: widget.tutorId!,
        startAt: widget.startAt!,
        durationMinutes: widget.durationMinutes!,
        studentNote: widget.goal,
      );
      await BookingService.payFromWallet(bookingId: bookingId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PaymentSuccessScreen()),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message, type: NotifyType.error);
    } catch (_) {
      if (!mounted) return;
      AppNotify.show(
        context,
        message: 'Could not complete payment',
        type: NotifyType.error,
      );
    } finally {
      if (mounted) setState(() => _paying = false);
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
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
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
                  const SizedBox(height: 8),

                  // ── Main card (tutor + details + goal) ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F6F6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tutor row (white background)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              // Avatar with white ring
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x1A000000),
                                      blurRadius: 4,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: widget.tutorImage.startsWith('http')
                                      ? Image.network(
                                          widget.tutorImage,
                                          width: 66,
                                          height: 66,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => Container(
                                            width: 66,
                                            height: 66,
                                            color: const Color(0xFFE0E0E0),
                                            child: const Icon(Icons.person, size: 30, color: Color(0xFFAAAAAA)),
                                          ),
                                        )
                                      : Image.asset(
                                          widget.tutorImage,
                                          width: 66,
                                          height: 66,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.tutorName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF272942),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Experience: ${widget.experience}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF999999),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEEEEEE),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'IELTS ${widget.ieltsScore}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFD32F2F),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // DETAILS header
                        const Text(
                          'DETAILS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFAAAAAA),
                            letterSpacing: 0.5,
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Details table (white bg)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              _DetailRow(
                                label: 'Lesson Date',
                                value: widget.lessonDate,
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Divider(height: 1, color: Color(0xFFEEEEEE)),
                              ),
                              _DetailRow(
                                label: 'Time',
                                value: widget.timeRange,
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Divider(height: 1, color: Color(0xFFEEEEEE)),
                              ),
                              _DetailRow(
                                label: 'Duration',
                                value: widget.duration,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Goal text
                        Text(
                          widget.goal,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF272942),
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Balance card ──
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F6F6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        // Balance row (white bg)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Balance',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF999999),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (_balanceLoading)
                                    const Skeleton(
                                      height: 24,
                                      width: 110,
                                      borderRadius: 6,
                                    )
                                  else
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          _formatAmount(_balance),
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            color: _canPay
                                                ? const Color(0xFF4CAF50)
                                                : const Color(0xFFD32F2F),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'UZS',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF999999),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              const Spacer(),
                              if (!_canPay)
                                GestureDetector(
                                  onTap: _onTopUp,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF272942),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.add_circle_outline,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Top up',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                GestureDetector(
                                  onTap: _onTopUp,
                                  child: const Icon(
                                    Icons.add_circle_outline,
                                    color: Color(0xFFBBBBBB),
                                    size: 24,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Total row (white bg)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Text(
                                'Total',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF272942),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _formatAmount(widget.totalAmount),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF272942),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'UZS',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF999999),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ── Pay button ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_canPay && !_paying) ? _onPay : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF272942),
                  disabledBackgroundColor: const Color(0xFFD0D0D0),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _paying
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Text(
                        'Pay',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ── Cancellation note ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
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
                      'In case of cancellation of the lesson, funds will not be debited.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

// ─── Detail row ─────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF272942),
          ),
        ),
      ],
    );
  }
}
