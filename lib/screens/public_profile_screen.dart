import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/social.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import '../widgets/cached_avatar.dart';
import '../widgets/phone_call_icon.dart';
import '../widgets/plus_badge.dart';
import 'chats_screen.dart' show openDirectConversation, startDirectCall;
import 'home_screen.dart' show StoryData;
import 'story_viewer_screen.dart';
import 'tutor_profile_screen.dart';

/// Anyone's public account: their bio, their counts, and the follow button that
/// decides whether their stories are readable.
///
/// Reached by tapping a sender in a channel, a ring in the stories row, or a
/// hit in the "new message" search on the chats screen — which is the only
/// people search in the app, and exists to start a private thread rather than
/// to browse.
///
/// [userId] is a **user** id (`UserMe.id`), not a student or tutor profile id.
class PublicProfileScreen extends StatefulWidget {
  final int userId;

  /// Shown while the profile loads, so opening from a chat message does not
  /// flash an empty header when the name is already known.
  final String? initialName;
  final String? initialImage;

  const PublicProfileScreen({
    super.key,
    required this.userId,
    this.initialName,
    this.initialImage,
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  SocialProfile? _profile;
  List<SocialUserCard> _followers = const [];
  List<SocialUserCard> _following = const [];
  List<SocialStory> _stories = const [];

  bool _loading = true;
  bool _missing = false;
  bool _followPending = false;
  bool _placingCall = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await SocialService.profile(widget.userId);
      if (!mounted) return;
      if (profile == null) {
        setState(() {
          _loading = false;
          _missing = true;
        });
        return;
      }

      // The three lists are independent; the profile had to come first only
      // for `storiesCount`, which says whether there is anything live to ask
      // for. Stories themselves are public — following gates nothing.
      final results = await Future.wait([
        SocialService.followers(widget.userId),
        SocialService.following(widget.userId),
        if (profile.storiesCount > 0)
          // Your own stories come from a different endpoint than anyone
          // else's — `/stories/my/` needs no follow check.
          profile.isMe
              ? SocialService.myStories()
              : SocialService.userStories(profile.userId),
      ]);

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _followers = results[0] as List<SocialUserCard>;
        _following = results[1] as List<SocialUserCard>;
        _stories = results.length > 2
            ? results[2] as List<SocialStory>
            : const <SocialStory>[];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppNotify.show(context, message: 'Could not open this profile.');
    }
  }

