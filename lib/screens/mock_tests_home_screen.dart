import 'package:flutter/material.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'ielts_booking_screen.dart';
import 'mock_test_history_screen.dart';
import 'mock_test_list_screen.dart';
import 'speaking_samples_list_screen.dart';
import 'tutors_screen.dart';
import 'writing_prompts_list_screen.dart';
import 'writing_samples_list_screen.dart';
import '../theme/app_colors.dart';

class MockTestsHomeScreen extends StatefulWidget {
  const MockTestsHomeScreen({super.key});

  @override
  State<MockTestsHomeScreen> createState() => _MockTestsHomeScreenState();
}

class _MockTestsHomeScreenState extends State<MockTestsHomeScreen> {
  /// Live test counts keyed by test type, so newly published tests show up in
  /// the subtitles without an app release. Null until loaded (or if the fetch
  /// fails) — the subtitle then omits the count rather than showing a stale one.
  int? _readingCount;
  int? _listeningCount;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final counts = await Future.wait([
      MockTestService.fetchTests('reading').then((t) => t.length).catchError((_) => -1),
      MockTestService.fetchTests('listening').then((t) => t.length).catchError((_) => -1),
    ]);
    if (!mounted) return;
    setState(() {
      if (counts[0] >= 0) _readingCount = counts[0];
      if (counts[1] >= 0) _listeningCount = counts[1];
    });
  }

  static String _testsSubtitle(int? count, String minutes) =>
      count == null ? 'Full practice tests · $minutes each' : '$count practice tests · $minutes each';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: mtAppBar(
        context,
        title: 'Mock Tests',
        actions: [
          IconButton(
            icon: Icon(Icons.history_rounded, color: context.colors.textPrimary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MockTestHistoryScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Text(
            'Choose a skill to practise a full IELTS mock test.',
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, color: context.colors.textSecondary),
          ),
          const SizedBox(height: 18),
          _SkillButton(
            icon: Icons.menu_book_rounded,
            title: 'Reading',
            subtitle: _testsSubtitle(_readingCount, '60 min'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MockTestListScreen(testType: 'reading')),
            ),
          ),
          const SizedBox(height: 12),
          _SkillButton(
            icon: Icons.headphones_rounded,
            title: 'Listening',
            subtitle: _testsSubtitle(_listeningCount, '40 min'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MockTestListScreen(testType: 'listening')),
            ),
          ),
          const SizedBox(height: 12),
          _SkillButton(
            icon: Icons.edit_note_rounded,
            title: 'Writing',
            subtitle: 'Task 1 & Task 2 · graded by AI',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WritingPromptsListScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SkillButton(
            icon: Icons.mic_rounded,
            title: 'Speaking',
            subtitle: 'Practise live with a tutor',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TutorsScreen(showBackButton: true)),
            ),
          ),
          const SizedBox(height: 12),
          _SkillButton(
            icon: Icons.badge_rounded,
            title: 'Book Real IELTS Test',
            subtitle: 'Register for an official test date',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IeltsBookingScreen()),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'SAMPLES FROM REAL TESTS',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: context.colors.textTertiary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          _SkillButton(
            icon: Icons.record_voice_over_rounded,
            title: 'Speaking Samples',
            subtitle: 'Real test answers with band scores',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SpeakingSamplesListScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SkillButton(
            icon: Icons.auto_stories_rounded,
            title: 'Writing Samples',
            subtitle: 'Real essays with band scores',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WritingSamplesListScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillButton extends StatelessWidget {
  const _SkillButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: mtSoftCard(context, radius: 18),
        child: Row(
          children: [
            MtAvatar(icon: icon, size: 52),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, color: context.colors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.colors.textTertiary),
          ],
        ),
      ),
    );
  }
}
