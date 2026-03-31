import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'api_constants.dart';

class AuthService {
  static const _baseUrl = apiBaseUrl;

  static void _logRequest(String method, String path, {String? body}) {
    dev.log('══════════════════════════════════════');
    dev.log('→ $method $path');
    if (body != null) dev.log('→ BODY: $body');
  }

  static void _logResponse(String method, String path, int statusCode, String body) {
    dev.log('← $statusCode $method $path');
    dev.log('← BODY: $body');
    dev.log('══════════════════════════════════════');
  }

  /// Sends OTP to the given phone number.
  static Future<Map<String, dynamic>> sendOtp(String phoneNumber, {required String userType}) async {
    const path = '/auth/send-otp/';
    final reqBody = jsonEncode({'phone_number': phoneNumber, 'user_type': userType});
    _logRequest('POST', path, body: reqBody);

    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: reqBody,
    );

    _logResponse('POST', path, response.statusCode, response.body);
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
    _logRequest('POST', path, body: reqBody);

    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: reqBody,
    );

    _logResponse('POST', path, response.statusCode, response.body);
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    }

    throw AuthException(data['message']?.toString() ?? 'Invalid OTP');
  }

  /// Refreshes the access token.
  static Future<Map<String, dynamic>> refreshToken(String refresh) async {
    const path = '/auth/refresh/';
    _logRequest('POST', path, body: '(refresh token)');

    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh': refresh}),
    );

    _logResponse('POST', path, response.statusCode, response.body);

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
    _logRequest('POST', path, body: '(refresh token)');

    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'refresh': refreshToken}),
    );

    _logResponse('POST', path, response.statusCode, response.body);
  }
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}
