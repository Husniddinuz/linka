import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_constants.dart';

/// Remote feature flags for temporarily closing sections of the app without
/// shipping a new build. Backed by GET /app-features/, which is reachable
/// without authentication so it can be loaded on the splash screen.
///
/// Keys are looked up via [isEnabled]; missing keys default to enabled so a
/// network failure or stale schema never blacks out the whole UI.
class AppFeatureService {
  static const _cacheKey = 'app_features_map';

  static Map<String, bool> _map = {};

  /// Bumped on every successful refresh (cache or network). Screens that
  /// should react to flag changes mid-session can [ValueListenableBuilder]
  /// on this notifier.
  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  static bool _refreshing = false;

  /// Returns `true` if [key] is unknown — safer than hiding sections on a
  /// schema mismatch or empty cache.
  static bool isEnabled(String key) {
    return _map[key] ?? true;
  }

  /// Loads cached flags from disk, then kicks off a network refresh in the
  /// background. Call from the splash screen before navigating.
  static Future<void> init() async {
    await _loadCached();
    unawaited(refresh());
  }

  static Future<void> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) {
        return;
      }
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _map = {
        for (final entry in json.entries)
          if (entry.value is bool) entry.key: entry.value as bool,
      };
      notifier.value++;
    } catch (_) {}
  }

  /// Pulls the latest flags from the server. Silent on failure — callers
  /// fall back to the last cached value (or `true` defaults).
  static Future<void> refresh() async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    final url = '$apiBaseUrl/app-features/';
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawMap = data['map'] as Map<String, dynamic>? ?? const {};
      final next = <String, bool>{
        for (final entry in rawMap.entries)
          if (entry.value is bool) entry.key: entry.value as bool,
      };
      if (mapEquals(_map, next)) {
        return;
      }
      _map = next;
      notifier.value++;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(_map));
    } on TimeoutException {
      // Keep cache on timeout.
    } on SocketException {
      // Keep cache while offline.
    } catch (_) {
      // Keep cache on any other error.
    } finally {
      _refreshing = false;
    }
  }
}
