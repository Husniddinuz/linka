import 'package:flutter/material.dart';

/// Semantic color tokens for the app's flat, navy-and-white design language.
///
/// The app has no ThemeData-driven styling historically — screens reference
/// hardcoded hex literals directly (e.g. `Color(0xFF272942)`). These tokens
/// give each of those legacy literals a themed home: [brand]/[accentYellow]/
/// etc. stay constant across light/dark (brand identity), while [textPrimary],
/// [surface] and friends flip so the UI actually re-skins in dark mode.
class AppColors extends ThemeExtension<AppColors> {
  final Color background; // Scaffold background
  final Color surface; // Card/sheet background (was Colors.white)
  final Color surfaceAlt; // Soft grey container/chip background
  final Color textPrimary; // Headings, primary navy text & icons
  final Color textSecondary; // Body secondary grey text
  final Color textTertiary; // Placeholder/hint/disabled grey
  final Color border; // Hairline dividers and outlines
  final Color brand; // Constant navy brand fill (buttons, badges, avatars)
  final Color onBrand; // Text/icon color on top of [brand] fills
  final Color accentYellow;
  final Color accentBlue;
  final Color success;
  final Color successBg;
  final Color error;
  final Color errorBg;
  final Color shadow;

  /// The AI coach's room. It is a cloud of lit dots, and light needs a dark
  /// room: the same sphere on a white card is grey grit. So these three are
  /// deliberately identical in both themes — a room the student steps into,
  /// the way a video call is dark whatever the rest of the app is doing.
  /// [coachGlow] is the near, hot end of a dot; the far end is the persona's
  /// own accent, which the API sends.
  final Color coachStage;
  final Color coachStageEdge;
  final Color coachGlow;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.brand,
    required this.onBrand,
    required this.accentYellow,
    required this.accentBlue,
    required this.success,
    required this.successBg,
    required this.error,
    required this.errorBg,
    required this.shadow,
    required this.coachStage,
    required this.coachStageEdge,
    required this.coachGlow,
  });

  static const light = AppColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF5F5F7),
    textPrimary: Color(0xFF272942),
    textSecondary: Color(0xFF6C6C6C),
    textTertiary: Color(0xFFAAAAAA),
    border: Color(0xFFEEEEEE),
    brand: Color(0xFF272942),
    onBrand: Color(0xFFFFFFFF),
    accentYellow: Color(0xFFF5C542),
    accentBlue: Color(0xFF5B7FD4),
    success: Color(0xFF27AE60),
    successBg: Color(0xFFEEF7EE),
    error: Color(0xFFE74C3C),
    errorBg: Color(0xFFFCECEC),
    shadow: Color(0xFF000000),
    coachStage: Color(0xFF0A0F1E),
    coachStageEdge: Color(0xFF141C33),
    coachGlow: Color(0xFFFFFFFF),
  );

  static const dark = AppColors(
    background: Color(0xFF121218),
    surface: Color(0xFF1C1D28),
    surfaceAlt: Color(0xFF262835),
    textPrimary: Color(0xFFF2F2F7),
    textSecondary: Color(0xFFB4B4BE),
    textTertiary: Color(0xFF8A8A96),
    border: Color(0xFF33333F),
    brand: Color(0xFF3D3F63),
    onBrand: Color(0xFFFFFFFF),
    accentYellow: Color(0xFFF5C542),
    accentBlue: Color(0xFF7B9AE0),
    success: Color(0xFF34C77B),
    successBg: Color(0xFF1B2E22),
    error: Color(0xFFFF6B6B),
    errorBg: Color(0xFF3A2020),
    shadow: Color(0xFF000000),
    coachStage: Color(0xFF0A0F1E),
    coachStageEdge: Color(0xFF141C33),
    coachGlow: Color(0xFFFFFFFF),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? border,
    Color? brand,
    Color? onBrand,
    Color? accentYellow,
    Color? accentBlue,
    Color? success,
    Color? successBg,
    Color? error,
    Color? errorBg,
    Color? shadow,
    Color? coachStage,
    Color? coachStageEdge,
    Color? coachGlow,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      border: border ?? this.border,
      brand: brand ?? this.brand,
      onBrand: onBrand ?? this.onBrand,
      accentYellow: accentYellow ?? this.accentYellow,
      accentBlue: accentBlue ?? this.accentBlue,
      success: success ?? this.success,
      successBg: successBg ?? this.successBg,
      error: error ?? this.error,
      errorBg: errorBg ?? this.errorBg,
      shadow: shadow ?? this.shadow,
      coachStage: coachStage ?? this.coachStage,
      coachStageEdge: coachStageEdge ?? this.coachStageEdge,
      coachGlow: coachGlow ?? this.coachGlow,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      border: Color.lerp(border, other.border, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      accentYellow: Color.lerp(accentYellow, other.accentYellow, t)!,
      accentBlue: Color.lerp(accentBlue, other.accentBlue, t)!,
      success: Color.lerp(success, other.success, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorBg: Color.lerp(errorBg, other.errorBg, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      coachStage: Color.lerp(coachStage, other.coachStage, t)!,
      coachStageEdge: Color.lerp(coachStageEdge, other.coachStageEdge, t)!,
      coachGlow: Color.lerp(coachGlow, other.coachGlow, t)!,
    );
  }
}

/// Shorthand for `Theme.of(context).extension<AppColors>()!`.
extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
