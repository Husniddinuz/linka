import 'dart:developer' as dev;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/cached_avatar.dart';
import '../widgets/lesson_card.dart';
import '../widgets/mini_player_bar.dart';
import '../widgets/skeleton.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/prefs_service.dart';
import '../services/update_service.dart';
import '../services/user_service.dart';
import '../widgets/update_dialog.dart';
import 'speaking_training_screen.dart';
import 'lesson_meeting_screen.dart';
import 'notifications_inbox_screen.dart';
import 'lessons_screen.dart';
import 'tutors_screen.dart';
import 'my_profile_screen.dart';
import 'story_upload_screen.dart';
import 'podcast_player_screen.dart';
import 'podcasts_list_screen.dart';
import 'articles_list_screen.dart';
import 'article_detail_screen.dart';
import 'story_viewer_screen.dart';
import 'tutor_earnings_screen.dart';
import 'tutor_stories_screen.dart';
import 'profile_setup_screen.dart';
import 'webinar_viewer_screen.dart';

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

/// Groups raw story JSON list by tutor name into StoryTutor
List<StoryTutor> _groupStories(List<dynamic> raw) {
  final map = <String, _StoryTutorBuilder>{};
  for (final item in raw) {
    final j = item as Map<String, dynamic>;
    final firstName = j['tutor_first_name'] as String? ?? '';
    final lastName = j['tutor_last_name'] as String? ?? '';
    final key = '$firstName $lastName'.trim();
    map.putIfAbsent(
      key,
      () => _StoryTutorBuilder(
        tutorId: (j['tutor_id'] ?? j['tutor'] ?? 0) as int,
        name: '$firstName\n$lastName'.trim(),
        image: j['tutor_profile_image'] as String?,
      ),
    );
    map[key]!.stories.add(StoryData(
      id: j['id'] as int? ?? 0,
      mediaFile: j['media_file'] as String? ?? '',
      mediaType: j['media_type'] as String? ?? 'photo',
      description: j['description'] as String?,
    ));
  }
  return map.values.map((b) => b.build()).toList();
}

class _StoryTutorBuilder {
  final int tutorId;
  final String name;
  final String? image;
  final List<StoryData> stories = [];
  _StoryTutorBuilder({required this.tutorId, required this.name, this.image});
  StoryTutor build() =>
      StoryTutor(tutorId: tutorId, name: name, image: image, stories: stories);
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
  bool _isTeacher = false;
  String? _tutorAccountStatus;
  Set<String> _viewedStories = {};
  List<StoryTutor> _storyTutors = [];
  List<Lesson> _todaysLessons = [];
  Set<int> _savedArticleIds = {};
  bool _loadingStories = true;
  bool _loadingLessons = true;
  bool _loadingPodcasts = true;
  bool _loadingArticles = true;

  @override
  void initState() {
    super.initState();
    _bootstrapRole();
    _loadViewedStories();
    _loadStoryTutors();
    _loadTodaysLessons();
    _loadPodcasts();
    _loadArticles();
    _loadSavedArticles();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (info == null || !mounted) return;
    await showUpdateDialog(context, info);
  }

  // TODO: remove before release — test-only trigger
  void _showTestUpdateDialog() {
    showUpdateDialog(
      context,
      const UpdateInfo(
        hasUpdate: true,
        isForce: false,
        title: 'New Update Available',
        message: 'A new version of Linka is available. Update now to get the latest features and improvements.',
        storeUrl: 'https://apps.apple.com',
      ),
    );
  }

