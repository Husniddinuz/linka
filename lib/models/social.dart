/// Models for the social graph: public profiles, follow edges and stories.
///
/// Everything here is addressed by **user id** — `UserMe.id` — never by
/// `studentProfileId` or `tutorProfileId`. Students and tutors live in two
/// separate profile tables on the server, so a follow edge between them can only
/// be expressed in terms of the user row they both have. A profile id sent to
/// these endpoints resolves to the wrong person or to nobody.
///
/// See `docs/FLUTTER_SOCIAL_2026-07-29.md` in the backend repo.
library;

/// Where a story in the feed came from.
///
/// `social` stories are posted through `/social/stories/` and carry a real
/// server-side `seen`. `tutor` stories come from the older tutor story table,
/// are included when you follow that tutor, and have no server view record — so
/// their seen state is still tracked locally, as it always has been.
enum StorySource { social, tutor }

class SocialStory {
  final int id;
  final int authorId;
  final String mediaFile;
  final String mediaType; // 'photo' | 'video'
  final String? description;
  final DateTime? createdAt;
  final bool seen;
  final StorySource source;

  const SocialStory({
    required this.id,
    required this.authorId,
    required this.mediaFile,
    required this.mediaType,
    this.description,
    this.createdAt,
    this.seen = false,
    this.source = StorySource.social,
  });

  bool get isVideo => mediaType == 'video';

  /// Unique across sources.
  ///
  /// Story ids are per-table — a tutor story, a Linka story and a social story
  /// can all be id 5 — so a "seen" key built from the bare id marks unrelated
  /// stories as watched. Anything persisting read state must use this.
  String get viewKey => '${source.name}_$id';

  factory SocialStory.fromJson(Map<String, dynamic> json) {
    final raw = json['source']?.toString();
    return SocialStory(
      id: (json['id'] as num?)?.toInt() ?? 0,
      authorId: (json['author_id'] as num?)?.toInt() ?? 0,
      mediaFile: json['media_file']?.toString() ?? '',
      mediaType: json['media_type']?.toString() ?? 'photo',
      description: json['description']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      seen: json['seen'] as bool? ?? false,
      source: raw == 'tutor' ? StorySource.tutor : StorySource.social,
    );
  }
}

/// One author's live stories, as the feed returns them — already grouped and
/// ordered by the server (your own first, then anyone with something unseen).
class SocialFeedAuthor {
  final int userId;
  final String role; // 'student' | 'tutor'
  final String displayName;
  final String? profileImage;
  final bool hasUnseen;
  final List<SocialStory> stories;

  const SocialFeedAuthor({
    required this.userId,
    required this.role,
    required this.displayName,
    this.profileImage,
    this.hasUnseen = false,
    this.stories = const [],
  });

  factory SocialFeedAuthor.fromJson(Map<String, dynamic> json) {
    final raw = json['stories'];
    return SocialFeedAuthor(
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      role: json['role']?.toString() ?? 'student',
      displayName: json['display_name']?.toString() ?? '',
      profileImage: json['profile_image']?.toString(),
      hasUnseen: json['has_unseen'] as bool? ?? false,
      stories: raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(SocialStory.fromJson)
              // A story with no uploaded file cannot be shown, so it is not a
              // story as far as the rail is concerned.
              .where((s) => s.mediaFile.startsWith('http'))
              .toList()
          : const [],
    );
  }
}

/// An account in a follower list — the compact card shape.
class SocialUserCard {
  final int userId;
  final String role;
  final String displayName;
  final String? profileImage;
  final String? englishLevel;
  final double? ieltsScore;
  final bool isFollowing;

  const SocialUserCard({
    required this.userId,
    required this.role,
    required this.displayName,
    this.profileImage,
    this.englishLevel,
    this.ieltsScore,
    this.isFollowing = false,
  });

  bool get isTutor => role == 'tutor';

  /// The one-line detail under the name: a tutor's band, a student's level.
  String? get subtitle => isTutor
      ? (ieltsScore != null ? 'IELTS $ieltsScore' : null)
      : englishLevel;

