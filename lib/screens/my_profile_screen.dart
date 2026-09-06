import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/cached_avatar.dart';
import '../widgets/plus_member_card.dart';
import '../services/api_service.dart';
import '../services/app_feature_service.dart';
import '../services/auth_service.dart';
import '../services/plus_service.dart';
import '../services/share_service.dart';
import '../services/theme_service.dart';
import '../services/token_service.dart';
import '../theme/app_colors.dart';
import '../services/user_service.dart';
import '../services/wallet_service.dart';
import '../widgets/app_notify.dart';
import '../widgets/skeleton.dart';
import 'affiliate_screen.dart';
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
import 'blocked_users_screen.dart';
import 'email_settings_screen.dart';
import 'tutor_schedule_screen.dart';
import 'tutor_speaking_samples_screen.dart';
import 'tutor_writing_samples_screen.dart';
import 'tutor_my_courses_screen.dart';

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

  Future<void> _openSupport() async {
    const username = 'Linka_Support';
    final telegramUri = Uri.parse('tg://resolve?domain=$username');
    final webUri = Uri.parse('https://t.me/$username');
    try {
      if (await canLaunchUrl(telegramUri)) {
        await launchUrl(telegramUri);
        return;
      }
    } catch (_) {
      // Fall through to the web link if the Telegram app can't be opened.
    }
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      AppNotify.show(context, message: 'Could not open support chat.');
    }
  }

  void _shareMyProfile() {
    final tutorId = UserService.current?.tutorProfileId;
    if (tutorId == null) return;
    final name = '${_profile?['first_name'] ?? ''} ${_profile?['last_name'] ?? ''}'.trim();
    ShareService.shareTutorProfile(tutorId: tutorId, tutorName: name);
  }

  void _openEditProfile() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ProfileSetupScreen(
              role: _isTeacher ? 'tutor' : 'student',
              profile: _profile,
            ),
          ),
        )
        .then((_) => _loadProfile());
  }

  Future<void> _openPlusSubscription() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PlusSubscriptionScreen()),
    );
    if (changed == true && mounted) _loadPlusStatus();
  }

  String _plusPlanLabel(PlusStatus? status) {
    // The server names its own plans ("3 Months"); the codes below are only
    // for the shape of `current_plan` that comes back as a bare string.
    final title = status?.currentPlan?.title?.trim();
    if (title != null && title.isNotEmpty) return title.toUpperCase();
    switch (status?.planCode) {
      case 'yearly':
        return 'ANNUAL';
      case 'quarterly':
        return '3 MONTHS';
      case 'monthly':
        return 'MONTHLY';
    }
    return status?.planCode?.toUpperCase() ?? 'PLUS';
  }

  String _plusPriceLabel(PlusStatus? status) {
    final price = status?.currentPlan?.priceUzs;
    if (price != null && price > 0) return '${_formatPrice(price)} UZS';
    // Only reached when the status came back without a plan object. Prices as
    // set on 2026-08-26.
    switch (status?.planCode) {
      case 'yearly':
        return '799 000 UZS';
      case 'quarterly':
        return '219 000 UZS';
      case 'monthly':
        return '99 000 UZS';
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
    final colors = context.colors;
    final showPlus = !_isTeacher &&
        !_isExemptFromPlus &&
        AppFeatureService.isEnabled('plus');

    // The hero stays navy in both themes, so status bar icons must be light.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: colors.background,
        body: RefreshIndicator(
          color: Colors.white,
          backgroundColor: colors.brand,
          onRefresh: _loadProfile,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                _buildHero(context),
                const SizedBox(height: 20),
                if (showPlus) ...[
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
                  const SizedBox(height: 20),
                ],
                _SectionLabel(_isTeacher ? 'My teaching' : 'My learning'),
                _CardGroup(children: _accountRows(context)),
                const SizedBox(height: 20),
                const _SectionLabel('Preferences'),
                _CardGroup(
                  children: [
                    const _AppearanceRow(),
                    _MenuRow(
                      icon: Symbols.notifications_rounded,
                      label: 'Notifications',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const NotificationsScreen()),
                      ),
                    ),
                    const _RowDivider(),
                    _MenuRow(
                      icon: Symbols.person_off_rounded,
                      label: 'Blocked users',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const BlockedUsersScreen()),
                      ),
                    ),
                    const _RowDivider(),
                    _MenuRow(
                      icon: Symbols.alternate_email_rounded,
                      label: 'Email sign-in',
                      // Returning from this screen can have linked or unlinked
                      // an address, and the row does not show which — but
                      // UserService.current has been refreshed, so anything
                      // else on this screen reading it needs a rebuild.
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const EmailSettingsScreen()),
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const _SectionLabel('Help & about'),
                _CardGroup(
                  children: [
                    _MenuRow(
                      icon: Symbols.live_help_rounded,
                      label: 'FAQs',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FaqScreen()),
                      ),
                    ),
                    if (AppFeatureService.isEnabled('support')) ...[
                      const _RowDivider(),
                      _MenuRow(
                        icon: Symbols.support_agent_rounded,
                        label: 'Support',
                        onTap: _openSupport,
                      ),
                    ],
                    const _RowDivider(),
                    _MenuRow(
                      icon: Symbols.description_rounded,
                      label: 'Public offer',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const PublicOfferScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const _LogoutCard(),
                const SizedBox(height: 28),
                _DeleteAccountCard(
                  phoneNumber: (_profile?['phone_number'] as String?) ??
                      UserService.current?.phone,
                  email: (_profile?['email'] as String?) ??
                      UserService.current?.email,
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _accountRows(BuildContext context) {
    if (_isTeacher) {
      return [
        _MenuRow(
          icon: Symbols.calendar_month_rounded,
          label: 'My schedule',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TutorScheduleScreen()),
          ),
        ),
        const _RowDivider(),
        _MenuRow(
          icon: Symbols.ios_share_rounded,
          label: 'Share profile',
          onTap: _shareMyProfile,
        ),
        const _RowDivider(),
        _MenuRow(
          icon: Symbols.redeem_rounded,
          label: 'My promo code',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AffiliateScreen()),
          ),
        ),
        const _RowDivider(),
        _MenuRow(
          icon: Symbols.mic_rounded,
          label: 'My speaking samples',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const TutorSpeakingSamplesScreen()),
          ),
        ),
        const _RowDivider(),
        _MenuRow(
          icon: Symbols.edit_note_rounded,
          label: 'My writing samples',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const TutorWritingSamplesScreen()),
          ),
        ),
        if (AppFeatureService.isEnabled('courses')) ...[
          const _RowDivider(),
          _MenuRow(
            icon: Symbols.menu_book_rounded,
            label: 'My courses',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TutorMyCoursesScreen()),
            ),
          ),
        ],
        const _RowDivider(),
        _MenuRow(
          icon: Symbols.reviews_rounded,
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
      ];
    }
    return [
      _MenuRow(
        icon: Symbols.school_rounded,
        label: 'My lessons',
        onTap: () => widget.onNavigateToLessons?.call(),
      ),
      const _RowDivider(),
      _MenuRow(
        icon: Symbols.reviews_rounded,
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
      const _RowDivider(),
      _MenuRow(
        icon: Symbols.favorite_rounded,
        label: 'Saved tutors',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SavedTutorsScreen()),
        ),
      ),
      const _RowDivider(),
      _MenuRow(
        icon: Symbols.bookmarks_rounded,
        label: 'Saved articles',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SavedArticlesScreen()),
        ),
      ),
    ];
  }

  // ─── Hero header ──────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final colors = context.colors;
    final hero = _HeroPanel(
      profile: _profile,
      loading: _loading,
      isTeacher: _isTeacher,
      // Students get extra bottom room for the overlapping balance card.
      bottomPadding: _isTeacher ? 28.0 : 56.0,
      onEdit: _openEditProfile,
    );
    if (_isTeacher) return hero;

    // Balance card overlaps the hero's bottom edge. The trailing SizedBox
    // keeps the card inside the Stack's bounds so its taps still register.
    return Stack(
      children: [
        Column(children: [hero, const SizedBox(height: 40)]),
        Positioned(
          left: 16,
          right: 16,
          bottom: 0,
          child: _BalanceCard(brandColor: colors.brand),
        ),
      ],
    );
  }
}

