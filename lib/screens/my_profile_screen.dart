import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/cached_avatar.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/token_service.dart';
import '../widgets/app_notify.dart';
import '../widgets/skeleton.dart';
import 'profile_setup_screen.dart';
import 'plus_subscription_screen.dart';
import 'saved_tutors_screen.dart';
import 'role_selection_screen.dart';
import 'faq_screen.dart';
import 'notifications_screen.dart';
import 'saved_articles_screen.dart';

class MyProfileScreen extends StatefulWidget {
  final VoidCallback? onNavigateToLessons;
  const MyProfileScreen({super.key, this.onNavigateToLessons});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final result = await ApiService.get('/student/profile/');
      if (!mounted) return;
      setState(() {
        _profile = result['data'] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // White safe area for status bar
          SafeArea(bottom: false, child: const SizedBox.shrink()),
          // Scrollable content on gray background
          Expanded(
            child: Container(
              color: const Color(0xFFF5F5F7),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // White section: header + profile card
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                        ),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Center(
                                    child: Text(
                                      'My profile',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF272942),
                                      ),
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.of(context)
                                        .push(
                                          MaterialPageRoute(
                                            builder: (_) => ProfileSetupScreen(
                                              role:
                                                  _profile?['role']
                                                      as String? ??
                                                  'student',
                                              firstName:
                                                  _profile?['first_name']
                                                      as String?,
                                              lastName:
                                                  _profile?['last_name']
                                                      as String?,
                                              gender:
                                                  _profile?['gender']
                                                      as String?,
                                              englishLevel:
                                                  _profile?['englishLevel']
                                                      as String?,
                                              profileImageUrl:
                                                  _profile?['profile_image']
                                                      as String?,
                                            ),
                                          ),
                                        )
                                        .then((_) => _loadProfile());
                                  },
                                  child: SvgPicture.asset(
                                    'assets/images/buttons/profile-edit.svg',
                                    width: 24,
                                    height: 24,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          _ProfileCard(profile: _profile, loading: _loading),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),

                    // Gray section: rest of content
                    const SizedBox(height: 16),
                    _JoinPlusBanner(),
                    const SizedBox(height: 16),
                    _CardGroup(
                      children: [
                        _MenuRow(
                          icon: 'assets/images/buttons/wallet.svg',
                          label: 'My wallet',
                          onTap: () {},
                        ),
                        const _Divider(),
                        _BalanceRow(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _CardGroup(
                      children: [
                        _MenuRow(
                          icon: 'assets/images/buttons/my-lessons.svg',
                          label: 'My lessons',
                          onTap: () => widget.onNavigateToLessons?.call(),
                        ),
                        const _Divider(),
                        _MenuRow(
                          icon: 'assets/images/buttons/my-reviews.svg',
                          label: 'My reviews',
                          onTap: () {},
                        ),
                        const _Divider(),
                        _MenuRow(
                          icon: 'assets/images/buttons/saved-tutors.svg',
                          label: 'Saved tutors',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SavedTutorsScreen()),
                          ),
                        ),
                        const _Divider(),
                        _MenuRow(
                          icon: 'assets/images/buttons/saved-articles.svg',
                          label: 'Saved articles',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SavedArticlesScreen()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _CardGroup(
                      children: [
                        _MenuRow(
                          icon: 'assets/images/buttons/notifications.svg',
                          label: 'Notifications',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                          ),
                        ),
                        const _Divider(),
                        // _MenuRow(
                        //   icon: 'assets/images/buttons/help_outline_20.svg',
                        //   label: 'Help center',
                        //   onTap: () {},
                        // ),
                        // const _Divider(),
                        _MenuRow(
                          icon: 'assets/images/buttons/faqs.svg',
                          label: 'FAQs',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const FaqScreen()),
                          ),
                        ),
                        const _Divider(),
                        _MenuRow(
                          icon: 'assets/images/buttons/public-offer.svg',
                          label: 'Public offer',
                          onTap: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const _LogoutCard(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Profile card ───────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final bool loading;

  const _ProfileCard({this.profile, this.loading = true});

  @override
  Widget build(BuildContext context) {
    final firstName = profile?['first_name'] ?? '';
    final lastName = profile?['last_name'] ?? '';
    final imageUrl = profile?['profile_image'] as String?;
    final displayName = loading ? '...' : '$firstName\n$lastName'.trim();

    final avatarImage = CachedAvatar(imageUrl: imageUrl, size: 64);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Avatar with white ring
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.white, width: 2),
              ),
              padding: const EdgeInsets.all(6),
              child: loading
                  ? const Skeleton(height: 64, width: 64, circle: true)
                  : avatarImage,
            ),
            const SizedBox(width: 12),
            // Name & phone on white background
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: loading
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Skeleton(height: 18, width: 120, borderRadius: 6),
                          SizedBox(height: 6),
                          Skeleton(height: 18, width: 100, borderRadius: 6),
                          SizedBox(height: 10),
                          Skeleton(height: 14, width: 150, borderRadius: 6),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF272942),
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            profile?['phone_number'] as String? ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF999999),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Join PLUS banner ───────────────────────────────────────────────────────

class _JoinPlusBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PlusSubscriptionScreen()),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Image.asset(
            'assets/images/branding/profile-join-plus.png',
            width: double.infinity,
            fit: BoxFit.fitWidth,
          ),
        ),
      ),
    );
  }
}

// ─── Card group ─────────────────────────────────────────────────────────────

class _CardGroup extends StatelessWidget {
  final List<Widget> children;
  const _CardGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: children),
      ),
    );
  }
}

// ─── Divider ────────────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Container(height: 0.5, color: const Color(0xFFEEEEEE)),
    );
  }
}

// ─── Menu row ───────────────────────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SvgPicture.asset(icon, width: 22, height: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF272942),
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFCCCCCC),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Balance row ────────────────────────────────────────────────────────────

class _BalanceRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Balance',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF999999),
                ),
              ),
              SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '0 ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF27AE60),
                      ),
                    ),
                    TextSpan(
                      text: 'UZS',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF999999),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          // Plus icon for top-up
          SvgPicture.asset(
            'assets/images/buttons/top-up.svg',
            width: 28,
            height: 28,
          ),
        ],
      ),
    );
  }
}

// ─── Logout card ────────────────────────────────────────────────────────────

class _LogoutCard extends StatelessWidget {
  const _LogoutCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: GestureDetector(
          onTap: () => _handleLogout(context),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                SvgPicture.asset(
                  'assets/images/buttons/logout.svg',
                  width: 22,
                  height: 22,
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Log out',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFE74C3C),
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFCCCCCC),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    try {
      final access = await TokenService.getAccessToken();
      final refresh = await TokenService.getRefreshToken();
      if (access != null && refresh != null) {
        await AuthService.logout(refreshToken: refresh, accessToken: access);
      }
    } catch (_) {
      // logout is best-effort
    }
    await TokenService.clearTokens();
    if (!context.mounted) return;
    AppNotify.show(
      context,
      message: 'Logged out successfully',
      type: NotifyType.success,
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }
}
