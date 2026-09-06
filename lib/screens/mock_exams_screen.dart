import 'package:flutter/material.dart';
import '../widgets/mock_test_styles.dart';
import 'ai_coach_screen.dart';
import 'mock_test_history_screen.dart';
import 'mock_test_list_screen.dart';
import 'student_progress_screen.dart';
import 'tutors_screen.dart';
import 'writing_prompts_list_screen.dart';
import '../theme/app_colors.dart';

class MockExamsScreen extends StatelessWidget {
  const MockExamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: mtAppBar(
        context,
        title: 'Mock Exams',
        actions: [
          IconButton(
            tooltip: 'My progress',
            icon: Icon(Icons.insights_rounded, color: context.colors.textPrimary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StudentProgressScreen()),
            ),
          ),
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
          _ExamTypeButton(
            icon: Icons.menu_book_rounded,
            title: 'Reading',
            subtitle: '28 practice tests · 60 min each',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MockTestListScreen(testType: 'reading')),
            ),
          ),
          const SizedBox(height: 12),
          _ExamTypeButton(
            icon: Icons.headphones_rounded,
            title: 'Listening',
            subtitle: '25 practice tests · 40 min each',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MockTestListScreen(testType: 'listening')),
            ),
          ),
          const SizedBox(height: 12),
          _ExamTypeButton(
            icon: Icons.edit_note_rounded,
            title: 'Writing',
            subtitle: 'Task 1 & Task 2 · graded by AI',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WritingPromptsListScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _ExamTypeButton(
            icon: Icons.mic_rounded,
            title: 'Speaking',
            subtitle: 'Practise live with a tutor',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TutorsScreen(showBackButton: true)),
            ),
          ),
          const SizedBox(height: 12),
          // Under Speaking: it answers the same want at the hours when no
          // tutor is free, which is most of them.
          _ExamTypeButton(
            icon: Icons.auto_awesome_rounded,
            title: 'AI Coach',
            subtitle: 'Talk out loud · scored sound by sound',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiCoachScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamTypeButton extends StatelessWidget {
  const _ExamTypeButton({
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
