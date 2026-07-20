import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_constants.dart';

class AuthService {
  static const _baseUrl = apiBaseUrl;

  /// Sends OTP to the given phone number.
  static Future<Map<String, dynamic>> sendOtp(String phoneNumber, {required String userType}) async {
    const path = '/auth/send-otp/';
    final reqBody = jsonEncode({'phone_number': phoneNumber, 'user_type': userType});

    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: reqBody,
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    }

    throw AuthException(data['message']?.toString() ?? 'Failed to send OTP');
  }

  /// Verifies OTP and returns tokens + user info.
  static Future<Map<String, dynamic>> verifyOtp({
    required String verifyId,
    required String otpCode,
  }) async {
    const path = '/auth/verify-otp/';
    final reqBody = jsonEncode({'verifyID': verifyId, 'otp_code': otpCode});

    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: reqBody,
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    }

    throw AuthException(data['message']?.toString() ?? 'Invalid OTP');
  }

  /// Exchanges a one-time Telegram login token (from the linkaapp.uz/tg-login
  /// deep link issued by the bot) for JWT tokens + user info.
  static Future<Map<String, dynamic>> exchangeTelegramToken(
    String token,
  ) async {
    const path = '/auth/telegram/exchange/';

    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token}),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    }

    throw AuthException(
      data['message']?.toString() ?? 'Telegram login failed',
    );
  }

  /// Refreshes the access token.
  static Future<Map<String, dynamic>> refreshToken(String refresh) async {
    const path = '/auth/refresh/';

    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh': refresh}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw AuthException('Failed to refresh token');
  }

  /// Logs out by invalidating the refresh token.
  static Future<void> logout({
    required String refreshToken,
    required String accessToken,
  }) async {
    const path = '/auth/logout/';

    await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'refresh': refreshToken}),
    );
  }
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}
