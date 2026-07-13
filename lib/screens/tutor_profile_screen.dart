import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';
import '../services/api_service.dart';
import '../services/app_feature_service.dart';
import '../services/share_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import '../widgets/cached_avatar.dart';
import '../widgets/skeleton.dart';
import 'availability_screen.dart';

class TutorProfileScreen extends StatefulWidget {
  final int tutorId;
  const TutorProfileScreen({super.key, required this.tutorId});

  @override
  State<TutorProfileScreen> createState() => _TutorProfileScreenState();
}

class _TutorProfileScreenState extends State<TutorProfileScreen> {
  Map<String, dynamic>? _tutor;
  List<Map<String, dynamic>> _reviews = const [];
  bool _loading = true;
  bool _reviewsLoading = true;
  bool _isBookmarked = false;
  bool _bookmarkLoading = false;

  @override
  void initState() {
    super.initState();
    _loadTutor();
    _loadReviews();
  }

  Future<void> _loadTutor() async {
    try {
      final result = await ApiService.get('/tutors/${widget.tutorId}/');
      if (!mounted) return;
      setState(() {
        _tutor = result;
        _isBookmarked = result['is_bookmarked'] as bool? ?? false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadReviews() async {
    try {
      final result = await ApiService.getList('/tutors/${widget.tutorId}/reviews/');
      if (!mounted) return;
      setState(() {
        _reviews = result.cast<Map<String, dynamic>>();
        _reviewsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _reviewsLoading = false);
    }
  }

  Future<void> _toggleBookmark() async {
    if (_bookmarkLoading) return;
    setState(() => _bookmarkLoading = true);
    try {
      if (_isBookmarked) {
        await ApiService.delete('/student/saved-tutors/${widget.tutorId}/');
      } else {
        await ApiService.post('/student/saved-tutors/', {'tutor_id': widget.tutorId});
      }
      if (mounted) setState(() => _isBookmarked = !_isBookmarked);
    } catch (_) {}
    if (mounted) setState(() => _bookmarkLoading = false);
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

  void _openAvailability() {
    final t = _tutor;
    if (t == null) return;
    if (!AppFeatureService.isEnabled('bookings')) {
      AppNotify.show(
        context,
        message: 'Booking is temporarily unavailable. Please try again later.',
        type: NotifyType.info,
      );
      return;
    }
    final rawExp = t['experience'];
    final expStr = rawExp is int
        ? '+$rawExp yrs'
        : rawExp is String
            ? '+${RegExp(r'(\d+)').firstMatch(rawExp)?.group(1) ?? '0'} yrs'
            : '+0 yrs';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AvailabilityScreen(
          tutorId: widget.tutorId,
          tutorName: '${t['first_name'] ?? ''} ${t['last_name'] ?? ''}'.trim(),
          tutorImage: t['profile_image'] as String? ?? '',
          experience: expStr,
          ieltsScore: (t['ielts_score'] as num?)?.toDouble() ?? 0,
          lessonPrices: (t['lesson_prices'] as List<dynamic>? ?? [])
              .map((p) => p as Map<String, dynamic>)
              .toList(),
        ),
      ),
    );
  }

  String _formatScore(num? score) {
    if (score == null) return '0.0';
    final d = score.toDouble();
    return d % 1 == 0 ? '${d.toInt()}.0' : '$d';
  }

  void _shareProfile() {
    final t = _tutor;
    final name = '${t?['first_name'] ?? ''} ${t?['last_name'] ?? ''}'.trim();
    ShareService.shareTutorProfile(tutorId: widget.tutorId, tutorName: name);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: context.colors.background,
        body: const SafeArea(
          child: SingleChildScrollView(
            physics: NeverScrollableScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(height: 340, borderRadius: 24),
                  SizedBox(height: 20),
                  Skeleton(width: 180, height: 22, borderRadius: 6),
                  SizedBox(height: 10),
                  Skeleton(width: 120, height: 14, borderRadius: 6),
                  SizedBox(height: 24),
                  Skeleton(height: 90, borderRadius: 16),
                  SizedBox(height: 20),
                  Skeleton(height: 120, borderRadius: 16),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final t = _tutor;
    final name = '${t?['first_name'] ?? ''} ${t?['last_name'] ?? ''}'.trim();
    final imageUrl = t?['profile_image'] as String?;
    final rawExp = t?['experience'];
    final experience = rawExp is int
        ? rawExp
        : rawExp is String
            ? (int.tryParse(RegExp(r'(\d+)').firstMatch(rawExp)?.group(1) ?? '') ?? 0)
            : 0;
    final ieltsScore = (t?['ielts_score'] as num?)?.toDouble() ?? 0;
    final scores = [
      ('Listening', _formatScore(t?['listening_score'])),
      ('Reading', _formatScore(t?['reading_score'])),
      ('Writing', _formatScore(t?['writing_score'])),
      ('Speaking', _formatScore(t?['speaking_score'])),
    ];
    final isFeatured = t?['pin_status'] as bool? ?? false;
    final isEnrollable = t?['is_enrollable'] as bool? ?? true;
    final hasCertificate = (t?['ielts_certificate'] as String?)?.isNotEmpty ?? false;
    final ratings = _reviews.map((r) => (r['rating'] as num?)?.toDouble() ?? 0).toList();
    final avgRating = ratings.isEmpty ? null : ratings.reduce((a, b) => a + b) / ratings.length;
    final reviewCount = _reviews.length;

    return Scaffold(
      backgroundColor: context.colors.surfaceAlt,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Surface top section ──────────────────────────────────────
                  Container(
                    color: context.colors.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProfileHero(
                          name: name,
                          imageUrl: imageUrl,
                          experience: experience,
                          ieltsScore: ieltsScore,
                          isFeatured: isFeatured,
                          isBookmarked: _isBookmarked,
                          avgRating: avgRating,
                          reviewCount: reviewCount,
                          reviewsLoading: _reviewsLoading,
                          onBookmarkTap: _toggleBookmark,
                          onShareTap: _shareProfile,
                          onBackTap: () => Navigator.of(context).pop(),
                        ),
                        if (hasCertificate) ...[
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _CertificateBadge(
                              onTap: () => _showCertificate(t!['ielts_certificate'] as String),
                            ),
                          ),
                        ],
                        if (t?['intro_video'] != null) ...[
                          const SizedBox(height: 16),
                          _TutorVideo(url: t!['intro_video'] as String),
                          const SizedBox(height: 16),
                        ] else
                          const SizedBox(height: 16),
                        // IELTS scores grid
                        _ScoresGrid(scores: scores),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Bio ─────────────────────────────────────────────────────
                  Builder(builder: (_) {
                    final bio = (t?['about_me'] as String?)?.trim() ?? '';
                    if (bio.isEmpty) return const SizedBox.shrink();
                    return _PremiumCard(
                      child: _BioSection(bio: bio),
                    );
                  }),

                  Builder(builder: (_) {
                    final bio = (t?['about_me'] as String?)?.trim() ?? '';
                    return bio.isEmpty ? const SizedBox.shrink() : const SizedBox(height: 16);
                  }),

                  // ── Lesson duration (info) ──────────────────────────────────
                  Builder(builder: (_) {
                    final prices = t?['lesson_prices'] as List<dynamic>? ?? [];
                    if (prices.isEmpty) return const SizedBox.shrink();
                    final durations = prices.map((p) {
                      final m = p as Map<String, dynamic>;
                      final mins = m['duration_minutes'] as int? ?? 0;
                      final priceStr = m['price']?.toString() ?? '0';
                      final price = double.tryParse(priceStr)?.toInt() ?? 0;
                      final formatted = _formatAmount(price);
                      return ('$mins min', '$formatted UZS');
                    }).toList();
                    return _PremiumCard(
                      child: _LessonDurationSection(durations: durations),
                    );
                  }),

                  const SizedBox(height: 16),

                  // ── Reviews ────────────────────────────────────────────────
                  if (_reviewsLoading || _reviews.isNotEmpty) ...[
                    _PremiumCard(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 0),
                      child: _ReviewsSection(
                        reviews: _reviews,
                        loading: _reviewsLoading,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),

          // ── Sticky Book Lesson button ───────────────────────────────────────
          Container(
            color: context.colors.surface,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: isEnrollable ? _openAvailability : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.brand,
                  disabledBackgroundColor: context.colors.border,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: context.colors.brand.withValues(alpha: 0.35),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  isEnrollable ? 'Book Lesson' : 'Fully booked',
                  style: const TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCertificate(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  height: 200,
                  color: context.colors.surface,
                  child: const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── App bar ───────────────────────────────────────────────────────────────────

// ─── Tutor video ──────────────────────────────────────────────────────────────

class _TutorVideo extends StatefulWidget {
  final String url;
  const _TutorVideo({required this.url});

  @override
  State<_TutorVideo> createState() => _TutorVideoState();
}

class _TutorVideoState extends State<_TutorVideo> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _initialized = true);
    }).catchError((_) {
      // Video URL is invalid or unreachable — hide the player silently.
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _showControls = true;

  void _togglePlay() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _showControls = true;
      } else {
        _controller.play();
        _hideControlsAfterDelay();
      }
    });
  }

  void _hideControlsAfterDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onTapVideo() {
    setState(() => _showControls = !_showControls);
    if (_showControls && _controller.value.isPlaying) {
      _hideControlsAfterDelay();
    }
  }

  void _seekBy(int seconds) {
    final current = _controller.value.position;
    final target = current + Duration(seconds: seconds);
    _controller.seekTo(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: _initialized
              ? GestureDetector(
                  onTap: _onTapVideo,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_controller),
                      AnimatedOpacity(
                        opacity: _showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: IgnorePointer(
                          ignoring: !_showControls,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Rewind 15s
                              GestureDetector(
                                onTap: () => _seekBy(-15),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: SvgPicture.asset(
                                      'assets/images/branding/video-back.svg',
                                      width: 28,
                                      height: 28,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),
                              // Play/Pause
                              GestureDetector(
                                onTap: _togglePlay,
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _controller.value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),
                              // Forward 15s
                              GestureDetector(
                                onTap: () => _seekBy(15),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: SvgPicture.asset(
                                      'assets/images/branding/video-front.svg',
                                      width: 28,
                                      height: 28,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  color: context.colors.border,
                  child: Center(
                    child: CircularProgressIndicator(color: context.colors.textPrimary),
                  ),
                ),
        ),
      ),
    );
  }
}

// ─── Profile hero ──────────────────────────────────────────────────────────────

class _ProfileHero extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final int experience;
  final double ieltsScore;
  final bool isFeatured;
  final bool isBookmarked;
  final double? avgRating;
  final int reviewCount;
  final bool reviewsLoading;
  final VoidCallback onBookmarkTap;
  final VoidCallback onShareTap;
  final VoidCallback onBackTap;

  const _ProfileHero({
    required this.name,
    this.imageUrl,
    required this.experience,
    required this.ieltsScore,
    required this.isFeatured,
    required this.isBookmarked,
    required this.avgRating,
    required this.reviewCount,
    required this.reviewsLoading,
    required this.onBookmarkTap,
    required this.onShareTap,
    required this.onBackTap,
  });

  @override
  Widget build(BuildContext context) {
    final scoreLabel = ieltsScore % 1 == 0 ? ieltsScore.toInt().toString() : ieltsScore.toString();
    return SizedBox(
      height: 340,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Portrait photo
          imageUrl != null
              ? Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: context.colors.border,
                    child: Icon(Icons.person, size: 64, color: context.colors.textTertiary),
                  ),
                )
              : Container(
                  color: context.colors.border,
                  child: Icon(Icons.person, size: 64, color: context.colors.textTertiary),
                ),

          // Top scrim for icon legibility
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Colors.transparent],
                stops: [0.0, 0.28],
              ),
            ),
          ),
          // Bottom scrim for text legibility
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xE6000000)],
                stops: [0.45, 1.0],
              ),
            ),
          ),

          // Floating top bar
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _heroIconButton(Icons.chevron_left_rounded, onBackTap, size: 26),
                  const Spacer(),
                  _heroIconButton(Icons.ios_share_rounded, onShareTap, size: 19),
                  const SizedBox(width: 10),
                  _heroIconButton(
                    isBookmarked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    onBookmarkTap,
                    size: 19,
                    tint: isBookmarked ? const Color(0xFFE53935) : Colors.white,
                  ),
                ],
              ),
            ),
          ),

          // Featured ribbon — real signal from admin-curated pin_status
          if (isFeatured)
            Positioned(
              top: 64,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFFD451), Color(0xFFF5B81E)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '★ FEATURED TUTOR',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF272942),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

          // Name + quick facts overlay
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _heroPill(
                      'IELTS $scoreLabel',
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE53935), Color(0xFFC62828)],
                      ),
                    ),
                    _heroPill('+$experience yrs experience'),
                    if (reviewsLoading)
                      _heroPill('Loading reviews…')
                    else if (avgRating != null)
                      _heroPill(
                        '★ ${avgRating!.toStringAsFixed(1)} ($reviewCount)',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroIconButton(IconData icon, VoidCallback onTap, {required double size, Color tint = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.32),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: size, color: tint),
      ),
    );
  }

  Widget _heroPill(String label, {Gradient? gradient}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? Colors.white.withValues(alpha: 0.18) : null,
        borderRadius: BorderRadius.circular(20),
        border: gradient == null ? Border.all(color: Colors.white.withValues(alpha: 0.3)) : null,
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'SF Pro',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.0,
        ),
      ),
    );
  }
}

