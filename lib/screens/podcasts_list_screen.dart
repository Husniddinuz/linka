import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/podcast.dart';
import '../services/api_service.dart';
import '../services/facebook_events_service.dart';
import '../services/podcast_playback_service.dart';
import '../services/podcast_progress_service.dart';
import '../theme/app_colors.dart';
import '../widgets/new_badge.dart';
import '../widgets/podcast_artwork.dart';
import '../widgets/skeleton.dart';
import 'podcast_player_screen.dart';

/// Which slice of the library the list is showing.
enum _EpisodeFilter { all, unplayed, inProgress, played }

extension on _EpisodeFilter {
  String get label => switch (this) {
        _EpisodeFilter.all => 'All',
        _EpisodeFilter.unplayed => 'New',
        _EpisodeFilter.inProgress => 'In progress',
        _EpisodeFilter.played => 'Played',
      };
}

/// The podcast library: browse, resume, and follow along with the transcript.
class PodcastsListScreen extends StatefulWidget {
  const PodcastsListScreen({super.key});

  @override
  State<PodcastsListScreen> createState() => _PodcastsListScreenState();
}

class _PodcastsListScreenState extends State<PodcastsListScreen> {
  final _service = PodcastPlaybackService.instance;
  final _searchController = TextEditingController();

  List<Podcast> _podcasts = [];
  bool _loading = true;
  bool _failed = false;
  String _query = '';
  _EpisodeFilter _filter = _EpisodeFilter.all;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _position = _service.position;
    // Only the row of the episode that's playing moves, but it moves once a
    // second — rebuild on whole seconds rather than on every position tick.
    _positionSub = _service.positionStream.listen((pos) {
      if (!mounted || pos.inSeconds == _position.inSeconds) return;
      setState(() => _position = pos);
    });
    _stateSub = _service.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _service.currentTrack.addListener(_onTrackChanged);
    PodcastProgressService.revision.addListener(_onProgressChanged);
    _loadPodcasts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _positionSub?.cancel();
    _stateSub?.cancel();
    _service.currentTrack.removeListener(_onTrackChanged);
    PodcastProgressService.revision.removeListener(_onProgressChanged);
    super.dispose();
  }

  void _onTrackChanged() {
    if (mounted) setState(() {});
  }

  void _onProgressChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPodcasts() async {
    try {
      final list = await ApiService.getList('/content/podcasts/');
      if (!mounted) return;
      setState(() {
        _podcasts = list
            .map((e) => Podcast.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
        _failed = false;
      });
    } catch (e) {
      debugPrint('[Podcasts] load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = _podcasts.isEmpty;
      });
    }
    if (!mounted) return;
    if (_podcasts.isEmpty && kDebugMode) {
      // Local stand-in so the transcript UI can be exercised without a
      // reachable content API.
      setState(() {
        _failed = false;
        _podcasts = const [
          Podcast(
            id: -1,
            title: 'Deep Dive: Health & Fitness',
            description:
                'Balance, risk and recovery — the ideas that underpin how we '
                'take care of ourselves.',
            audioUrl: '',
            subtitleUrl: 'asset://assets/subtitles/audio_729f7f7467.srt',
            category: 'Wellbeing',
            isNew: true,
          ),
        ];
      });
    }
  }

  // ─── Playback ───────────────────────────────────────────────────────────

  /// Queues every playable episode so lock-screen next/previous walks the
  /// library, starting at [podcast].
  void _play(Podcast podcast, {bool fromStart = false}) {
    final tracks = <PodcastTrack>[];
    var startIndex = 0;
    for (final p in _podcasts) {
      if (!p.playable) continue;
      if (p.id == podcast.id) startIndex = tracks.length;
      tracks.add(p.toTrack());
    }
    if (tracks.isEmpty) return;
    _service.setQueue(
      tracks,
      startIndex,
      initialPosition: fromStart ? Duration.zero : null,
    );
  }

  void _open(Podcast podcast, {bool fromStart = false}) {
    debugPrint('[Podcasts] opened id=${podcast.id} title="${podcast.title}"');
    FacebookEventsService.logEvent('podcast_opened', parameters: {
      'podcast_id': podcast.id,
      'podcast_title': podcast.title,
    });
    _play(podcast, fromStart: fromStart);
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

  /// Play/pause straight from a row, without leaving the list.
  void _togglePlay(Podcast podcast) {
    if (_isCurrent(podcast)) {
      _service.togglePlay();
      return;
    }
    if (!podcast.playable) {
      _open(podcast);
      return;
    }
    _play(podcast);
  }

  bool _isCurrent(Podcast podcast) =>
      _service.currentTrack.value?.id == podcast.id;

  void _showEpisodeActions(Podcast podcast) {
    final progress = PodcastProgressService.of(podcast.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                podcast.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            _sheetAction(
              icon: Symbols.replay_rounded,
              label: 'Play from the beginning',
              onTap: () {
                Navigator.pop(sheetContext);
                _open(podcast, fromStart: true);
              },
            ),
            if (progress == null || !progress.completed)
              _sheetAction(
                icon: Symbols.check_circle_rounded,
                label: 'Mark as played',
                onTap: () {
                  Navigator.pop(sheetContext);
                  PodcastProgressService.markCompleted(
                    podcast.id,
                    duration: podcast.duration,
                  );
                },
              ),
            if (progress != null)
              _sheetAction(
                icon: Symbols.restart_alt_rounded,
                label: 'Reset progress',
                onTap: () {
                  Navigator.pop(sheetContext);
                  PodcastProgressService.clear(podcast.id);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sheetAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: context.colors.textPrimary),
      title: Text(
        label,
        style: TextStyle(fontSize: 15, color: context.colors.textPrimary),
      ),
    );
  }

  // ─── Derived data ───────────────────────────────────────────────────────

  List<Podcast> get _visible {
    final query = _query.trim().toLowerCase();
    return _podcasts.where((p) {
      if (query.isNotEmpty &&
          !p.title.toLowerCase().contains(query) &&
          !p.description.toLowerCase().contains(query)) {
        return false;
      }
      final progress = PodcastProgressService.of(p.id);
      return switch (_filter) {
        _EpisodeFilter.all => true,
        _EpisodeFilter.unplayed =>
          progress == null || (!progress.started && !progress.completed),
        _EpisodeFilter.inProgress => progress?.started ?? false,
        _EpisodeFilter.played => progress?.completed ?? false,
      };
    }).toList();
  }

  /// The episode the Continue-listening card offers: the most recently played
  /// unfinished one that's still in the library.
  Podcast? get _continueEpisode {
    for (final progress in PodcastProgressService.inProgress()) {
      for (final podcast in _podcasts) {
        if (podcast.id == progress.podcastId) return podcast;
      }
    }
    return null;
  }

  /// Live position for [podcast] — the player's own clock while it's the
  /// current episode, the stored resume point otherwise.
  Duration _positionOf(Podcast podcast) {
    if (_isCurrent(podcast)) return _position;
    return PodcastProgressService.of(podcast.id)?.position ?? Duration.zero;
  }

  Duration _durationOf(Podcast podcast) {
    if (_isCurrent(podcast) && _service.duration > Duration.zero) {
      return _service.duration;
    }
    return podcast.duration ??
        PodcastProgressService.of(podcast.id)?.duration ??
        Duration.zero;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final visible = _visible;
    final continueEpisode = _continueEpisode;

    return Scaffold(
      backgroundColor: colors.background,
      body: RefreshIndicator(
        color: colors.accentYellow,
        onRefresh: _loadPodcasts,
        child: CustomScrollView(
          slivers: [
            _PodcastsHeader(
              episodeCount: _podcasts.length,
              minutesListened: _minutesListened(),
              inProgressCount: _podcasts
                  .where((p) => PodcastProgressService.of(p.id)?.started ?? false)
                  .length,
            ),
            if (_loading)
              const SliverToBoxAdapter(child: _LoadingSkeleton())
            else ...[
              if (continueEpisode != null)
                SliverToBoxAdapter(
                  child: _ContinueCard(
                    podcast: continueEpisode,
                    position: _positionOf(continueEpisode),
                    duration: _durationOf(continueEpisode),
                    playing: _isCurrent(continueEpisode) && _service.isPlaying,
                    onTap: () => _open(continueEpisode),
                    onToggle: () => _togglePlay(continueEpisode),
                  ),
                ),
              SliverToBoxAdapter(child: _buildSearchField()),
              if (_podcasts.isNotEmpty)
                SliverToBoxAdapter(child: _buildFilterRow()),
              if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    failed: _failed,
                    filtered: _podcasts.isNotEmpty,
                    onRetry: () {
                      setState(() => _loading = true);
                      _loadPodcasts();
                    },
                  ),
                )
              else
                SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final podcast = visible[i];
                    return _EpisodeTile(
                      podcast: podcast,
                      position: _positionOf(podcast),
                      duration: _durationOf(podcast),
                      progress: PodcastProgressService.of(podcast.id),
                      isCurrent: _isCurrent(podcast),
                      isPlaying: _isCurrent(podcast) && _service.isPlaying,
                      onTap: () => _open(podcast),
                      onToggle: () => _togglePlay(podcast),
                      onLongPress: () => _showEpisodeActions(podcast),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ],
        ),
      ),
    );
  }

  int _minutesListened() {
    var total = Duration.zero;
    for (final podcast in _podcasts) {
      final progress = PodcastProgressService.of(podcast.id);
      if (progress != null) total += progress.position;
    }
    return total.inMinutes;
  }

  Widget _buildSearchField() {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value),
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 15, color: colors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.surfaceAlt,
          hintText: 'Search episodes',
          hintStyle: TextStyle(fontSize: 15, color: colors.textTertiary),
          prefixIcon: Icon(Symbols.search_rounded, color: colors.textTertiary),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Symbols.close_rounded,
                      size: 18, color: colors.textTertiary),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    final colors = context.colors;
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        children: [
          for (final filter in _EpisodeFilter.values) ...[
            GestureDetector(
              onTap: () => setState(() => _filter = filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _filter == filter ? colors.brand : colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Text(
                  filter.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _filter == filter
                        ? colors.onBrand
                        : colors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────

/// Collapsing brand header with the library's at-a-glance numbers.
class _PodcastsHeader extends StatelessWidget {
  final int episodeCount;
  final int minutesListened;
  final int inProgressCount;

  const _PodcastsHeader({
    required this.episodeCount,
    required this.minutesListened,
    required this.inProgressCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SliverAppBar(
      pinned: true,
      expandedHeight: 176,
      backgroundColor: colors.brand,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Symbols.chevron_left_rounded, color: Colors.white, size: 28),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 16),
        title: const Text(
          'Podcasts',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.brand, const Color(0xFF4A3F6B)],
                ),
              ),
            ),
            Positioned(
              right: -40,
              top: -30,
              child: Icon(
                Symbols.graphic_eq_rounded,
                size: 200,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 52,
              child: Row(
                children: [
                  _stat('$episodeCount', 'episodes'),
                  _divider(),
                  _stat('$inProgressCount', 'in progress'),
                  _divider(),
                  _stat('$minutesListened', 'min listened'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: Colors.white.withValues(alpha: 0.18),
      );

  Widget _stat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ─── Continue listening ───────────────────────────────────────────────────

/// Pick-up-where-you-left-off card for the most recent unfinished episode.
class _ContinueCard extends StatelessWidget {
  final Podcast podcast;
  final Duration position;
  final Duration duration;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  const _ContinueCard({
    required this.podcast,
    required this.position,
    required this.duration,
    required this.playing,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = podcastGradient(podcast.title);
    final fraction = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: gradient.first.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PodcastArtwork(
                    seed: podcast.title,
                    imageUrl: podcast.imageUrl,
                    size: 64,
                    borderRadius: 16,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Symbols.headphones_rounded,
                                size: 13,
                                color: Colors.white.withValues(alpha: 0.75)),
                            const SizedBox(width: 5),
                            Text(
                              'CONTINUE LISTENING',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          podcast.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: onToggle,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                        color: gradient.last,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 4,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    context.colors.accentYellow,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                duration > Duration.zero
                    ? '${formatClock(position)} · ${formatRemainingLabel(duration - position)}'
                    : formatClock(position),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Episode row ──────────────────────────────────────────────────────────

class _EpisodeTile extends StatelessWidget {
  final Podcast podcast;
  final Duration position;
  final Duration duration;
  final PodcastProgress? progress;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  const _EpisodeTile({
    required this.podcast,
    required this.position,
    required this.duration,
    required this.progress,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onToggle,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final completed = progress?.completed ?? false;
    final started = progress?.started ?? false;
    final fraction = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Material(
      color: isCurrent
          ? colors.accentYellow.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PodcastArtwork(
                seed: podcast.title,
                imageUrl: podcast.imageUrl,
                size: 62,
                playing: isPlaying,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _labelRow(context),
                    Text(
                      podcast.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: completed
                            ? colors.textSecondary
                            : colors.textPrimary,
                      ),
                    ),
                    if (podcast.description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        podcast.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    _metaRow(context, completed: completed, started: started),
                    if (started || (isCurrent && fraction > 0)) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 3,
                          backgroundColor: colors.border,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isCurrent ? colors.accentYellow : colors.brand,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _playButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labelRow(BuildContext context) {
    final colors = context.colors;
    final chips = <Widget>[];
    if (podcast.isNew) chips.add(const NewBadge());
    if (podcast.category != null && podcast.category!.isNotEmpty) {
      chips.add(_chip(
        podcast.category!.toUpperCase(),
        color: colors.accentBlue,
        background: colors.accentBlue.withValues(alpha: 0.12),
      ));
    }
    if (podcast.subtitleUrl != null && podcast.subtitleUrl!.isNotEmpty) {
      chips.add(_chip(
        'TRANSCRIPT',
        color: colors.textSecondary,
        background: colors.surfaceAlt,
        icon: Symbols.closed_caption_rounded,
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }

  Widget _chip(
    String label, {
    required Color color,
    required Color background,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(
    BuildContext context, {
    required bool completed,
    required bool started,
  }) {
    final colors = context.colors;
    final parts = <Widget>[];

    if (completed) {
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.check_circle_rounded, size: 14, color: colors.success),
          const SizedBox(width: 4),
          Text(
            'Played',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.success,
            ),
          ),
        ],
      ));
    } else if (started && duration > Duration.zero) {
      parts.add(Text(
        formatRemainingLabel(duration - position),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isCurrent ? colors.accentYellow : colors.textPrimary,
        ),
      ));
    } else if (podcast.formattedDuration.isNotEmpty) {
      parts.add(Text(
        podcast.formattedDuration,
        style: TextStyle(fontSize: 12, color: colors.textSecondary),
      ));
    }

    if (isCurrent) {
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          EqualizerBars(
            color: colors.accentYellow,
            height: 11,
            playing: isPlaying,
          ),
          const SizedBox(width: 5),
          Text(
            isPlaying ? 'Now playing' : 'Paused',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.accentYellow,
            ),
          ),
        ],
      ));
    }

    if (parts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: parts,
    );
  }

  Widget _playButton(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isCurrent ? colors.brand : colors.surfaceAlt,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isPlaying ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
          size: 24,
          color: isCurrent ? colors.onBrand : colors.textPrimary,
        ),
      ),
    );
  }
}

// ─── States ───────────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        children: [
          const Skeleton(height: 132, borderRadius: 20),
          const SizedBox(height: 20),
          const Skeleton(height: 48, borderRadius: 14),
          const SizedBox(height: 20),
          for (var i = 0; i < 5; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 62, height: 62, borderRadius: 14),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(height: 13, borderRadius: 4),
                        SizedBox(height: 8),
                        Skeleton(width: 180, height: 13, borderRadius: 4),
                        SizedBox(height: 10),
                        Skeleton(width: 90, height: 11, borderRadius: 4),
                      ],
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

class _EmptyState extends StatelessWidget {
  final bool failed;
  final bool filtered;
  final VoidCallback onRetry;

  const _EmptyState({
    required this.failed,
    required this.filtered,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            failed
                ? Symbols.cloud_off_rounded
                : filtered
                    ? Symbols.search_off_rounded
                    : Symbols.podcasts_rounded,
            size: 56,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            failed
                ? "Couldn't load podcasts"
                : filtered
                    ? 'No episodes match'
                    : 'No podcasts yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            failed
                ? 'Check your connection and try again.'
                : filtered
                    ? 'Try a different search or filter.'
                    : 'New episodes land here every week.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
          ),
          if (failed) ...[
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: colors.brand),
              child: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Shared formatting ────────────────────────────────────────────────────

/// `7:04` / `1:07:04` — the running clock shown next to a progress bar.
String formatClock(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;
  final mm = hours > 0 ? minutes.toString().padLeft(2, '0') : '$minutes';
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// `12 min left` — rounded, human phrasing for how much of an episode is left.
String formatRemainingLabel(Duration remaining) {
  if (remaining.isNegative || remaining < const Duration(seconds: 30)) {
    return 'Almost done';
  }
  if (remaining.inMinutes < 1) return '${remaining.inSeconds} sec left';
  if (remaining.inMinutes < 60) return '${remaining.inMinutes} min left';
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes % 60;
  return minutes > 0 ? '$hours h $minutes min left' : '$hours h left';
}