  Future<void> _bootstrapRole() async {
    // First paint: use cached role so bottom nav doesn't flicker.
    final cached = await UserService.getCachedIsTeacher();
    if (mounted && cached != null) {
      setState(() => _isTeacher = cached);
    }
    // Authoritative fetch — may correct the cached value.
    try {
      final me = await UserService.fetchMe();
      if (!mounted) return;
      setState(() {
        _isTeacher = me.isTeacher;
        _tutorAccountStatus = me.tutorAccountStatus;
      });
      if (!me.isProfileComplete) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ProfileSetupScreen(
              role: me.isTeacher ? 'tutor' : 'student',
            ),
          ),
          (route) => false,
        );
        return;
      }
    } catch (_) {
      // Fall back to cached value on failure.
    }
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final me = UserService.current ?? await UserService.fetchMe();
      final path = _isTeacher
          ? '/tutors/${me.tutorProfileId}/'
          : '/student/profile/';
      final result = await ApiService.get(path);
      final data = (result['data'] is Map<String, dynamic>)
          ? result['data'] as Map<String, dynamic>
          : result;
      if (!mounted) return;
      setState(() {
        _profileImage = data['profile_image'] as String?;
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

  Future<void> _refreshStudentHome() async {
    await Future.wait([
      _loadStoryTutors(),
      _loadTodaysLessons(),
      _loadPodcasts(),
      _loadArticles(),
      _loadSavedArticles(),
      _loadProfile(),
    ]);
  }

  Future<void> _cancelLesson(Lesson lesson) async {
    if (lesson.id == 0) return;
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CancelLessonSheet(),
    );
    if (reason == null) return;
    try {
      await ApiService.patch('/bookings/${lesson.id}/cancel/', {'reason': reason});
      _loadTodaysLessons();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _joinLesson(Lesson lesson) async {
    if (lesson.id == 0) return;
    try {
      final data = await ApiService.post('/bookings/${lesson.id}/join/', {});
      final payload = (data['data'] is Map<String, dynamic>)
          ? data['data'] as Map<String, dynamic>
          : data;
      final roomUrl = (payload['joinUrl'] ??
              payload['join_url'] ??
              payload['room_url'] ??
              payload['daily_room_url'] ??
              payload['roomUrl'] ??
              lesson.dailyRoomUrl)
          .toString();
      final token = (payload['token'] ??
              payload['daily_token'] ??
              payload['meeting_token'] ??
              payload['daily_meeting_token'] ??
              '')
          .toString();
      if (roomUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get room info')),
          );
        }
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LessonMeetingScreen(
            roomUrl: roomUrl,
            token: token,
            tutorName: lesson.participantName,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
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

  Widget _buildStudentHomeBody() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(profileImage: _profileImage, isTutor: false, onLogoLongPress: _showTestUpdateDialog),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF272942),
              onRefresh: _refreshStudentHome,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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

                  // Webinar block
                  const _WebinarBlock(),
                  const SizedBox(height: 28),

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
                    onStartLesson: _joinLesson,
                    onCancelLesson: _cancelLesson,
                    onRatedLesson: _loadTodaysLessons,
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
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navItems = _isTeacher ? _tutorNavItems : _studentNavItems;
    final children = _isTeacher
        ? <Widget>[
            TutorHomeBody(
              profileImage: _profileImage,
              storyTutors: _storyTutors,
              viewedStories: _viewedStories,
              loadingStories: _loadingStories,
              onStoryViewed: _onStoryViewed,
              tutorAccountStatus: _tutorAccountStatus,
            ),
            const TutorStoriesScreen(),
            // Earnings is opened as a full-screen push, not an IndexedStack
            // child. The placeholder keeps indices aligned with the nav.
            const SizedBox.shrink(),
            MyProfileScreen(
              onNavigateToLessons: () => setState(() => _selectedTab = 0),
            ),
          ]
        : <Widget>[
            _buildStudentHomeBody(),
            LessonsScreen(onFindTutor: () => setState(() => _selectedTab = 2)),
            const TutorsScreen(),
            MyProfileScreen(
              onNavigateToLessons: () => setState(() => _selectedTab = 1),
            ),
          ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(index: _selectedTab, children: children),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayerBar(),
          _BottomNav(
            items: navItems,
            selectedIndex: _selectedTab,
            onTap: (i) {
              if (_isTeacher && i == 2) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TutorEarningsScreen(),
                  ),
                );
                return;
              }
              setState(() => _selectedTab = i);
            },
          ),
        ],
      ),
    );
  }
}

// ─── Bottom nav tab configs ───────────────────────────────────────────────────

const _studentNavItems = <_NavItem>[
  _NavItem(
    activeIcon: 'assets/images/icons/home_active.svg',
    inactiveIcon: 'assets/images/icons/home_inactive.svg',
    label: 'Home',
  ),
  _NavItem(
    activeIcon: 'assets/images/icons/lessons_active.svg',
    inactiveIcon: 'assets/images/icons/lessons_inactive.svg',
    label: 'Lessons',
  ),
  _NavItem(
    activeIcon: 'assets/images/icons/tutors_active.svg',
    inactiveIcon: 'assets/images/icons/tutors_inactive.svg',
    label: 'Tutors',
  ),
  _NavItem(
    activeIcon: 'assets/images/icons/profile_active.svg',
    inactiveIcon: 'assets/images/icons/profile_inactive.svg',
    label: 'Profile',
  ),
];

