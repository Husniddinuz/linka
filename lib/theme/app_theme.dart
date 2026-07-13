import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Light/dark [ThemeData] pair, both carrying an [AppColors] extension so
/// screens can read semantic tokens via `context.colors` instead of
/// hardcoded hex literals.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(AppColors.light, Brightness.light);
  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final base = ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF272942),
        brightness: brightness,
      ),
      fontFamily: 'Inter',
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      cardColor: colors.surface,
      dividerColor: colors.border,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        surfaceTintColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
      ),
      iconTheme: IconThemeData(color: colors.textPrimary),
    );
    return base.copyWith(extensions: [colors]);
  }
}
