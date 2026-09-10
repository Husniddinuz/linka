import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The Task 1 / Task 2 switcher shared by the Writing prompt list and the
/// Writing samples list.
///
/// It lives here because both screens have the same problem to solve: Task 1
/// outnumbers Task 2 by enough that stacking the two made students scroll past
/// a screen of charts and conclude Task 2 was never published. One control,
/// one look, whichever list you came in through.

class TaskSegmentLabel {
  const TaskSegmentLabel(this.title, this.caption, this.count);
  final String title;
  final String caption;
  final int count;
}

/// The task switcher, as a segmented control rather than an underlined TabBar.
///
/// The old bar sat on a hardcoded white plate, which in dark mode was a white
/// stripe across the top of a dark screen. This one is built from theme
/// tokens, and being a filled pill it also carries what the underline could
/// not: what each paper actually is, and how many tasks are behind it.
class TaskSegments extends StatelessWidget {
  const TaskSegments({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.labels,
  });

  final int selected;
  final ValueChanged<int> onSelect;
  final List<TaskSegmentLabel> labels;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: selected == i ? colors.brand : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              labels[i].title,
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: selected == i ? colors.onBrand : colors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: selected == i
                                    ? colors.onBrand.withValues(alpha: 0.22)
                                    : colors.background,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${labels[i].count}',
                                style: TextStyle(
                                  fontFamily: 'SF Pro',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: selected == i ? colors.onBrand : colors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          labels[i].caption,
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: selected == i
                                ? colors.onBrand.withValues(alpha: 0.75)
                                : colors.textTertiary,
                          ),
                        ),
                      ],
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
