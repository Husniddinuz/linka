import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/cached_avatar.dart';
import '../services/api_service.dart';
import '../services/prefs_service.dart';
import 'lessons_screen.dart';
import 'tutors_screen.dart';
import 'speaking_training_screen.dart';
import 'my_profile_screen.dart';
import 'story_upload_screen.dart';
import 'podcast_player_screen.dart';
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
        tutorId: '${j['id'] ?? 0}',
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

class _Lesson {
  final int id;
  final String tutorName;
  final String? tutorImage;
  final String timeRange;
  final String duration;
  final String status;
  const _Lesson({
    required this.id,
    required this.tutorName,
    this.tutorImage,
    required this.timeRange,
    required this.duration,
    required this.status,
  });

  factory _Lesson.fromBooking(Map<String, dynamic> booking) {
    final tutor = booking['tutor'] as Map<String, dynamic>? ?? {};
    final firstName = tutor['first_name'] as String? ?? '';
    final lastName = tutor['last_name'] as String? ?? '';
    final startAt = DateTime.tryParse(booking['start_at'] as String? ?? '');
    final durationMin = booking['duration_minutes'] as int? ?? 0;

    String timeRange = '';
    if (startAt != null) {
      final localStart = startAt.toLocal();
      final localEnd = localStart.add(Duration(minutes: durationMin));
      timeRange =
          '${localStart.hour}:${localStart.minute.toString().padLeft(2, '0')}'
          ' - '
          '${localEnd.hour}:${localEnd.minute.toString().padLeft(2, '0')}';
    }

    return _Lesson(
      id: booking['id'] as int? ?? 0,
      tutorName: '$firstName $lastName'.trim(),
      tutorImage: tutor['profile_image'] as String?,
      timeRange: timeRange,
      duration: '$durationMin min',
      status: booking['status'] as String? ?? '',
    );
  }
}

class _Movie {
  final String title;
  final String image;
  const _Movie(this.title, this.image);
}

class _Podcast {
  final int id;
  final String title;
  final String? audioUrl;

  const _Podcast({
    required this.id,
    required this.title,
    this.audioUrl,
  });

  factory _Podcast.fromJson(Map<String, dynamic> json) {
    return _Podcast(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      audioUrl: json['audio_url'] as String?,
    );
  }
}

class _Article {
  final String title;
  const _Article(this.title);
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
  Set<String> _viewedStories = {};
  List<_TutorWithStories> _storyTutors = [];
  List<_Lesson> _todaysLessons = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadViewedStories();
    _loadStoryTutors();
    _loadTodaysLessons();
    _loadPodcasts();
  }

  Future<void> _loadProfile() async {
    try {
      final result = await ApiService.get('/student/profile/');
      if (!mounted) return;
      final data = result['data'] as Map<String, dynamic>?;
      setState(() {
        _profileImage = data?['profile_image'] as String?;
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
      });
    } catch (_) {}
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
      });
    } catch (e) {
      dev.log('Podcasts error: $e');
    }
  }

  Future<void> _loadTodaysLessons() async {
    try {
      final result = await ApiService.get('/bookings/my/?status=confirmed');
      if (!mounted) return;
      final list = (result is List ? result : (result['data'] as List?) ?? []) as List<dynamic>;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final lessons = <_Lesson>[];
      for (final item in list) {
        final booking = item as Map<String, dynamic>;
        final startAt = DateTime.tryParse(booking['start_at'] as String? ?? '');
        if (startAt == null) continue;
        final localStart = startAt.toLocal();
        if (localStart.isAfter(today) && localStart.isBefore(tomorrow)) {
          lessons.add(_Lesson.fromBooking(booking));
        }
      }
      lessons.sort((a, b) => a.timeRange.compareTo(b.timeRange));
      setState(() => _todaysLessons = lessons);
    } catch (_) {}
  }

  static const _movies = [
    _Movie('Little Women', 'assets/images/movies/little-women.png'),
    _Movie('Thor', 'assets/images/movies/thor.png'),
    _Movie('Joker', 'assets/images/movies/joker.png'),
  ];

  List<_Podcast> _podcasts = [];

  static const _articles = [
    _Article('10 Tips to Improve\nYour English'),
    _Article('How to Sound Like\na Native Speaker'),
    _Article('Common English\nMistakes to Avoid'),
  ];

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
                _Header(profileImage: _profileImage),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),

                        // Tutors list
                        _TutorsList(
                          tutors: _storyTutors,
                          viewedStories: _viewedStories,
                          onStoryViewed: _onStoryViewed,
                        ),

                        const SizedBox(height: 28),

                        // Speaking practice button
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 21),
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SpeakingTrainingScreen(),
                              ),
                            ),
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
                        _LessonsSection(lessons: _todaysLessons),

                        const SizedBox(height: 28),

                        // Video chat button
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 21),
                          child: LayoutBuilder(
                            builder: (context, constraints) =>
                                SvgPicture.asset(
                                  'assets/images/buttons/video-chat.svg',
                                  width: constraints.maxWidth,
                                ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Watch a movie section
                        _SectionHeader(title: 'WATCH A MOVIE'),
                        const SizedBox(height: 12),
                        _MoviesSection(movies: _movies),

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
                        _PodcastsSection(podcasts: _podcasts),

                        const SizedBox(height: 28),

                        // Articles section
                        _SectionHeader(title: 'ARTICLES'),
                        const SizedBox(height: 12),
                        _ArticlesSection(articles: _articles),

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
          const MyProfileScreen(),
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
  const _Header({this.profileImage});

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

          // Add story button
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
  final List<_Lesson> lessons;
  const _LessonsSection({required this.lessons});

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
              const Text(
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
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (lessons.isEmpty)
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
              child: _LessonCard(lesson: l),
            ),
          ),
      ],
    );
  }
}

