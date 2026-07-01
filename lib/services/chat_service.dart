import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_constants.dart';
import 'api_service.dart';
import 'token_service.dart';

class ChatService {
  static Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  // Performs a GET against the chat backend and parses the JSON body.
  // Converts non-JSON or error responses into readable ApiExceptions.
  static Future<Map<String, dynamic>> _get(String path) async {
    final token = await TokenService.getAccessToken();
    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$chatApiBaseUrl$path'),
        headers: _headers(token),
      );
    } on SocketException {
      throw const ApiException('No internet connection', statusCode: 0);
    }

    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw ApiException(
          'Unexpected response format (${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 200) return body;
      throw ApiException(
        body['detail']?.toString() ??
            body['message']?.toString() ??
            'Request failed (${response.statusCode})',
        statusCode: response.statusCode,
      );
    } on FormatException {
      final preview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      debugPrint('[ChatService] Non-JSON response (${response.statusCode}): $preview');
      throw ApiException(
        'Server error (${response.statusCode}) — chat backend may be unreachable',
        statusCode: response.statusCode,
      );
    }
  }

  static Future<List<Map<String, dynamic>>> fetchChannels() async {
    final data = await _get('/chats/channels/');
    final results = data['results'];
    if (results is! List) return [];
    return results.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> fetchMessages(
    String slug, {
    String? before,
    int limit = 50,
  }) async {
    var path = '/chats/channels/$slug/messages/?limit=$limit';
    if (before != null) path += '&before=$before';
    final data = await _get(path);
    if (data['results'] is! List) {
      return {'results': <dynamic>[], 'has_more': false};
    }
    return data;
  }

  static Future<void> sendTextMessageRest(
    String slug,
    String text, {
    String? replyToId,
  }) async {
    final token = await TokenService.getAccessToken();
    final body = <String, dynamic>{'text': text};
    if (replyToId != null) body['reply_to_id'] = int.tryParse(replyToId) ?? replyToId;
    await http.post(
      Uri.parse('$chatApiBaseUrl/chats/channels/$slug/messages/'),
      headers: _headers(token),
      body: jsonEncode(body),
    );
  }

  static Future<void> deleteMessage(String slug, String messageId) async {
    final token = await TokenService.getAccessToken();
    await http.delete(
      Uri.parse('$chatApiBaseUrl/chats/channels/$slug/messages/$messageId/'),
      headers: _headers(token),
    );
  }

  static Future<void> uploadVoiceMessage(
    String slug,
    File file,
    int duration, {
    String? replyToId,
  }) async {
    final token = await TokenService.getAccessToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$chatApiBaseUrl/chats/channels/$slug/messages/voice/'),
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields['duration'] = duration.toString();
    if (replyToId != null) request.fields['reply_to_id'] = replyToId;
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    await request.send();
  }

  static Future<void> uploadImageMessage(
    String slug,
    File file, {
    String? replyToId,
  }) async {
    final token = await TokenService.getAccessToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$chatApiBaseUrl/chats/channels/$slug/messages/image/'),
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (replyToId != null) request.fields['reply_to_id'] = replyToId;
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await request.send();
    if (streamed.statusCode == 400 || streamed.statusCode == 403) {
      final body = await streamed.stream.bytesToString();
      String detail;
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        detail = json['detail']?.toString() ?? 'Upload failed (${streamed.statusCode})';
      } catch (_) {
        detail = 'Upload failed (${streamed.statusCode})';
      }
      throw ApiException(detail, statusCode: streamed.statusCode);
    }
  }

  static Future<void> markRead(String slug) async {
    try {
      final token = await TokenService.getAccessToken();
      await http.post(
        Uri.parse('$chatApiBaseUrl/chats/channels/$slug/read/'),
        headers: _headers(token),
      );
    } catch (_) {}
  }

  static Future<WebSocketChannel> connectWebSocket(String slug) async {
    final token = await TokenService.getAccessToken();
    final uri = Uri.parse('$chatWsBaseUrl/ws/chats/$slug/?token=$token');
    return WebSocketChannel.connect(uri);
  }

  static Future<WebSocketChannel> connectPresenceWebSocket() async {
    final token = await TokenService.getAccessToken();
    final uri = Uri.parse('$chatWsBaseUrl/ws/presence/?token=$token');
    return WebSocketChannel.connect(uri);
  }

  static Future<Map<String, dynamic>> submitQuizAnswer(
    String slug,
    int quizId,
    int optionId,
  ) async {
    final token = await TokenService.getAccessToken();
    final response = await http.post(
      Uri.parse('$chatApiBaseUrl/chats/channels/$slug/quiz/$quizId/answer/'),
      headers: _headers(token),
      body: jsonEncode({'option_id': optionId}),
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) return body;
      throw ApiException(
        body['detail']?.toString() ?? 'Failed to submit (${response.statusCode})',
        statusCode: response.statusCode,
      );
    } on FormatException {
      throw ApiException('Server error (${response.statusCode})',
          statusCode: response.statusCode);
    }
  }

  static Future<void> createQuiz(
    String slug, {
    required String title,
    required List<Map<String, dynamic>> options,
    String? replyToId,
  }) async {
    final token = await TokenService.getAccessToken();
    final body = <String, dynamic>{
      'title': title,
      'options': options,
      if (replyToId != null) 'reply_to_id': int.tryParse(replyToId) ?? replyToId,
    };
    final response = await http.post(
      Uri.parse('$chatApiBaseUrl/chats/channels/$slug/messages/quiz/'),
      headers: _headers(token),
      body: jsonEncode(body),
    );
    if (response.statusCode != 201) {
      String detail;
      try {
        final parsed = jsonDecode(response.body) as Map<String, dynamic>;
        detail = parsed['detail']?.toString() ??
            'Failed to create quiz (${response.statusCode})';
      } catch (_) {
        detail = 'Failed to create quiz (${response.statusCode})';
      }
      throw ApiException(detail, statusCode: response.statusCode);
    }
  }

  static Future<List<Map<String, dynamic>>> fetchAudioStorage() async {
    final data = await _get('/chats/audio-storage/');
    final results = data['results'];
    if (results is! List) return [];
    return results.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> uploadAudioStorage(
    File file, {
    String? title,
  }) async {
    final token = await TokenService.getAccessToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$chatApiBaseUrl/chats/audio-storage/'),
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (title != null && title.isNotEmpty) request.fields['title'] = title;
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode == 201) {
      return jsonDecode(body) as Map<String, dynamic>;
    }
    String detail;
    try {
      final parsed = jsonDecode(body) as Map<String, dynamic>;
      detail = parsed['detail']?.toString() ??
          'Upload failed (${streamed.statusCode})';
    } catch (_) {
      detail = 'Upload failed (${streamed.statusCode})';
    }
    throw ApiException(detail, statusCode: streamed.statusCode);
  }

  static Future<void> sendStorageAudio(
    String slug,
    int audioId, {
    String? replyToId,
  }) async {
    final token = await TokenService.getAccessToken();
    final body = <String, dynamic>{
      'audio_id': audioId,
      if (replyToId != null) 'reply_to_id': int.tryParse(replyToId) ?? replyToId,
    };
    final response = await http.post(
      Uri.parse('$chatApiBaseUrl/chats/channels/$slug/messages/storage-audio/'),
      headers: _headers(token),
      body: jsonEncode(body),
    );
    if (response.statusCode != 201) {
      String detail;
      try {
        final parsed = jsonDecode(response.body) as Map<String, dynamic>;
        detail = parsed['detail']?.toString() ??
            'Failed to send audio (${response.statusCode})';
      } catch (_) {
        detail = 'Failed to send audio (${response.statusCode})';
      }
      throw ApiException(detail, statusCode: response.statusCode);
    }
  }

  static Future<void> reportMessage({
    required int messageId,
    required String reason,
    String comment = '',
  }) async {
    final token = await TokenService.getAccessToken();
    final response = await http.post(
      Uri.parse('$chatApiBaseUrl/chats/messages/$messageId/report/'),
      headers: _headers(token),
      body: jsonEncode({'reason': reason, 'comment': comment}),
    );
    if (response.statusCode != 201) {
      String detail;
      try {
        final parsed = jsonDecode(response.body) as Map<String, dynamic>;
        detail = parsed['detail']?.toString() ??
            'Report failed (${response.statusCode})';
      } catch (_) {
        detail = 'Report failed (${response.statusCode})';
      }
      throw ApiException(detail, statusCode: response.statusCode);
    }
  }

  static Future<void> blockUser({required int userId}) async {
    final token = await TokenService.getAccessToken();
    await http.post(
      Uri.parse('$chatApiBaseUrl/chats/users/$userId/block/'),
      headers: _headers(token),
    );
  }

  static Future<void> unblockUser({required int userId}) async {
    final token = await TokenService.getAccessToken();
    await http.delete(
      Uri.parse('$chatApiBaseUrl/chats/users/$userId/block/'),
      headers: _headers(token),
    );
  }

  static Future<List<Map<String, dynamic>>> fetchBlockedUsers() async {
    final data = await _get('/chats/users/blocked/');
    final results = data['results'];
    if (results is! List) return [];
    return results.cast<Map<String, dynamic>>();
  }

  /// Converts a relative server path (e.g. /media/photo.jpg) to an absolute
  /// URL. Absolute URLs are returned unchanged. Null/empty → null.
  static String? absoluteUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    return '${Uri.parse(chatApiBaseUrl).origin}$path';
  }
}
