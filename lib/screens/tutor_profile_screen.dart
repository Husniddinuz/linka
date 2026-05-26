import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';
import '../services/api_service.dart';
import '../services/app_feature_service.dart';
import '../widgets/app_notify.dart';
import '../widgets/cached_avatar.dart';
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F7),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF272942)),
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

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── White top section ──────────────────────────────────────
                  Container(
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AppBar(
                          isBookmarked: _isBookmarked,
                          onBookmarkTap: _toggleBookmark,
                        ),
                        _TutorInfoCard(
                          name: name,
                          imageUrl: imageUrl,
                          experience: experience,
                          ieltsScore: ieltsScore,
                        ),
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

                  const SizedBox(height: 8),

                  // ── Bio ─────────────────────────────────────────────────────
                  Builder(builder: (_) {
                    final bio = (t?['about_me'] as String?)?.trim() ?? '';
                    if (bio.isEmpty) return const SizedBox.shrink();
                    return Container(
                      width: double.infinity,
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      child: _BioSection(bio: bio),
                    );
                  }),

                  Builder(builder: (_) {
                    final bio = (t?['about_me'] as String?)?.trim() ?? '';
                    return bio.isEmpty ? const SizedBox.shrink() : const SizedBox(height: 8);
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
                    return Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      child: _LessonDurationSection(durations: durations),
                    );
                  }),

                  const SizedBox(height: 8),

                  // ── Reviews ────────────────────────────────────────────────
                  if (_reviewsLoading || _reviews.isNotEmpty) ...[
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: _ReviewsSection(
                        reviews: _reviews,
                        loading: _reviewsLoading,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),

          // ── Sticky Schedule button ─────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _openAvailability,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF272942),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Schedule',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── App bar ───────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final bool isBookmarked;
  final VoidCallback onBookmarkTap;

  const _AppBar({
    required this.isBookmarked,
    required this.onBookmarkTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(
                Icons.chevron_left_rounded,
                size: 30,
                color: Color(0xFF272942),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onBookmarkTap,
              child: Icon(
                isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                size: 26,
                color: isBookmarked ? const Color(0xFF272942) : const Color(0xFF9E9E9E),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
                  color: const Color(0xFFE0E0E0),
                  child: const Center(
                    child: CircularProgressIndicator(color: Color(0xFF272942)),
                  ),
                ),
        ),
      ),
    );
  }
}

// ─── Tutor info card ───────────────────────────────────────────────────────────

class _TutorInfoCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final int experience;
  final double ieltsScore;

  const _TutorInfoCard({
    required this.name,
    this.imageUrl,
    required this.experience,
    required this.ieltsScore,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Avatar with yellow ring
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF5C542), width: 3),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: ClipOval(
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          width: 60,
                          height: 60,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.person,
                            size: 30,
                            color: Color(0xFFAAAAAA),
                          ),
                        )
                      : const Icon(
                          Icons.person,
                          size: 30,
                          color: Color(0xFFAAAAAA),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Name, experience, IELTS — white block
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF272942),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Experience: +$experience yrs',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9E9E9E),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'IELTS ${ieltsScore % 1 == 0 ? ieltsScore.toInt() : ieltsScore}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE53935),
                        ),
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
          color: const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: List.generate(scores.length, (i) {
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      scores[i].$1,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF272942),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      scores[i].$2,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE53935),
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

// ─── Bio section ──────────────────────────────────────────────────────────────

class _BioSection extends StatelessWidget {
  final String bio;
  const _BioSection({required this.bio});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BIO',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF9E9E9E),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          bio,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF272942),
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
        const Text(
          'LESSON DURATION',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF9E9E9E),
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
                    const Icon(
                      Icons.access_time_rounded,
                      size: 18,
                      color: Color(0xFF9E9E9E),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      durations[i].$1,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF272942),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      durations[i].$2,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF272942),
                      ),
                    ),
                  ],
                ),
              ),
              if (i < durations.length - 1)
                const Divider(height: 1, color: Color(0xFFEEEEEE)),
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
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'REVIEWS',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF9E9E9E),
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF272942)),
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
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
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF272942),
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
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF272942),
                                height: 1.5,
                              ),
                              overflow: TextOverflow.fade,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            date,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9E9E9E),
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
