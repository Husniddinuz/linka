import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_feature_service.dart';

/// Persists the user's light/dark preference and exposes it as a
/// [ValueNotifier] so [MaterialApp] can rebuild immediately on toggle.
///
/// Admins can remotely kill either theme via the `light_mode` / `dark_mode`
/// app feature flags (see [AppFeatureService]). Whenever those flags change
/// — including on startup, once cached/fetched — [_syncWithFlags] forces the
/// user off a theme that just got disabled, onto whichever one is still
/// allowed.
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
    AppFeatureService.notifier.addListener(_syncWithFlags);
  }

  static Future<void> setDark(bool value) async {
    isDarkNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }

  /// If the theme the user is currently on has been disabled server-side
  /// while the other one is still allowed, force-switch them onto it. If
  /// both (or neither) are disabled — an admin misconfiguration — leave the
  /// current theme alone rather than fight the user.
  static void _syncWithFlags() {
    final lightAllowed = AppFeatureService.isEnabled('light_mode');
    final darkAllowed = AppFeatureService.isEnabled('dark_mode');
    if (isDark && !darkAllowed && lightAllowed) {
      setDark(false);
    } else if (!isDark && !lightAllowed && darkAllowed) {
      setDark(true);
    }
  }
}
