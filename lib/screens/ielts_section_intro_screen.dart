import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import 'ielts_course_screen.dart';

/// The first stop of every IELTS course section: how the section works,
/// before Unit 1. Pops `true` when the student taps the start button, which
/// is what marks the intro as done on the path.
class IeltsSectionIntroScreen extends StatelessWidget {
  const IeltsSectionIntroScreen({
    super.key,
    required this.part,
    required this.unitCount,
    required this.owned,
    required this.priceLabel,
  });

  final IeltsPart part;
  final int unitCount;
  final bool owned;

  /// The subscription's price, e.g. "99 000 UZS/month"; null when unknown.
  final String? priceLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final steps = <(IconData, String, String)>[
      (
        Symbols.play_circle_rounded,
        'Watch the lesson',
        'Every unit is a short video lesson on ${part.label}.',
      ),
      (
        Symbols.stairs_2_rounded,
        'Go step by step',
        'Units open in order — finish one to unlock the next.',
      ),
      (
        Symbols.route_rounded,
        'Follow your path',
        'The path lights up as you go. Finish all $unitCount units to '
            'complete the section.',
      ),
      owned
          ? (
              Symbols.verified_rounded,
              'Unlocked',
              'All $unitCount units are open to you.',
            )
          : (
              Symbols.lock_open_rounded,
              'Unit 1 is free',
              'Try it first, then subscribe'
                  '${priceLabel == null ? '' : ' for $priceLabel'} to open '
                  'units 2–$unitCount and every other section.',
            ),
    ];

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Symbols.arrow_back_rounded,
                      color: c.textPrimary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${part.label} · Intro',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // balances the back button
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: c.success,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: Color.lerp(c.success, Colors.black, 0.28)!,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(part.icon, size: 44, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'How the ${part.label} course works',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    part.section.description.trim().isNotEmpty
                        ? part.section.description.trim()
                        : '$unitCount units, one path. Here is what to expect.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 14,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  for (final (i, step) in steps.indexed)
                    _Step(
                      number: i + 1,
                      icon: step.$1,
                      title: step.$2,
                      body: step.$3,
                      last: i == steps.length - 1,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Got it — start Unit 1',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One numbered step, joined to the next by a short rail.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
    required this.last,
  });

  final int number;
  final IconData icon;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 22, color: c.textPrimary),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 3,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: c.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: last ? 0 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'STEP $number',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800,
                      color: c.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 14,
                      color: c.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