const _tutorNavItems = <_NavItem>[
  _NavItem(
    activeIcon: 'assets/images/icons/home_active.svg',
    inactiveIcon: 'assets/images/icons/home_inactive.svg',
    label: 'Home',
  ),
  _NavItem(
    activeIcon: 'assets/images/icons/story_active.svg',
    inactiveIcon: 'assets/images/icons/story_inactive.svg',
    label: 'Stories',
  ),
  _NavItem(
    activeIcon: 'assets/images/icons/earnings_inactive.svg',
    inactiveIcon: 'assets/images/icons/earnings_inactive.svg',
    label: 'Earnings',
  ),
  _NavItem(
    activeIcon: 'assets/images/icons/profile_active.svg',
    inactiveIcon: 'assets/images/icons/profile_inactive.svg',
    label: 'Profile',
  ),
];

class _NavItem {
  final String activeIcon;
  final String inactiveIcon;
  final String label;
  const _NavItem({
    required this.activeIcon,
    required this.inactiveIcon,
    required this.label,
  });
}

// ─── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatefulWidget {
  final String? profileImage;
  final bool isTutor;
  final VoidCallback? onLogoLongPress;
  const _Header({this.profileImage, this.isTutor = false, this.onLogoLongPress});

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  bool _hasNew = false;

  @override
  void initState() {
    super.initState();
    _refreshHasNew();
  }

  Future<void> _refreshHasNew() async {
    final v = await NotificationService.hasNew();
    if (!mounted) return;
    setState(() => _hasNew = v);
  }

  Future<void> _openInbox() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsInboxScreen()),
    );
    // Inbox interactions (tap, mark-all) may have changed unread state.
    if (mounted) _refreshHasNew();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = CachedAvatar(imageUrl: widget.profileImage, size: 44);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          avatar,

          // Logo centered
          Expanded(
            child: Center(
              child: GestureDetector(
                onLongPress: widget.onLogoLongPress,
                child: SvgPicture.asset(
                  'assets/images/branding/header-logo.svg',
                  height: 26,
                ),
              ),
            ),
          ),

          // Add story button (tutors only)
          if (widget.isTutor)
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

          // Bell — red dot shown only when the inbox has unread items.
          GestureDetector(
            onTap: _openInbox,
            behavior: HitTestBehavior.opaque,
            child: SvgPicture.asset(
              _hasNew
                  ? 'assets/images/icons/notification.svg'
                  : 'assets/images/icons/notification_empty.svg',
              width: 30,
              height: 27,
            ),
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
  final List<StoryTutor> tutors;
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
          tutorIndex: i,
          tutors: tutors,
          isStoryViewed: viewedStories.contains('${tutors[i].tutorId}'),
          onStoryViewed: onStoryViewed,
        ),
      ),
    );
  }
}

class _TutorItem extends StatelessWidget {
  final int tutorIndex;
  final List<StoryTutor> tutors;
  final bool isStoryViewed;
  final void Function(String tutorId) onStoryViewed;
  const _TutorItem({
    required this.tutorIndex,
    required this.tutors,
    required this.isStoryViewed,
    required this.onStoryViewed,
  });

  StoryTutor get tutor => tutors[tutorIndex];

