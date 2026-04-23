import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_constants.dart';
import 'auth_service.dart';
import 'token_service.dart';

typedef UploadProgressCallback = void Function(int sent, int total);

class ApiService {
  static const _baseUrl = apiBaseUrl;
  static bool _refreshing = false;

  /// Invoked when an authenticated request returns 401 and token refresh
  /// cannot recover the session. Set from main.dart to clear tokens and
  /// navigate the user back to the login screen.
  static Future<void> Function()? onSessionExpired;
  static bool _handlingAuthFailure = false;

  /// Invoked when a request fails due to no network (SocketException /
  /// host lookup failure). Set from ConnectivityWrapper.
  static void Function()? onNetworkFailure;

  static Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on SocketException {
      onNetworkFailure?.call();
      throw const ApiException('No internet connection', statusCode: 0);
    } on http.ClientException catch (e) {
      if (e.message.contains('SocketException') ||
          e.message.contains('Failed host lookup') ||
          e.message.contains('Connection refused')) {
        onNetworkFailure?.call();
        throw const ApiException('No internet connection', statusCode: 0);
      }
      rethrow;
    }
  }

  static Future<void> _handleAuthFailure() async {
    if (_handlingAuthFailure) return;
    _handlingAuthFailure = true;
    try {
      final handler = onSessionExpired;
      if (handler != null) await handler();
    } finally {
      _handlingAuthFailure = false;
    }
  }

  static Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static void _logRequest(String method, String path, {String? body}) {}

  static void _logResponse(String method, String path, int statusCode, String body) {}

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
    var response = await _guard(() => http.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(token),
    ));

    // Retry once with refreshed token on 401
    if (response.statusCode == 401) {
      final newToken = await _tryRefreshToken();
      if (newToken != null) {
        response = await http.get(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(newToken),
        );
      }
      if (response.statusCode == 401) {
        await _handleAuthFailure();
      }
    }

    _logResponse('GET', path, response.statusCode, response.body);
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return data;
    }

    throw ApiException(
      data['message']?.toString() ??
          data['detail']?.toString() ??
          'Request failed (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  /// Makes an authenticated GET request that returns a JSON array.
  static Future<List<dynamic>> getList(String path) async {
    _logRequest('GET', path);
    var token = await TokenService.getAccessToken();
    var response = await _guard(() => http.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(token),
    ));

    if (response.statusCode == 401) {
      final newToken = await _tryRefreshToken();
      if (newToken != null) {
        response = await http.get(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(newToken),
        );
      }
      if (response.statusCode == 401) {
        await _handleAuthFailure();
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
  /// Pass [onProgress] to track byte-level upload progress (useful when the
  /// JSON body contains large base64-encoded media).
  static Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    UploadProgressCallback? onProgress,
  }) async {
    final encodedBody = jsonEncode(body);
    _logRequest('PUT', path, body: encodedBody);

    Future<http.StreamedResponse> send(String? t) {
      final request = onProgress != null
          ? _ProgressRequest('PUT', Uri.parse('$_baseUrl$path'), onProgress)
          : http.Request('PUT', Uri.parse('$_baseUrl$path'));
      request.headers.addAll(_headers(t));
      request.body = encodedBody;
      return http.Client().send(request);
    }

    var token = await TokenService.getAccessToken();
    var response = await _guard(() => send(token));

    // Retry once with refreshed token on 401
    if (response.statusCode == 401) {
      final newToken = await _tryRefreshToken();
      if (newToken != null) response = await send(newToken);
      if (response.statusCode == 401) {
        await _handleAuthFailure();
      }
    }

    final bodyStr = await response.stream.bytesToString();
    _logResponse('PUT', path, response.statusCode, bodyStr);
    final data = jsonDecode(bodyStr) as Map<String, dynamic>;

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
          errors.add('${entry.key}: ${(entry.value as List).join(', ')}');
        }
      }
      if (errors.isNotEmpty) errorMsg = errors.join('\n');
    }

    throw ApiException(errorMsg, statusCode: response.statusCode);
  }

  /// Makes an authenticated POST request. Throws [ApiException] on failure.
  /// Pass [onProgress] to track byte-level upload progress (useful when the
  /// JSON body contains large base64-encoded media).
  static Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    UploadProgressCallback? onProgress,
  }) async {
    final encodedBody = jsonEncode(body);
    _logRequest('POST', path, body: encodedBody);

    Future<http.StreamedResponse> send(String? t) {
      final request = onProgress != null
          ? _ProgressRequest('POST', Uri.parse('$_baseUrl$path'), onProgress)
          : http.Request('POST', Uri.parse('$_baseUrl$path'));
      request.headers.addAll(_headers(t));
      request.body = encodedBody;
      return http.Client().send(request);
    }

    var token = await TokenService.getAccessToken();
    var response = await _guard(() => send(token));

    if (response.statusCode == 401) {
      final newToken = await _tryRefreshToken();
      if (newToken != null) response = await send(newToken);
      if (response.statusCode == 401) {
        await _handleAuthFailure();
      }
    }

    final bodyStr = await response.stream.bytesToString();
    _logResponse('POST', path, response.statusCode, bodyStr);
    final data = jsonDecode(bodyStr) as Map<String, dynamic>;

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
    var response = await _guard(() => http.patch(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(token),
      body: encodedBody,
    ));

    if (response.statusCode == 401) {
      final newToken = await _tryRefreshToken();
      if (newToken != null) {
        response = await http.patch(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(newToken),
          body: encodedBody,
        );
      }
      if (response.statusCode == 401) {
        await _handleAuthFailure();
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
    var response = await _guard(() => http.delete(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(token),
    ));

    if (response.statusCode == 401) {
      final newToken = await _tryRefreshToken();
      if (newToken != null) {
        response = await http.delete(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(newToken),
        );
      }
      if (response.statusCode == 401) {
        await _handleAuthFailure();
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
  /// Pass [onProgress] to track byte-level upload progress.
  static Future<Map<String, dynamic>> postMultipart(
    String path, {
    Map<String, File> files = const {},
    Map<String, String> fields = const {},
    UploadProgressCallback? onProgress,
  }) async {
    _logRequest('POST(multipart)', path, body: 'fields=$fields, files=${files.keys}');
    var token = await TokenService.getAccessToken();

    Future<http.StreamedResponse> send(String? t) async {
      final request = onProgress != null
          ? _ProgressMultipartRequest(
              'POST', Uri.parse('$_baseUrl$path'), onProgress)
          : http.MultipartRequest('POST', Uri.parse('$_baseUrl$path'));
      if (t != null) request.headers['Authorization'] = 'Bearer $t';
      request.fields.addAll(fields);
      for (final entry in files.entries) {
        request.files.add(
          await http.MultipartFile.fromPath(entry.key, entry.value.path),
        );
      }
      return request.send();
    }

    var response = await _guard(() => send(token));

    if (response.statusCode == 401) {
      final newToken = await _tryRefreshToken();
      if (newToken != null) response = await send(newToken);
      if (response.statusCode == 401) {
        await _handleAuthFailure();
      }
    }

    final body = await response.stream.bytesToString();
    _logResponse('POST(multipart)', path, response.statusCode, body);

    Map<String, dynamic>? data;
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) data = parsed;
    } catch (_) {
      // Non-JSON body (e.g. nginx HTML error page for 413/502/504).
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      return data ?? {};
    }

    String errorMsg = 'Request failed (${response.statusCode})';
    if (response.statusCode == 413) {
      errorMsg = 'File is too large to upload';
    } else if (data != null) {
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

/// Wraps a finalized request body stream to report byte-level upload progress.
http.ByteStream _trackStreamProgress(
  http.ByteStream source,
  int total,
  UploadProgressCallback onProgress,
) {
  int sent = 0;
  return http.ByteStream(
    source.transform<List<int>>(
      StreamTransformer.fromHandlers(
        handleData: (chunk, sink) {
          sent += chunk.length;
          sink.add(chunk);
          onProgress(sent, total);
        },
      ),
    ),
  );
}

class _ProgressMultipartRequest extends http.MultipartRequest {
  _ProgressMultipartRequest(super.method, super.url, this._onProgress);
  final UploadProgressCallback _onProgress;

  @override
  http.ByteStream finalize() =>
      _trackStreamProgress(super.finalize(), contentLength, _onProgress);
}

class _ProgressRequest extends http.Request {
  _ProgressRequest(super.method, super.url, this._onProgress);
  final UploadProgressCallback _onProgress;

  @override
  http.ByteStream finalize() =>
      _trackStreamProgress(super.finalize(), contentLength, _onProgress);
}