// ─── Hero panel ───────────────────────────────────────────────────────────────

class _HeroPanel extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final bool loading;
  final bool isTeacher;
  final double bottomPadding;
  final VoidCallback onEdit;

  const _HeroPanel({
    required this.profile,
    required this.loading,
    required this.isTeacher,
    required this.bottomPadding,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final firstName = profile?['first_name'] ?? '';
    final lastName = profile?['last_name'] ?? '';
    final displayName = '$firstName $lastName'.trim();
    final phone = profile?['phone_number'] as String? ?? '';
    final imageUrl = profile?['profile_image'] as String?;
    final gradientEnd = Color.lerp(colors.brand, Colors.black, 0.35)!;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.brand, gradientEnd],
        ),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: ClipRRect(
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(32)),
        child: Stack(
          children: [
            // Decorative glows that keep the panel from feeling flat.
            Positioned(
              top: -50,
              right: -30,
              child: _GlowCircle(
                  size: 180, color: Colors.white.withValues(alpha: 0.05)),
            ),
            Positioned(
              bottom: -60,
              left: -40,
              child: _GlowCircle(
                  size: 200, color: Colors.white.withValues(alpha: 0.04)),
            ),
            Column(
              children: [
                const SafeArea(bottom: false, child: SizedBox.shrink()),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 40),
                      Expanded(
                        child: Center(
                          child: Text(
                            'My profile',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                          ),
                        ),
                      ),
                      _FrostedIconButton(
                        icon: Symbols.edit_rounded,
                        onTap: onEdit,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Avatar with a subtle ring.
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.transparent,
                    ),
                    child: loading
                        ? Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                            child: Icon(
                              Symbols.person_rounded,
                              color: Colors.white.withValues(alpha: 0.5),
                              size: 36,
                            ),
                          )
                        : CachedAvatar(imageUrl: imageUrl, size: 84),
                  ),
                ),
                const SizedBox(height: 14),
                if (loading)
                  Container(
                    width: 150,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      displayName.isEmpty ? '—' : displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RoleChip(isTeacher: isTeacher),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _PhoneChip(phone: phone),
                    ],
                  ],
                ),
                SizedBox(height: bottomPadding),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _FrostedIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _FrostedIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.14),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final bool isTeacher;
  const _RoleChip({required this.isTeacher});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isTeacher ? Symbols.school_rounded : Symbols.local_library_rounded,
            size: 13,
            fill: 1,
            color: Colors.white.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 4),
          Text(
            isTeacher ? 'Tutor' : 'Student',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneChip extends StatelessWidget {
  final String phone;
  const _PhoneChip({required this.phone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.call_rounded,
            size: 13,
            fill: 1,
            color: Colors.white.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 4),
          Text(
            phone,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Balance card (overlaps hero) ─────────────────────────────────────────────

class _BalanceCard extends StatefulWidget {
  final Color brandColor;
  const _BalanceCard({required this.brandColor});

  @override
  State<_BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends State<_BalanceCard> {
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

  Future<void> _onTopUp() async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const PaymentTopUpScreen()),
    );
    if (result != null && mounted) {
      // Re-fetch wallet balance from server after a successful top-up
      await _loadBalance();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Symbols.account_balance_wallet_rounded,
              color: colors.textPrimary,
              size: 24,
              opticalSize: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Balance',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                if (_loading)
                  const Skeleton(height: 20, width: 90, borderRadius: 6)
                else
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${_formatAmount(_balance ?? 0)} ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: colors.success,
                          ),
                        ),
                        TextSpan(
                          text: 'UZS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _onTopUp,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: widget.brandColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.add_rounded,
                      size: 18, color: colors.onBrand, weight: 700),
                  const SizedBox(width: 4),
                  Text(
                    'Top up',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.onBrand,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
    final colors = context.colors;
    final gradientEnd = Color.lerp(colors.brand, Colors.black, 0.35)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.brand, gradientEnd],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                top: -30,
                right: -20,
                child: _GlowCircle(
                    size: 120, color: Colors.white.withValues(alpha: 0.05)),
              ),
              // Oversized watermark glyph anchored to the right edge.
              Positioned(
                right: -14,
                bottom: -22,
                child: Icon(
                  Symbols.workspace_premium_rounded,
                  size: 110,
                  color: Colors.white.withValues(alpha: 0.06),
                  fill: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Symbols.workspace_premium_rounded,
                                size: 18,
                                fill: 1,
                                color: colors.accentYellow,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Linka PLUS',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Unlimited chat, webinars & debates,\npriority support',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Join',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colors.brand,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            Symbols.arrow_forward_rounded,
                            size: 15,
                            weight: 700,
                            color: colors.brand,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Section label ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: context.colors.textTertiary,
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
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Material(
            color: Colors.transparent,
            child: Column(children: children),
          ),
        ),
      ),
    );
  }
}