  @override
  Widget build(BuildContext context) {
    final showYellowRing = !isStoryViewed;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StoryViewerScreen(
              tutors: tutors,
              initialTutorIndex: tutorIndex,
              onTutorViewed: (id) => onStoryViewed('$id'),
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
  final ValueChanged<Lesson>? onStartLesson;
  final ValueChanged<Lesson>? onCancelLesson;
  final VoidCallback? onRatedLesson;
  const _LessonsSection({required this.lessons, this.loading = false, this.onSeeAll, this.onStartLesson, this.onCancelLesson, this.onRatedLesson});

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
        Builder(builder: (context) {
          final cardWidth = MediaQuery.of(context).size.width - 52;
          if (loading) {
            return SizedBox(
              height: 114,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: 2,
                itemBuilder: (_, _) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: cardWidth,
                    child: const Skeleton(height: 98, borderRadius: 16),
                  ),
                ),
              ),
            );
          }
          if (lessons.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'No lessons scheduled for today',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 13,
                  color: Color(0xFFAAAAAA),
                ),
              ),
            );
          }
          return SizedBox(
            height: 162,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: lessons.length,
              itemBuilder: (_, i) {
                final l = lessons[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: cardWidth,
                    child: LessonCard(
                      lesson: l,
                      showStartButton: l.dailyRoomUrl.isNotEmpty,
                      onStart: onStartLesson != null ? () => onStartLesson!(l) : null,
                      onCancel: onCancelLesson != null ? () => onCancelLesson!(l) : null,
                      onRated: onRatedLesson,
                    ),
                  ),
                );
              },
            ),
          );
        }),
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

  static const _posters = [
    'assets/images/movies/joker.png',
    'assets/images/movies/little-women.png',
    'assets/images/movies/thor.png',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 160,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Blurred movie posters row
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                child: Row(
                  children: _posters.map((path) => Expanded(
                    child: Image.asset(
                      path,
                      fit: BoxFit.cover,
                      height: double.infinity,
                    ),
                  )).toList(),
                ),
              ),
              // Dark overlay
              Container(color: const Color(0xFF272942).withValues(alpha: 0.55)),
              // Coming soon badge
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.movie_outlined,
                      color: Color(0xFFF5C542),
                      size: 32,
                    ),
                    const SizedBox(height: 8),
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
                    const SizedBox(height: 4),
                    Text(
                      'Movies will be available shortly',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.75),
                        height: 1.3,
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

// ─── Webinar block (single featured webinar) ───────────────────────────────────

class _WebinarBlock extends StatelessWidget {
  const _WebinarBlock();

