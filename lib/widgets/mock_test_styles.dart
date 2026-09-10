import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/plus_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';

/// Legacy light-mode palette for the Mock Tests feature.
///
/// Superseded by [AppColors] / `context.colors`, which re-skins in dark mode.
/// Only the IELTS registration flow (`ielts_*_screen.dart`) still reads these
/// directly; everything else in Mock Tests goes through `context.colors`.
/// Prefer `context.colors` in new code — these constants never flip.
class MockTestColors {
  static const navy = Color(0xFF272942);
  static const grey = Color(0xFF6C6C6C);
  static const greyLight = Color(0xFFAAAAAA);
  static const softBg = Color(0xFFF6F6F6);
  static const chipBg = Color(0xFFF2F2F4);
  static const divider = Color(0xFFEEEEEE);
  static const yellow = Color(0xFFF5C542);
  static const yellowDark = Color(0xFFF5B81E);
  static const green = Color(0xFF27AE60);
  static const greenBg = Color(0xFFEEF7EE);
  static const red = Color(0xFFE55353);
  static const redBg = Color(0xFFFCECEC);
}

/// Soft filled container used for list rows and panels. Takes [context] so the
/// default fill follows the active theme.
BoxDecoration mtSoftCard(BuildContext context, {Color? color, double radius = 16, Border? border}) {
  return BoxDecoration(
    color: color ?? context.colors.surfaceAlt,
    borderRadius: BorderRadius.circular(radius),
    border: border,
  );
}

AppBar mtAppBar(BuildContext context, {required String title, List<Widget>? actions, PreferredSizeWidget? bottom}) {
  final colors = context.colors;
  return AppBar(
    backgroundColor: colors.background,
    elevation: 0,
    surfaceTintColor: colors.background,
    leading: IconButton(
      onPressed: () => Navigator.pop(context),
      icon: Icon(Symbols.chevron_left_rounded, color: colors.textPrimary, size: 30),
    ),
    title: Text(
      title,
      style: TextStyle(
        fontFamily: 'SF Pro',
        color: colors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      overflow: TextOverflow.ellipsis,
    ),
    centerTitle: true,
    actions: actions,
    bottom: bottom,
  );
}

/// Full-width primary action button matching the app's navy/white style.
class MtPrimaryButton extends StatelessWidget {
  const MtPrimaryButton({super.key, required this.label, this.onPressed, this.loading = false});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.brand,
          foregroundColor: colors.onBrand,
          disabledBackgroundColor: colors.brand.withValues(alpha: 0.5),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: loading
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: colors.onBrand),
              )
            : Text(
                label,
                style: const TextStyle(fontFamily: 'SF Pro', fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}

/// Pill selector matching the topic chips on the booking screen — navy fill
/// when selected, white with a navy outline otherwise.
class MtChip extends StatelessWidget {
  const MtChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? colors.brand : colors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? colors.brand : colors.border, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: selected ? colors.onBrand : colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Circular navy badge used for list-row leading icons/numbers.
class MtAvatar extends StatelessWidget {
  const MtAvatar({super.key, this.icon, this.text, this.size = 46, this.background});
  final IconData? icon;
  final String? text;
  final double size;

  /// Defaults to the themed brand fill — a const default can't read the theme,
  /// hence nullable rather than `= MockTestColors.navy`.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background ?? colors.brand, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, color: colors.onBrand, size: size * 0.46)
          : Text(
              text ?? '',
              style: TextStyle(color: colors.onBrand, fontWeight: FontWeight.w700, fontSize: size * 0.36),
            ),
    );
  }
}

/// Small rounded pill, e.g. for the countdown timer or a status label.
class MtPill extends StatelessWidget {
  const MtPill({
    super.key,
    required this.child,
    this.background,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  });

  final Widget child;

  /// Defaults to the themed soft fill — see [MtAvatar.background].
  final Color? background;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? context.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

/// True when Reading/Listening/Writing content should be shown locked for
/// the current user (no active Plus, not the exempt QA account). Fails open
/// on a network hiccup so a status-check failure never blocks access.
Future<bool> mtCheckContentLocked() async {
  if (UserService.isExemptFromPlus) return false;
  try {
    final status = await PlusService.getMyStatus();
    return !status.isActive;
  } catch (_) {
    return false;
  }
}

