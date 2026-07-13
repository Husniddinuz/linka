import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's light/dark preference and exposes it as a
/// [ValueNotifier] so [MaterialApp] can rebuild immediately on toggle.
class ThemeService {
  ThemeService._();

  static const _prefsKey = 'dark_mode_enabled';

  static final ValueNotifier<bool> isDarkNotifier = ValueNotifier<bool>(false);

  static bool get isDark => isDarkNotifier.value;

  /// Loads the saved preference. Call once during startup, before
  /// [runApp], so the first frame renders in the right theme.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    isDarkNotifier.value = prefs.getBool(_prefsKey) ?? false;
  }

  static Future<void> setDark(bool value) async {
    isDarkNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }
}
