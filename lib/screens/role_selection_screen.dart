import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'auth_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  String? _selectedRole;

  void _continue() {
    if (_selectedRole == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuthScreen(role: _selectedRole!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              const Text(
                'You are\nregistering as ...',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF272942),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Please select one of the options so we can continue.',
                style: TextStyle(
                  color: Color(0xFFAAAAAA),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),

              // Cards in a row
              Row(
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: _RoleCard(
                        title: 'Tutor',
                        imagePath: 'assets/images/tutors/auth-tutor.svg',
                        isSelected: _selectedRole == 'tutor',
                        onTap: () => setState(() => _selectedRole = 'tutor'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: _RoleCard(
                        title: 'Student',
                        imagePath: 'assets/images/tutors/auth-student.svg',
                        isSelected: _selectedRole == 'student',
                        onTap: () => setState(() => _selectedRole = 'student'),
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selectedRole != null ? _continue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF272942),
                    disabledBackgroundColor: const Color(0xFFE0E0E0),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: const Color(0xFFAAAAAA),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String imagePath;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.imagePath,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF5C542)
                : const Color(0xFFE5E5E5),
            width: isSelected ? 2 : 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFF5C542).withAlpha(51),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              imagePath,
              height: 80,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF272942),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
