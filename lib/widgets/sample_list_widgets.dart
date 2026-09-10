import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import 'mock_test_styles.dart';

/// The list furniture shared by the sample libraries.
///
/// Speaking samples, the Speaking topic bank and Writing samples all index the
/// same shape of thing — pick a tutor, then pick one of their answers — and
/// they sit a tap or two apart under Mock Tests. Drawn from three private
/// copies they drifted into three different-looking screens, so the rows,
/// chips, search field and empty states live here once and every library reads
/// as one library.

/// Rounded artwork (a tutor photo, usually), sized by the caller. Falls back to
/// a brand-filled tile so a missing or broken image never leaves a grey hole.
class SampleArtwork extends StatelessWidget {
  const SampleArtwork({
    super.key,
    required this.imageUrl,
    required this.size,
    this.fallbackIcon = Symbols.person_rounded,
  });

  final String? imageUrl;
  final double size;

  /// What the fallback tile shows — the skill this library is about, so a
  /// tutor with no photo still reads as "a recorded answer" or "an essay".
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: SizedBox(
        width: size,
        height: size,
        child: (imageUrl != null && imageUrl!.isNotEmpty)
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    SampleArtworkFallback(size: size, icon: fallbackIcon),
              )
            : SampleArtworkFallback(size: size, icon: fallbackIcon),
      ),
    );
  }
}

class SampleArtworkFallback extends StatelessWidget {
  const SampleArtworkFallback({
    super.key,
    required this.size,
    this.icon = Symbols.person_rounded,
  });

  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.brand, colors.brand.withValues(alpha: 0.78)],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.36, color: colors.onBrand),
    );
  }
}

/// An answer row's artwork: the band score that answer earned.
///
/// The band is what varies between one tutor's answers, and it is the reason a
/// student picks one — unlike the tutor's photo, which is the same face on
/// every row once the tutor has been chosen.
class SampleBandTile extends StatelessWidget {
  const SampleBandTile({
    super.key,
    required this.score,
    this.emptyIcon = Symbols.workspace_premium_rounded,
    this.size = 62,
  });

  final String? score;

  /// Shown in place of the band when a sample has none.
  final IconData emptyIcon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.brand, colors.brand.withValues(alpha: 0.78)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (score == null)
            Icon(emptyIcon, size: 26, color: colors.onBrand)
          else ...[
            Text(
              'BAND',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: colors.onBrand.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              score!,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 21,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: colors.onBrand,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// States outright what the page is. These libraries used to open on a grid of
/// tutor photos, which students read as the Tutors directory and tapped
/// expecting to book someone; a sentence at the top costs one row and settles
/// it.
class SampleIntroHeader extends StatelessWidget {
  const SampleIntroHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.accentYellow.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 20, color: colors.textPrimary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 12,
                    height: 1.3,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The row that takes a student from reading or listening to producing
/// something of their own — offered where they are already hunting for a
/// question, rather than behind a nav entry nobody would look for.
class SampleCtaRow extends StatelessWidget {
  const SampleCtaRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: mtSoftCard(context, radius: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: colors.accentBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 11.5,
                          height: 1.3,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Symbols.chevron_right_rounded, size: 20, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class SampleSearchField extends StatelessWidget {
  const SampleSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.query,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontFamily: 'SF Pro', fontSize: 14, color: colors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          hintText: hint,
          hintStyle: TextStyle(fontFamily: 'SF Pro', fontSize: 14, color: colors.textTertiary),
          prefixIcon: Icon(Symbols.search_rounded, size: 20, color: colors.textTertiary),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Symbols.close_rounded, size: 18, color: colors.textTertiary),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: colors.surfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class SampleChip extends StatelessWidget {
  const SampleChip({
    super.key,
    required this.label,
    required this.color,
    required this.background,
    this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class SampleEmptyState extends StatelessWidget {
  const SampleEmptyState({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'SF Pro',
            color: context.colors.textSecondary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class SampleErrorState extends StatelessWidget {
  const SampleErrorState({super.key, required this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Failed to load: $error',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'SF Pro',
            color: context.colors.textSecondary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
