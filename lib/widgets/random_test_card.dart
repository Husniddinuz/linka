import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'mock_test_styles.dart';

/// The "Try a random test" row that sits at the top of every test list.
///
/// Students who open a list of 28 identical-looking tests often close it
/// again without picking one. This gives them a single tap that decides for
/// them. Styled like the list rows below it, with a shuffle badge in place of
/// the test number so it reads as an action rather than test zero.
class RandomTestCard extends StatelessWidget {
  const RandomTestCard({
    super.key,
    required this.subtitle,
    required this.onTap,
    this.busy = false,
  });

  final String subtitle;
  final VoidCallback onTap;

  /// True while the tap is still resolving (the hub has to fetch the lists
  /// before it can pick). Shows a spinner and ignores further taps.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: mtSoftCard(context, border: Border.all(color: colors.border)),
        child: Row(
          children: [
            MtAvatar(icon: Icons.shuffle_rounded, background: colors.accentBlue),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Try a random test',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            if (busy)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: colors.textTertiary),
              )
            else
              Icon(Icons.chevron_right_rounded, color: colors.textTertiary, size: 24),
          ],
        ),
      ),
    );
  }
}
