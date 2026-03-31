import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// In-memory image cache. Images are downloaded once and kept in memory
/// for the lifetime of the app session.
class ImageCacheService {
  static final Map<String, MemoryImage> _cache = {};

  static Future<ImageProvider?> getImage(String url) async {
    if (_cache.containsKey(url)) return _cache[url]!;

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final provider = MemoryImage(response.bodyBytes);
        _cache[url] = provider;
        return provider;
      }
    } catch (_) {}
    return null;
  }

  static void evict(String url) {
    _cache.remove(url);
  }
}
