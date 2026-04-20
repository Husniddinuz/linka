import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/cached_avatar.dart';
import '../widgets/lesson_card.dart';
import '../widgets/skeleton.dart';
import '../services/api_service.dart';
import '../services/prefs_service.dart';
import 'lessons_screen.dart';
import 'tutors_screen.dart';
import 'speaking_training_screen.dart';
import 'my_profile_screen.dart';
import 'story_upload_screen.dart';
import 'podcast_player_screen.dart';
import 'podcasts_list_screen.dart';
import 'articles_list_screen.dart';
import 'article_detail_screen.dart';
import 'story_viewer_screen.dart';

// ─── Data models ───────────────────────────────────────────────────────────────

class StoryData {
  final int id;
  final String mediaFile;
  final String mediaType; // "photo" or "video"
  final String? description;
  const StoryData({
    required this.id,
    required this.mediaFile,
    required this.mediaType,
    this.description,
  });
}

class _TutorWithStories {
  final String tutorId;
  final String name;
  final String? image;
  final List<StoryData> stories;
  _TutorWithStories({
    required this.tutorId,
    required this.name,
    this.image,
    required this.stories,
  });
}

/// Groups raw story JSON list by tutor name into _TutorWithStories
List<_TutorWithStories> _groupStories(List<dynamic> raw) {
  final map = <String, _TutorWithStories>{};
  for (final item in raw) {
    final j = item as Map<String, dynamic>;
    final firstName = j['tutor_first_name'] as String? ?? '';
    final lastName = j['tutor_last_name'] as String? ?? '';
    final key = '$firstName $lastName'.trim();
    map.putIfAbsent(
      key,
      () => _TutorWithStories(
        tutorId: '${j['tutor_id'] ?? j['tutor'] ?? 0}',
        name: '$firstName\n$lastName'.trim(),
        image: j['tutor_profile_image'] as String?,
        stories: [],
      ),
    );
    map[key]!.stories.add(StoryData(
      id: j['id'] as int? ?? 0,
      mediaFile: j['media_file'] as String? ?? '',
      mediaType: j['media_type'] as String? ?? 'photo',
      description: j['description'] as String?,
    ));
  }
  return map.values.toList();
}

class _Podcast {
  final int id;
  final String title;
  final String? audioUrl;
  final int? durationSeconds;

  const _Podcast({
    required this.id,
    required this.title,
    this.audioUrl,
    this.durationSeconds,
  });

  factory _Podcast.fromJson(Map<String, dynamic> json) {
    return _Podcast(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      audioUrl: json['audio_url'] as String?,
      durationSeconds: json['duration'] as int?,
    );
  }

  String get formattedDuration {
    if (durationSeconds == null || durationSeconds == 0) return '';
    final m = durationSeconds! ~/ 60;
    final s = durationSeconds! % 60;
    if (m > 0 && s > 0) return '$m min $s sec';
    if (m > 0) return '$m min';
    return '$s sec';
  }
}

class _Article {
  final int id;
  final String title;

  const _Article({required this.id, required this.title});

  factory _Article.fromJson(Map<String, dynamic> json) {
    return _Article(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
    );
  }
}

