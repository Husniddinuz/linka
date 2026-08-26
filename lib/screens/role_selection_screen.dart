import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_constants.dart';
import '../services/app_feature_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import 'auth_screen.dart';
import 'email_auth_screen.dart';

const _telegramBlue = Color(0xFF229ED9);

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  String? _selectedRole;

  void _loginWithPhone() {
    if (_selectedRole == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuthScreen(role: _selectedRole!),
      ),
    );
  }

  void _loginWithEmail() {
    if (_selectedRole == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmailAuthScreen(role: _selectedRole!),
      ),
    );
  }

  Future<void> _loginWithTelegram() async {
    final role = _selectedRole;
    if (role == null) return;
    // The bot asks for the phone via a "share contact" button, then replies
    // with a https://linkaapp.uz/tg-login deep link back into the app.
    final uri = Uri.parse('https://t.me/$telegramBotUsername?start=$role');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      AppNotify.show(context, message: 'Could not open Telegram');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when remote feature flags refresh (e.g. telegram_login toggled).
    return ValueListenableBuilder<int>(
      valueListenable: AppFeatureService.notifier,
      builder: (context, _, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final telegramLoginEnabled = AppFeatureService.isEnabled('telegram_login');
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Text(
                'You are\nregistering as ...',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Please select one of the options so we can continue.',
                style: TextStyle(
                  color: context.colors.textTertiary,
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
              // Email, Telegram, phone — the same order the web sign-in uses,
              // so a student who starts on one and finishes on the other is
              // offered the routes in the same places. Email leads because it
              // is the channel that costs nothing to send on, never disappears
              // into a carrier filter, and works for students whose number is
              // not +998.
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selectedRole != null ? _loginWithEmail : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.brand,
                    disabledBackgroundColor: context.colors.border,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: context.colors.textTertiary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mail_outline_rounded,
                        size: 20,
                        color: _selectedRole != null
                            ? Colors.white
                            : context.colors.textTertiary,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Continue with email',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (telegramLoginEnabled) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        _selectedRole != null ? _loginWithTelegram : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _telegramBlue,
                      disabledBackgroundColor: context.colors.border,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: context.colors.textTertiary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          'assets/images/icons/telegram.svg',
                          height: 22,
                          colorFilter: ColorFilter.mode(
                            _selectedRole != null
                                ? Colors.white
                                : context.colors.textTertiary,
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Login via Telegram',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Text rather than a third button. Phone still registers and
              // signs in exactly as the two above do — it gets quieter weight,
              // not less capability.
              Center(
                child: TextButton(
                  onPressed: _selectedRole != null ? _loginWithPhone : null,
                  child: Text(
                    'Use phone number instead',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _selectedRole != null
                          ? context.colors.textPrimary
                          : context.colors.textTertiary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
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
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? colors.accentYellow : colors.border,
            width: isSelected ? 2 : 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: colors.accentYellow.withAlpha(51),
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
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
