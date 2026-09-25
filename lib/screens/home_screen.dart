import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../models/announcement.dart';
import '../models/podcast.dart';
import '../services/podcast_progress_service.dart';
import '../widgets/cached_avatar.dart';
import '../widgets/podcast_artwork.dart';
import '../widgets/lesson_card.dart';
import '../widgets/mini_player_bar.dart';
import '../widgets/skeleton.dart';
import '../widgets/category_grid.dart';
import 'ielts_course_screen.dart';
import '../services/api_service.dart';
import '../services/announcement_service.dart';
import '../services/app_feature_service.dart';
import '../services/notification_service.dart';
import '../services/prefs_service.dart';
import '../services/update_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../utils/announcement_target.dart';
import '../widgets/announcement_popup.dart';
import '../widgets/update_dialog.dart';
import 'speaking_training_screen.dart';
import 'lesson_meeting_screen.dart';
import 'notifications_inbox_screen.dart';
import 'chats_screen.dart';
import 'lessons_screen.dart';
import 'tutors_screen.dart';
import 'my_profile_screen.dart';
import 'story_upload_screen.dart';
import 'podcast_player_screen.dart';
import 'podcasts_list_screen.dart';
import '../services/podcast_playback_service.dart';
import 'articles_list_screen.dart';
import 'article_detail_screen.dart';
import '../widgets/new_badge.dart';
import 'story_viewer_screen.dart';
import 'tutor_earnings_screen.dart';
import 'tutor_stories_screen.dart';
import 'profile_setup_screen.dart';
import 'webinar_viewer_screen.dart';
import 'debate_room_screen.dart';
import '../services/debate_service.dart';
import 'ielts_booking_screen.dart';
import 'mock_exams_screen.dart';
import 'speaking_samples_list_screen.dart';
import 'writing_samples_list_screen.dart';
import 'course_reels_screen.dart';
import 'courses_list_screen.dart';
import '../models/course.dart';
import '../models/course_reel.dart';
import '../models/social.dart';
import '../services/course_reels_service.dart';
import '../services/course_service.dart';
import '../services/social_service.dart';

// ─── Data models ───────────────────────────────────────────────────────────────

class StoryData {
  final int id;
  final String mediaFile;
  final String mediaType; // "photo" or "video"
  final String? description;
  final bool isPin;

  /// Which table the story came from.
  ///
  /// Ids are per-table — a tutor story, a Linka story and a student's story can
  /// all be id 5 — so anything that remembers "seen" must key on
  /// [viewKey] rather than on [id]. Keying on the bare id marked unrelated
  /// stories as watched.
  final StorySource source;

  const StoryData({
    required this.id,
    required this.mediaFile,
    required this.mediaType,
    this.description,
    this.isPin = false,
    this.source = StorySource.tutor,
  });

  /// Stable, collision-free key for [PrefsService.markStoryViewed].
  String get viewKey => 'story_${source.name}_$id';
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
        // Backend ships `is_enrollable` soon; default true until then.
        isEnrollable: j['is_enrollable'] as bool? ?? true,
        // `tutor_id: null` marks a platform-wide Linka story.
        isLinka: j['tutor_id'] == null,
      ),
    );
    map[key]!.stories.add(
      StoryData(
        id: j['id'] as int? ?? 0,
        mediaFile: j['media_file'] as String? ?? '',
        mediaType: j['media_type'] as String? ?? 'photo',
        description: j['description'] as String?,
        isPin: j['is_pin'] as bool? ?? false,
      ),
    );
  }
  // Pinned stories come first — within each tutor, and tutors that have any
  // pinned story are surfaced ahead of the rest in the stories row.
  for (final b in map.values) {
    b.stories.sort((a, c) {
      if (a.isPin == c.isPin) return 0;
      return a.isPin ? -1 : 1;
    });
  }
  final tutors = map.values.map((b) => b.build()).toList();
  tutors.sort((a, c) {
    final aPinned = a.stories.any((s) => s.isPin);
    final cPinned = c.stories.any((s) => s.isPin);
    if (aPinned == cPinned) return 0;
    return aPinned ? -1 : 1;
  });
  return tutors;
}

/// Turns the social feed into rings, dropping the tutor rows the tutor feed
/// already supplied. See `_loadStoryTutors`.
List<StoryTutor> _groupSocialStories(List<SocialFeedAuthor> authors) {
  final rings = <StoryTutor>[];
  for (final author in authors) {
    final stories = author.stories
        .where((s) => s.source == StorySource.social)
        .map(
          (s) => StoryData(
            id: s.id,
            mediaFile: s.mediaFile,
            mediaType: s.mediaType,
            description: s.description,
            source: StorySource.social,
          ),
        )
        .toList();
    if (stories.isEmpty) continue;

    rings.add(
      StoryTutor(
        // Booking runs off a tutor profile id, which the feed does not carry.
        tutorId: 0,
        userId: author.userId,
        name: author.displayName,
        image: author.profileImage,
        isEnrollable: false,
        stories: stories,
      ),
    );
  }
  return rings;
}

class _StoryTutorBuilder {
  final int tutorId;
  final String name;
  final String? image;
  final bool isEnrollable;
  final bool isLinka;
  final List<StoryData> stories = [];
  _StoryTutorBuilder({
    required this.tutorId,
    required this.name,
    this.image,
    this.isEnrollable = true,
    this.isLinka = false,
  });
  StoryTutor build() => StoryTutor(
    tutorId: tutorId,
    name: name,
    image: image,
    stories: stories,
    isEnrollable: isEnrollable,
    isLinka: isLinka,
  );
}

class _Article {
  final int id;
  final String title;
  final String? category;
  final bool isNew;

  const _Article({
    required this.id,
    required this.title,
    this.category,
    this.isNew = false,
  });

