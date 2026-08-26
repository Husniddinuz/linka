import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// The one text field a promo code is ever typed into — by a student applying
/// a tutor's code at Plus checkout, and by the tutor naming their own.
///
/// Both ends normalise the same way the server does: letters and digits only,
/// upper-cased, 24 characters. A code that is dictated in a lesson and typed
/// back with a dash in it has to reach the API as the same code.
class PromoCodeField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  const PromoCodeField({
    super.key,
    required this.controller,
    required this.hintText,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.done,
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted?.call(),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
        LengthLimitingTextInputFormatter(24),
        _UpperCaseFormatter(),
      ],
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: colors.textPrimary,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          color: colors.textTertiary,
        ),
        filled: true,
        fillColor: colors.surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.brand, width: 1.5),
        ),
      ),
    );
  }
}

/// Codes are stored upper-case; typing one lower-case should not produce a
/// different code from the one printed in a tutor's bio.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    if (upper == newValue.text) return newValue;
    return newValue.copyWith(text: upper);
  }
}
