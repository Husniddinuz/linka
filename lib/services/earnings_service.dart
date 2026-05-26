import 'api_service.dart';

class EarningsService {
  /// Fetches paginated tutor earnings with optional date range filter.
  ///
  /// The `/payments/tutor-earnings/` endpoint only returns `{id, phone}` for
  /// the student. We enrich each entry with name + avatar from `/bookings/my/`
  /// (joined on `booking_id`) so the list shows the student's full name.
  static Future<EarningsPage> fetch({
    DateTime? from,
    DateTime? to,
    int page = 1,
    int limit = 20,
  }) async {
    final qp = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (from != null) 'date_from': _fmtDate(from),
      if (to != null) 'date_to': _fmtDate(to),
    };
    final query = qp.entries.map((e) => '${e.key}=${e.value}').join('&');
    final path = '/payments/tutor-earnings/?$query';

    final results = await Future.wait([
      ApiService.get(path),
      ApiService.getList('/bookings/my/').catchError((_) => const <dynamic>[]),
    ]);
    final earningsJson = results[0] as Map<String, dynamic>;
    final bookings = results[1] as List<dynamic>;

    final studentByBookingId = <int, Map<String, dynamic>>{};
    for (final b in bookings) {
      if (b is! Map<String, dynamic>) continue;
      final id = (b['id'] as num?)?.toInt();
      final s = b['student'] as Map<String, dynamic>?;
      if (id != null && s != null) studentByBookingId[id] = s;
    }

    return EarningsPage.fromJson(earningsJson, studentByBookingId);
  }

  /// Fetches the tutor's current wallet balance in UZS.
  static Future<int> fetchWalletBalance() async {
    final result = await ApiService.get('/payments/tutor-wallet/');
    final balance = EarningsPage._parseInt(result['balance_uzs']);
    return balance;
  }

  /// Fetches tutor withdrawals history with optional date range / status filter.
  static Future<WithdrawalsPage> fetchWithdrawals({
    DateTime? from,
    DateTime? to,
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    final qp = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (from != null) 'date_from': _fmtDate(from),
      if (to != null) 'date_to': _fmtDate(to),
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final query = qp.entries.map((e) => '${e.key}=${e.value}').join('&');
    final result = await ApiService.get('/payments/tutor-withdrawals/?$query');
    return WithdrawalsPage.fromJson(result);
  }

  /// Fetches the withdraw screen options: balance, min/max amount, preset
  /// buttons, partner_id status and the payout-schedule hint string.
  static Future<WithdrawOptions> fetchWithdrawOptions() async {
    final result = await ApiService.get('/payments/tutor-withdraw/options/');
    return WithdrawOptions.fromJson(result);
  }

  /// Submits a withdraw request. The wallet is debited immediately; the
  /// accountant later marks the row `completed` or `rejected` (which refunds).
  /// Returns the updated wallet balance + the created withdrawal record.
  static Future<WithdrawResult> performWithdraw({
    required String amountUzs,
  }) async {
    final result = await ApiService.post(
      '/payments/tutor-withdraw/',
      {'amount_uzs': amountUzs},
    );
    return WithdrawResult.fromJson(result);
  }

  static String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}

class EarningsPage {
  final int totalCompletedUzs;
  final int totalPendingUzs;
  final int page;
  final int totalPages;
  final List<EarningEntry> entries;

  const EarningsPage({
    required this.totalCompletedUzs,
    required this.totalPendingUzs,
    required this.page,
    required this.totalPages,
    required this.entries,
  });

  factory EarningsPage.fromJson(
    Map<String, dynamic> json, [
    Map<int, Map<String, dynamic>> studentByBookingId = const {},
  ]) {
    final pagination = (json['pagination'] as Map<String, dynamic>?) ?? {};
    final listRaw = (json['data'] as List?) ?? [];
    final entries = listRaw
        .map((e) => EarningEntry.fromJson(
              e as Map<String, dynamic>,
              studentByBookingId,
            ))
        .toList();

    // API doesn't split completed/pending — derive from lesson time.
    int completed = 0;
    int pending = 0;
    for (final e in entries) {
      if (e.status == 'completed') {
        completed += e.amountUzs;
      } else {
        pending += e.amountUzs;
      }
    }

    return EarningsPage(
      totalCompletedUzs: completed,
      totalPendingUzs: pending,
      page: (pagination['page'] as num?)?.toInt() ?? 1,
      totalPages: (pagination['total_pages'] as num?)?.toInt() ?? 1,
      entries: entries,
    );
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return double.tryParse(v.toString())?.toInt() ?? 0;
  }
}