  factory _Article.fromJson(Map<String, dynamic> json) {
    return _Article(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      category: json['category'] as String?,
      isNew: json['is_new'] as bool? ?? false,
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

  // Keys to drive the self-contained webinar/debate blocks on pull-to-refresh.
  final GlobalKey<_WebinarBlockState> _webinarKey = GlobalKey();
  final GlobalKey<CategoryGridState> _categoryKey = GlobalKey();
  final GlobalKey<_DebateBlockState> _debateKey = GlobalKey();

  bool get _isInitialLoading =>
      _loadingStories &&
      _loadingLessons &&
      _loadingPodcasts &&
      _loadingArticles;

  @override
  void initState() {
    super.initState();
    _bootstrapRole();
    _loadViewedStories();
    _loadStoryTutors();
    _loadTodaysLessons();
    _loadPodcasts();
    _loadArticles();
    _loadCourses();
    _loadCourseReels();
    _loadSavedArticles();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    NotificationService.registerDevice().catchError((_) {});
    NotificationService.listenTokenRefresh();
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (info != null && mounted) {
      await showUpdateDialog(context, info);
    }
    // After the update prompt, never on top of it: one card per launch.
    if (mounted) await _showAnnouncement();
  }

  /// The "what's new" popup for a freshly added course or feature. The
  /// server already filtered to cards this account has not seen, so the
  /// first one is the one to show; closing or opening it marks it seen.
  Future<void> _showAnnouncement() async {
    if (AnnouncementService.shownThisSession) return;
    List<Announcement> items;
    try {
      items = await AnnouncementService.fetchUnseen();
    } catch (_) {
      return;
    }
    if (items.isEmpty || !mounted || AnnouncementService.shownThisSession) return;
    AnnouncementService.shownThisSession = true;
    final item = items.first;
    final open = await showAnnouncementPopup(context, item);
    AnnouncementService.markSeen(item.id);
    if (!open || !mounted) return;
    await AnnouncementTarget.open(
      context,
      item.target,
      selectTab: _selectHomeTab,
      openSpeakingPractice: _openSpeakingTraining,
    );
  }

  /// Bottom-tab indices differ between the two layouts (see [_buildScaffold]).
  void _selectHomeTab(HomeTab tab) {
    final index = switch (tab) {
      HomeTab.chats => 1,
      HomeTab.tutors => _isTeacher ? 0 : 2,
      HomeTab.profile => _isTeacher ? 4 : 3,
    };
    if (mounted) setState(() => _selectedTab = index);
  }

  // TODO: remove before release — test-only trigger
  void _showTestUpdateDialog() {
    showUpdateDialog(
      context,
      const UpdateInfo(
        hasUpdate: true,
        isForce: false,
        title: 'New Update Available',
        message:
            'A new version of Linka is available. Update now to get the latest features and improvements.',
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
            builder: (_) =>
                ProfileSetupScreen(role: me.isTeacher ? 'tutor' : 'student'),
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

  /// Re-fetches the authenticated user and updates the tutor activation
  /// status so the pending banner reflects an admin approval on refresh.
  Future<void> _refreshTutorStatus() async {
    try {
      final me = await UserService.fetchMe();
      if (!mounted) return;
      setState(() => _tutorAccountStatus = me.tutorAccountStatus);
    } catch (_) {
      // Best-effort: keep the last known status on failure.
    }
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

  /// The rail has two sources, in this order.
  ///
  /// `/tutors/stories/` is Linka's own stories plus every active tutor's, shown
  /// to everyone. `/social/feed/stories/` is every student who posted in the
  /// last day, this account's own stories first — following decides the order
  /// of that rail, not who is on it.
  ///
  /// Only the feed's `social` rows are taken: it also carries stories from
  /// followed *tutors*, but those are the same rows the first call already
  /// returned, and keeping them would give every followed tutor two rings. When
  /// the tutor story table is eventually folded into the social one, that filter
  /// is what goes away.
  Future<void> _loadStoryTutors() async {
    try {
      // Started together, awaited separately: `Future.wait` over two different
      // element types erases both to `dynamic` and needs casts back.
      final tutorRequest = ApiService.getList('/tutors/stories/');
      final feedRequest = SocialService.storyFeed().catchError(
        // A follow graph that fails to load should not take the tutor rail
        // down with it.
        (_) => <SocialFeedAuthor>[],
      );

      final tutorRows = await tutorRequest;
      final feed = await feedRequest;

      if (!mounted) return;
      setState(() {
        _storyTutors = _ownRingFirst([
          ..._groupStories(tutorRows),
          ..._groupSocialStories(feed),
        ]);
        _loadingStories = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingStories = false);
    }
  }

  /// Hoists this account's own ring to the front of the rail.
  ///
  /// The server already puts it first in the social feed, but the rail renders
  /// the tutor feed ahead of that one, so without this the author's own story
  /// sits behind every tutor — and now behind the community too.
  List<StoryTutor> _ownRingFirst(List<StoryTutor> rings) {
    final myId = UserService.current?.id;
    if (myId == null) return rings;
    final mine = rings.indexWhere((r) => r.userId == myId);
    if (mine <= 0) return rings;
    final ordered = [...rings];
    ordered.insert(0, ordered.removeAt(mine));
    return ordered;
  }

  /// Marks a whole ring as seen — arriving at it marks all of its stories, the
  /// same rule the web client applies.
  ///
  /// Takes the ring itself rather than an id: ids are per-table and no longer
  /// identify a ring on their own. `StoryData.viewKey` carries the source, which
  /// is what stops a tutor story and a followed student's story with the same id
  /// from marking each other as watched.
  Future<void> _onStoryViewed(StoryTutor tutor) async {
    for (final story in tutor.stories) {
      await PrefsService.markStoryViewed(story.viewKey);
      // Followers-only stories also have a read record on the server, so the
      // ring agrees on this account's other devices. Fire-and-forget — the
      // local mark above has already dimmed it.
      if (story.source == StorySource.social) {
        unawaited(SocialService.markSeen(story.id));
      }
    }
    if (!mounted) return;
    setState(() {
      for (final story in tutor.stories) {
        _viewedStories.add(story.viewKey);
      }
    });
  }

  Future<void> _loadPodcasts() async {
    try {
      final list = await ApiService.getList('/content/podcasts/');
      if (!mounted) return;
      setState(() {
        _podcasts = list
            .map((e) => Podcast.fromJson(e as Map<String, dynamic>))
            .toList();
        _loadingPodcasts = false;
      });
    } catch (e) {
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
      if (!mounted) return;
      setState(() => _loadingArticles = false);
    }
  }

  Future<void> _loadCourseReels() async {
    if (!AppFeatureService.isEnabled('course_reels')) return;
    try {
      final resume = await CourseReelsService.fetchResume();
      final hasCourses = resume.course != null ||
          (await CourseReelsService.fetchLanguages()).isNotEmpty;
      if (!mounted) return;
      setState(() {
        _reelResume = resume;
        _hasReelCourses = hasCourses;
      });
    } catch (_) {
      // Leave it hidden on failure (also before the backend ships the API).
    }
  }

  Future<void> _openCourseReels() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CourseReelsScreen()),
    );
    if (mounted) _loadCourseReels();
  }

  Future<void> _continueCourseReel(ReelResume resume) async {
    await openCourseReel(
      context,
      courseId: resume.course!.id,
      lessonId: resume.lesson?.id,
    );
    if (mounted) _loadCourseReels();
  }

  Future<void> _loadCourses() async {
    try {
      final list = await CourseService.fetchCourses();
      if (!mounted) return;
      setState(() => _courses = list);
    } catch (_) {
      // Leave the list empty so the section stays hidden on failure.
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
    } catch (e) {}
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
        await ApiService.post('/student/saved-articles/', {
          'article_id': articleId,
        });
      }
    } catch (e) {
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

  Future<void> _openSpeakingTraining() async {
    final agreed = await PrefsService.isSpeakingTermsAgreed();
    if (!mounted) return;
    if (!agreed) {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: false,
        builder: (_) => const _SpeakingTermsSheet(),
      );
      if (ok != true || !mounted) return;
      await PrefsService.setSpeakingTermsAgreed();
    }
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SpeakingTrainingScreen()));
  }

  Future<void> _refreshStudentHome() async {
    await Future.wait([
      // Re-pull feature flags so newly enabled sections (e.g. a freshly
      // added webinar) appear on refresh without waiting for an app resume.
      AppFeatureService.refresh(),
      _loadStoryTutors(),
      _loadTodaysLessons(),
      _loadPodcasts(),
      _loadArticles(),
      _loadCourses(),
      _loadCourseReels(),
      _loadSavedArticles(),
      _loadProfile(),
      // The webinar/debate blocks manage their own state, so explicitly ask
      // them to re-fetch — otherwise a freshly created session won't appear.
      _webinarKey.currentState?.refresh() ?? Future.value(),
      _debateKey.currentState?.refresh() ?? Future.value(),
      _categoryKey.currentState?.refresh() ?? Future.value(),
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
      await ApiService.patch('/bookings/${lesson.id}/cancel/', {
        'reason': reason,
      });
      _loadTodaysLessons();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
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
      final roomUrl =
          (payload['joinUrl'] ??
                  payload['join_url'] ??
                  payload['room_url'] ??
                  payload['daily_room_url'] ??
                  payload['roomUrl'] ??
                  lesson.dailyRoomUrl)
              .toString();
      final token =
          (payload['token'] ??
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
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
        final status = (booking['status'] as String? ?? '').toString();
        final startAt = DateTime.tryParse(
          booking['start_at'] as String? ??
              booking['start_time'] as String? ??
              '',
        );
        if (startAt == null) {
          continue;
        }
        final local = startAt.toLocal();
        final isToday =
            local.year == now.year &&
            local.month == now.month &&
            local.day == now.day;
        if (!isToday) {
          continue;
        }
        if (status == 'cancelled' || status == 'pending') {
          continue;
        }
        lessons.add(Lesson.fromBooking(booking));
      }
      lessons.sort((a, b) => a.timeRange.compareTo(b.timeRange));
      setState(() {
        _todaysLessons = lessons;
        _loadingLessons = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingLessons = false);
    }
  }

  List<Podcast> _podcasts = [];

  /// A course path (e.g. Linka IELTS) replaces the home feed in the Home
  /// tab, keeping the header and bottom nav around it.
  int? _openCourseId;

  List<_Article> _articles = [];

  List<Course> _courses = [];
  ReelResume? _reelResume;
  bool _hasReelCourses = false;

  Widget _buildStudentHomeBody() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The course path brings its own header with a back button.
          if (_openCourseId == null)
          _Header(
            profileImage: _profileImage,
            isTutor: false,
            onLogoLongPress: _showTestUpdateDialog,
            onAvatarTap: () => setState(() => _selectedTab = 3),
            // Posting a story is a student's only way into the social feed, so
            // it lives on the surface they land on.
            showAddStory: true,
            onStoryPosted: _loadStoryTutors,
          ),
          if (_openCourseId != null)
            Expanded(
              child: IeltsCourseView(
                key: ValueKey(_openCourseId),
                courseId: _openCourseId!,
                onBack: () => setState(() => _openCourseId = null),
              ),
            )
          else
          Expanded(
            child: _isInitialLoading
                ? Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: const _StudentHomeSkeleton(),
                    ),
                  )
                : RefreshIndicator(
                    color: context.colors.textPrimary,
                    onRefresh: _refreshStudentHome,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
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
                                const SizedBox(height: 16),
                              ] else
                                const SizedBox(height: 20),

                              // Webinar/Debate blocks carry their own bottom
                              // spacing, so they collapse fully when absent.
                              _WebinarBlock(key: _webinarKey),
                              _DebateBlock(key: _debateKey),

                              if (AppFeatureService.isEnabled('tutors'))
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 21,
                                  ),
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _selectedTab = 2),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) =>
                                          SvgPicture.asset(
                                            'assets/images/buttons/speaking-practice.svg',
                                            width: constraints.maxWidth,
                                          ),
                                    ),
                                  ),
                                ),

                              const SizedBox(height: 32),

                              if (AppFeatureService.isEnabled('bookings'))
                                _LessonsSection(
                                  lessons: _todaysLessons,
                                  loading: _loadingLessons,
                                  onSeeAll: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => LessonsScreen(
                                        onFindTutor: () => setState(
                                          () => _selectedTab = 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  onStartLesson: _joinLesson,
                                  onCancelLesson: _cancelLesson,
                                  onRatedLesson: _loadTodaysLessons,
                                ),

                              if (!UserService.isExemptFromPlus &&
                                  AppFeatureService.isEnabled('speaking')) ...[
                                const SizedBox(height: 28),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 21,
                                  ),
                                  child: GestureDetector(
                                    onTap: _openSpeakingTraining,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) =>
                                          SvgPicture.asset(
                                            'assets/images/buttons/video-chat.svg',
                                            width: constraints.maxWidth,
                                          ),
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 32),

                              // "Your progress" + subject categories.
                              CategoryGrid(
                                key: _categoryKey,
                                onOpenCourse: (course) =>
                                    setState(() => _openCourseId = course.id),
                              ),

                              if (AppFeatureService.isEnabled('ielts') ||
                                  AppFeatureService.isEnabled(
                                      'mock_tests')) ...[
                                const _IeltsSection(),
                                const SizedBox(height: 28),
                              ],

                              if (AppFeatureService.isEnabled('course_reels') &&
                                  _hasReelCourses) ...[
                                _SectionHeader(
                                  title: 'COURSE REELS',
                                  onSeeAll: _openCourseReels,
                                ),
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: _reelResume?.course != null
                                      ? ReelContinueCard(
                                          course: _reelResume!.course!,
                                          lesson: _reelResume!.lesson,
                                          onTap: () =>
                                              _continueCourseReel(_reelResume!),
                                        )
                                      : ReelsPromoBanner(
                                          onTap: _openCourseReels,
                                        ),
                                ),
                                const SizedBox(height: 28),
                              ],

                              if (AppFeatureService.isEnabled('courses') &&
                                  _courses.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: _CoursesPromoBanner(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const CoursesListScreen(),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 28),
                              ],

                              _SectionHeader(
                                title: 'PODCASTS',
                                onSeeAll: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const PodcastsListScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _PodcastsSection(
                                podcasts: _podcasts,
                                loading: _loadingPodcasts,
                              ),

                              const SizedBox(height: 28),

                              _SectionHeader(
                                title: 'ARTICLES',
                                onSeeAll: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ArticlesListScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _ArticlesSection(
                                articles: _articles,
                                loading: _loadingArticles,
                                savedArticleIds: _savedArticleIds,
                                onToggleBookmark: _toggleArticleBookmark,
                              ),

                              const SizedBox(height: 28),

                              const _SectionHeader(title: 'WATCH A MOVIE'),
                              const SizedBox(height: 12),
                              const _ComingSoonBanner(),

                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
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
    return ValueListenableBuilder<int>(
      valueListenable: AppFeatureService.notifier,
      builder: (context, _, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final navItems = _isTeacher ? _tutorNavItems : _studentNavItems;
    final tutorsEnabled = AppFeatureService.isEnabled('tutors');
    final children = _isTeacher
        ? <Widget>[
            TutorHomeBody(
              profileImage: _profileImage,
              storyTutors: _storyTutors,
              viewedStories: _viewedStories,
              loadingStories: _loadingStories,
              onStoryViewed: _onStoryViewed,
              tutorAccountStatus: _tutorAccountStatus,
              onRefreshStatus: _refreshTutorStatus,
              onAvatarTap: () => setState(() => _selectedTab = 4),
            ),
            ChatsScreen(isActive: _selectedTab == 1),
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
            ChatsScreen(isActive: _selectedTab == 1),
            tutorsEnabled
                ? const TutorsScreen()
                : const _SectionClosed(title: 'Tutors'),
            MyProfileScreen(
              onNavigateToLessons: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LessonsScreen(
                    onFindTutor: () => setState(() => _selectedTab = 2),
                  ),
                ),
              ),
            ),
          ];

    void handleNavTap(int i) {
      if (_isTeacher && i == 3) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TutorEarningsScreen()));
        return;
      }
      setState(() {
        // Tapping Home while on Home backs out of the course path.
        if (i == 0 && _selectedTab == 0) _openCourseId = null;
        _selectedTab = i;
      });
    }

    if (isTablet) {
      return Scaffold(
        backgroundColor: context.colors.background,
        body: Row(
          children: [
            _SideNav(
              items: navItems,
              selectedIndex: _selectedTab,
              onTap: handleNavTap,
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: IndexedStack(
                      index: _selectedTab,
                      children: children,
                    ),
                  ),
                  const MiniPlayerBar(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return PopScope(
      // System back closes the course path before it leaves the app.
      canPop: !(_openCourseId != null && _selectedTab == 0),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _openCourseId = null);
      },
      child: Scaffold(
      backgroundColor: context.colors.background,
      body: IndexedStack(index: _selectedTab, children: children),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayerBar(),
          _BottomNav(
            items: navItems,
            selectedIndex: _selectedTab,
            onTap: handleNavTap,
          ),
        ],
      ),
    ),
    );
  }
}