// ─── Divider ────────────────────────────────────────────────────────────────

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 66),
      child: Container(height: 0.5, color: context.colors.border),
    );
  }
}

// ─── Menu row ───────────────────────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;

  const _MenuRow({
    required this.icon,
    required this.label,
    this.destructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = destructive ? colors.error : colors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: destructive
                    ? colors.error.withValues(alpha: 0.1)
                    : colors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                opticalSize: 20,
                color: foreground,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: foreground,
                ),
              ),
            ),
            Icon(
              Symbols.chevron_right_rounded,
              color: colors.textTertiary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Appearance row with light/dark segmented pill ──────────────────────────

class _AppearanceRow extends StatelessWidget {
  const _AppearanceRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: AppFeatureService.notifier,
      builder: (context, _) {
        // Admin has locked the app to a single theme (via the light_mode /
        // dark_mode flags) — nothing left for the user to choose.
        final lightAllowed = AppFeatureService.isEnabled('light_mode');
        final darkAllowed = AppFeatureService.isEnabled('dark_mode');
        if (!lightAllowed || !darkAllowed) {
          return const SizedBox.shrink();
        }

        return Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Symbols.routine_rounded,
                      size: 20,
                      opticalSize: 20,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Appearance',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const _ThemeModePill(),
                ],
              ),
            ),
            const _RowDivider(),
          ],
        );
      },
    );
  }
}

