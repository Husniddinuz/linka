import 'dart:convert';
import 'dart:io';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'api_constants.dart';
import 'auth_service.dart';
import 'token_service.dart';

class ApiService {
  static const _baseUrl = apiBaseUrl;
  static bool _refreshing = false;

  static Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

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

  /// Attempts to refresh the access token. Returns the new token or null.
  static Future<String?> _tryRefreshToken() async {
    if (_refreshing) return null;
    _refreshing = true;
    try {
      final refresh = await TokenService.getRefreshToken();
      if (refresh == null) return null;
      final result = await AuthService.refreshToken(refresh);
      final newAccess = result['access'] as String?;
      if (newAccess != null) {
        await TokenService.saveTokens(
          access: newAccess,
          refresh: result['refresh'] as String? ?? refresh,
        );
        return newAccess;
      }
    } catch (_) {
      // Refresh failed — caller should handle as 401
    } finally {
      _refreshing = false;
    }
    return null;
  }

  /// Makes an authenticated GET request. Throws [ApiException] on failure.
  static Future<Map<String, dynamic>> get(String path) async {
    _logRequest('GET', path);
    var token = await TokenService.getAccessToken();
    var response = await http.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(token),
    );

    // Retry once with refreshed token on 401
    if (response.statusCode == 401) {
      final newToken = await _tryRefreshToken();
      if (newToken != null) {
        response = await http.get(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(newToken),
        );
      }
    }