class _LessonCard extends StatelessWidget {
  final _Lesson lesson;
  const _LessonCard({required this.lesson});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tutor image with rounded corners + padding from card edge
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: lesson.tutorImage != null && lesson.tutorImage!.startsWith('http')
                ? Image.network(
                    lesson.tutorImage!,
                    width: 82,
                    height: 82,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Image.asset(
                      'assets/images/tutors/tutor.png',
                      width: 82,
                      height: 82,
                      fit: BoxFit.cover,
                    ),
                  )
                : Image.asset(
                    'assets/images/tutors/tutor.png',
                    width: 82,
                    height: 82,
                    fit: BoxFit.cover,
                  ),
          ),

          const SizedBox(width: 8),

          // White text section — same height, same border radius
          Expanded(
            child: Container(
              height: 82,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          lesson.tutorName,
                          style: const TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF272942),
                            height: 1.0,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            SvgPicture.asset(
                              'assets/images/icons/recent_outline_20.svg',
                              width: 15,
                              height: 15,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              lesson.timeRange,
                              style: const TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6C6C6C),
                                height: 1.0,
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            SvgPicture.asset(
                              'assets/images/icons/tabler_hourglass-high.svg',
                              width: 15,
                              height: 15,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              lesson.duration,
                              style: const TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6C6C6C),
                                height: 1.0,
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 3-dot pinned to top-right inside white block
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        3,
                        (i) => Padding(
                          padding: EdgeInsets.only(top: i == 0 ? 0 : 3),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: Color(0xFF272942),
                              shape: BoxShape.circle,
                            ),
                          ),
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

// ─── Watch a movie section ─────────────────────────────────────────────────────

class _MoviesSection extends StatelessWidget {
  final List<_Movie> movies;
  const _MoviesSection({required this.movies});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: movies.length,
        itemBuilder: (_, i) => _MovieCard(movie: movies[i]),
      ),
    );
  }
}

class _MovieCard extends StatelessWidget {
  final _Movie movie;
  const _MovieCard({required this.movie});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              movie.image,
              width: double.infinity,
              height: 170,
              fit: BoxFit.cover,
              cacheWidth: 280,
              cacheHeight: 340,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                movie.title,
                style: const TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2B2B2B),
                  height: 1.0,
                  letterSpacing: 0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Podcasts section ──────────────────────────────────────────────────────────

class _PodcastsSection extends StatelessWidget {
  final List<_Podcast> podcasts;
  const _PodcastsSection({required this.podcasts});

  @override
  Widget build(BuildContext context) {
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
            child: Text(
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
  const _ArticlesSection({required this.articles});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: articles.length,
        itemBuilder: (_, i) => _ArticleCard(article: articles[i]),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final _Article article;
  const _ArticleCard({required this.article});

  @override
  Widget build(BuildContext context) {
    return Container(
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
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: Color(0xFF272942),
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
