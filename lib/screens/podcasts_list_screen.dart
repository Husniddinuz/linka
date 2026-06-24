import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import '../services/podcast_playback_service.dart';
import '../widgets/new_badge.dart';
import 'podcast_player_screen.dart';

class PodcastsListScreen extends StatefulWidget {
  const PodcastsListScreen({super.key});

  @override
  State<PodcastsListScreen> createState() => _PodcastsListScreenState();
}

class _PodcastsListScreenState extends State<PodcastsListScreen> {
  List<Map<String, dynamic>> _podcasts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPodcasts();
  }

  Future<void> _loadPodcasts() async {
    try {
      final list = await ApiService.getList('/content/podcasts/');
      if (!mounted) return;
      for (final p in list) {
        final m = p as Map<String, dynamic>;
        debugPrint('[Podcasts] id=${m['id']} audio_url=${m['audio_url']} subtitle_url=${m['subtitle_url']}');
      }
      setState(() {
        _podcasts = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Podcasts] load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
    if (!mounted) return;
    if (_podcasts.isEmpty && kDebugMode) {
      setState(() {
        _podcasts = [
          {
            'id': -1,
            'title': 'Deep Dive: Health & Fitness',
            'audio_url': '',
            'subtitle_url': 'asset://assets/subtitles/audio_729f7f7467.srt',
            'duration': null,
            'is_new': true,
          },
        ];
      });
    }
  }

  void _playFrom(int tappedIndex) {
    final tracks = <PodcastTrack>[];
    int startIndex = 0;
    for (var i = 0; i < _podcasts.length; i++) {
      final p = _podcasts[i];
      final url = p['audio_url'] as String?;
      if (url == null || url.isEmpty) continue;
      if (i == tappedIndex) startIndex = tracks.length;
      tracks.add(PodcastTrack(
        id: p['id'] as int,
        title: p['title'] as String? ?? '',
        audioUrl: url,
        imageUrl: p['image_url'] as String? ?? p['cover_url'] as String?,
        subtitleUrl: p['subtitle_url'] as String?,
      ));
    }
    if (tracks.isEmpty) return;
    PodcastPlaybackService.instance.setQueue(tracks, startIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left, color: Color(0xFF272942), size: 28),
        ),
        title: const Text(
          'Podcasts',
          style: TextStyle(
            color: Color(0xFF272942),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF5C542)))
          : _podcasts.isEmpty
              ? const Center(
                  child: Text(
                    'No podcasts available',
                    style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 16),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _podcasts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
                  itemBuilder: (context, i) {
                    final podcast = _podcasts[i];
                    final title = podcast['title'] as String? ?? '';
                    final id = podcast['id'] as int;
                    final audioUrl = podcast['audio_url'] as String?;
                    final subtitleUrl = podcast['subtitle_url'] as String?;
                    final durationSec = podcast['duration'] as int?;
                    final isNew = podcast['is_new'] as bool? ?? false;

                    String durationText = '';
                    if (durationSec != null && durationSec > 0) {
                      final m = durationSec ~/ 60;
                      final s = durationSec % 60;
                      if (m > 0 && s > 0) {
                        durationText = '$m min $s sec';
                      } else if (m > 0) {
                        durationText = '$m min';
                      } else {
                        durationText = '$s sec';
                      }
                    }

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: Color(0xFF272942),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/images/icons/podcast.svg',
                            width: 24,
                            height: 24,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF272942),
                              ),
                            ),
                          ),
                          if (isNew) ...[
                            const SizedBox(width: 8),
                            const NewBadge(),
                          ],
                        ],
                      ),
                      subtitle: durationText.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                durationText,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF6C6C6C),
                                ),
                              ),
                            )
                          : null,
                      trailing: const Icon(
                        Icons.play_circle_fill,
                        color: Color(0xFF272942),
                        size: 32,
                      ),
                      onTap: () {
                        _playFrom(i);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PodcastPlayerScreen(
                              podcastId: id,
                              initialTitle: title,
                              initialAudioUrl: audioUrl,
                              initialSubtitleUrl: subtitleUrl,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