    _logResponse('GET', path, response.statusCode, response.body);
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return data;
    }

    throw ApiException(
      data['message']?.toString() ?? 'Request failed',
      statusCode: response.statusCode,
    );
  }

  /// Makes an authenticated GET request that returns a JSON array.
  static Future<List<dynamic>> getList(String path) async {
    _logRequest('GET', path);
    var token = await TokenService.getAccessToken();
    var response = await http.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(token),
    );

    if (response.statusCode == 401) {
      final newToken = await _tryRefreshToken();
      if (newToken != null) {
        response = await http.get(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(newToken),
        );
      }
    }

    _logResponse('GET', path, response.statusCode, response.body);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    final data = jsonDecode(response.body);
    final msg = data is Map ? (data['message']?.toString() ?? 'Request failed') : 'Request failed';
    throw ApiException(msg, statusCode: response.statusCode);
  }

  /// Makes an authenticated PUT request. Throws [ApiException] on failure.
  static Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final encodedBody = jsonEncode(body);
    _logRequest('PUT', path, body: encodedBody);
    var token = await TokenService.getAccessToken();
    var response = await http.put(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(token),
      body: encodedBody,
    );

    // Retry once with refreshed token on 401
    if (response.statusCode == 401) {
      final newToken = await _tryRefreshToken();
      if (newToken != null) {
        response = await http.put(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(newToken),
          body: encodedBody,
        );
      }
    }

    _logResponse('PUT', path, response.statusCode, response.body);
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 || response.statusCode == 201) {
      return data;
    }

    // Extract error message: supports {field: [errors]} and {message: "..."}
    String errorMsg = 'Request failed (${response.statusCode})';
    if (data.containsKey('message')) {
      errorMsg = data['message'].toString();
    } else if (data.containsKey('detail')) {
      errorMsg = data['detail'].toString();
    } else {
      // Field-level errors like {"first_name": ["Must contain only letters."]}
      final errors = <String>[];
      for (final entry in data.entries) {
        if (entry.value is List) {
          errors.add((entry.value as List).join(', '));
        }
      }
      if (errors.isNotEmpty) errorMsg = errors.join('\n');
    }

    throw ApiException(errorMsg, statusCode: response.statusCode);
  }

  /// Makes an authenticated POST request. Throws [ApiException] on failure.
  static Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final encodedBody = jsonEncode(body);
    _logRequest('POST', path, body: encodedBody);
    var token = await TokenService.getAccessToken();
    var response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(token),
      body: encodedBody,
    );

    if (response.statusCode == 401) {
      final newToken = await _tryRefreshToken();
      if (newToken != null) {
        response = await http.post(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(newToken),
          body: encodedBody,
        );
      }
    }

    _logResponse('POST', path, response.statusCode, response.body);
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 || response.statusCode == 201) {
      return data;
    }

    String errorMsg = 'Request failed (${response.statusCode})';
    if (data.containsKey('message')) {
      errorMsg = data['message'].toString();
    } else if (data.containsKey('detail')) {
      errorMsg = data['detail'].toString();
    } else {
      final errors = <String>[];
      for (final entry in data.entries) {
        if (entry.value is List) {
          errors.add((entry.value as List).join(', '));
        }
      }
      if (errors.isNotEmpty) errorMsg = errors.join('\n');
    }

    throw ApiException(errorMsg, statusCode: response.statusCode);
  }

  /// Makes an authenticated PATCH request. Throws [ApiException] on failure.
  static Future<Map<String, dynamic>> patch(
    String path, [
    Map<String, dynamic> body = const {},
  ]) async {
    final encodedBody = jsonEncode(body);
    _logRequest('PATCH', path, body: encodedBody);
    var token = await TokenService.getAccessToken();
    var response = await http.patch(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(token),
      body: encodedBody,
    );

    if (response.statusCode == 401) {
      final newToken = await _tryRefreshToken();
      if (newToken != null) {
        response = await http.patch(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(newToken),
          body: encodedBody,
        );
      }
    }

    _logResponse('PATCH', path, response.statusCode, response.body);
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 || response.statusCode == 201) {
      return data;
    }

    String errorMsg = 'Request failed (${response.statusCode})';
    if (data.containsKey('message')) {
      errorMsg = data['message'].toString();
    } else if (data.containsKey('detail')) {
      errorMsg = data['detail'].toString();
    } else {
      final errors = <String>[];
      for (final entry in data.entries) {
        if (entry.value is List) {
          errors.add((entry.value as List).join(', '));
        }
      }
      if (errors.isNotEmpty) errorMsg = errors.join('\n');
    }

    throw ApiException(errorMsg, statusCode: response.statusCode);
  }

  /// Makes an authenticated DELETE request. Throws [ApiException] on failure.
  static Future<void> delete(String path) async {
    _logRequest('DELETE', path);
    var token = await TokenService.getAccessToken();
    var response = await http.delete(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(token),
    );

    if (response.statusCode == 401) {
      final newToken = await _tryRefreshToken();
      if (newToken != null) {
        response = await http.delete(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(newToken),
        );
      }
    }

    _logResponse('DELETE', path, response.statusCode, response.body);

    if (response.statusCode == 200 || response.statusCode == 204) {
      return;
    }

    String errorMsg = 'Request failed (${response.statusCode})';
    if (response.body.isNotEmpty) {
      try {
        final data = jsonDecode(response.body);
        if (data is Map) {
          errorMsg = data['message']?.toString() ??
              data['detail']?.toString() ??
              errorMsg;
        }
      } catch (_) {}
    }
    throw ApiException(errorMsg, statusCode: response.statusCode);
  }

  /// Makes an authenticated multipart POST request for file uploads.
  /// [files] is a map of field name → File. [fields] are additional text fields.
  static Future<Map<String, dynamic>> postMultipart(
    String path, {
    Map<String, File> files = const {},
    Map<String, String> fields = const {},
  }) async {
    _logRequest('POST(multipart)', path, body: 'fields=$fields, files=${files.keys}');
    var token = await TokenService.getAccessToken();

    Future<http.StreamedResponse> send(String? t) async {
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl$path'));
      if (t != null) request.headers['Authorization'] = 'Bearer $t';
      request.fields.addAll(fields);
      for (final entry in files.entries) {
        request.files.add(
          await http.MultipartFile.fromPath(entry.key, entry.value.path),
        );
      }
      return request.send();
    }

    var response = await send(token);

    if (response.statusCode == 401) {
      final newToken = await _tryRefreshToken();
      if (newToken != null) response = await send(newToken);
    }

    final body = await response.stream.bytesToString();
    _logResponse('POST(multipart)', path, response.statusCode, body);

    final data = jsonDecode(body) as Map<String, dynamic>;

    if (response.statusCode == 200 || response.statusCode == 201) {
      return data;
    }

    String errorMsg = 'Request failed (${response.statusCode})';
    if (data.containsKey('message')) {
      errorMsg = data['message'].toString();
    } else if (data.containsKey('detail')) {
      errorMsg = data['detail'].toString();
    } else {
      final errors = <String>[];
      for (final entry in data.entries) {
        if (entry.value is List) {
          errors.add((entry.value as List).join(', '));
        }
      }
      if (errors.isNotEmpty) errorMsg = errors.join('\n');
    }

    throw ApiException(errorMsg, statusCode: response.statusCode);
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  const ApiException(this.message, {this.statusCode = 0});

  @override
  String toString() => message;
}