// ─── Certificate badge ─────────────────────────────────────────────────────────

class _CertificateBadge extends StatelessWidget {
  final VoidCallback onTap;
  const _CertificateBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: context.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded, size: 18, color: Color(0xFF2E7D32)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'IELTS certificate verified',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: context.colors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ─── Scores grid ──────────────────────────────────────────────────────────────

class _ScoresGrid extends StatelessWidget {
  final List<(String, String)> scores;
  const _ScoresGrid({required this.scores});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: List.generate(scores.length, (i) {
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      scores[i].$1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      scores[i].$2,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: context.colors.error,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ─── Premium card wrapper ──────────────────────────────────────────────────────

class _PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _PremiumCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

// ─── Bio section ──────────────────────────────────────────────────────────────

class _BioSection extends StatelessWidget {
  final String bio;
  const _BioSection({required this.bio});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BIO',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.colors.textTertiary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          bio,
          style: TextStyle(
            fontSize: 15,
            color: context.colors.textPrimary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

// ─── Lesson duration section ──────────────────────────────────────────────────

class _LessonDurationSection extends StatelessWidget {
  final List<(String, String)> durations;
  const _LessonDurationSection({required this.durations});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LESSON DURATION',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.colors.textTertiary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(durations.length, (i) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 18,
                      color: context.colors.textTertiary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      durations[i].$1,
                      style: TextStyle(
                        fontSize: 15,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      durations[i].$2,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < durations.length - 1)
                Divider(height: 1, color: context.colors.border),
            ],
          );
        }),
      ],
    );
  }
}

