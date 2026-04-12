import 'api_service.dart';

class WalletService {
  /// Fetches the current wallet balance in UZS.
  /// Returns 0 on error so callers can render gracefully.
  static Future<int> getBalance() async {
    final result = await ApiService.get('/payments/wallet/');
    // API may wrap payload in {data: {...}} or return the model directly.
    final payload = (result['data'] is Map<String, dynamic>)
        ? result['data'] as Map<String, dynamic>
        : result;
    final raw = payload['balance_uzs'];
    if (raw == null) return 0;
    // balance_uzs is a decimal string like "100000.00"
    return double.tryParse(raw.toString())?.toInt() ?? 0;
  }

  /// Creates a Paylov checkout for top-up.
  /// [amountUzs] — amount in whole UZS (sums); API converts to tiyin.
  /// [provider] — one of "uzum", "payme", "click".
  /// Returns the parsed [PaylovCheckoutResult].
  static Future<PaylovCheckoutResult> createPaylovCheckout({
    required int amountUzs,
    required String provider,
  }) async {
    final result = await ApiService.post('/payments/paylov/checkout/', {
      'amount_uzs': amountUzs,
      'payment_provider': provider,
    });
    final payload = (result['data'] is Map<String, dynamic>)
        ? result['data'] as Map<String, dynamic>
        : result;
    return PaylovCheckoutResult.fromJson(payload);
  }
}

class PaylovCheckoutResult {
  final bool success;
  final int orderId;
  final String? checkoutUrl;
  final int? paylovOrderId;
  final int? state;
  final bool requiresOtp;
  final String? message;

  const PaylovCheckoutResult({
    required this.success,
    required this.orderId,
    this.checkoutUrl,
    this.paylovOrderId,
    this.state,
    this.requiresOtp = false,
    this.message,
  });

  factory PaylovCheckoutResult.fromJson(Map<String, dynamic> json) {
    return PaylovCheckoutResult(
      success: json['success'] as bool? ?? false,
      orderId: (json['order_id'] as num?)?.toInt() ?? 0,
      checkoutUrl: json['checkout_url'] as String?,
      paylovOrderId: (json['paylov_order_id'] as num?)?.toInt(),
      state: (json['state'] as num?)?.toInt(),
      requiresOtp: json['requires_otp'] as bool? ?? false,
      message: json['message'] as String?,
    );
  }
}
