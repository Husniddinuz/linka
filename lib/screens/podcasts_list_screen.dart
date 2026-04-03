import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
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
      setState(() {
        _podcasts = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
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
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
                  itemBuilder: (context, i) {
                    final podcast = _podcasts[i];
                    final title = podcast['title'] as String? ?? '';
                    final id = podcast['id'] as int;
                    final audioUrl = podcast['audio_url'] as String?;
                    final durationSec = podcast['duration'] as int?;

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
                      title: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF272942),
                        ),
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
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PodcastPlayerScreen(
                            podcastId: id,
                            initialTitle: title,
                            initialAudioUrl: audioUrl,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