// ─── Reviews section ──────────────────────────────────────────────────────────

class _ReviewsSection extends StatelessWidget {
  final List<Map<String, dynamic>> reviews;
  final bool loading;

  const _ReviewsSection({required this.reviews, required this.loading});

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }

  String _reviewerName(Map<String, dynamic> r) {
    final s = r['student'];
    if (s is Map) {
      for (final key in ['display_name', 'full_name', 'name']) {
        final v = (s[key] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      final first = (s['first_name'] ?? '').toString().trim();
      final last = (s['last_name'] ?? '').toString().trim();
      final full = '$first $last'.trim();
      if (full.isNotEmpty) return full;
    }
    return 'Student';
  }

  String? _reviewerImage(Map<String, dynamic> r) {
    final s = r['student'];
    if (s is Map) {
      final img = (s['profile_image'] ?? s['image'] ?? s['avatar']) as String?;
      if (img != null && img.isNotEmpty) return img;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'REVIEWS',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.colors.textTertiary,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: loading
              ? Center(
                  child: CircularProgressIndicator(color: context.colors.textPrimary),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: reviews.length,
                  itemBuilder: (_, i) {
                    final r = reviews[i];
                    final name = _reviewerName(r);
                    final stars = (r['rating'] as num?)?.toInt() ?? 0;
                    final body = (r['comment'] as String?) ?? '';
                    final date = _formatDate(r['created_at'] as String?);
                    final imageUrl = _reviewerImage(r);
                    return Container(
                      width: 280,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.colors.border, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CachedAvatar(imageUrl: imageUrl, size: 40),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: context.colors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: List.generate(5, (s) {
                                      return Icon(
                                        s < stars
                                            ? Icons.star_rounded
                                            : Icons.star_outline_rounded,
                                        size: 16,
                                        color: const Color(0xFFF5C542),
                                      );
                                    }),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Text(
                              body,
                              style: TextStyle(
                                fontSize: 13,
                                color: context.colors.textPrimary,
                                height: 1.5,
                              ),
                              overflow: TextOverflow.fade,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            date,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