// ─── Bottom nav tab configs ───────────────────────────────────────────────────

const _studentNavItems = <_NavItem>[
  _NavItem(icon: Symbols.home_rounded, label: 'Home'),
  _NavItem(icon: Symbols.forum_rounded, label: 'Chats'),
  _NavItem(icon: Symbols.group_rounded, label: 'Tutors'),
  _NavItem(icon: Symbols.person_rounded, label: 'Profile'),
];

const _tutorNavItems = <_NavItem>[
  _NavItem(icon: Symbols.home_rounded, label: 'Home'),
  _NavItem(icon: Symbols.forum_rounded, label: 'Chats'),
  _NavItem(icon: Symbols.web_stories_rounded, label: 'Stories'),
  _NavItem(icon: Symbols.payments_rounded, label: 'Earnings'),
  _NavItem(icon: Symbols.person_rounded, label: 'Profile'),
];

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

/// Nav icon that fills in and re-tints when selected. Uses theme tokens so
/// it re-skins in dark mode (the old SVG assets had baked-in colors).
class _NavIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;
  const _NavIcon({required this.icon, required this.selected});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Icon(
      icon,
      size: 24,
      opticalSize: 24,
      fill: selected ? 1 : 0,
      weight: selected ? 500 : 400,
      color: selected ? colors.textPrimary : colors.textTertiary,
    );
  }
}

