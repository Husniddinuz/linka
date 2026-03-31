import 'package:shared_preferences/shared_preferences.dart';

class TokenService {
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get _instance async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    final prefs = await _instance;
    await prefs.setString(_accessKey, access);
    await prefs.setString(_refreshKey, refresh);
  }

  static Future<String?> getAccessToken() async {
    final prefs = await _instance;
    return prefs.getString(_accessKey);
  }

  static Future<String?> getRefreshToken() async {
    final prefs = await _instance;
    return prefs.getString(_refreshKey);
  }

  static Future<void> clearTokens() async {
    final prefs = await _instance;
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null;
  }
}
