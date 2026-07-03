import 'package:flutter/material.dart';
import '../widgets/mock_test_styles.dart';
import 'mock_test_history_screen.dart';
import 'mock_test_list_screen.dart';
import 'tutors_screen.dart';
import 'writing_prompts_list_screen.dart';

class MockTestsHomeScreen extends StatelessWidget {
  const MockTestsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(
        context,
        title: 'Mock Tests',
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: MockTestColors.navy),
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
          const Text(
            'Choose a skill to practise a full IELTS mock test.',
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, color: MockTestColors.grey),
          ),
          const SizedBox(height: 18),
          _SkillButton(
            icon: Icons.menu_book_rounded,
            title: 'Reading',
            subtitle: '28 practice tests · 60 min each',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MockTestListScreen(testType: 'reading')),
            ),
          ),
          const SizedBox(height: 12),
          _SkillButton(
            icon: Icons.headphones_rounded,
            title: 'Listening',
            subtitle: '25 practice tests · 40 min each',
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
        decoration: mtSoftCard(radius: 18),
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
                    style: const TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: MockTestColors.navy,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, color: MockTestColors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: MockTestColors.greyLight),
          ],
        ),
      ),
    );
  }
}