class EarningEntry {
  final int id;
  final String studentName;
  final String? studentImage;
  final int amountUzs;
  final String status; // 'completed' | 'pending'
  final DateTime? occurredAt;
  final String? timeRange;

  const EarningEntry({
    required this.id,
    required this.studentName,
    this.studentImage,
    required this.amountUzs,
    required this.status,
    this.occurredAt,
    this.timeRange,
  });

  factory EarningEntry.fromJson(
    Map<String, dynamic> json, [
    Map<int, Map<String, dynamic>> studentByBookingId = const {},
  ]) {
    final student = json['student'] as Map<String, dynamic>? ?? {};
    final bookingId = (json['booking_id'] as num?)?.toInt();
    final enriched = bookingId != null ? studentByBookingId[bookingId] : null;
    final firstName =
        (enriched?['first_name'] ?? student['first_name'] ?? '').toString();
    final lastName =
        (enriched?['last_name'] ?? student['last_name'] ?? '').toString();
    final phone = (student['phone'] ?? '').toString();
    final name = '$firstName $lastName'.trim();

    final startStr =
        (json['lesson_start_at'] ?? json['created_at'] ?? '').toString();
    final start = DateTime.tryParse(startStr)?.toLocal();
    final duration = (json['duration_minutes'] as num?)?.toInt() ?? 0;
    final end = start != null && duration > 0
        ? start.add(Duration(minutes: duration))
        : null;

    String hhmm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    String? range;
    if (start != null) {
      range = end != null ? '${hhmm(start)} - ${hhmm(end)}' : hhmm(start);
    }

    return EarningEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      studentName: name.isEmpty ? phone : name,
      studentImage: (enriched?['profile_image'] ?? student['profile_image'])
          as String?,
      amountUzs: EarningsPage._parseInt(json['tutor_amount_uzs']),
      status: 'completed',
      occurredAt: start,
      timeRange: range,
    );
  }
}

/// One page of tutor withdrawals + summary card data.
class WithdrawalsPage {
  final int totalCount;
  final int completedCount;
  final int requestedTotalUzs;
  final int commissionTotalUzs;
  final int payoutTotalUzs;
  final int currentWalletBalanceUzs;
  final int page;
  final int totalPages;
  final bool hasNext;
  final List<WithdrawalEntry> entries;

  const WithdrawalsPage({
    required this.totalCount,
    required this.completedCount,
    required this.requestedTotalUzs,
    required this.commissionTotalUzs,
    required this.payoutTotalUzs,
    required this.currentWalletBalanceUzs,
    required this.page,
    required this.totalPages,
    required this.hasNext,
    required this.entries,
  });