// ─── Screen ────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;
  String? _profileImage;
  String _userRole = 'student';
  Set<String> _viewedStories = {};
  List<_TutorWithStories> _storyTutors = [];
  List<Lesson> _todaysLessons = [];
  Set<int> _savedArticleIds = {};
  bool _loadingStories = true;
  bool _loadingLessons = true;
  bool _loadingPodcasts = true;
  bool _loadingArticles = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadViewedStories();
    _loadStoryTutors();
    _loadTodaysLessons();
    _loadPodcasts();
    _loadArticles();
    _loadSavedArticles();
  }

  Future<void> _loadProfile() async {
    try {
      final result = await ApiService.get('/student/profile/');
      if (!mounted) return;
      final data = result['data'] as Map<String, dynamic>?;
      setState(() {
        _profileImage = data?['profile_image'] as String?;
        _userRole = data?['role'] as String? ?? 'student';
      });
    } catch (_) {}
  }

  Future<void> _loadViewedStories() async {
    final viewed = await PrefsService.getViewedStories();
    if (!mounted) return;
    setState(() => _viewedStories = viewed);
  }

  Future<void> _loadStoryTutors() async {
    try {
      final list = await ApiService.getList('/tutors/stories/');
      if (!mounted) return;
      setState(() {
        _storyTutors = _groupStories(list);
        _loadingStories = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingStories = false);
    }
  }

  Future<void> _onStoryViewed(String tutorId) async {
    await PrefsService.markStoryViewed(tutorId);
    if (!mounted) return;
    setState(() => _viewedStories.add(tutorId));
  }

  Future<void> _loadPodcasts() async {
    try {
      final list = await ApiService.getList('/content/podcasts/');
      if (!mounted) return;
      setState(() {
        _podcasts = list
            .map((e) => _Podcast.fromJson(e as Map<String, dynamic>))
            .toList();
        _loadingPodcasts = false;
      });
    } catch (e) {
      dev.log('Podcasts error: $e');
      if (!mounted) return;
      setState(() => _loadingPodcasts = false);
    }
  }

  Future<void> _loadArticles() async {
    try {
      final list = await ApiService.getList('/content/articles/');
      if (!mounted) return;
      setState(() {
        _articles = list
            .map((e) => _Article.fromJson(e as Map<String, dynamic>))
            .toList();
        _loadingArticles = false;
      });
    } catch (e) {
      dev.log('Articles error: $e');
      if (!mounted) return;
      setState(() => _loadingArticles = false);
    }
  }

  Future<void> _loadSavedArticles() async {
    try {
      final response = await ApiService.get('/student/saved-articles/');
      if (!mounted) return;
      final savedList = response['data'] as List<dynamic>? ?? [];
      setState(() {
        _savedArticleIds = savedList
            .map((e) => (e as Map<String, dynamic>)['id'] as int? ?? 0)
            .toSet();
      });
    } catch (e) {
      dev.log('Saved articles error: $e');
    }
  }

  Future<void> _toggleArticleBookmark(int articleId) async {
    final wasSaved = _savedArticleIds.contains(articleId);
    setState(() {
      if (wasSaved) {
        _savedArticleIds.remove(articleId);
      } else {
        _savedArticleIds.add(articleId);
      }
    });
    try {
      if (wasSaved) {
        await ApiService.delete('/student/saved-articles/$articleId/');
      } else {
        await ApiService.post('/student/saved-articles/', {'article_id': articleId});
      }
    } catch (e) {
      dev.log('ARTICLE BOOKMARK ERROR: $e');
      if (!mounted) return;
      setState(() {
        if (wasSaved) {
          _savedArticleIds.add(articleId);
        } else {
          _savedArticleIds.remove(articleId);
        }
      });
    }
  }

  Future<void> _loadTodaysLessons() async {
    try {
      final list = await ApiService.getList('/bookings/my/');
      if (!mounted) return;
      final now = DateTime.now();
      final lessons = <Lesson>[];
      for (final item in list) {
        final booking = item as Map<String, dynamic>;
        final startAt = DateTime.tryParse(
          booking['start_at'] as String? ?? booking['start_time'] as String? ?? '',
        );
        if (startAt == null) continue;
        final local = startAt.toLocal();
        final isToday = local.year == now.year &&
            local.month == now.month &&
            local.day == now.day;
        if (!isToday) continue;
        if ((booking['status'] as String? ?? '') == 'cancelled') continue;
        lessons.add(Lesson.fromBooking(booking));
      }
      lessons.sort((a, b) => a.timeRange.compareTo(b.timeRange));
      setState(() {
        _todaysLessons = lessons;
        _loadingLessons = false;
      });
    } catch (e) {
      dev.log('TODAYS LESSONS ERROR: $e');
      if (!mounted) return;
      setState(() => _loadingLessons = false);
    }
  }

  List<_Podcast> _podcasts = [];

  List<_Article> _articles = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: _selectedTab,
        children: [
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(profileImage: _profileImage, isTutor: _userRole == 'tutor'),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_loadingStories) ...[
                          const SizedBox(height: 24),
                          const _StoriesSkeleton(),
                          const SizedBox(height: 28),
                        ] else if (_storyTutors.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _TutorsList(
                            tutors: _storyTutors,
                            viewedStories: _viewedStories,
                            onStoryViewed: _onStoryViewed,
                          ),
                          const SizedBox(height: 28),
                        ] else
                          const SizedBox(height: 20),

                        // Speaking practice button
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 21),
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedTab = 2),
                            child: LayoutBuilder(
                              builder: (context, constraints) => SvgPicture.asset(
                                'assets/images/buttons/speaking-practice.svg',
                                width: constraints.maxWidth,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Today's lessons
                        _LessonsSection(
                          lessons: _todaysLessons,
                          loading: _loadingLessons,
                          onSeeAll: () => setState(() => _selectedTab = 1),
                        ),

                        const SizedBox(height: 28),

                        // Video chat button
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 21),
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SpeakingTrainingScreen(),
                              ),
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) =>
                                  SvgPicture.asset(
                                    'assets/images/buttons/video-chat.svg',
                                    width: constraints.maxWidth,
                                  ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Watch a movie section — coming soon
                        const _SectionHeader(title: 'WATCH A MOVIE'),
                        const SizedBox(height: 12),
                        const _ComingSoonBanner(),

                        const SizedBox(height: 28),

                        // Podcasts section
                        _SectionHeader(
                          title: 'PODCASTS',
                          onSeeAll: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PodcastsListScreen()),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _PodcastsSection(podcasts: _podcasts, loading: _loadingPodcasts),

                        const SizedBox(height: 28),

                        // Articles section
                        _SectionHeader(
                          title: 'ARTICLES',
                          onSeeAll: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ArticlesListScreen()),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ArticlesSection(
                          articles: _articles,
                          loading: _loadingArticles,
                          savedArticleIds: _savedArticleIds,
                          onToggleBookmark: _toggleArticleBookmark,
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const LessonsScreen(),
          const TutorsScreen(),
          MyProfileScreen(
            onNavigateToLessons: () => setState(() => _selectedTab = 1),
          ),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        selectedIndex: _selectedTab,
        onTap: (i) => setState(() => _selectedTab = i),
      ),
    );
  }
}

