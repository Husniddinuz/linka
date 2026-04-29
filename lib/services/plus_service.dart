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

  /// POST /payments/plus/checkout/ — buy Plus from wallet balance.
  static Future<PlusCheckoutResult> checkout(String planCode) async {
    const path = '/payments/plus/checkout/';
    final body = {'plan_code': planCode};
    final result = await ApiService.post(path, body);
    final payload = (result['data'] is Map<String, dynamic>)
        ? result['data'] as Map<String, dynamic>
        : result;
    return PlusCheckoutResult.fromJson(payload);
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

  const PlusCheckoutResult({
    required this.success,
    this.plusUntil,
    this.balanceUzs,
    this.message,
  });

  factory PlusCheckoutResult.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

    double? parseBalance(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return PlusCheckoutResult(
      success: json['success'] as bool? ?? true,
      plusUntil: parseDate(json['plus_until']),
      balanceUzs: parseBalance(json['balance_uzs']),
      message: json['message'] as String?,
    );
  }
}
