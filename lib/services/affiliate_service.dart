import 'api_service.dart';

/// The tutor's half of the promo code a student types at Plus checkout.
///
/// One code per tutor. `GET /payments/affiliate/me/` mints it on the first
/// read rather than behind a "join the programme" button — there is nothing
/// for a tutor to decide about a code, and a screen that opens empty with one
/// button is a step that exists only because the row did not.
class AffiliateService {
  /// What a student may type → what the server stores. Spaces and dashes are
  /// dropped, so "ali-72" is six characters typed and five stored — the same
  /// normalisation the backend applies, done here so the length checks in the
  /// UI count the characters the server will count.
  static String normalizeCode(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    return cleaned.length > 24 ? cleaned.substring(0, 24) : cleaned;
  }

  /// GET /payments/affiliate/me/ — the tutor's code, its terms and its totals.
  static Future<AffiliateCode> getMyCode() async {
    final result = await ApiService.get('/payments/affiliate/me/');
    return AffiliateCode.fromJson(result);
  }

  /// PATCH /payments/affiliate/me/ — rename the code.
  ///
  /// Allowed only while the code has never been used: after that it is written
  /// in someone's Telegram bio, and renaming it would silently break every
  /// copy of it. The server refuses with `code_locked`.
  static Future<AffiliateCode> renameCode(String code) async {
    final result = await ApiService.patch(
      '/payments/affiliate/me/',
      {'code': normalizeCode(code)},
    );
    return AffiliateCode.fromJson(result);
  }

  /// GET /payments/affiliate/commissions/ — what the code has earned,
  /// purchase by purchase.
  static Future<AffiliateCommissionsPage> getCommissions({
    int page = 1,
    int limit = 50,
  }) async {
    final result = await ApiService.get(
      '/payments/affiliate/commissions/?page=$page&limit=$limit',
    );
    return AffiliateCommissionsPage.fromJson(result);
  }
}

/// Money crosses this API as DRF decimal strings ("12000.00"); a missing or
/// unparseable one reads as zero rather than as NaN on screen.
int _uzs(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.round();
  return double.tryParse(value.toString())?.round() ?? 0;
}

double _percent(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

class AffiliateCode {
  final String code;
  final bool isActive;

  /// The terms in force for *this* code — global unless the admin gave this
  /// tutor its own, which is why they are shown rather than hardcoded.
  final double discountPercent;
  final double tutorSharePercent;

  /// False once the code has earned anything.
  final bool canRename;

  final int purchases;
  final int students;
  final int earnedTotalUzs;

  const AffiliateCode({
    required this.code,
    required this.isActive,
    required this.discountPercent,
    required this.tutorSharePercent,
    required this.canRename,
    required this.purchases,
    required this.students,
    required this.earnedTotalUzs,
  });

  factory AffiliateCode.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] is Map<String, dynamic>
        ? json['summary'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return AffiliateCode(
      code: (json['code'] ?? '').toString(),
      isActive: json['is_active'] as bool? ?? true,
      discountPercent: _percent(json['discount_percent']),
      tutorSharePercent: _percent(json['tutor_share_percent']),
      canRename: json['can_rename'] as bool? ?? false,
      purchases: (summary['purchases'] as num?)?.toInt() ?? 0,
      students: (summary['students'] as num?)?.toInt() ?? 0,
      earnedTotalUzs: _uzs(summary['earned_total_uzs']),
    );
  }
}

/// One Plus subscription bought with this tutor's code. The student is named
/// by first name only — a referral is not a booking, so the API withholds the
/// phone number it hands over for a lesson.
class AffiliateCommission {
  final int id;
  final String? planTitle;
  final String studentName;
  final String? studentImage;
  final int listPriceUzs;
  final int discountAmountUzs;
  final int paidAmountUzs;
  final int tutorAmountUzs;
  final DateTime? createdAt;

  const AffiliateCommission({
    required this.id,
    this.planTitle,
    required this.studentName,
    this.studentImage,
    required this.listPriceUzs,
    required this.discountAmountUzs,
    required this.paidAmountUzs,
    required this.tutorAmountUzs,
    this.createdAt,
  });

  factory AffiliateCommission.fromJson(Map<String, dynamic> json) {
    final student = json['student'] is Map<String, dynamic>
        ? json['student'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final image = student['profile_image'];
    final created = json['created_at'];
    return AffiliateCommission(
      id: (json['id'] as num?)?.toInt() ?? 0,
      planTitle: (json['plan_title'] as String?)?.trim(),
      studentName: (student['first_name'] ?? '').toString().trim(),
      studentImage: image is String && image.isNotEmpty ? image : null,
      listPriceUzs: _uzs(json['list_price_uzs']),
      discountAmountUzs: _uzs(json['discount_amount_uzs']),
      paidAmountUzs: _uzs(json['paid_amount_uzs']),
      tutorAmountUzs: _uzs(json['tutor_amount_uzs']),
      createdAt: created is String ? DateTime.tryParse(created) : null,
    );
  }
}

class AffiliateCommissionsPage {
  final int count;
  final int students;
  final int paidTotalUzs;
  final int discountTotalUzs;
  final int tutorTotalUzs;
  final List<AffiliateCommission> entries;

  const AffiliateCommissionsPage({
    required this.count,
    required this.students,
    required this.paidTotalUzs,
    required this.discountTotalUzs,
    required this.tutorTotalUzs,
    required this.entries,
  });

  static const empty = AffiliateCommissionsPage(
    count: 0,
    students: 0,
    paidTotalUzs: 0,
    discountTotalUzs: 0,
    tutorTotalUzs: 0,
    entries: [],
  );

  factory AffiliateCommissionsPage.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] is Map<String, dynamic>
        ? json['summary'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final rows = json['data'] is List
        ? json['data'] as List<dynamic>
        : const <dynamic>[];
    return AffiliateCommissionsPage(
      count: (summary['count'] as num?)?.toInt() ?? 0,
      students: (summary['students'] as num?)?.toInt() ?? 0,
      paidTotalUzs: _uzs(summary['paid_total_uzs']),
      discountTotalUzs: _uzs(summary['discount_total_uzs']),
      tutorTotalUzs: _uzs(summary['tutor_total_uzs']),
      entries: rows
          .whereType<Map<String, dynamic>>()
          .map(AffiliateCommission.fromJson)
          .toList(),
    );
  }
}