  factory WithdrawalsPage.fromJson(Map<String, dynamic> json) {
    final summary = (json['summary'] as Map<String, dynamic>?) ?? const {};
    final pagination =
        (json['pagination'] as Map<String, dynamic>?) ?? const {};
    final list = (json['data'] as List?) ?? const [];
    return WithdrawalsPage(
      totalCount: EarningsPage._parseInt(summary['total_count']),
      completedCount: EarningsPage._parseInt(summary['completed_count']),
      requestedTotalUzs: EarningsPage._parseInt(summary['requested_total_uzs']),
      commissionTotalUzs:
          EarningsPage._parseInt(summary['commission_total_uzs']),
      payoutTotalUzs: EarningsPage._parseInt(summary['payout_total_uzs']),
      currentWalletBalanceUzs:
          EarningsPage._parseInt(summary['current_wallet_balance_uzs']),
      page: (pagination['page'] as num?)?.toInt() ?? 1,
      totalPages: (pagination['total_pages'] as num?)?.toInt() ?? 1,
      hasNext: pagination['has_next'] as bool? ?? false,
      entries: list
          .map((e) => WithdrawalEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class WithdrawalEntry {
  final int id;
  // 'pending' | 'completed' | 'rejected' | 'failed'
  // 'failed' is the legacy Paylov-API failure status; treat like 'pending' for
  // refund UX. 'rejected' is the new accountant-rejection status and the
  // wallet is auto-refunded by the backend.
  final String status;
  final int requestedAmountUzs;
  final int payoutAmountUzs;
  final int commissionAmountUzs;
  final int? partnerId;
  final int? paylovPaymentId;
  final int? linkaOrderId;
  final String paylovSplitRef;
  final String failReason;
  final String accountantNote;
  final DateTime? createdAt;
  final DateTime? processedAt;

  const WithdrawalEntry({
    required this.id,
    required this.status,
    required this.requestedAmountUzs,
    required this.payoutAmountUzs,
    required this.commissionAmountUzs,
    this.partnerId,
    this.paylovPaymentId,
    this.linkaOrderId,
    this.paylovSplitRef = '',
    this.failReason = '',
    this.accountantNote = '',
    this.createdAt,
    this.processedAt,
  });

  factory WithdrawalEntry.fromJson(Map<String, dynamic> json) {
    return WithdrawalEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? '').toString(),
      requestedAmountUzs:
          EarningsPage._parseInt(json['requested_amount_uzs']),
      payoutAmountUzs: EarningsPage._parseInt(json['payout_amount_uzs']),
      commissionAmountUzs:
          EarningsPage._parseInt(json['commission_amount_uzs']),
      partnerId: (json['partner_id'] as num?)?.toInt(),
      paylovPaymentId: (json['paylov_payment_id'] as num?)?.toInt(),
      linkaOrderId: (json['linka_order_id'] as num?)?.toInt(),
      paylovSplitRef: (json['paylov_split_ref'] ?? '').toString(),
      failReason: (json['fail_reason'] ?? '').toString(),
      accountantNote: (json['accountant_note'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['created_at'] ?? '').toString())?.toLocal(),
      processedAt:
          DateTime.tryParse((json['processed_at'] ?? '').toString())?.toLocal(),
    );
  }
}

/// Response of `GET /payments/tutor-withdraw/options/` — drives the withdraw
/// sheet (preset buttons, custom-amount cap, partner_id gate, hint string).
class WithdrawOptions {
  final int walletBalanceUzs;
  final int minAmountUzs;
  final int maxAmountUzs;
  final List<WithdrawPreset> presets;
  final bool partnerIdConfigured;
  final String payoutScheduleNote;

  const WithdrawOptions({
    required this.walletBalanceUzs,
    required this.minAmountUzs,
    required this.maxAmountUzs,
    required this.presets,
    required this.partnerIdConfigured,
    required this.payoutScheduleNote,
  });

  factory WithdrawOptions.fromJson(Map<String, dynamic> json) {
    final list = (json['preset_options'] as List?) ?? const [];
    return WithdrawOptions(
      walletBalanceUzs: EarningsPage._parseInt(json['wallet_balance_uzs']),
      minAmountUzs: EarningsPage._parseInt(json['min_amount_uzs']),
      maxAmountUzs: EarningsPage._parseInt(json['max_amount_uzs']),
      presets: list
          .whereType<Map<String, dynamic>>()
          .map(WithdrawPreset.fromJson)
          .toList(),
      partnerIdConfigured: json['partner_id_configured'] as bool? ?? false,
      payoutScheduleNote:
          (json['payout_schedule_note'] ?? '').toString(),
    );
  }
}

class WithdrawPreset {
  final int amountUzs;
  final bool available;

  const WithdrawPreset({required this.amountUzs, required this.available});

  factory WithdrawPreset.fromJson(Map<String, dynamic> json) {
    return WithdrawPreset(
      amountUzs: EarningsPage._parseInt(json['amount_uzs']),
      available: json['available'] as bool? ?? false,
    );
  }
}

class WithdrawResult {
  final WithdrawalEntry withdrawal;
  final int walletBalanceUzs;

  const WithdrawResult({
    required this.withdrawal,
    required this.walletBalanceUzs,
  });

  factory WithdrawResult.fromJson(Map<String, dynamic> json) {
    final w = (json['withdrawal'] as Map<String, dynamic>?) ?? const {};
    return WithdrawResult(
      withdrawal: WithdrawalEntry.fromJson(w),
      walletBalanceUzs: EarningsPage._parseInt(json['wallet_balance_uzs']),
    );
  }
}
