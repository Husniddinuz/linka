import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class NumKey extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const NumKey({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox(height: 56);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: label == '⌫'
            ? Icon(
                Icons.backspace_outlined,
                color: context.colors.textPrimary,
                size: 22,
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
      ),
    );
  }
}

class NumPad extends StatelessWidget {
  final void Function(String digit) onDigit;
  final VoidCallback onDelete;

  const NumPad({super.key, required this.onDigit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        children: [
          for (final row in [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['', '0', '⌫'],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: row
                    .map(
                      (key) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: NumKey(
                            label: key,
                            onTap: key.isEmpty
                                ? null
                                : key == '⌫'
                                    ? onDelete
                                    : () => onDigit(key),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}
