import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/social.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import '../widgets/cached_avatar.dart';
import '../widgets/skeleton.dart';
import 'public_profile_screen.dart';

enum FollowListTab { followers, following }

/// An account's full follower and following lists, one tab each, paged as the
/// user scrolls.
///
/// Opened from your own profile's counts. Every row carries a follow button, so
/// this is also where you follow people back and prune who you follow.
/// [userId] is a **user** id (`UserMe.id`), like everything social.
class FollowListScreen extends StatefulWidget {
  final int userId;
  final String title;
  final FollowListTab initialTab;

  /// Shown in the tab labels until the first page brings the real totals.
  final int? followersCount;
  final int? followingCount;

  /// Replaces [SocialService] as the source of pages, so tests need no network.
  @visibleForTesting
  final Future<SocialUserPage> Function(FollowListTab tab, int offset)?
      loadPage;

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.title,
    this.initialTab = FollowListTab.followers,
    this.followersCount,
    this.followingCount,
    this.loadPage,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTab.index,
  );

  late final _followers = _PagedPeople(
    (offset) =>
        widget.loadPage?.call(FollowListTab.followers, offset) ??
        SocialService.followersPage(widget.userId, offset: offset),
    initialCount: widget.followersCount,
  );
  late final _following = _PagedPeople(
    (offset) =>
        widget.loadPage?.call(FollowListTab.following, offset) ??
        SocialService.followingPage(widget.userId, offset: offset),
    initialCount: widget.followingCount,
  );

  /// Follow state changed from this screen, by user id. A row reads this before
  /// its own card, so a tap in one tab shows in the other without a refetch.
  final Map<int, bool> _followOverrides = {};
  final Set<int> _pending = {};

  bool get _isMine => widget.userId == UserService.current?.id;

  @override
  void initState() {
    super.initState();
    _followers.refresh();
    _following.refresh();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _followers.dispose();
    _following.dispose();
    super.dispose();
  }

  bool _isFollowing(SocialUserCard person) =>
      _followOverrides[person.userId] ?? person.isFollowing;

  Future<void> _toggleFollow(SocialUserCard person, FollowListTab from) async {
    if (_pending.contains(person.userId)) return;
    final next = !_isFollowing(person);

    // Optimistic: both directions are idempotent upstream, so a failure reverts
    // rather than leaving a wrong write behind.
    setState(() {
      _pending.add(person.userId);
      _followOverrides[person.userId] = next;
    });
    if (_isMine) _following.adjustCount(next ? 1 : -1);

    try {
      next
          ? await SocialService.follow(person.userId)
          : await SocialService.unfollow(person.userId);
      // Following someone back adds a row to your following tab. The reverse
      // is not true: an unfollowed row stays put, showing "Follow", so a slip
      // of the thumb can be undone where it happened.
      if (_isMine && from == FollowListTab.followers) _following.refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() => _followOverrides[person.userId] = !next);
      if (_isMine) _following.adjustCount(next ? -1 : 1);
      AppNotify.show(context, message: 'Could not update follow.');
    } finally {
      if (mounted) setState(() => _pending.remove(person.userId));
    }
  }

  Future<void> _openProfile(SocialUserCard person) async {
    final before = _isFollowing(person);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(
          userId: person.userId,
          initialName: person.displayName,
          initialImage: person.profileImage,
        ),
      ),
    );
    // Their profile has a follow button of its own. Read back only this one
    // person rather than reloading lists the user may have scrolled deep into.
    try {
      final profile = await SocialService.profile(person.userId);
      if (!mounted || profile == null || profile.isFollowing == before) return;
      setState(() => _followOverrides[person.userId] = profile.isFollowing);
      if (_isMine) _following.refresh();
    } catch (_) {
      // The row keeps its last known state; pull to refresh corrects it.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text(
          widget.title,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: colors.textPrimary,
          unselectedLabelColor: colors.textTertiary,
          indicatorColor: colors.textPrimary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: colors.border,
          labelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: [
            _CountTab(label: 'Followers', people: _followers),
            _CountTab(label: 'Following', people: _following),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _list(
            _followers,
            FollowListTab.followers,
            emptyIcon: Symbols.group_rounded,
            emptyTitle: _isMine ? 'No followers yet' : 'No followers',
            emptyBody: _isMine
                ? 'When someone follows you, they will show up here.'
                : 'Nobody follows this account yet.',
          ),
          _list(
            _following,
            FollowListTab.following,
            emptyIcon: Symbols.person_add_rounded,
            emptyTitle: 'Not following anyone',
            emptyBody: _isMine
                ? 'Follow students and tutors to see their stories in your feed.'
                : 'This account does not follow anyone yet.',
          ),
        ],
      ),
    );
  }

  Widget _list(
    _PagedPeople people,
    FollowListTab tab, {
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyBody,
  }) {
    return ListenableBuilder(
      listenable: people,
      builder: (context, _) {
        if (people.items.isEmpty) {
          if (people.loading) return const _SkeletonList();
          return RefreshIndicator(
            onRefresh: people.refresh,
            // Scrollable even when empty, or there is nothing to pull.
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                people.failed
                    ? _Message(
                        icon: Symbols.cloud_off_rounded,
                        title: 'Could not load',
                        body: 'Check your connection and try again.',
                        onRetry: people.refresh,
                      )
                    : _Message(
                        icon: emptyIcon,
                        title: emptyTitle,
                        body: emptyBody,
                      ),
              ],
            ),
          );
        }

        final me = UserService.current?.id;
        return RefreshIndicator(
          onRefresh: people.refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 600) people.loadMore();
              return false;
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: people.items.length + (people.hasMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == people.items.length) return const _LoadingMore();
                final person = people.items[i];
                final following = _isFollowing(person);
                return _PersonRow(
                  person: person,
                  onTap: person.userId == me ? null : () => _openProfile(person),
                  // No button on your own row: the server refuses a self-follow.
                  button: person.userId == me
                      ? null
                      : _RowFollowButton(
                          following: following,
                          label: following
                              ? 'Following'
                              : (_isMine && tab == FollowListTab.followers
                                  ? 'Follow back'
                                  : 'Follow'),
                          pending: _pending.contains(person.userId),
                          onTap: () => _toggleFollow(person, tab),
                        ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// One tab's list, loaded a page at a time.
class _PagedPeople extends ChangeNotifier {
  final Future<SocialUserPage> Function(int offset) _fetch;

  _PagedPeople(this._fetch, {int? initialCount}) : count = initialCount;

  List<SocialUserCard> items = const [];
  int? count;
  int? _nextOffset;
  bool loading = false;
  bool _loadingMore = false;
  bool failed = false;

  /// Bumped by every refresh, so a page requested before it is dropped instead
  /// of being appended to the new list.
  int _generation = 0;
  bool _disposed = false;

  bool get hasMore => _nextOffset != null;

  Future<void> refresh() async {
    final generation = ++_generation;
    loading = true;
    failed = false;
    _notify();
    try {
      final page = await _fetch(0);
      if (generation != _generation) return;
      items = page.results;
      count = page.count;
      _nextOffset = page.nextOffset;
    } catch (_) {
      if (generation != _generation) return;
      // Rows already on screen stay; only an empty tab shows the error.
      failed = true;
    }
    loading = false;
    _notify();
  }

  Future<void> loadMore() async {
    final offset = _nextOffset;
    if (offset == null || loading || _loadingMore) return;
    final generation = _generation;
    _loadingMore = true;
    try {
      final page = await _fetch(offset);
      if (generation != _generation) return;
      // The list can shift under the offset while it is being read — someone
      // follows you mid-scroll — so a row already shown is not shown twice.
      final seen = items.map((p) => p.userId).toSet();
      items = [...items, ...page.results.where((p) => seen.add(p.userId))];
      count = page.count;
      _nextOffset = page.nextOffset;
      _notify();
    } catch (_) {
      // The next scroll tries again.
    } finally {
      _loadingMore = false;
    }
  }

  void adjustCount(int delta) {
    final current = count;
    if (current == null) return;
    count = (current + delta).clamp(0, 1 << 30);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _CountTab extends StatelessWidget {
  final String label;
  final _PagedPeople people;
  const _CountTab({required this.label, required this.people});

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: ListenableBuilder(
        listenable: people,
        builder: (context, _) => Text(
          people.count == null ? label : '$label (${people.count})',
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final SocialUserCard person;
  final VoidCallback? onTap;
  final Widget? button;

  const _PersonRow({required this.person, this.onTap, this.button});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            CachedAvatar(imageUrl: person.profileImage, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      person.isTutor ? 'Tutor' : 'Student',
                      ?person.subtitle,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (button != null) ...[
              const SizedBox(width: 12),
              button!,
            ],
          ],
        ),
      ),
    );
  }
}

class _RowFollowButton extends StatelessWidget {
  final bool following;
  final String label;
  final bool pending;
  final VoidCallback onTap;

  const _RowFollowButton({
    required this.following,
    required this.label,
    required this.pending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Same weighting as the profile's button: following is the resting state
    // and stays quiet; the action still to take is the filled one.
    return SizedBox(
      height: 34,
      child: ElevatedButton(
        onPressed: pending ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: following ? colors.surfaceAlt : colors.brand,
          foregroundColor: following ? colors.textPrimary : colors.onBrand,
          disabledBackgroundColor:
              (following ? colors.surfaceAlt : colors.brand)
                  .withValues(alpha: 0.6),
          disabledForegroundColor:
              (following ? colors.textPrimary : colors.onBrand)
                  .withValues(alpha: 0.7),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(96, 34),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      itemCount: 8,
      itemBuilder: (_, _) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Skeleton(height: 44, width: 44, circle: true),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(height: 14, width: 140, borderRadius: 6),
                  SizedBox(height: 6),
                  Skeleton(height: 11, width: 80, borderRadius: 6),
                ],
              ),
            ),
            SizedBox(width: 12),
            Skeleton(height: 34, width: 96, borderRadius: 999),
          ],
        ),
      ),
    );
  }
}

class _LoadingMore extends StatelessWidget {
  const _LoadingMore();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onRetry;

  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: colors.textTertiary, size: 28),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}
