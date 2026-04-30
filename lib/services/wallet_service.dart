import 'api_service.dart';

class WalletService {
  static int? _cachedBalance;

  /// Last known balance, available instantly without a network call.
  static int? get cachedBalance => _cachedBalance;

  /// Fetches the current wallet balance in UZS and updates the in-memory cache.
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
    final balance = double.tryParse(raw.toString())?.toInt() ?? 0;
    _cachedBalance = balance;
    return balance;
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

  /// Checks the real transaction status for a Paylov top-up by order id.
  /// Backend queries the gateway and returns the current state.
  static Future<PaylovFinalizeResult> checkPaylovTransactionStatus({
    required int orderId,
  }) async {
    final result = await ApiService.get(
      '/payments/paylov/transaction-status/?order_id=$orderId',
    );
    final payload = (result['data'] is Map<String, dynamic>)
        ? result['data'] as Map<String, dynamic>
        : result;
    return PaylovFinalizeResult.fromJson(payload);
  }

  /// Finalizes a Paylov top-up after the user returns from the bank app.
  /// Backend re-checks the payment status. [paymentStatus] and
  /// [gatewayPaymentId] come from the return URL query string when available.
  static Future<PaylovFinalizeResult> finalizePaylovCheckout({
    required int orderId,
    int? paymentStatus,
    String? gatewayPaymentId,
  }) async {
    final body = <String, dynamic>{'order_id': orderId};
    if (paymentStatus != null) body['payment_status'] = paymentStatus;
    if (gatewayPaymentId != null) body['gateway_payment_id'] = gatewayPaymentId;
    final result = await ApiService.post('/payments/paylov/finalize/', body);
    final payload = (result['data'] is Map<String, dynamic>)
        ? result['data'] as Map<String, dynamic>
        : result;
    return PaylovFinalizeResult.fromJson(payload);
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

class PaylovFinalizeResult {
  final bool success;
  final bool credited;
  final int? orderId;
  final int? paymentStatus;
  final String? orderStatus;
  final String? syncStatus;
  final double? balanceUzs;
  final String? message;
  final Map<String, dynamic> raw;

  const PaylovFinalizeResult({
    required this.success,
    this.credited = false,
    this.orderId,
    this.paymentStatus,
    this.orderStatus,
    this.syncStatus,
    this.balanceUzs,
    this.message,
    this.raw = const {},
  });

  /// Considered paid if the backend credited the wallet, order_status is
  /// "paid", sync_status is "credited", or payment_status == 2.
  bool get isPaid =>
      credited ||
      orderStatus == 'paid' ||
      syncStatus == 'credited' ||
      paymentStatus == 2;

  factory PaylovFinalizeResult.fromJson(Map<String, dynamic> json) {
    return PaylovFinalizeResult(
      success: json['success'] as bool? ?? false,
      credited: json['credited'] as bool? ?? false,
      orderId: (json['order_id'] as num?)?.toInt(),
      paymentStatus: (json['payment_status'] as num?)?.toInt(),
      orderStatus: json['order_status'] as String?,
      syncStatus: json['sync_status'] as String?,
      balanceUzs: (json['balance_uzs'] as num?)?.toDouble(),
      message: json['message'] as String?,
      raw: json,
    );
  }
}