  Future<void> _toggleFollow() async {
    final profile = _profile;
    if (profile == null || _followPending) return;

    final next = !profile.isFollowing;
    setState(() {
      _followPending = true;
      // Optimistic: both directions are idempotent upstream, so a failure
      // reverts rather than leaving a wrong write behind.
      _profile = profile.copyWith(
        isFollowing: next,
        followersCount:
            (profile.followersCount + (next ? 1 : -1)).clamp(0, 1 << 30),
      );
    });

    try {
      final count = next
          ? await SocialService.follow(profile.userId)
          : await SocialService.unfollow(profile.userId);
      if (!mounted) return;
      if (count != null) {
        setState(() => _profile = _profile!.copyWith(followersCount: count));
      }
      // The counts on both sides moved, so the page reloads behind the button.
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _profile = profile);
      AppNotify.show(context, message: 'Could not update follow.');
    } finally {
      if (mounted) setState(() => _followPending = false);
    }
  }

  /// Rings this person, the same control the chat header carries — a profile
  /// reached from a chat is where the reader already is when they decide to
  /// call, and sending them back into the thread to find the button is a
  /// detour. The thread and the Plus check are the helper's business.
  Future<void> _startVideoCall() async {
    final profile = _profile;
    if (profile == null || _placingCall) return;
    setState(() => _placingCall = true);
    try {
      await startDirectCall(context, userId: profile.userId);
    } finally {
      if (mounted) setState(() => _placingCall = false);
    }
  }

  void _openStories() {
    final profile = _profile;
    if (profile == null || _stories.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryViewerScreen(
          tutors: [
            StoryTutor(
              tutorId: 0,
              userId: profile.userId,
              name: profile.displayName,
              image: profile.profileImage,
              isEnrollable: false,
              stories: _stories
                  .map((s) => StoryData(
                        id: s.id,
                        mediaFile: s.mediaFile,
                        mediaType: s.mediaType,
                        description: s.description,
                        source: s.source,
                      ))
                  .toList(),
            ),
          ],
          initialTutorIndex: 0,
        ),
      ),
    ).then((_) {
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final profile = _profile;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text(
          profile?.displayName ?? widget.initialName ?? '',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          // Placed where the chat header keeps it. A call is student-to-
          // student, so it appears on exactly the profiles that offer the
          // Message button below — never on your own, never on a tutor's.
          if (profile != null && !profile.isMe && !profile.isTutor)
            IconButton(
              icon: PhoneCallIcon(size: 24, color: colors.textPrimary),
              tooltip: 'Video call',
              onPressed: _placingCall ? null : _startVideoCall,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _missing || profile == null
              ? _EmptyState(
                  icon: Symbols.person_off_rounded,
                  title: 'Profile unavailable',
                  body: 'This account no longer exists.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      _header(profile),
                      const SizedBox(height: 20),
                      _storiesSection(profile),
                      const SizedBox(height: 24),
                      _people('Followers', _followers, profile.followersCount),
                      const SizedBox(height: 20),
                      _people('Following', _following, profile.followingCount),
                    ],
                  ),
                ),
    );
  }

  Widget _header(SocialProfile profile) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CachedAvatar(
              imageUrl: profile.profileImage ?? widget.initialImage,
              size: 72,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The badge rides beside the name, where a long name yields
                  // to it rather than pushing it off the row.
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (profile.isPlus) ...[
                        const SizedBox(width: 8),
                        const PlusBadge(compact: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          profile.isTutor ? 'Tutor' : 'Student',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (profile.subtitle != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            profile.subtitle!,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
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

        const SizedBox(height: 18),
        Row(
          children: [
            _count(profile.followersCount, 'followers'),
            const SizedBox(width: 24),
            _count(profile.followingCount, 'following'),
            const SizedBox(width: 24),
            _count(profile.storiesCount, 'stories'),
          ],
        ),

        if (profile.bio.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            profile.bio,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],

        if (profile.isFollowedBy && !profile.isMe) ...[
          const SizedBox(height: 10),
          Text(
            'Follows you',
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
        ],

        if (!profile.isMe) ...[
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: _FollowButton(
              following: profile.isFollowing,
              pending: _followPending,
              onTap: _toggleFollow,
            ),
          ),
          // Private threads are student-to-student: a tutor's profile keeps
          // its booking path and does not offer one.
          if (!profile.isTutor) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => openDirectConversation(
                  context,
                  userId: profile.userId,
                ),
                icon: const Icon(Symbols.chat_bubble_rounded, size: 18),
                label: const Text('Message'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textPrimary,
                  side: BorderSide(color: colors.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ],

        // A tutor's public account is also a shopfront; this page should not be
        // a dead end when the bookable profile is one tap away.
        if (profile.isEnrollable && profile.tutorProfileId != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      TutorProfileScreen(tutorId: profile.tutorProfileId!),
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: Text(
                'View tutor profile',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _count(int value, String label) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _storiesSection(SocialProfile profile) {
    final colors = context.colors;

    if (_stories.isEmpty) {
      return _EmptyState(
        icon: Symbols.web_stories_rounded,
        title: 'Nothing live',
        body: 'Stories disappear 24 hours after they are posted.',
      );
    }

    return GestureDetector(
      onTap: _openStories,
      child: SizedBox(
        height: 132,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _stories.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final story = _stories[i];
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 84,
                color: colors.surfaceAlt,
                child: story.isVideo
                    ? Icon(Symbols.play_circle_rounded,
                        color: colors.textTertiary)
                    : Image.network(story.mediaFile, fit: BoxFit.cover),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _people(String title, List<SocialUserCard> people, int total) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${title.toUpperCase()} ($total)',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 10),
        if (people.isEmpty)
          Text(
            'Nobody yet.',
            style: TextStyle(color: colors.textTertiary, fontSize: 13),
          )
        else
          ...people.map(
            (person) => _PersonRow(
              person: person,
              // Opening yourself from someone else's follower list would push a
              // second copy of your own profile onto the stack.
              onTap: person.userId == UserService.current?.id
                  ? null
                  : () => Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) => PublicProfileScreen(
                            userId: person.userId,
                            initialName: person.displayName,
                            initialImage: person.profileImage,
                          ),
                        ),
                      )
                      .then((_) {
                        if (mounted) _load();
                      }),
              onMessage: person.isTutor ||
                      person.userId == UserService.current?.id ||
                      (UserService.current?.isTeacher ?? false)
                  ? null
                  : () => openDirectConversation(
                        context,
                        userId: person.userId,
                      ),
            ),
          ),
      ],
    );
  }
}

class _FollowButton extends StatelessWidget {
  final bool following;
  final bool pending;
  final VoidCallback onTap;

  const _FollowButton({
    required this.following,
    required this.pending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Following is the resting state and should not shout; the call to action
    // is the one that still needs pressing.
    return ElevatedButton(
      onPressed: pending ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: following ? colors.surfaceAlt : colors.brand,
        foregroundColor: following ? colors.textPrimary : colors.onBrand,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      child: Text(
        following ? 'Following' : 'Follow',
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final SocialUserCard person;
  final VoidCallback? onTap;

  /// Opens a private thread with this person, when one is on offer. Null on
  /// your own row and on a tutor's — private threads are student-to-student.
  final VoidCallback? onMessage;

  const _PersonRow({required this.person, this.onTap, this.onMessage});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CachedAvatar(imageUrl: person.profileImage, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.displayName,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (person.subtitle != null)
                    Text(
                      person.subtitle!,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (person.isFollowing)
              Icon(Symbols.check_rounded, size: 18, color: colors.textTertiary),
            if (onMessage != null)
              IconButton(
                onPressed: onMessage,
                tooltip: 'Message',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Symbols.chat_bubble_rounded,
                  size: 18,
                  color: colors.accentBlue,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: colors.textTertiary, size: 26),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