  @override
  Widget build(BuildContext context) {
    final webinar = WebinarData(
      id: 1,
      title: 'English Grammar Masterclass',
      tutorName: 'Sarah Johnson',
      tutorImage: null,
      scheduledAt: DateTime.now().copyWith(hour: 21, minute: 0, second: 0),
      status: 'live',
      playbackUrl: 'https://live.143b.ch/cam/flux/ts:abr.m3u8',
      viewerCount: 12,
    );

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WebinarViewerScreen(webinar: webinar)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF272942),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5C542).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.live_tv_rounded,
                      color: Color(0xFFF5C542),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'WEBINAR',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF5C542),
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          'Today, Tutor ${webinar.tutorName} will hold a session at 21:00',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.85),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.people_outline_rounded, size: 14, color: Color(0xFFAAAAAA)),
                  const SizedBox(width: 4),
                  Text(
                    'Unlimited viewers · Chat only',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5C542),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Join',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF272942),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
  final List<_NavItem> items;
  final int selectedIndex;
  final void Function(int) onTap;
  const _BottomNav({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
            final item = items[i];
            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      selected ? item.activeIcon : item.inactiveIcon,
                      width: 26,
                      height: 26,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.label,
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

// ─── Tutor Home body ───────────────────────────────────────────────────────────

class TutorHomeBody extends StatefulWidget {
  final String? profileImage;
  final List<StoryTutor> storyTutors;
  final Set<String> viewedStories;
  final bool loadingStories;
  final void Function(String) onStoryViewed;
  final String? tutorAccountStatus;

  const TutorHomeBody({
    super.key,
    this.profileImage,
    required this.storyTutors,
    required this.viewedStories,
    required this.loadingStories,
    required this.onStoryViewed,
    this.tutorAccountStatus,
  });

  @override
  State<TutorHomeBody> createState() => _TutorHomeBodyState();
}

class _TutorHomeBodyState extends State<TutorHomeBody> {
  bool _calendarMode = false;
  String _listTab = 'upcoming'; // 'upcoming' | 'past'
  List<Map<String, dynamic>> _bookings = [];
  Set<int> _busyDays = {};
  DateTime _focusedMonth =
      DateTime(DateTime.now().year, DateTime.now().month);
  int _selectedDay = DateTime.now().day;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.getList('/bookings/my/');
      if (!mounted) return;
      final bookings = list.cast<Map<String, dynamic>>();
      setState(() {
        _bookings = bookings;
        _busyDays = _busyDaysForMonth(bookings, _focusedMonth);
        _loading = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _bookings = [];
        _loading = false;
      });
    }
  }

  Set<int> _busyDaysForMonth(
      List<Map<String, dynamic>> bookings, DateTime month) {
    final busy = <int>{};
    for (final b in bookings) {
      final d = DateTime.tryParse((b['start_at'] ?? b['start_time'] ?? '')
          .toString());
      if (d == null) continue;
      final local = d.toLocal();
      if (local.year == month.year && local.month == month.month) {
        busy.add(local.day);
      }
    }
    return busy;
  }

  void _changeMonth(int delta) {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
      _selectedDay = 1;
      _busyDays = _busyDaysForMonth(_bookings, _focusedMonth);
    });
  }

  Future<void> _joinLesson(Lesson lesson) async {
    if (lesson.id == 0) return;
    try {
      final data = await ApiService.post('/bookings/${lesson.id}/join/', {});
      final payload = (data['data'] is Map<String, dynamic>)
          ? data['data'] as Map<String, dynamic>
          : data;
      final roomUrl = (payload['joinUrl'] ??
              payload['join_url'] ??
              payload['room_url'] ??
              payload['daily_room_url'] ??
              payload['roomUrl'] ??
              lesson.dailyRoomUrl)
          .toString();
      final token = (payload['token'] ??
              payload['daily_token'] ??
              payload['meeting_token'] ??
              payload['daily_meeting_token'] ??
              '')
          .toString();
      if (roomUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get room info')),
          );
        }
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LessonMeetingScreen(
            roomUrl: roomUrl,
            token: token,
            tutorName: lesson.participantName,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  List<Lesson> get _upcomingLessons {
    final now = DateTime.now();
    final list = _bookings.where((b) {
      final d = DateTime.tryParse((b['start_at'] ?? b['start_time'] ?? '')
          .toString());
      if (d == null) return false;
      return d.toLocal().isAfter(now) && (b['status'] ?? '') != 'cancelled';
    }).map((b) => Lesson.fromBooking(b, viewerIsTutor: true)).toList()
      ..sort((a, b) => (a.startAt ?? DateTime(0))
          .compareTo(b.startAt ?? DateTime(0)));
    return list;
  }

  List<Lesson> get _pastLessons {
    final now = DateTime.now();
    final list = _bookings.where((b) {
      final d = DateTime.tryParse((b['start_at'] ?? b['start_time'] ?? '')
          .toString());
      if (d == null) return false;
      return d.toLocal().isBefore(now);
    }).map((b) => Lesson.fromBooking(b, viewerIsTutor: true)).toList()
      ..sort((a, b) => (b.startAt ?? DateTime(0))
          .compareTo(a.startAt ?? DateTime(0)));
    return list;
  }

  List<Lesson> get _selectedDayLessons {
    final selected = DateTime(
      _focusedMonth.year,
      _focusedMonth.month,
      _selectedDay,
    );
    return _bookings.where((b) {
      final d = DateTime.tryParse((b['start_at'] ?? b['start_time'] ?? '')
          .toString());
      if (d == null) return false;
      final local = d.toLocal();
      return local.year == selected.year &&
          local.month == selected.month &&
          local.day == selected.day;
    }).map((b) => Lesson.fromBooking(b, viewerIsTutor: true)).toList()
      ..sort((a, b) => a.timeRange.compareTo(b.timeRange));
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.tutorAccountStatus;
    final showPendingBanner = status != null && status != 'active';

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(profileImage: widget.profileImage),
          if (showPendingBanner) _PendingActivationBanner(status: status),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF272942),
              onRefresh: _fetch,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.loadingStories) ...[
                      const SizedBox(height: 24),
                      const _StoriesSkeleton(),
                      const SizedBox(height: 28),
                    ] else if (widget.storyTutors.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _TutorsList(
                        tutors: widget.storyTutors,
                        viewedStories: widget.viewedStories,
                        onStoryViewed: widget.onStoryViewed,
                      ),
                      const SizedBox(height: 20),
                    ] else
                      const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          const Text(
                            'MY LESSONS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF272942),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _calendarMode = !_calendarMode),
                            child: SvgPicture.asset(
                              _calendarMode
                                  ? 'assets/images/icons/calendar_off.svg'
                                  : 'assets/images/icons/calendar_on.svg',
                              width: 22,
                              height: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_calendarMode)
                      _TutorCalendarMode(
                        loading: _loading,
                        focusedMonth: _focusedMonth,
                        selectedDay: _selectedDay,
                        busyDays: _busyDays,
                        dayLessons: _selectedDayLessons,
                        onPrevMonth: () => _changeMonth(-1),
                        onNextMonth: () => _changeMonth(1),
                        onDayTap: (d) => setState(() => _selectedDay = d),
                        onStartLesson: _joinLesson,
                      )
                    else
                      _TutorListMode(
                        tab: _listTab,
                        loading: _loading,
                        upcoming: _upcomingLessons,
                        past: _pastLessons,
                        onTabChange: (t) => setState(() => _listTab = t),
                        onStartLesson: _joinLesson,
                      ),
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

// ─── Pending activation banner ─────────────────────────────────────────────────

class _PendingActivationBanner extends StatelessWidget {
  final String status;
  const _PendingActivationBanner({required this.status});

  String get _title {
    switch (status) {
      case 'rejected':
        return 'Account rejected';
      case 'suspended':
        return 'Account suspended';
      default:
        return 'Pending activation';
    }
  }

  String get _message {
    switch (status) {
      case 'rejected':
        return 'Your application was not approved. Contact support for details.';
      case 'suspended':
        return 'Your account is temporarily suspended. Contact support.';
      default:
        return 'Your account is under review. You\'ll be able to accept lessons once approved.';
    }
  }

  Color get _accent {
    switch (status) {
      case 'rejected':
      case 'suspended':
        return const Color(0xFFE74C3C);
      default:
        return const Color(0xFFF5C542);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: _accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF272942),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6C6C6C),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tutor list mode (Upcoming / Past tabs) ────────────────────────────────────

class _TutorListMode extends StatelessWidget {
  final String tab;
  final bool loading;
  final List<Lesson> upcoming;
  final List<Lesson> past;
  final ValueChanged<String> onTabChange;
  final ValueChanged<Lesson> onStartLesson;

  const _TutorListMode({
    required this.tab,
    required this.loading,
    required this.upcoming,
    required this.past,
    required this.onTabChange,
    required this.onStartLesson,
  });

  @override
  Widget build(BuildContext context) {
    final lessons = tab == 'upcoming' ? upcoming : past;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _SegBtn(
                    label: 'Upcoming',
                    active: tab == 'upcoming',
                    onTap: () => onTabChange('upcoming'),
                  ),
                ),
                Expanded(
                  child: _SegBtn(
                    label: 'Past',
                    active: tab == 'past',
                    onTap: () => onTabChange('past'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Skeleton(height: 98, borderRadius: 16),
          )
        else if (lessons.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  tab == 'upcoming'
                      ? 'No upcoming lessons'
                      : 'No past lessons',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFAAAAAA),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          )
        else
          ..._groupByDay(lessons).entries.expand((g) => [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        g.key.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF272942),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      if (g.key.isToday)
                        const Text(
                          'Today',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF2B85DB),
                          ),
                        ),
                    ],
                  ),
                ),
                ...g.value.map((lesson) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: LessonCard(
                      lesson: lesson,
                      showStartButton:
                          tab == 'upcoming' && lesson.dailyRoomUrl.isNotEmpty,
                      showCopyLink:
                          tab == 'upcoming' && lesson.dailyRoomUrl.isNotEmpty,
                      onStart: () => onStartLesson(lesson),
                    ),
                  );
                }),
              ]),
      ],
    );
  }

  Map<_DayKey, List<Lesson>> _groupByDay(List<Lesson> items) {
    final map = <_DayKey, List<Lesson>>{};
    for (final l in items) {
      final k = _DayKey.fromLesson(l);
      map.putIfAbsent(k, () => []).add(l);
    }
    return map;
  }
}

