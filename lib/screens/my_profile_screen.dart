import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/cached_avatar.dart';
import '../widgets/plus_member_card.dart';
import '../services/api_service.dart';
import '../services/app_feature_service.dart';
import '../services/auth_service.dart';
import '../services/plus_service.dart';
import '../services/token_service.dart';
import '../services/user_service.dart';
import '../services/wallet_service.dart';
import '../widgets/app_notify.dart';
import '../widgets/skeleton.dart';
import 'profile_setup_screen.dart';
import 'plus_subscription_screen.dart';
import 'saved_tutors_screen.dart';
import 'role_selection_screen.dart';
import 'faq_screen.dart';
import 'notifications_screen.dart';
import 'my_reviews_screen.dart';
import 'saved_articles_screen.dart';
import 'payment_topup_screen.dart';
import 'public_offer_screen.dart';
import 'tutor_schedule_screen.dart';

class MyProfileScreen extends StatefulWidget {
  final VoidCallback? onNavigateToLessons;
  const MyProfileScreen({super.key, this.onNavigateToLessons});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _isTeacher = UserService.current?.isTeacher ?? false;
  bool _isExemptFromPlus = false;
  PlusStatus? _plusStatus;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (UserService.current == null) {
      final cached = await UserService.getCachedIsTeacher();
      if (mounted && cached != null) setState(() => _isTeacher = cached);
    }
    _loadProfile();
    _loadPlusStatus();
  }

  Future<void> _loadPlusStatus() async {
    if (_isTeacher) return;
    try {
      final status = await PlusService.getMyStatus();
      if (!mounted) return;
      setState(() => _plusStatus = status);
    } catch (_) {
      // Leave _plusStatus null — the card is hidden when we can't confirm.
    }
  }

  Future<void> _openPlusSubscription() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PlusSubscriptionScreen()),
    );
    if (changed == true && mounted) _loadPlusStatus();
  }

  String _plusPlanLabel(PlusStatus? status) {
    switch (status?.planCode) {
      case 'yearly':
        return 'ANNUAL';
      case 'monthly':
        return 'MONTHLY';
    }
    return status?.planCode?.toUpperCase() ?? 'PLUS';
  }

  String _plusPriceLabel(PlusStatus? status) {
    final price = status?.currentPlan?.priceUzs;
    if (price != null && price > 0) return '${_formatPrice(price)} UZS';
    switch (status?.planCode) {
      case 'yearly':
        return '240 000 UZS';
      case 'monthly':
        return '30 000 UZS';
    }
    return '';
  }

  String _formatPrice(int price) {
    final str = price.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = months[(date.month - 1).clamp(0, 11)];
    return '$month ${date.day}, ${date.year}';
  }

  Future<void> _loadProfile() async {
    try {
      final me = UserService.current ?? await UserService.fetchMe();
      final isTeacher = me.isTeacher;
      if (mounted && isTeacher != _isTeacher) {
        setState(() => _isTeacher = isTeacher);
      }
      final path = isTeacher
          ? '/tutors/${me.tutorProfileId}/'
          : '/student/profile/';
      final result = await ApiService.get(path);
      final profile = (result['data'] is Map<String, dynamic>)
          ? result['data'] as Map<String, dynamic>
          : result;
      profile.putIfAbsent('phone_number', () => me.phone);
      final exempt = me.phone.replaceAll(RegExp(r'[^\d]'), '') == '998101002233';
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
        _isExemptFromPlus = exempt;
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
              child: RefreshIndicator(
                color: const Color(0xFF272942),
                onRefresh: _loadProfile,
                child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                                              role: _isTeacher
                                                  ? 'tutor'
                                                  : 'student',
                                              profile: _profile,
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
                    if (!_isTeacher) ...[
                      if (!_isExemptFromPlus &&
                          AppFeatureService.isEnabled('plus')) ...[
                        if (_plusStatus?.isActive == true)
                          PlusMemberCard(
                            plan: _plusPlanLabel(_plusStatus),
                            memberSince: _formatDate(_plusStatus?.since),
                            nextRenewal: _formatDate(_plusStatus?.plusUntil),
                            priceLabel: _plusPriceLabel(_plusStatus),
                            onTap: null,
                          )
                        else
                          _JoinPlusBanner(onTap: _openPlusSubscription),
                        const SizedBox(height: 16),
                      ],
                      _CardGroup(children: [_BalanceRow()]),
                      const SizedBox(height: 16),
                    ],
                    _CardGroup(
                      children: [
                        if (!_isTeacher) ...[
                          _MenuRow(
                            icon: 'assets/images/buttons/my-lessons.svg',
                            label: 'My lessons',
                            onTap: () => widget.onNavigateToLessons?.call(),
                          ),
                          const _Divider(),
                        ],
                        if (_isTeacher) ...[
                          _MenuRow(
                            icon: 'assets/images/icons/calendar_outline_20.svg',
                            label: 'My schedule',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const TutorScheduleScreen()),
                            ),
                          ),
                          const _Divider(),
                        ],
                        _MenuRow(
                          icon: 'assets/images/buttons/my-reviews.svg',
                          label: 'My reviews',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MyReviewsScreen(
                                isTutor: _isTeacher,
                                tutorProfileId: UserService.current?.tutorProfileId,
                              ),
                            ),
                          ),
                        ),
                        if (!_isTeacher) ...[
                          const _Divider(),
                          _MenuRow(
                            icon: 'assets/images/buttons/saved-tutors.svg',
                            label: 'Saved tutors',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const SavedTutorsScreen()),
                            ),
                          ),
                          const _Divider(),
                          _MenuRow(
                            icon: 'assets/images/buttons/saved-articles.svg',
                            label: 'Saved articles',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const SavedArticlesScreen()),
                            ),
                          ),
                        ],
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
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const PublicOfferScreen()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const _LogoutCard(),
                    const SizedBox(height: 24),
                    _DeleteAccountCard(
                      phoneNumber: _profile?['phone_number'] as String?,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
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
  final VoidCallback onTap;
  const _JoinPlusBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Image.asset(
          'assets/images/branding/profile-join-plus.png',
          width: double.infinity,
          fit: BoxFit.fitWidth,
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

class _BalanceRow extends StatefulWidget {
  @override
  State<_BalanceRow> createState() => _BalanceRowState();
}

class _BalanceRowState extends State<_BalanceRow> {
  int? _balance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final cached = WalletService.cachedBalance;
    if (cached != null) {
      _balance = cached;
      _loading = false;
    }
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    try {
      final balance = await WalletService.getBalance();
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _formatAmount(int amount) {
    final str = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Balance',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF999999),
                ),
              ),
              const SizedBox(height: 4),
              if (_loading)
                const Skeleton(height: 22, width: 90, borderRadius: 6)
              else
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${_formatAmount(_balance ?? 0)} ',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF27AE60),
                        ),
                      ),
                      const TextSpan(
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
          GestureDetector(
            onTap: _onTopUp,
            behavior: HitTestBehavior.opaque,
            child: SvgPicture.asset(
              'assets/images/buttons/top-up.svg',
              width: 28,
              height: 28,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onTopUp() async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const PaymentTopUpScreen()),
    );
    if (result != null && mounted) {
      // Re-fetch wallet balance from server after a successful top-up
      await _loadBalance();
    }
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
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const _LogoutConfirmSheet(),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

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
    await UserService.clear();
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

// ─── Logout confirmation sheet ──────────────────────────────────────────────

class _LogoutConfirmSheet extends StatelessWidget {
  const _LogoutConfirmSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SvgPicture.asset(
              'assets/images/buttons/logout.svg',
              width: 40,
              height: 40,
            ),
            const SizedBox(height: 16),
            const Text(
              'Log out',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF272942),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Are you sure you want to log out of your account?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Color(0xFF999999),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: 'Cancel',
                    background: const Color(0xFFF2F2F2),
                    textColor: const Color(0xFF272942),
                    onTap: () => Navigator.pop(context, false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SheetButton(
                    label: 'Log out',
                    background: const Color(0xFFE74C3C),
                    textColor: Colors.white,
                    onTap: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color textColor;
  final VoidCallback onTap;

  const _SheetButton({
    required this.label,
    required this.background,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

// ─── Delete account card ──────────────────────────────────────────────────────

class _DeleteAccountCard extends StatefulWidget {
  final String? phoneNumber;
  const _DeleteAccountCard({this.phoneNumber});

  @override
  State<_DeleteAccountCard> createState() => _DeleteAccountCardState();
}

class _DeleteAccountCardState extends State<_DeleteAccountCard> {
  bool _deleting = false;

  Future<void> _onTap() async {
    final phone = widget.phoneNumber;
    if (phone == null || phone.isEmpty) {
      AppNotify.show(
        context,
        message: 'Unable to verify your phone number. Please try again later.',
      );
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _DeleteAccountConfirmSheet(phoneNumber: phone),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ApiService.delete('/users/me/');
      await TokenService.clearTokens();
      await UserService.clear();
      if (!mounted) return;
      AppNotify.show(
        context,
        message: 'Account deleted',
        type: NotifyType.success,
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: _deleting ? null : _onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_deleting)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFE74C3C),
                ),
              )
            else
              const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFE74C3C),
                size: 16,
              ),
            const SizedBox(width: 6),
            const Text(
              'Delete account',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFFE74C3C),
                decoration: TextDecoration.underline,
                decorationColor: Color(0xFFE74C3C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Delete account confirmation sheet ────────────────────────────────────────

class _DeleteAccountConfirmSheet extends StatefulWidget {
  final String phoneNumber;
  const _DeleteAccountConfirmSheet({required this.phoneNumber});

  @override
  State<_DeleteAccountConfirmSheet> createState() =>
      _DeleteAccountConfirmSheetState();
}

class _DeleteAccountConfirmSheetState
    extends State<_DeleteAccountConfirmSheet> {
  final _controller = TextEditingController();

  String _normalize(String s) => s.replaceAll(RegExp(r'[\s\-()]'), '');

  bool get _matches =>
      _normalize(_controller.text) == _normalize(widget.phoneNumber);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE74C3C).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFE74C3C),
                  size: 34,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Permanently delete account?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE74C3C),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action is IRREVERSIBLE.\n'
              'Your profile, lessons, messages, reviews, wallet balance, and '
              'all related data will be permanently deleted and cannot be '
              'recovered.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: Color(0xFF555555),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFE74C3C).withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'To confirm, type your phone number:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF272942),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.phoneNumber,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF272942),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF272942),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter phone number',
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFBBBBBB),
                        fontWeight: FontWeight.w400,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFFE74C3C),
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: const Color(0xFFE74C3C)
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFFE74C3C),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: 'Cancel',
                    background: const Color(0xFFF2F2F2),
                    textColor: const Color(0xFF272942),
                    onTap: () => Navigator.pop(context, false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _matches
                        ? () => Navigator.pop(context, true)
                        : null,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _matches
                            ? const Color(0xFFE74C3C)
                            : const Color(0xFFE74C3C).withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'Delete forever',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
