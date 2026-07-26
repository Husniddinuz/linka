// Typed model for the listening content served by `/content/podcasts/`.
//
// The endpoint is thin (id, title, description, audio_url, sort_order) and the
// optional fields below — cover art, subtitles, duration, category — are only
// present on some episodes, so everything past the id and title is nullable.

import '../services/podcast_playback_service.dart';

class Podcast {
  final int id;
  final String title;
  final String description;
  final String? audioUrl;
  final String? imageUrl;
  final String? subtitleUrl;
  final String? category;
  final int? durationSeconds;
  final bool isNew;

  const Podcast({
    required this.id,
    required this.title,
    this.description = '',
    this.audioUrl,
    this.imageUrl,
    this.subtitleUrl,
    this.category,
    this.durationSeconds,
    this.isNew = false,
  });

  factory Podcast.fromJson(Map<String, dynamic> json) {
    final duration = json['duration'];
    return Podcast(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      audioUrl: json['audio_url'] as String?,
      imageUrl: json['image_url'] as String? ?? json['cover_url'] as String?,
      subtitleUrl: json['subtitle_url'] as String?,
      category: json['category'] as String?,
      durationSeconds: duration is num ? duration.toInt() : null,
      isNew: json['is_new'] as bool? ?? false,
    );
  }

  bool get playable => audioUrl != null && audioUrl!.isNotEmpty;

  Duration? get duration =>
      durationSeconds == null || durationSeconds! <= 0
          ? null
          : Duration(seconds: durationSeconds!);

  /// Compact runtime for list rows: `48 min`, `1 h 12 min`, `40 sec`.
  String get formattedDuration {
    final total = durationSeconds;
    if (total == null || total <= 0) return '';
    if (total < 60) return '$total sec';
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    if (hours > 0) {
      return minutes > 0 ? '$hours h $minutes min' : '$hours h';
    }
    return '$minutes min';
  }

  PodcastTrack toTrack() => PodcastTrack(
        id: id,
        title: title,
        audioUrl: audioUrl ?? '',
        imageUrl: imageUrl,
        subtitleUrl: subtitleUrl,
      );
}
