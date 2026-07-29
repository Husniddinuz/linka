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

  /// Requests a sign-in code by email.
  ///
  /// Email is a second way into an account that already exists — it is never a
  /// way to create one, so unlike [sendOtp] this cannot register anybody. The
  /// address has to have been confirmed from the profile first (see
  /// [addEmail]/[confirmEmail]).
  ///
  /// The server answers the same way whether or not the address belongs to an
  /// account, so a `verifyID` coming back is not evidence that a code was
  /// actually sent. Say "if that address is registered…" in the UI rather than
  /// promising mail that may not exist.
  static Future<Map<String, dynamic>> sendEmailOtp(
    String email, {
    required String userType,
  }) async {
    const path = '/auth/email/send-otp/';

    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'user_type': userType}),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    }

    throw AuthException(
      data['message']?.toString() ?? 'Failed to send the email',
    );
  }

  /// Verifies an emailed code. Same response shape as [verifyOtp].
  static Future<Map<String, dynamic>> verifyEmailOtp({
    required String verifyId,
    required String otpCode,
  }) async {
    const path = '/auth/email/verify-otp/';

    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'verifyID': verifyId, 'otp_code': otpCode}),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    }

    throw AuthException(data['message']?.toString() ?? 'Invalid code');
  }

  /// Starts attaching [email] to the signed-in account: mails a code and
  /// returns a `verifyID` for [confirmEmail]. Nothing is stored until that
  /// second call succeeds.
  static Future<Map<String, dynamic>> addEmail({
    required String email,
    required String accessToken,
  }) async {
    const path = '/auth/email/add/';

    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'email': email}),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    }

    throw AuthException(
      data['message']?.toString() ?? 'Could not send the confirmation email',
    );
  }

  /// Finishes what [addEmail] started; the address is stored on success.
  static Future<String> confirmEmail({
    required String verifyId,
    required String otpCode,
    required String accessToken,
  }) async {
    const path = '/auth/email/confirm/';

    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'verifyID': verifyId, 'otp_code': otpCode}),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 && data['success'] == true) {
      return data['email']?.toString() ?? '';
    }

    throw AuthException(data['message']?.toString() ?? 'Invalid code');
  }

  /// Unlinks the account's email. The phone number is untouched, so this only
  /// removes a way in — it never locks anyone out.
  static Future<void> removeEmail({required String accessToken}) async {
    const path = '/auth/email/add/';

    final response = await http.delete(
      Uri.parse('$_baseUrl$path'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode != 200) {
      throw const AuthException('Could not remove the email');
    }
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
