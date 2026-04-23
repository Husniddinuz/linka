import 'package:flutter/material.dart';

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
    const gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFD8D674), Color(0xFF8EC79A), Color(0xFF2E4E5C)],
      stops: [0.0, 0.38, 1.0],
    );

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
              gradient: gradient,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x38272942),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      const _PlusCrest(),
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
                                    fontWeight: FontWeight.w700,
                                    fontSize: 17,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    plan,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'All benefits unlocked · since $memberSince',
                              style: const TextStyle(
                                color: Color(0xD1FFFFFF),
                                fontWeight: FontWeight.w500,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: Color(0xB3FFFFFF),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: Colors.white.withValues(alpha: 0.10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: const [
                      _Benefit(label: 'Unlimited chat', dot: Color(0xFF1CB219)),
                      _Benefit(
                        label: 'Webinar & Debates',
                        dot: Color(0xFFFFC65C),
                      ),
                      _Benefit(
                        label: 'Priority support',
                        dot: Color(0xFFFF8D28),
                      ),
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
                        style: const TextStyle(
                          color: Color(0xB8FFFFFF),
                          fontWeight: FontWeight.w700,
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
          ),
        ),
      ),
    );
  }
}

class _PlusCrest extends StatelessWidget {
  const _PlusCrest();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: Icon(Icons.auto_awesome, size: 22, color: Color(0xFF2E4E5C)),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final String label;
  final Color dot;
  const _Benefit({required this.label, required this.dot});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
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