// ─── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatefulWidget {
  final String? profileImage;
  final bool isTutor;
  final VoidCallback? onLogoLongPress;
  final VoidCallback? onAvatarTap;

  /// Reloads the stories row after a story is posted, so the author's own ring
  /// appears without waiting for the next pull-to-refresh.
  final VoidCallback? onStoryPosted;

  /// Whether to offer the compose control.
  ///
  /// Off by default, which is what the tutor home relies on: tutors post from
  /// their own Stories tab, and this header is not where that flow lives.
  final bool showAddStory;

  const _Header({
    this.profileImage,
    this.isTutor = false,
    this.onLogoLongPress,
    this.onAvatarTap,
    this.onStoryPosted,
    this.showAddStory = false,
  });

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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationsInboxScreen()));
    // Inbox interactions (tap, mark-all) may have changed unread state.
    if (mounted) _refreshHasNew();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.colors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onAvatarTap,
            behavior: HitTestBehavior.opaque,
            child: CachedAvatar(imageUrl: widget.profileImage, size: 44),
          ),

          // Logo centered
          Expanded(
            child: Center(
              child: GestureDetector(
                onLongPress: widget.onLogoLongPress,
                child: SvgPicture.asset(
                  Theme.of(context).brightness == Brightness.dark
                      ? 'assets/images/branding/header-logo-dark.svg'
                      : 'assets/images/branding/header-logo.svg',
                  height: 26,
                ),
              ),
            ),
          ),

          // Compose. The two roles post to different places: a tutor's story
          // goes to the tutor feed; a student's goes to the social feed. Both
          // are seen by the whole platform, and both last 24 hours.
          if (widget.showAddStory)
            GestureDetector(
              onTap: () async {
                final posted = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => StoryUploadScreen(
                      audience: widget.isTutor
                          ? StoryAudience.tutor
                          : StoryAudience.social,
                    ),
                  ),
                );
                if (posted == true) widget.onStoryPosted?.call();
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  Symbols.add_circle_rounded,
                  color: context.colors.textPrimary,
                  size: 26,
                  opticalSize: 24,
                ),
              ),
            ),

          // Bell — red dot shown only when the inbox has unread items.
          GestureDetector(
            onTap: _openInbox,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Symbols.notifications_rounded,
                  size: 26,
                  opticalSize: 24,
                  color: context.colors.textPrimary,
                ),
                if (_hasNew)
                  Positioned(
                    top: 1,
                    right: 2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: context.colors.error,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.colors.surface,
                          width: 1.5,
                        ),
                      ),
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

class _StudentHomeSkeleton extends StatelessWidget {
  const _StudentHomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stories row
          const SizedBox(height: 24),
          const _StoriesSkeleton(),
          const SizedBox(height: 28),

          // Webinar card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 96,
              decoration: BoxDecoration(
                color: context.colors.brand,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Skeleton(width: 40, height: 40, circle: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Skeleton(height: 12, borderRadius: 6),
                        SizedBox(height: 8),
                        Skeleton(width: 160, height: 10, borderRadius: 5),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Speaking practice button placeholder
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 21),
            child: Skeleton(height: 60, borderRadius: 14),
          ),
          const SizedBox(height: 32),

