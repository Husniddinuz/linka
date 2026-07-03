import 'package:flutter/material.dart';

/// Shared colors/decorations for the Mock Tests feature, matching the app's
/// existing flat design language (navy + soft grey containers, no Material
/// card shadows) — see lesson_card.dart / podcasts_list_screen.dart.
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

BoxDecoration mtSoftCard({Color? color, double radius = 16, Border? border}) {
  return BoxDecoration(
    color: color ?? MockTestColors.softBg,
    borderRadius: BorderRadius.circular(radius),
    border: border,
  );
}

AppBar mtAppBar(BuildContext context, {required String title, List<Widget>? actions, PreferredSizeWidget? bottom}) {
  return AppBar(
    backgroundColor: Colors.white,
    elevation: 0,
    surfaceTintColor: Colors.white,
    leading: IconButton(
      onPressed: () => Navigator.pop(context),
      icon: const Icon(Icons.chevron_left_rounded, color: MockTestColors.navy, size: 30),
    ),
    title: Text(
      title,
      style: const TextStyle(
        fontFamily: 'SF Pro',
        color: MockTestColors.navy,
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
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: MockTestColors.navy,
          foregroundColor: Colors.white,
          disabledBackgroundColor: MockTestColors.navy.withValues(alpha: 0.5),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? MockTestColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? MockTestColors.navy : const Color(0xFFDDDDDD), width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : MockTestColors.navy,
          ),
        ),
      ),
    );
  }
}

/// Circular navy badge used for list-row leading icons/numbers.
class MtAvatar extends StatelessWidget {
  const MtAvatar({super.key, this.icon, this.text, this.size = 46, this.background = MockTestColors.navy});
  final IconData? icon;
  final String? text;
  final double size;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, color: Colors.white, size: size * 0.46)
          : Text(
              text ?? '',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.36),
            ),
    );
  }
}

/// Small rounded pill, e.g. for the countdown timer or a status label.
class MtPill extends StatelessWidget {
  const MtPill({
    super.key,
    required this.child,
    this.background = MockTestColors.chipBg,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  });

  final Widget child;
  final Color background;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: child,
    );
  }
}
