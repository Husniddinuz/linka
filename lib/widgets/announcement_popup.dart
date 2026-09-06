import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/announcement.dart';
import '../theme/app_colors.dart';
import 'new_badge.dart';

/// The "what's new" popup: an ad-style card for a freshly added course or
/// feature. Resolves to `true` when the user taps the call-to-action and
/// `false` when they close it; the caller navigates, so it controls the
/// order of pop and push on the navigator.
Future<bool> showAnnouncementPopup(BuildContext context, Announcement item) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => AnnouncementCard(item: item),
  );
  return result ?? false;
}

class AnnouncementCard extends StatelessWidget {
  final Announcement item;
  const AnnouncementCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final width = MediaQuery.sizeOf(context).width;
    // Phones get a near-edge card; tablets a fixed-width one so the banner
    // never stretches into a strip.
    final cardWidth = width >= 600 ? 420.0 : width - 48;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: cardWidth),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(item: item),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        item.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      if (item.body.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          item.body,
                          textAlign: TextAlign.center,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w400,
                            color: colors.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.brand,
                            foregroundColor: colors.onBrand,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  item.ctaLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'SF Pro',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Symbols.arrow_forward, size: 18, weight: 600),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.textTertiary,
                          minimumSize: const Size.fromHeight(40),
                        ),
                        child: const Text(
                          'Maybe later',
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
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

/// Banner image when the card has one, otherwise a brand-navy block with a
/// spark — either way with the NEW ribbon and a close control on top.
class _Header extends StatelessWidget {
  final Announcement item;
  const _Header({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final image = item.imageUrl;

    Widget fallback() => Container(
          color: colors.brand,
          child: Center(
            child: Icon(
              item.isCourse ? Symbols.school : Symbols.auto_awesome,
              size: 44,
              color: colors.accentYellow,
              fill: 1,
            ),
          ),
        );

    return AspectRatio(
      aspectRatio: image != null ? 16 / 9 : 16 / 7,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            Image.network(
              image,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback(),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : fallback(),
            )
          else
            fallback(),
          const Positioned(
            top: 14,
            left: 14,
            child: NewBadge(onColored: true),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