          // Today's lessons header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: const [
                Skeleton(width: 120, height: 12, borderRadius: 4),
                Spacer(),
                Skeleton(width: 48, height: 12, borderRadius: 4),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              height: 98,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: 2,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: constraints.maxWidth - 52,
                    child: const Skeleton(height: 98, borderRadius: 16),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Video chat button placeholder
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 21),
            child: Skeleton(height: 60, borderRadius: 14),
          ),
          const SizedBox(height: 32),

          // Watch a movie header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: const [
                Skeleton(width: 110, height: 12, borderRadius: 4),
                Spacer(),
                Skeleton(width: 48, height: 12, borderRadius: 4),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Skeleton(height: 160, borderRadius: 14),
          ),
          const SizedBox(height: 28),

          // Podcasts header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: const [
                Skeleton(width: 80, height: 12, borderRadius: 4),
                Spacer(),
                Skeleton(width: 48, height: 12, borderRadius: 4),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 232,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 3,
              itemBuilder: (_, _) => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: SizedBox(
                  width: 158,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(height: 158, borderRadius: 18),
                      SizedBox(height: 10),
                      Skeleton(height: 12, borderRadius: 4),
                      SizedBox(height: 6),
                      Skeleton(width: 90, height: 12, borderRadius: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Articles header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: const [
                Skeleton(width: 70, height: 12, borderRadius: 4),
                Spacer(),
                Skeleton(width: 48, height: 12, borderRadius: 4),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 4,
              itemBuilder: (_, _) => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: SizedBox(
                  width: 160,
                  child: Skeleton(height: 210, borderRadius: 16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _TutorsList extends StatelessWidget {
  final List<StoryTutor> tutors;
  final Set<String> viewedStories;
  final void Function(StoryTutor tutor) onStoryViewed;
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
          isStoryViewed: tutors[i].stories.every(
            (s) => viewedStories.contains(s.viewKey),
          ),
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
  final void Function(StoryTutor tutor) onStoryViewed;
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
              onTutorViewed: onStoryViewed,
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
                      ? context.colors.accentYellow
                      : context.colors.border,
                  width: showYellowRing ? 3.5 : 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: tutor.isLinka
                    ? ClipOval(
                        child: Container(
                          width: 80,
                          height: 80,
                          color: context.colors.surface,
                          padding: const EdgeInsets.all(12),
                          child: Image.asset(
                            'assets/images/branding/new-logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      )
                    : CachedAvatar(imageUrl: tutor.image, size: 80),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tutor.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: context.colors.textPrimary,
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
  const _LessonsSection({
    required this.lessons,
    this.loading = false,
    this.onSeeAll,
    this.onStartLesson,
    this.onCancelLesson,
    this.onRatedLesson,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                "TODAY'S LESSONS",
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                  height: 1.0,
                  letterSpacing: 0,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onSeeAll,
                child: Text(
                  'See all',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textTertiary,
                    height: 1.0,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth - 52;
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
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'No lessons scheduled for today',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 13,
                    color: context.colors.textTertiary,
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
                        onStart: onStartLesson != null
                            ? () => onStartLesson!(l)
                            : null,
                        onCancel: onCancelLesson != null
                            ? () => onCancelLesson!(l)
                            : null,
                        onRated: onRatedLesson,
                      ),
                    ),
                  );
                },
              ),
            );
          },
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
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              height: 1.0,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'See all',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textTertiary,
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

// ─── Courses promo banner ──────────────────────────────────────────────────────

/// A single generic hero on the home feed that opens the courses catalogue.
/// It doesn't render specific courses — tapping it opens the full list.
class _CoursesPromoBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _CoursesPromoBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 132,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF5B3FD4),
                        Color(0xFF7A4BE0),
                        Color(0xFF9B5DE5),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -28,
                top: -28,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              ),
              Positioned(
                right: 44,
                bottom: -38,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'LIVE COURSES',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Learn live with top tutors',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Join a cohort — seats are limited',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Browse',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6C3FD4),
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Symbols.arrow_forward_rounded,
                            color: Color(0xFF6C3FD4),
                            size: 14,
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

// ─── Coming soon banner ────────────────────────────────────────────────────────

class _ComingSoonBanner extends StatelessWidget {
  const _ComingSoonBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 160,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Gradient background
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1E2040),
                      Color(0xFF272942),
                      Color(0xFF323566),
                    ],
                  ),
                ),
              ),
              // Decorative circles
              Positioned(
                right: -30,
                top: -30,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF5C542).withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                right: 30,
                bottom: -40,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF5C542).withValues(alpha: 0.06),
                  ),
                ),
              ),
              Positioned(
                left: -20,
                bottom: -20,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    // Left: text
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFF5C542,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(
                                  0xFFF5C542,
                                ).withValues(alpha: 0.4),
                                width: 1,
                              ),
                            ),
                            child: const Text(
                              'COMING SOON',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFF5C542),
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Watch & Learn\nin English',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Movies with subtitles\nto boost your skills',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withValues(alpha: 0.6),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Right: icon stack
                    SizedBox(
                      width: 90,
                      height: 110,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Back card
                          Positioned(
                            right: 0,
                            top: 10,
                            child: Transform.rotate(
                              angle: 0.18,
                              child: Container(
                                width: 62,
                                height: 88,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFF5C542,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(
                                      0xFFF5C542,
                                    ).withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Front card
                          Positioned(
                            left: 0,
                            top: 8,
                            child: Transform.rotate(
                              angle: -0.1,
                              child: Container(
                                width: 62,
                                height: 88,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    width: 1,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Symbols.play_circle_rounded,
                                    color: Color(0xFFF5C542),
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
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

// ─── IELTS section ──────────────────────────────────────────────────────────────

class _IeltsSection extends StatelessWidget {
  const _IeltsSection();

  @override
  Widget build(BuildContext context) {
    // Independently toggleable: 'ielts' = registration banner (IDP flow),
    // 'mock_tests' = mock exams + writing/speaking samples grid.
    final registrationEnabled = AppFeatureService.isEnabled('ielts');
    final mockTestsEnabled = AppFeatureService.isEnabled('mock_tests');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Registration banner
        if (registrationEnabled)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IeltsBookingScreen()),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFE4002B),
                            Color(0xFFC8102E),
                            Color(0xFFA30021),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -30,
                    top: -30,
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 40,
                    bottom: -40,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Register for IELTS',
                                style: TextStyle(
                                  fontFamily: 'SF Pro',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Get 1 month of Linka Plus, free',
                                style: TextStyle(
                                  fontFamily: 'SF Pro',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF8A001C)
                                    .withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Register',
                                style: TextStyle(
                                  fontFamily: 'SF Pro',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFC8102E),
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Symbols.arrow_forward_rounded,
                                color: Color(0xFFC8102E),
                                size: 14,
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
        ),

        if (registrationEnabled && mockTestsEnabled)
          const SizedBox(height: 10),

        // 3-button grid
        if (mockTestsEnabled)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 96,
                      child: _IeltsActionButton(
                        label: 'Speaking Samples',
                        icon: Symbols.record_voice_over_rounded,
                        colors: const [Color(0xFFFF9500), Color(0xFFF08300), Color(0xFFCC6D00)],
                        shadowColor: const Color(0xFF8F4C00),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SpeakingSamplesListScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 96,
                      child: _IeltsActionButton(
                        label: 'Writing Samples',
                        icon: Symbols.edit_rounded,
                        colors: const [Color(0xFF8A7EF0), Color(0xFF7C6CE8), Color(0xFF5F4FC7)],
                        shadowColor: const Color(0xFF3F3494),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WritingSamplesListScreen(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 202,
                  child: _IeltsActionButton(
                    label: 'Mock Exams',
                    subtitle: 'Reading · Listening\nWriting · Speaking',
                    icon: Symbols.assignment_rounded,
                    colors: const [Color(0xFF34C759), Color(0xFF2CAF4F), Color(0xFF1F8A3D)],
                    shadowColor: const Color(0xFF14602A),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MockExamsScreen()),
                    ),
                    large: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IeltsActionButton extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool large;
  final List<Color> colors;
  final Color shadowColor;

  const _IeltsActionButton({
    required this.label,
    this.subtitle,
    required this.icon,
    required this.onTap,
    this.large = false,
    this.colors = const [Color(0xFFE4002B), Color(0xFFC8102E), Color(0xFFA30021)],
    this.shadowColor = const Color(0xFF8A001C),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: shadowColor.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              right: -26,
              top: -26,
              child: Container(
                width: large ? 120 : 84,
                height: large ? 120 : 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            Positioned(
              left: -18,
              bottom: -18,
              child: Container(
                width: large ? 84 : 56,
                height: large ? 84 : 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(large ? 16 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: large ? 48 : 36,
                        height: large ? 48 : 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          color: Colors.white,
                          size: large ? 24 : 18,
                        ),
                      ),
                      Icon(
                        Symbols.arrow_outward_rounded,
                        color: Colors.white.withValues(alpha: 0.55),
                        size: large ? 18 : 14,
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: large ? 17 : 13.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.78),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Webinar block (today's session) ───────────────────────────────────────────

class _WebinarBlock extends StatefulWidget {
  const _WebinarBlock({super.key});

  @override
  State<_WebinarBlock> createState() => _WebinarBlockState();
}

class _WebinarBlockState extends State<_WebinarBlock> {
  WebinarData? _webinar;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (AppFeatureService.isEnabled('webinars')) {
      _fetchToday();
    } else {
      _loading = false;
    }
  }

  /// Re-pull the latest session, e.g. on pull-to-refresh from the parent.
  Future<void> refresh() async {
    if (!AppFeatureService.isEnabled('webinars')) return;
    await _fetchToday();
  }

  Future<void> _fetchToday() async {
    try {
      final data = await ApiService.get('/live/webinar/today/');
      if (!mounted) return;
      final hasSession = data['has_session'] as bool? ?? false;
      setState(() {
        _webinar = hasSession ? WebinarData.fromJson(data) : null;
        _loading = false;
      });
    } on ApiException {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppFeatureService.isEnabled('webinars')) {
      return const SizedBox.shrink();
    }
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            color: const Color(0xFF272942),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Color(0xFFF5C542),
                strokeWidth: 2,
              ),
            ),
          ),
        ),
      );
    }

    final webinar = _webinar;
    if (webinar == null) return const SizedBox.shrink();

    // Status badge
    final (String badgeLabel, Color badgeColor) = switch (webinar.status) {
      'live' => ('LIVE', const Color(0xFFE53935)),
      'ended' => ('ENDED', const Color(0xFF6C6C6C)),
      _ => ('UPCOMING', const Color(0xFFF5C542)),
    };

    // Time label
    String timeLabel = '';
    if (webinar.scheduledAt != null) {
      final h = webinar.scheduledAt!.hour.toString().padLeft(2, '0');
      final m = webinar.scheduledAt!.minute.toString().padLeft(2, '0');
      timeLabel = '$h:$m';
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebinarViewerScreen(webinar: webinar),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
                      Symbols.live_tv_rounded,
                      color: Color(0xFFF5C542),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                badgeLabel,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: badgeColor,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'WEBINAR',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFF5C542),
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          webinar.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  if (webinar.tutorName.isNotEmpty) ...[
                    const Icon(
                      Symbols.person_rounded,
                      size: 14,
                      color: Color(0xFFAAAAAA),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        timeLabel.isNotEmpty
                            ? '${webinar.tutorName} · $timeLabel'
                            : webinar.tutorName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (webinar.joinEnabled) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Debate block ──────────────────────────────────────────────────────────────

class _DebateBlock extends StatefulWidget {
  const _DebateBlock({super.key});

  @override
  State<_DebateBlock> createState() => _DebateBlockState();
}

class _DebateBlockState extends State<_DebateBlock>
    with SingleTickerProviderStateMixin {
  DebateState? _state;
  String? _topic;
  bool _hasSession = false;
  bool _loading = true;
  bool _failed = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    if (AppFeatureService.isEnabled('debates')) {
      _fetchState();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Re-pull the latest debate state, e.g. on pull-to-refresh from the parent.
  Future<void> refresh() async {
    if (!AppFeatureService.isEnabled('debates')) return;
    await _fetchState();
  }

  Future<void> _fetchState() async {
    try {
      final results = await Future.wait([
        DebateService.getState(),
        DebateService.today().catchError((_) {
          return const DailyDebate(topic: '');
        }),
      ]);
      final state = results[0] as DebateState;
      final daily = results[1] as DailyDebate;
      if (!mounted) return;
      setState(() {
        _state = state;
        _hasSession = daily.hasSession;
        if (daily.topic.isNotEmpty) _topic = daily.topic;
        _failed = false;
        _loading = false;
      });
    } on ApiException {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppFeatureService.isEnabled('debates')) {
      return const SizedBox.shrink();
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Skeleton(height: 168, borderRadius: 16),
      );
    }

    final state = _state;
    if (_failed || state == null || !_hasSession) {
      return const SizedBox.shrink();
    }

    // The "main" room is always available in the new flow.
    final String topic = _topic ?? 'Daily Debate';
    final int memberCount = state.members.length;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DebateRoomScreen(title: topic)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2B2B52), Color(0xFF222241)],
            ),
            border: Border.all(
              color: const Color(0xFFF5C542).withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5B7FD4).withValues(alpha: 0.30),
                blurRadius: 24,
                spreadRadius: -6,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned(
                  right: -28,
                  bottom: -34,
                  child: Icon(
                    Symbols.forum_rounded,
                    size: 150,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildBadge(
                            'LIVE NOW',
                            const Color(0xFFFF4D4D),
                            true,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'DAILY DEBATE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF5C542),
                              letterSpacing: 1.4,
                            ),
                          ),
                          const Spacer(),
                          if (memberCount > 0)
                            Row(
                              children: [
                                const Icon(
                                  Symbols.visibility_rounded,
                                  size: 13,
                                  color: Color(0xFFAEB9D6),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$memberCount',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFAEB9D6),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFF5C542), Color(0xFFE0A92E)],
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'VS',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1B2440),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              topic,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: const Color(0xFFF5C542),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Join the debate',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1B2440),
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(
                              Symbols.arrow_forward_rounded,
                              size: 17,
                              color: Color(0xFF1B2440),
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
      ),
    );
  }

  Widget _buildBadge(String label, Color color, bool animate) {
    final dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (animate) FadeTransition(opacity: _pulse, child: dot) else dot,
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Podcasts section ──────────────────────────────────────────────────────────

class _PodcastsSection extends StatefulWidget {
  final List<Podcast> podcasts;
  final bool loading;
  const _PodcastsSection({required this.podcasts, this.loading = false});

  @override
  State<_PodcastsSection> createState() => _PodcastsSectionState();
}

class _PodcastsSectionState extends State<_PodcastsSection> {
  static const _cardWidth = 158.0;
  static const _artSize = 158.0;

  final _service = PodcastPlaybackService.instance;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _position = _service.position;
    // The playing card's "x min left" only changes once a second.
    _positionSub = _service.positionStream.listen((pos) {
      if (!mounted || pos.inSeconds == _position.inSeconds) return;
      setState(() => _position = pos);
    });
    _stateSub = _service.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _service.currentTrack.addListener(_rebuild);
    PodcastProgressService.revision.addListener(_rebuild);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _service.currentTrack.removeListener(_rebuild);
    PodcastProgressService.revision.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// Queues every playable episode so the lock screen can walk the library,
  /// starting at [podcast].
  void _play(Podcast podcast) {
    final tracks = <PodcastTrack>[];
    var startIndex = 0;
    for (final p in widget.podcasts) {
      if (!p.playable) continue;
      if (p.id == podcast.id) startIndex = tracks.length;
      tracks.add(p.toTrack());
    }
    if (tracks.isEmpty) return;
    _service.setQueue(tracks, startIndex);
  }

  void _open(Podcast podcast) {
    _play(podcast);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PodcastPlayerScreen(
          podcastId: podcast.id,
          initialTitle: podcast.title,
          initialAudioUrl: podcast.audioUrl,
          initialSubtitleUrl: podcast.subtitleUrl,
          initialImageUrl: podcast.imageUrl,
        ),
      ),
    );
  }

  void _toggle(Podcast podcast) {
    if (_service.currentTrack.value?.id == podcast.id) {
      _service.togglePlay();
    } else if (podcast.playable) {
      _play(podcast);
    } else {
      _open(podcast);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return SizedBox(
        height: 232,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 3,
          itemBuilder: (_, _) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: SizedBox(
              width: _cardWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(height: _artSize, borderRadius: 18),
                  SizedBox(height: 10),
                  Skeleton(height: 12, borderRadius: 4),
                  SizedBox(height: 6),
                  Skeleton(width: 90, height: 12, borderRadius: 4),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 232,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: widget.podcasts.length,
        itemBuilder: (_, i) {
          final podcast = widget.podcasts[i];
          final isCurrent = _service.currentTrack.value?.id == podcast.id;
          final stored = PodcastProgressService.of(podcast.id);
          final position =
              isCurrent ? _position : stored?.position ?? Duration.zero;
          final duration = isCurrent && _service.duration > Duration.zero
              ? _service.duration
              : podcast.duration ?? stored?.duration ?? Duration.zero;
          return _PodcastCard(
            podcast: podcast,
            width: _cardWidth,
            artSize: _artSize,
            position: position,
            duration: duration,
            completed: stored?.completed ?? false,
            started: stored?.started ?? false,
            isCurrent: isCurrent,
            isPlaying: isCurrent && _service.isPlaying,
            onTap: () => _open(podcast),
            onToggle: () => _toggle(podcast),
          );
        },
      ),
    );
  }
}

/// Cover-art tile in the dashboard's podcast carousel, showing how far into
/// the episode the listener already is.
class _PodcastCard extends StatelessWidget {
  final Podcast podcast;
  final double width;
  final double artSize;
  final Duration position;
  final Duration duration;
  final bool completed;
  final bool started;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  const _PodcastCard({
    required this.podcast,
    required this.width,
    required this.artSize,
    required this.position,
    required this.duration,
    required this.completed,
    required this.started,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fraction = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                PodcastArtwork(
                  seed: podcast.title,
                  imageUrl: podcast.imageUrl,
                  size: artSize,
                  borderRadius: 18,
                  playing: isPlaying,
                ),
                if (podcast.isNew)
                  const Positioned(top: 10, left: 0, child: NewBadge(onColored: true)),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: GestureDetector(
                    onTap: onToggle,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        isPlaying ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                        size: 21,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
                if (started || (isCurrent && fraction > 0))
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 3,
                        backgroundColor: Colors.white.withValues(alpha: 0.35),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colors.accentYellow,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              podcast.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            _meta(context, fraction),
          ],
        ),
      ),
    );
  }

  Widget _meta(BuildContext context, double fraction) {
    final colors = context.colors;
    if (isCurrent) {
      return Row(
        children: [
          EqualizerBars(
            color: colors.accentYellow,
            height: 10,
            playing: isPlaying,
          ),
          const SizedBox(width: 5),
          Text(
            isPlaying ? 'Now playing' : 'Paused',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colors.accentYellow,
            ),
          ),
        ],
      );
    }
    if (completed) {
      return Row(
        children: [
          Icon(Symbols.check_circle_rounded, size: 13, color: colors.success),
          const SizedBox(width: 4),
          Text(
            'Played',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colors.success,
            ),
          ),
        ],
      );
    }
    final label = started && duration > Duration.zero
        ? formatRemainingLabel(duration - position)
        : podcast.formattedDuration;
    if (label.isEmpty) return const SizedBox(height: 14);
    return Text(
      label,
      style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
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
        height: 210,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 4,
          itemBuilder: (_, _) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: SizedBox(
              width: 160,
              child: Skeleton(height: 210, borderRadius: 16),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 210,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: articles.length,
        itemBuilder: (_, i) => _ArticleCard(
          article: articles[i],
          index: i,
          isSaved: savedArticleIds.contains(articles[i].id),
          onToggleBookmark: onToggleBookmark,
        ),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final _Article article;
  final int index;
  final bool isSaved;
  final void Function(int articleId) onToggleBookmark;
  const _ArticleCard({
    required this.article,
    required this.index,
    required this.isSaved,
    required this.onToggleBookmark,
  });

  static const _accents = [
    Color(0xFF4776E6),
    Color(0xFF11998E),
    Color(0xFFEB3349),
    Color(0xFFF7971E),
    Color(0xFF8E54E9),
    Color(0xFF1D976C),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = _accents[index % _accents.length];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArticleDetailScreen(articleId: article.id),
        ),
      ),
      child: Container(
        width: 160,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.border),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Colored top band with decorative shapes
            SizedBox(
              height: 110,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.hardEdge,
                children: [
                  Container(color: accent),
                  // Large decorative circle top-right
                  Positioned(
                    top: -28,
                    right: -28,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                  ),
                  // Small decorative circle bottom-left
                  Positioned(
                    bottom: -18,
                    left: -18,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  // Bookmark button
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onToggleBookmark(article.id),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: SvgPicture.asset(
                            isSaved
                                ? 'assets/images/icons/bookmarked.svg'
                                : 'assets/images/icons/bookmark_outline_16.svg',
                            width: 14,
                            height: 14,
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Linka logo centered in the band
                  Center(
                    child: SvgPicture.asset(
                      'assets/images/branding/white-logo.svg',
                      height: 28,
                      colorFilter: ColorFilter.mode(
                        Colors.white.withValues(alpha: 0.90),
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  // "NEW" badge top-left
                  if (article.isNew)
                    const Positioned(
                      top: 10,
                      left: 10,
                      child: NewBadge(onColored: true),
                    ),
                  // Article number badge
                  Positioned(
                    bottom: 10,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'ARTICLE',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Title area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Text(
                  article.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                    height: 1.35,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Colored bottom accent line
            Container(height: 3, color: accent),
          ],
        ),
      ),
    );
  }
}

// ─── Side navigation rail (tablet) ────────────────────────────────────────────

class _SideNav extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final void Function(int) onTap;
  const _SideNav({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(right: BorderSide(color: context.colors.border, width: 1)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 16),
            ...List.generate(items.length, (i) {
              final selected = i == selectedIndex;
              final item = items[i];
              return GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _NavIcon(icon: item.icon, selected: selected),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected
                              ? context.colors.textPrimary
                              : context.colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
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
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.border, width: 1)),
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
                    _NavIcon(icon: item.icon, selected: selected),
                    const SizedBox(height: 4),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected
                            ? context.colors.textPrimary
                            : context.colors.textTertiary,
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
  final void Function(StoryTutor) onStoryViewed;
  final String? tutorAccountStatus;
  final VoidCallback? onAvatarTap;
  // Re-pulls the tutor's account status (activation) on refresh, so an
  // admin approval clears the "pending" banner without a full app restart.
  final Future<void> Function()? onRefreshStatus;

  const TutorHomeBody({
    super.key,
    this.profileImage,
    required this.storyTutors,
    required this.viewedStories,
    required this.loadingStories,
    required this.onStoryViewed,
    this.tutorAccountStatus,
    this.onAvatarTap,
    this.onRefreshStatus,
  });

  @override
  State<TutorHomeBody> createState() => _TutorHomeBodyState();
}

class _TutorHomeBodyState extends State<TutorHomeBody> {
  bool _calendarMode = false;
  String _listTab = 'upcoming'; // 'upcoming' | 'past'
  List<Map<String, dynamic>> _bookings = [];
  Set<int> _busyDays = {};
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _selectedDay = DateTime.now().day;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    // Refresh the activation status alongside bookings so a freshly
    // approved tutor sees the pending banner clear on pull-to-refresh.
    final statusRefresh = widget.onRefreshStatus?.call() ?? Future.value();
    try {
      final results = await Future.wait([
        ApiService.getList('/bookings/my/'),
        statusRefresh,
      ]);
      if (!mounted) return;
      final bookings = (results[0] as List).cast<Map<String, dynamic>>();
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
    List<Map<String, dynamic>> bookings,
    DateTime month,
  ) {
    final busy = <int>{};
    for (final b in bookings) {
      final d = DateTime.tryParse(
        (b['start_at'] ?? b['start_time'] ?? '').toString(),
      );
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
      final roomUrl =
          (payload['joinUrl'] ??
                  payload['join_url'] ??
                  payload['room_url'] ??
                  payload['daily_room_url'] ??
                  payload['roomUrl'] ??
                  lesson.dailyRoomUrl)
              .toString();
      final token =
          (payload['token'] ??
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  DateTime _effectiveEndAt(Map<String, dynamic> b) {
    final endD = DateTime.tryParse(
      (b['end_at'] ?? b['end_time'] ?? '').toString(),
    );
    if (endD != null) return endD.toLocal();
    final startD = DateTime.tryParse(
      (b['start_at'] ?? b['start_time'] ?? '').toString(),
    );
    if (startD == null) return DateTime(0);
    final durationMin = (b['duration_minutes'] as num?)?.toInt() ?? 60;
    return startD.toLocal().add(Duration(minutes: durationMin));
  }

  List<Lesson> get _upcomingLessons {
    final now = DateTime.now();
    final list =
        _bookings
            .where((b) {
              final status = (b['status'] ?? '').toString();
              if (status == 'cancelled' || status == 'pending') return false;
              final startD = DateTime.tryParse(
                (b['start_at'] ?? b['start_time'] ?? '').toString(),
              );
              if (startD == null) return false;
              return _effectiveEndAt(b).isAfter(now);
            })
            .map((b) => Lesson.fromBooking(b, viewerIsTutor: true))
            .toList()
          ..sort(
            (a, b) =>
                (a.startAt ?? DateTime(0)).compareTo(b.startAt ?? DateTime(0)),
          );
    return list;
  }

  List<Lesson> get _pastLessons {
    final now = DateTime.now();
    final list =
        _bookings
            .where((b) {
              final startD = DateTime.tryParse(
                (b['start_at'] ?? b['start_time'] ?? '').toString(),
              );
              if (startD == null) return false;
              return _effectiveEndAt(b).isBefore(now);
            })
            .map((b) => Lesson.fromBooking(b, viewerIsTutor: true))
            .toList()
          ..sort(
            (a, b) =>
                (b.startAt ?? DateTime(0)).compareTo(a.startAt ?? DateTime(0)),
          );
    return list;
  }

  List<Lesson> get _selectedDayLessons {
    final selected = DateTime(
      _focusedMonth.year,
      _focusedMonth.month,
      _selectedDay,
    );
    return _bookings
        .where((b) {
          final d = DateTime.tryParse(
            (b['start_at'] ?? b['start_time'] ?? '').toString(),
          );
          if (d == null) return false;
          final local = d.toLocal();
          return local.year == selected.year &&
              local.month == selected.month &&
              local.day == selected.day;
        })
        .map((b) => Lesson.fromBooking(b, viewerIsTutor: true))
        .toList()
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
          _Header(
            profileImage: widget.profileImage,
            onAvatarTap: widget.onAvatarTap,
          ),
          if (showPendingBanner) _PendingActivationBanner(status: status),
          Expanded(
            child: RefreshIndicator(
              color: context.colors.textPrimary,
              onRefresh: _fetch,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
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
                              Text(
                                'MY LESSONS',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: context.colors.textPrimary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => setState(
                                  () => _calendarMode = !_calendarMode,
                                ),
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
                        const SizedBox(height: 24),
                      ],
                    ),
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
          Icon(Symbols.info_rounded, color: _accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _message,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
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
              color: context.colors.surfaceAlt,
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
                color: context.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  tab == 'upcoming' ? 'No upcoming lessons' : 'No past lessons',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          )
        else
          ..._groupByDay(lessons).entries.expand(
            (g) => [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: Row(
                  children: [
                    Text(
                      g.key.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    if (g.key.isToday)
                      Text(
                        'Today',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: context.colors.accentBlue,
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
            ],
          ),
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
    '',
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];
  static const _weekdays = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
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
          color: active ? context.colors.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : context.colors.textPrimary,
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
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
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
                color: context.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  'No lessons on this day',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.textTertiary,
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
    '',
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];
  static const _weekdays = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
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
    '',
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
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
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onPrevMonth,
                child: Icon(
                  Symbols.chevron_left_rounded,
                  color: context.colors.textPrimary,
                  size: 24,
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_monthNames[month]} $year',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onNextMonth,
                child: Icon(
                  Symbols.chevron_right_rounded,
                  color: context.colors.textPrimary,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: _dayHeaders
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textTertiary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                )
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
                      dayNum == now.day &&
                      month == now.month &&
                      year == now.year;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onDayTap(dayNum),
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected ? context.colors.brand : null,
                            borderRadius: BorderRadius.circular(8),
                            border: isToday && !isSelected
                                ? Border.all(
                                    color: context.colors.brand,
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
                                      : context.colors.textPrimary,
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
                                          : context.colors.success,
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

// ─── Speaking practice community-guidelines sheet ─────────────────────────────

class _SpeakingTermsSheet extends StatelessWidget {
  const _SpeakingTermsSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1F3A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Community Guidelines',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Please read and agree to our community standards before joining Speaking Practice.',
            style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          _rule(
            Symbols.person_search_rounded,
            'You will see your partner\'s name and gender before connecting — you can skip any match.',
          ),
          _rule(
            Symbols.do_not_disturb_on_rounded,
            'Zero tolerance for harassment, hate speech, or sexually inappropriate content.',
          ),
          _rule(
            Symbols.flag_rounded,
            'Use the Report or Block buttons during a call to flag abusive users instantly.',
          ),
          _rule(
            Symbols.schedule_rounded,
            'All reports are reviewed and acted upon within 24 hours; violators are suspended.',
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () => Navigator.pop(context, true),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5C542),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text(
                    'I Agree — Continue',
                    style: TextStyle(
                      color: Color(0xFF272942),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rule(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFF5C542), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Closed section placeholder ───────────────────────────────────────────────

/// Shown in place of a tab body whose feature flag is currently disabled.
class _SectionClosed extends StatelessWidget {
  final String title;
  const _SectionClosed({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: context.colors.surfaceAlt,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Symbols.lock_clock_rounded,
                    color: context.colors.textPrimary,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This section is temporarily unavailable. Please check back soon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
