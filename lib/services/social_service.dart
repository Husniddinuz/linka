import 'dart:io';

import '../models/social.dart';
import 'api_service.dart';

/// The social API: public profiles, the follow graph, and stories.
///
/// One rule governs the whole surface: **a story is visible to its author and to
/// that author's followers, and to nobody else.** Following is instant and
/// public — there is no request or approval step — but profiles are readable by
/// any signed-in account while stories are not.
///
/// `/tutors/stories/` is untouched by any of this and still returns every active
/// tutor's stories to everyone. This service only decides what belongs in *your*
/// feed. See `docs/FLUTTER_SOCIAL_2026-07-29.md` in the backend repo.
class SocialService {
  /// The public profile of any account, by **user id**.
  ///
  /// Returns null when there is nobody to show: an account that does not exist,
  /// or a tutor an administrator has hidden or not yet activated.
  static Future<SocialProfile?> profile(int userId) async {
    try {
      final json = await ApiService.get('/social/profiles/$userId/');
      return SocialProfile.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Your own profile, as others see it.
  static Future<SocialProfile?> myProfile() async {
    try {
      final json = await ApiService.get('/social/profile/me/');
      return SocialProfile.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Follow an account. Idempotent — following twice succeeds rather than
  /// conflicting, so a double tap needs no guard. Returns the new follower
  /// count, which the button should render instead of refetching the profile.
  static Future<int?> follow(int userId) async {
    final json = await ApiService.post('/social/follow/$userId/', const {});
    return (json['followers_count'] as num?)?.toInt();
  }

  /// Unfollow. Also idempotent.
  static Future<int?> unfollow(int userId) async {
    final json = await ApiService.delete('/social/follow/$userId/');
    return (json['followers_count'] as num?)?.toInt();
  }

  /// These two are paginated upstream — `{count, next, previous, results}` —
  /// unlike most list endpoints here, which return a bare array. Only the first
  /// page is read: no screen shows more, and a follower list long enough to
  /// need paging does not exist yet.
  static Future<List<SocialUserCard>> followers(int userId) =>
      _cards('/social/users/$userId/followers/');

  static Future<List<SocialUserCard>> following(int userId) =>
      _cards('/social/users/$userId/following/');

  /// Accounts matching [query] by name.
  ///
  /// Upstream already drops hidden, deleted and pending-tutor accounts and
  /// excludes the caller's own row. Below two characters it does not search at
  /// all, so the round trip is skipped rather than sent to be refused.
  static Future<List<SocialUserCard>> search(String query) async {
    final term = query.trim();
    if (term.length < 2) return const [];
    return _cards('/social/users/search/?q=${Uri.encodeQueryComponent(term)}');
  }

  static Future<List<SocialUserCard>> _cards(String path) async {
    final json = await ApiService.get(path);
    final results = json['results'];
    if (results is! List) return const [];
    return results
        .whereType<Map<String, dynamic>>()
        .map(SocialUserCard.fromJson)
        .toList();
  }

  /// Live stories from every account you follow, plus your own, grouped by
  /// author and ordered by the server.
  static Future<List<SocialFeedAuthor>> storyFeed() async {
    final raw = await ApiService.getList('/social/feed/stories/');
    return raw
        .whereType<Map<String, dynamic>>()
        .map(SocialFeedAuthor.fromJson)
        // An author whose every story failed the media check has nothing to
        // put in a ring.
        .where((author) => author.stories.isNotEmpty)
        .toList();
  }

  /// Your own live stories.
  static Future<List<SocialStory>> myStories() async {
    final raw = await ApiService.getList('/social/stories/my/');
    return raw
        .whereType<Map<String, dynamic>>()
        .map(SocialStory.fromJson)
        .toList();
  }

  /// Another account's live stories.
  ///
  /// Answers 403 unless you follow them, which is the followers-only rule being
  /// enforced rather than merely advertised — check `canViewStories` on the
  /// profile first and this never fires. A refusal returns an empty list rather
  /// than throwing, so a stale profile cannot break the screen.
  static Future<List<SocialStory>> userStories(int userId) async {
    try {
      final raw = await ApiService.getList('/social/users/$userId/stories/');
      return raw
          .whereType<Map<String, dynamic>>()
          .map(SocialStory.fromJson)
          .toList();
    } on ApiException catch (e) {
      if (e.statusCode == 403 || e.statusCode == 404) return const [];
      rethrow;
    }
  }

  /// Post a story, visible to your followers for 24 hours.
  ///
  /// Streams the file from disk rather than sending base64 in JSON, so a large
  /// video is never held in memory whole. The server re-encodes video in the
  /// background and compresses images inline.
  static Future<void> postStory({
    required File media,
    String? description,
    UploadProgressCallback? onProgress,
  }) async {
    await ApiService.postMultipart(
      '/social/stories/',
      files: {'media_file': media},
      fields: {
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
      },
      onProgress: onProgress,
    );
  }

  static Future<void> deleteStory(int storyId) =>
      ApiService.delete('/social/stories/$storyId/');

  /// Record that this account watched a story, so the ring agrees on their
  /// other devices.
  ///
  /// Only meaningful for [StorySource.social]; tutor stories have no server view
  /// record. Failures are swallowed: the local mark has already dimmed the ring
  /// and a lost write costs nothing but a ring relighting elsewhere.
  static Future<void> markSeen(int storyId) async {
    try {
      await ApiService.post('/social/stories/$storyId/seen/', const {});
    } catch (_) {
      // Deliberately ignored — see above.
    }
  }
}
