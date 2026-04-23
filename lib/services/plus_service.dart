import 'dart:developer' as dev;

import 'api_service.dart';

const _logTag = 'plus';

void _logRequest(String method, String path, [Object? body]) {
  final suffix = body == null ? '' : ' body=$body';
  dev.log('→ $method $path$suffix', name: _logTag);
}

void _logResponse(String method, String path, Object? result) {
  dev.log('← $method $path $result', name: _logTag);
}

void _logError(String method, String path, Object error, [StackTrace? st]) {
  dev.log('✖ $method $path — $error',
      name: _logTag, error: error, stackTrace: st);
}

class PlusService {
  /// GET /payments/plus/me/ — current user's Plus status.
  static Future<PlusStatus> getMyStatus() async {
    const path = '/payments/plus/me/';
    _logRequest('GET', path);
    try {
      final result = await ApiService.get(path);
      _logResponse('GET', path, result);
      final payload = (result['data'] is Map<String, dynamic>)
          ? result['data'] as Map<String, dynamic>
          : result;
      final status = PlusStatus.fromJson(payload);
      dev.log(
        'parsed status: isActive=${status.isActive} '
        'planCode=${status.planCode} '
        'plusUntil=${status.plusUntil} since=${status.since}',
        name: _logTag,
      );
      return status;
    } catch (e, st) {
      _logError('GET', path, e, st);
      rethrow;
    }
  }

  /// GET /payments/plus/plans/ — available Plus plans.
  /// The backend may return a bare JSON array or a wrapped object
  /// (`{data: [...]}`, `{results: [...]}`, `{plans: [...]}`).
  static Future<List<PlusPlan>> getPlans() async {
    const path = '/payments/plus/plans/';
    _logRequest('GET', path);
    try {
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
      _logResponse('GET', path, rawList);
      final plans = rawList
          .whereType<Map<String, dynamic>>()
          .map(PlusPlan.fromJson)
          .toList();
      for (final p in plans) {
        dev.log(
          'parsed plan: code=${p.code} title=${p.title} '
          'priceUzs=${p.priceUzs} durationDays=${p.durationDays}',
          name: _logTag,
        );
      }
      return plans;
    } catch (e, st) {
      _logError('GET', path, e, st);
      rethrow;
    }
  }

  /// POST /payments/plus/checkout/ — buy Plus from wallet balance.
  static Future<PlusCheckoutResult> checkout(String planCode) async {
    const path = '/payments/plus/checkout/';
    final body = {'plan_code': planCode};
    _logRequest('POST', path, body);
    try {
      final result = await ApiService.post(path, body);
      _logResponse('POST', path, result);
      final payload = (result['data'] is Map<String, dynamic>)
          ? result['data'] as Map<String, dynamic>
          : result;
      final parsed = PlusCheckoutResult.fromJson(payload);
      dev.log(
        'parsed checkout: success=${parsed.success} '
        'plusUntil=${parsed.plusUntil} balanceUzs=${parsed.balanceUzs} '
        'message=${parsed.message}',
        name: _logTag,
      );
      return parsed;
    } catch (e, st) {
      _logError('POST', path, e, st);
      rethrow;
    }
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