// ─── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String? profileImage;
  final bool isTutor;
  const _Header({this.profileImage, this.isTutor = false});

  @override
  Widget build(BuildContext context) {
    final avatar = CachedAvatar(imageUrl: profileImage, size: 44);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          avatar,

          // Logo centered
          Expanded(
            child: Center(
              child: SvgPicture.asset(
                'assets/images/branding/header-logo.svg',
                height: 26,
              ),
            ),
          ),

          // Add story button (tutors only)
          if (isTutor)
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StoryUploadScreen()),
              ),
              child: const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.add_circle_outline_rounded,
                  color: Color(0xFF272942),
                  size: 28,
                ),
              ),
            ),

          // Bell with red dot
          SvgPicture.asset(
            'assets/images/icons/notification.svg',
            width: 30,
            height: 27,
          ),
        ],
      ),
    );
  }
}

// ─── Tutors list ───────────────────────────────────────────────────────────────

class _StoriesSkeleton extends StatelessWidget {
  const _StoriesSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 128,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 6,
        itemBuilder: (_, _) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              Skeleton(width: 86, height: 86, circle: true),
              SizedBox(height: 8),
              Skeleton(width: 60, height: 10, borderRadius: 4),
              SizedBox(height: 4),
              Skeleton(width: 40, height: 10, borderRadius: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _TutorsList extends StatelessWidget {
  final List<_TutorWithStories> tutors;
  final Set<String> viewedStories;
  final void Function(String tutorId) onStoryViewed;
  const _TutorsList({
    required this.tutors,
    required this.viewedStories,
    required this.onStoryViewed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 128,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tutors.length,
        itemBuilder: (_, i) => _TutorItem(
          tutor: tutors[i],
          isStoryViewed: viewedStories.contains(tutors[i].tutorId),
          onStoryViewed: onStoryViewed,
        ),
      ),
    );
  }
}

class _TutorItem extends StatelessWidget {
  final _TutorWithStories tutor;
  final bool isStoryViewed;
  final void Function(String tutorId) onStoryViewed;
  const _TutorItem({
    required this.tutor,
    required this.isStoryViewed,
    required this.onStoryViewed,
  });