class _DayKey {
  final String label;
  final bool isToday;
  final String sortKey;
  const _DayKey({
    required this.label,
    required this.isToday,
    required this.sortKey,
  });

  static const _months = [
    '', 'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];
  static const _weekdays = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY',
  ];

  factory _DayKey.fromLesson(Lesson l) {
    final d = l.startAt ?? DateTime.now();
    final now = DateTime.now();
    final isToday =
        d.year == now.year && d.month == now.month && d.day == now.day;
    return _DayKey(
      label: '${d.day} ${_months[d.month]}, ${_weekdays[d.weekday - 1]}',
      isToday: isToday,
      sortKey: '${d.year}-${d.month}-${d.day}',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _DayKey && other.sortKey == sortKey;
  @override
  int get hashCode => sortKey.hashCode;
}

class _SegBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SegBtn({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF272942) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : const Color(0xFF272942),
          ),
        ),
      ),
    );
  }
}

// ─── Tutor calendar mode ───────────────────────────────────────────────────────

class _TutorCalendarMode extends StatelessWidget {
  final bool loading;
  final DateTime focusedMonth;
  final int selectedDay;
  final Set<int> busyDays;
  final List<Lesson> dayLessons;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<int> onDayTap;
  final ValueChanged<Lesson> onStartLesson;

