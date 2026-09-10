import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The "PLUS" pill that marks a paying account on a profile header.
///
/// Yellow on navy text in both themes and on either backdrop: the badge sits on
/// the navy hero of your own profile and on the white surface of someone
/// else's, and a themed fill would disappear into one of them.
class PlusBadge extends StatelessWidget {
  /// Shrinks the pill for tight rows (beside a name rather than beside chips).
  final bool compact;

  const PlusBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 11.0 : 13.0;
    final fontSize = compact ? 10.0 : 12.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD451), Color(0xFFF5B81E)],
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.workspace_premium_rounded,
            size: iconSize,
            fill: 1,
            color: const Color(0xFF272942),
          ),
          SizedBox(width: compact ? 3 : 4),
          Text(
            'PLUS',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              height: 1.0,
              color: const Color(0xFF272942),
            ),
          ),
        ],
      ),
    );
  }
}
