import 'api_service.dart';

class PlusService {
  /// GET /payments/plus/me/ — current user's Plus status.
  static Future<PlusStatus> getMyStatus() async {
    const path = '/payments/plus/me/';
    final result = await ApiService.get(path);
    final payload = (result['data'] is Map<String, dynamic>)
        ? result['data'] as Map<String, dynamic>
        : result;
    return PlusStatus.fromJson(payload);
  }

  /// GET /payments/plus/plans/ — available Plus plans.
  /// The backend may return a bare JSON array or a wrapped object
  /// (`{data: [...]}`, `{results: [...]}`, `{plans: [...]}`).
  static Future<List<PlusPlan>> getPlans() async {
    const path = '/payments/plus/plans/';
    List<dynamic> rawList;
    try {
      rawList = await ApiService.getList(path);
    } on ApiException {
      rethrow;
    } catch (_) {
      final result = await ApiService.get(path);
      rawList = (result['data'] ??
              result['results'] ??
              result['plans'] ??
              const <dynamic>[])
          as List<dynamic>;
    }
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(PlusPlan.fromJson)
        .toList();
  }

  /// POST /payments/plus/promo/check/ — what a tutor's promo code does to a
  /// plan's price, without buying anything.
  ///
  /// The discount is never computed here: the percentage can be overridden per
  /// code in the admin, so a client that assumed 10% would quote the wrong
  /// total to exactly the students whose tutor negotiated something else. This
  /// endpoint and checkout call the same arithmetic on the server, which is
  /// what makes the figure on screen the figure that gets debited.
  static Future<PromoQuote> checkPromo({
    required String planCode,
    required String promoCode,
  }) async {
    const path = '/payments/plus/promo/check/';
    final result = await ApiService.post(path, {
      'plan_code': planCode,
      'promo_code': promoCode,
    });
    final payload = (result['data'] is Map<String, dynamic>)
        ? result['data'] as Map<String, dynamic>
        : result;
    return PromoQuote.fromJson(payload);
  }

  /// POST /payments/plus/checkout/ — buy Plus from wallet balance.
  ///
  /// A [promoCode] that the server refuses fails the purchase rather than
  /// quietly charging full price: the student typed it because they expected
  /// the discount.
  static Future<PlusCheckoutResult> checkout(
    String planCode, {
    String? promoCode,
  }) async {
    const path = '/payments/plus/checkout/';
    final code = (promoCode ?? '').trim();
    final body = {
      'plan_code': planCode,
      if (code.isNotEmpty) 'promo_code': code,
    };
    final result = await ApiService.post(path, body);
    final payload = (result['data'] is Map<String, dynamic>)
        ? result['data'] as Map<String, dynamic>
        : result;
    return PlusCheckoutResult.fromJson(payload);
  }
}

/// Amounts cross this API as DRF decimal strings ("240000.00"); a missing or
/// unparseable one reads as zero rather than as NaN on a price tag.
int _uzs(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.round();
  return double.tryParse(value.toString())?.round() ?? 0;
}

/// What a promo code is worth against one specific plan, priced by the server.
class PromoQuote {
  final String code;

  /// The tutor whose code it is — the student is being asked to trust it.
  final String tutorName;
  final double discountPercent;
  final int discountAmountUzs;

  /// The undiscounted plan price, for the struck-through figure.
  final int listPriceUzs;

  /// What this purchase actually costs.
  final int payableUzs;

  const PromoQuote({
    required this.code,
    required this.tutorName,
    required this.discountPercent,
    required this.discountAmountUzs,
    required this.listPriceUzs,
    required this.payableUzs,
  });

  factory PromoQuote.fromJson(Map<String, dynamic> json) {
    return PromoQuote(
      code: (json['promo_code'] ?? json['code'] ?? '').toString().toUpperCase(),
      tutorName: (json['tutor_name'] ?? '').toString().trim(),
      discountPercent:
          double.tryParse((json['discount_percent'] ?? '0').toString()) ?? 0,
      discountAmountUzs: _uzs(json['discount_amount_uzs']),
      listPriceUzs: _uzs(json['list_price_uzs']),
      payableUzs: _uzs(json['payable_uzs']),
    );
  }
}

class PlusStatus {
  final bool isActive;
  final String? planCode;
  final PlusPlan? currentPlan;
  final DateTime? plusUntil;
  final DateTime? since;

  const PlusStatus({
    required this.isActive,
    this.planCode,
    this.currentPlan,
    this.plusUntil,
    this.since,
  });

