import 'dart:convert';
import 'dart:developer' as developer;
import 'api_service.dart';

class EarningsService {
  /// Fetches paginated tutor earnings with optional date range filter.
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
    developer.log('GET $path', name: 'EarningsService');
    final result = await ApiService.get(path);
    developer.log(
      'raw response: ${jsonEncode(result)}',
      name: 'EarningsService',
    );
    final parsed = EarningsPage.fromJson(result);
    developer.log(
      'parsed: completed=${parsed.totalCompletedUzs} UZS, '
      'pending=${parsed.totalPendingUzs} UZS, '
      'entries=${parsed.entries.length}, '
      'page=${parsed.page}/${parsed.totalPages}',
      name: 'EarningsService',
    );
    return parsed;
  }

  /// Fetches the tutor's current wallet balance in UZS.
  static Future<int> fetchWalletBalance() async {
    developer.log('GET /payments/tutor-wallet/', name: 'EarningsService');
    final result = await ApiService.get('/payments/tutor-wallet/');
    developer.log(
      'wallet raw: ${jsonEncode(result)}',
      name: 'EarningsService',
    );
    final balance = EarningsPage._parseInt(result['balance_uzs']);
    developer.log('wallet balance: $balance UZS', name: 'EarningsService');
    return balance;
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

  factory EarningsPage.fromJson(Map<String, dynamic> json) {
    final pagination = (json['pagination'] as Map<String, dynamic>?) ?? {};
    final listRaw = (json['data'] as List?) ?? [];
    final entries = listRaw
        .map((e) => EarningEntry.fromJson(e as Map<String, dynamic>))
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

  factory EarningEntry.fromJson(Map<String, dynamic> json) {
    final student = json['student'] as Map<String, dynamic>? ?? {};
    final firstName = (student['first_name'] ?? '').toString();
    final lastName = (student['last_name'] ?? '').toString();
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
      studentImage: student['profile_image'] as String?,
      amountUzs: EarningsPage._parseInt(json['tutor_amount_uzs']),
      status: 'completed',
      occurredAt: start,
      timeRange: range,
    );
  }
}