  factory SocialUserCard.fromJson(Map<String, dynamic> json) => SocialUserCard(
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
        role: json['role']?.toString() ?? 'student',
        displayName: json['display_name']?.toString() ?? '',
        profileImage: json['profile_image']?.toString(),
        englishLevel: json['english_level']?.toString(),
        ieltsScore: (json['ielts_score'] as num?)?.toDouble(),
        isFollowing: json['is_following'] as bool? ?? false,
      );
}

/// One page of a follower or following list.
class SocialUserPage {
  final List<SocialUserCard> results;

  /// The whole list's length, not this page's.
  final int count;

  /// Where the next page starts, or null when this was the last one.
  final int? nextOffset;

  const SocialUserPage({
    required this.results,
    required this.count,
    this.nextOffset,
  });
}

/// A student's or tutor's public account page.
class SocialProfile {
  final int userId;
  final String role;
  final String displayName;
  final String? profileImage;
  final String bio;
  final String? englishLevel;
  final double? ieltsScore;
  final bool isEnrollable;

  /// The id the tutor endpoints take (`/tutors/{id}/`, booking). Null for
  /// students — it is *not* interchangeable with [userId].
  final int? tutorProfileId;

  final int followersCount;
  final int followingCount;
  final int storiesCount;
  final bool isMe;
  final bool isFollowing;
  final bool isFollowedBy;

  /// True while this account's Plus subscription is live — the badge on the
  /// profile header. Absent from older backends, which reads as no badge.
  final bool isPlus;

  /// Always true against a current backend: stories are public to any signed-in
  /// account. Kept because the field is still sent, and because a client built
  /// against the followers-only backend is still in the wild.
  final bool canViewStories;

  const SocialProfile({
    required this.userId,
    required this.role,
    required this.displayName,
    this.profileImage,
    this.bio = '',
    this.englishLevel,
    this.ieltsScore,
    this.isEnrollable = false,
    this.tutorProfileId,
    this.followersCount = 0,
    this.followingCount = 0,
    this.storiesCount = 0,
    this.isMe = false,
    this.isFollowing = false,
    this.isFollowedBy = false,
    this.isPlus = false,
    this.canViewStories = false,
  });

  bool get isTutor => role == 'tutor';

  String? get subtitle => isTutor
      ? (ieltsScore != null ? 'IELTS $ieltsScore' : null)
      : englishLevel;

  factory SocialProfile.fromJson(Map<String, dynamic> json) => SocialProfile(
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
        role: json['role']?.toString() ?? 'student',
        displayName: json['display_name']?.toString() ?? '',
        profileImage: json['profile_image']?.toString(),
        bio: json['bio']?.toString() ?? '',
        englishLevel: json['english_level']?.toString(),
        ieltsScore: (json['ielts_score'] as num?)?.toDouble(),
        isEnrollable: json['is_enrollable'] as bool? ?? false,
        tutorProfileId: (json['tutor_profile_id'] as num?)?.toInt(),
        followersCount: (json['followers_count'] as num?)?.toInt() ?? 0,
        followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
        storiesCount: (json['stories_count'] as num?)?.toInt() ?? 0,
        isMe: json['is_me'] as bool? ?? false,
        isFollowing: json['is_following'] as bool? ?? false,
        isFollowedBy: json['is_followed_by'] as bool? ?? false,
        isPlus: json['is_plus'] as bool? ?? false,
        canViewStories: json['can_view_stories'] as bool? ?? false,
      );

  /// Used after a follow toggle, so the header updates without a refetch.
  SocialProfile copyWith({
    bool? isFollowing,
    int? followersCount,
    bool? canViewStories,
  }) =>
      SocialProfile(
        userId: userId,
        role: role,
        displayName: displayName,
        profileImage: profileImage,
        bio: bio,
        englishLevel: englishLevel,
        ieltsScore: ieltsScore,
        isEnrollable: isEnrollable,
        tutorProfileId: tutorProfileId,
        followersCount: followersCount ?? this.followersCount,
        followingCount: followingCount,
        storiesCount: storiesCount,
        isMe: isMe,
        isFollowing: isFollowing ?? this.isFollowing,
        isFollowedBy: isFollowedBy,
        isPlus: isPlus,
        canViewStories: canViewStories ?? this.canViewStories,
      );
}