  @override
  Widget build(BuildContext context) {
    final showYellowRing = !isStoryViewed;

    return GestureDetector(
      onTap: () {
        if (!isStoryViewed) onStoryViewed(tutor.tutorId);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StoryViewerScreen(
              tutorId: int.tryParse(tutor.tutorId) ?? 0,
              tutorName: tutor.name.replaceAll('\n', ' '),
              tutorImage: tutor.image,
              stories: tutor.stories,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: showYellowRing
                      ? const Color(0xFFF5C542)
                      : const Color(0xFFDDDDDD),
                  width: showYellowRing ? 3.5 : 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: ClipOval(
                  child: tutor.image != null && tutor.image!.startsWith('http')
                      ? Image.network(
                          tutor.image!,
                          fit: BoxFit.cover,
                          width: 80,
                          height: 80,
                          errorBuilder: (_, _, _) => Container(
                            width: 80,
                            height: 80,
                            color: const Color(0xFFE0E0E0),
                            child: const Icon(Icons.person, size: 30, color: Color(0xFFAAAAAA)),
                          ),
                        )
                      : Container(
                          width: 80,
                          height: 80,
                          color: const Color(0xFFE0E0E0),
                          child: const Icon(Icons.person, size: 30, color: Color(0xFFAAAAAA)),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tutor.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF272942),
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Lessons section ───────────────────────────────────────────────────────────

class _LessonsSection extends StatelessWidget {
  final List<Lesson> lessons;
  final bool loading;
  final VoidCallback? onSeeAll;
  const _LessonsSection({required this.lessons, this.loading = false, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Text(
                "TODAY'S LESSONS",
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF272942),
                  height: 1.0,
                  letterSpacing: 0,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onSeeAll,
                child: const Text(
                  'See all',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFB9BCBE),
                    height: 1.0,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(left: 20, right: 20, bottom: 8),
            child: Skeleton(height: 98, borderRadius: 16),
          )
        else if (lessons.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'No lessons scheduled for today',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 13,
                color: Color(0xFFAAAAAA),
              ),
            ),
          )
        else
          ...lessons.map(
            (l) => Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8),
              child: LessonCard(lesson: l),
            ),
          ),
      ],
    );
  }
}

// ─── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  const _SectionHeader({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF272942),
              height: 1.0,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onSeeAll,
            child: const Text(
              'See all',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFFB9BCBE),
                height: 1.0,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Coming soon banner ────────────────────────────────────────────────────────

class _ComingSoonBanner extends StatelessWidget {
  const _ComingSoonBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: const Color(0xFF272942),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.movie_outlined,
              color: Color(0xFFF5C542),
              size: 36,
            ),
            const SizedBox(height: 10),
            const Text(
              'Coming soon',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Movies will be available shortly',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.7),
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Podcasts section ──────────────────────────────────────────────────────────

class _PodcastsSection extends StatelessWidget {
  final List<_Podcast> podcasts;
  final bool loading;
  const _PodcastsSection({required this.podcasts, this.loading = false});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SizedBox(
        height: 100,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 3,
          itemBuilder: (_, _) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: SizedBox(
              width: 240,
              child: Skeleton(height: 100, borderRadius: 14),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: podcasts.length,
        itemBuilder: (_, i) => _PodcastCard(podcast: podcasts[i]),
      ),
    );
  }
}

class _PodcastCard extends StatelessWidget {
  final _Podcast podcast;
  const _PodcastCard({required this.podcast});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PodcastPlayerScreen(
            podcastId: podcast.id,
            initialTitle: podcast.title,
            initialAudioUrl: podcast.audioUrl,
          ),
        ),
      ),
      child: Container(
      width: 240,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xFF272942),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: SvgPicture.asset(
                'assets/images/icons/podcast.svg',
                width: 28,
                height: 28,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  podcast.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF272942),
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (podcast.formattedDuration.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    podcast.formattedDuration,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF6C6C6C),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ─── Articles section ──────────────────────────────────────────────────────────

class _ArticlesSection extends StatelessWidget {
  final List<_Article> articles;
  final bool loading;
  final Set<int> savedArticleIds;
  final void Function(int articleId) onToggleBookmark;
  const _ArticlesSection({
    required this.articles,
    this.loading = false,
    required this.savedArticleIds,
    required this.onToggleBookmark,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SizedBox(
        height: 180,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 4,
          itemBuilder: (_, _) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: SizedBox(
              width: 140,
              child: Skeleton(height: 180, borderRadius: 14),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: articles.length,
        itemBuilder: (_, i) => _ArticleCard(
          article: articles[i],
          isSaved: savedArticleIds.contains(articles[i].id),
          onToggleBookmark: onToggleBookmark,
        ),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final _Article article;
  final bool isSaved;
  final void Function(int articleId) onToggleBookmark;
  const _ArticleCard({
    required this.article,
    required this.isSaved,
    required this.onToggleBookmark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArticleDetailScreen(articleId: article.id),
        ),
      ),
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F6F6),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Image.asset(
                  'assets/images/article.png',
                  width: double.infinity,
                  height: 110,
                  fit: BoxFit.cover,
                  cacheWidth: 280,
                  cacheHeight: 220,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onToggleBookmark(article.id),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: SvgPicture.asset(
                          isSaved
                              ? 'assets/images/icons/bookmarked.svg'
                              : 'assets/images/icons/bookmark_outline_16.svg',
                          width: 14,
                          height: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                article.title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF272942),
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom navigation bar ─────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onTap;
  const _BottomNav({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'assets/images/icons/home_active.svg',
        'assets/images/icons/home_inactive.svg',
        'Home',
      ),
      (
        'assets/images/icons/lessons_active.svg',
        'assets/images/icons/lessons_inactive.svg',
        'Lessons',
      ),
      (
        'assets/images/icons/tutors_active.svg',
        'assets/images/icons/tutors_inactive.svg',
        'Tutors',
      ),
      (
        'assets/images/icons/profile_active.svg',
        'assets/images/icons/profile_inactive.svg',
        'Profile',
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(items.length, (i) {
            final selected = i == selectedIndex;
            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      selected ? items[i].$1 : items[i].$2,
                      width: 26,
                      height: 26,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      items[i].$3,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected
                            ? const Color(0xFF272942)
                            : const Color(0xFFCCCCCC),
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