/// Compact animated segmented control: [ ☀ | ☾ ] with a sliding thumb.
class _ThemeModePill extends StatelessWidget {
  const _ThemeModePill();

  void _select(bool dark) {
    if (ThemeService.isDark == dark) return;
    HapticFeedback.selectionClick();
    ThemeService.setDark(dark);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeService.isDarkNotifier,
      builder: (context, isDark, _) {
        final thumbColor = isDark ? colors.brand : Colors.white;
        return Container(
          width: 92,
          height: 36,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.border),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Thumb is exactly half the track, so it always shares a
              // center with the icon segment it covers.
              final half = constraints.maxWidth / 2;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    left: isDark ? half : 0,
                    top: 0,
                    bottom: 0,
                    width: half,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: thumbColor,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: colors.shadow.withValues(alpha: 0.15),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _select(false),
                          behavior: HitTestBehavior.opaque,
                          child: Center(
                            child: Icon(
                              Symbols.light_mode_rounded,
                              size: 16,
                              opticalSize: 20,
                              fill: isDark ? 0 : 1,
                              color: isDark
                                  ? colors.textTertiary
                                  : colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _select(true),
                          behavior: HitTestBehavior.opaque,
                          child: Center(
                            child: Icon(
                              Symbols.dark_mode_rounded,
                              size: 16,
                              opticalSize: 20,
                              fill: isDark ? 1 : 0,
                              color: isDark
                                  ? Colors.white
                                  : colors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

// ─── Logout card ────────────────────────────────────────────────────────────

class _LogoutCard extends StatelessWidget {
  const _LogoutCard();

  @override
  Widget build(BuildContext context) {
    return _CardGroup(
      children: [
        _MenuRow(
          icon: Symbols.logout_rounded,
          label: 'Log out',
          destructive: true,
          onTap: () => _handleLogout(context),
        ),
      ],
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.colors.surface,
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
    final colors = context.colors;
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
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.errorBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Symbols.logout_rounded,
                  color: colors.error,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Log out',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Are you sure you want to log out of your account?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: 'Cancel',
                    background: colors.surfaceAlt,
                    textColor: colors.textPrimary,
                    onTap: () => Navigator.pop(context, false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SheetButton(
                    label: 'Log out',
                    background: colors.error,
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
  /// The phone this account signed up with, or null/empty for an
  /// email-registered account.
  final String? phoneNumber;

  /// Fallback confirmation identifier when there is no phone.
  final String? email;

  const _DeleteAccountCard({this.phoneNumber, this.email});

  @override
  State<_DeleteAccountCard> createState() => _DeleteAccountCardState();
}

class _DeleteAccountCardState extends State<_DeleteAccountCard> {
  bool _deleting = false;

  Future<void> _onTap() async {
    // An account has a phone OR an email (either may be null). Confirm
    // against whichever one exists — phone first, email otherwise.
    final phone = widget.phoneNumber?.trim() ?? '';
    final email = widget.email?.trim() ?? '';
    final identifier = phone.isNotEmpty ? phone : email;
    if (identifier.isEmpty) {
      AppNotify.show(
        context,
        message: 'Unable to verify your account. Please try again later.',
      );
      return;
    }
    final isEmail = phone.isEmpty;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _DeleteAccountConfirmSheet(
          identifier: identifier,
          isEmail: isEmail,
        ),
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
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.error,
                ),
              )
            else
              Icon(
                Symbols.delete_forever_rounded,
                color: context.colors.error,
                size: 16,
              ),
            const SizedBox(width: 6),
            Text(
              'Delete account',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.colors.error,
                decoration: TextDecoration.underline,
                decorationColor: context.colors.error,
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
  /// What the user must retype: their phone number, or their email address
  /// when the account was registered by email.
  final String identifier;
  final bool isEmail;

  const _DeleteAccountConfirmSheet({
    required this.identifier,
    required this.isEmail,
  });

  @override
  State<_DeleteAccountConfirmSheet> createState() =>
      _DeleteAccountConfirmSheetState();
}

class _DeleteAccountConfirmSheetState
    extends State<_DeleteAccountConfirmSheet> {
  final _controller = TextEditingController();

  String _normalize(String s) => widget.isEmail
      ? s.trim().toLowerCase()
      : s.replaceAll(RegExp(r'[\s\-()]'), '');

  bool get _matches =>
      _normalize(_controller.text) == _normalize(widget.identifier);

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
                  color: context.colors.border,
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
                  color: context.colors.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Symbols.warning_rounded,
                  color: context.colors.error,
                  size: 32,
                  fill: 1,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Permanently delete account?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: context.colors.error,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action is IRREVERSIBLE.\n'
              'Your profile, lessons, messages, reviews, wallet balance, and '
              'all related data will be permanently deleted and cannot be '
              'recovered.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: context.colors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.colors.errorBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: context.colors.error.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isEmail
                        ? 'To confirm, type your email address:'
                        : 'To confirm, type your phone number:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.identifier,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _controller,
                    keyboardType: widget.isEmail
                        ? TextInputType.emailAddress
                        : TextInputType.phone,
                    autocorrect: false,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.isEmail
                          ? 'Enter email address'
                          : 'Enter phone number',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: context.colors.textTertiary,
                        fontWeight: FontWeight.w400,
                      ),
                      filled: true,
                      fillColor: context.colors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: context.colors.error,
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: context.colors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: context.colors.error,
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
                    background: context.colors.surfaceAlt,
                    textColor: context.colors.textPrimary,
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
                            ? context.colors.error
                            : context.colors.error.withValues(alpha: 0.35),
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