  const _TutorCalendarMode({
    required this.loading,
    required this.focusedMonth,
    required this.selectedDay,
    required this.busyDays,
    required this.dayLessons,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onDayTap,
    required this.onStartLesson,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _TutorCalendarCard(
            focusedMonth: focusedMonth,
            selectedDay: selectedDay,
            busyDays: busyDays,
            onPrevMonth: onPrevMonth,
            onNextMonth: onNextMonth,
            onDayTap: onDayTap,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            _formatDateHeader(focusedMonth, selectedDay),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF272942),
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Skeleton(height: 98, borderRadius: 16),
          )
        else if (dayLessons.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text(
                  'No lessons on this day',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFFAAAAAA),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          )
        else
          ...dayLessons.map(
            (l) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: LessonCard(
                lesson: l,
                showStartButton: l.dailyRoomUrl.isNotEmpty,
                showCopyLink: l.dailyRoomUrl.isNotEmpty,
                onStart: () => onStartLesson(l),
              ),
            ),
          ),
      ],
    );
  }

  static const _months = [
    '', 'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];
  static const _weekdays = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY',
  ];
  String _formatDateHeader(DateTime month, int day) {
    final d = DateTime(month.year, month.month, day);
    return '${d.day} ${_months[d.month]}, ${_weekdays[d.weekday - 1]}';
  }
}

class _TutorCalendarCard extends StatelessWidget {
  final DateTime focusedMonth;
  final int selectedDay;
  final Set<int> busyDays;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<int> onDayTap;

  const _TutorCalendarCard({
    required this.focusedMonth,
    required this.selectedDay,
    required this.busyDays,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onDayTap,
  });

  static const _dayHeaders = ['SAN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
  static const _monthNames = [
    '', 'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];

  @override
  Widget build(BuildContext context) {
    final year = focusedMonth.year;
    final month = focusedMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday % 7;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onPrevMonth,
                child: const Icon(Icons.chevron_left,
                    color: Color(0xFF272942), size: 24),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_monthNames[month]} $year',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF272942),
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onNextMonth,
                child: const Icon(Icons.chevron_right,
                    color: Color(0xFF272942), size: 24),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: _dayHeaders
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFAAAAAA),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          ...List.generate(6, (week) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: List.generate(7, (weekday) {
                  final dayNum = week * 7 + weekday - firstWeekday + 1;
                  if (dayNum < 1 || dayNum > daysInMonth) {
                    return const Expanded(child: SizedBox());
                  }
                  final isSelected = dayNum == selectedDay;
                  final hasLesson = busyDays.contains(dayNum);
                  final now = DateTime.now();
                  final isToday =
                      dayNum == now.day && month == now.month && year == now.year;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onDayTap(dayNum),
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF272942) : null,
                            borderRadius: BorderRadius.circular(8),
                            border: isToday && !isSelected
                                ? Border.all(
                                    color: const Color(0xFF272942),
                                    width: 1.5,
                                  )
                                : null,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Text(
                                '$dayNum',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF272942),
                                ),
                              ),
                              if (hasLesson)
                                Positioned(
                                  bottom: 4,
                                  child: Container(
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.white
                                          : const Color(0xFF4CAF50),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ],
      ),
    );
  }
}
