import 'package:flutter/material.dart';

import '../models/student_progress.dart';
import '../screens/student_progress_screen.dart';
import '../services/student_progress_service.dart';
import '../theme/app_colors.dart';

/// Where the student stands, on the screen they actually land on — the
/// website's dashboard strip, on the phone.
///
/// Self-contained: it fetches, and it collapses to nothing while loading, on
/// failure, or when there is no history at all. A student who signed up a
/// minute ago should see the practice grid, not a row of dashes; the numbers
/// appear once there is something to count. Every tile opens the full
/// progress screen.
class ProgressStrip extends StatefulWidget {
  const ProgressStrip({super.key});

  @override
  State<ProgressStrip> createState() => ProgressStripState();
}

class ProgressStripState extends State<ProgressStrip> {
  StudentProgress? _progress;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Re-fetches — called by the home screen's pull-to-refresh so a band
  /// earned a minute ago shows up without relaunching the app.
  Future<void> refresh() async {
    try {
      final progress = await StudentProgressService.fetch();
      if (mounted) setState(() => _progress = progress);
    } catch (_) {
      // Leave whatever was shown; a failed refresh is not worth blanking.
    }
  }

  void _open(BuildContext context, ProgressTileKind _) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StudentProgressScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    if (progress == null || !progress.hasAny) return const SizedBox.shrink();
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'YOUR PROGRESS',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                    height: 1.0,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _open(context, ProgressTileKind.writing),
                  child: Text(
                    'See all',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textTertiary,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ProgressTiles(progress: progress, onOpen: _open),
          ),
        ],
      ),
    );
  }
}