  factory PlusStatus.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic s) =>
        s is String && s.isNotEmpty ? DateTime.tryParse(s) : null;

    // `current_plan` may be a plain string ("yearly") or a nested plan object
    // (`{code, title, price_uzs, duration_days}`).
    String? code;
    PlusPlan? plan;
    final rawCurrent = json['current_plan'];
    if (rawCurrent is String) {
      code = rawCurrent;
    } else if (rawCurrent is Map<String, dynamic>) {
      plan = PlusPlan.fromJson(rawCurrent);
      code = plan.code.isNotEmpty ? plan.code : null;
    }
    code ??= json['plan_code'] as String?;

    final plusUntil = parseDate(json['plus_until']);
    var since = parseDate(json['plus_since']) ??
        parseDate(json['since']) ??
        parseDate(json['started_at']);
    // Fallback: derive start date from the renewal date minus plan length.
    if (since == null && plusUntil != null && plan?.durationDays != null) {
      since = plusUntil.subtract(Duration(days: plan!.durationDays!));
    }

    return PlusStatus(
      isActive: json['plus_active'] as bool? ??
          json['is_active'] as bool? ??
          json['active'] as bool? ??
          json['is_plus'] as bool? ??
          false,
      planCode: code,
      currentPlan: plan,
      plusUntil: plusUntil,
      since: since,
    );
  }
}

class PlusPlan {
  final String code;
  final String? title;
  final int priceUzs;
  final int? durationDays;

  const PlusPlan({
    required this.code,
    this.title,
    required this.priceUzs,
    this.durationDays,
  });

  /// The period in whole months, which is how the plans are actually sold: a
  /// year is twelve of them, not 365/30 of them. Getting this wrong is the
  /// difference between a "save 33%" badge and a "save 34%" one on the same
  /// two prices.
  int get months {
    final days = durationDays ?? 0;
    if (days <= 0) return 0;
    return (days / 30).round();
  }

  /// What this plan saves against buying [baseline] over and over — three
  /// months at 219 000 beside three separate months at 99 000.
  ///
  /// A real comparison, not an invented "was" price. Null when this *is* the
  /// baseline, when either plan is unpriced, or when it saves nothing.
  int? savePercentAgainst(PlusPlan baseline) {
    if (baseline.code == code) return null;
    if (baseline.months <= 0 || months <= 0 || baseline.priceUzs <= 0) {
      return null;
    }
    final equivalent = baseline.priceUzs * (months / baseline.months);
    if (equivalent <= 0) return null;
    final percent = ((1 - priceUzs / equivalent) * 100).round();
    return percent > 0 ? percent : null;
  }

  factory PlusPlan.fromJson(Map<String, dynamic> json) {
    int parsePrice(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return double.tryParse(v.toString())?.toInt() ?? 0;
    }

    final code = (json['code'] ??
            json['plan_code'] ??
            json['slug'] ??
            json['key'] ??
            '')
        .toString();

    final price = parsePrice(
      json['price_uzs'] ??
          json['price'] ??
          json['amount_uzs'] ??
          json['amount'] ??
          json['cost_uzs'] ??
          json['cost'] ??
          json['total'],
    );

    final duration = (json['duration_days'] as num?)?.toInt() ??
        (json['days'] as num?)?.toInt() ??
        (json['period_days'] as num?)?.toInt();

    return PlusPlan(
      code: code,
      title: json['title'] as String? ?? json['name'] as String?,
      priceUzs: price,
      durationDays: duration,
    );
  }
}

class PlusCheckoutResult {
  final bool success;
  final DateTime? plusUntil;
  final double? balanceUzs;
  final String? message;

  /// The promo code the server actually honoured, and what it took off — null
  /// and zero on a full-price purchase.
  final String? promoCode;
  final int discountAmountUzs;

  const PlusCheckoutResult({
    required this.success,
    this.plusUntil,
    this.balanceUzs,
    this.message,
    this.promoCode,
    this.discountAmountUzs = 0,
  });

  factory PlusCheckoutResult.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

    double? parseBalance(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    final promo = json['promo_code'];
    return PlusCheckoutResult(
      success: json['success'] as bool? ?? true,
      plusUntil: parseDate(json['plus_until']),
      balanceUzs: parseBalance(json['balance_uzs']),
      message: json['message'] as String?,
      promoCode: promo is String && promo.isNotEmpty ? promo : null,
      discountAmountUzs: _uzs(json['discount_amount_uzs']),
    );
  }
}
