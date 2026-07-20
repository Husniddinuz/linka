import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../theme/app_colors.dart';

class PlusMemberCard extends StatelessWidget {
  final String plan;
  final String memberSince;
  final String nextRenewal;
  final String priceLabel;
  final VoidCallback? onTap;

  const PlusMemberCard({
    super.key,
    this.plan = 'ANNUAL',
    this.memberSince = 'Mar 14, 2026',
    this.nextRenewal = 'Mar 14, 2027',
    this.priceLabel = '240 000 UZS',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gradientEnd = Color.lerp(colors.brand, Colors.black, 0.35)!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.brand, gradientEnd],
              ),
              border: Border.all(
                color: colors.accentYellow.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned(
                  right: -18,
                  top: -20,
                  child: Icon(
                    Symbols.workspace_premium_rounded,
                    size: 110,
                    fill: 1,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Symbols.workspace_premium_rounded,
                              size: 22,
                              fill: 1,
                              color: colors.accentYellow,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      "You're PLUS",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        height: 1.1,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.18),
                                        borderRadius:
                                            BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        plan,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'All benefits unlocked · since $memberSince',
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.75),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (onTap != null)
                            Icon(
                              Symbols.chevron_right_rounded,
                              size: 20,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      color: Colors.white.withValues(alpha: 0.08),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: const Row(
                        children: [
                          _Benefit(label: 'Unlimited chat'),
                          _Benefit(label: 'Webinars & debates'),
                          _Benefit(label: 'Priority support'),
                        ],
                      ),
                    ),
                    Container(
                      color: Colors.black.withValues(alpha: 0.22),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Next renewal · $nextRenewal',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            priceLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final String label;
  const _Benefit({required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.check_rounded,
            size: 12,
            weight: 800,
            color: Colors.white.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
