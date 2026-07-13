import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'facebook_events_service.dart';

class PodcastTrack {
  final int id;
  final String title;
  final String audioUrl;
  final String? imageUrl;
  final String? subtitleUrl;
  const PodcastTrack({
    required this.id,
    required this.title,
    required this.audioUrl,
    this.imageUrl,
    this.subtitleUrl,
  });
}

class PodcastPlaybackService {
  PodcastPlaybackService._() {
    _player.currentIndexStream.listen(_onIndexChanged);
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onQueueCompleted();
      }
    });
  }

  static final PodcastPlaybackService instance = PodcastPlaybackService._();

  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<PodcastTrack?> currentTrack = ValueNotifier(null);

  List<PodcastTrack> _queue = [];
  int _currentIndex = -1;

  // Every screen shares this one player (see loadAdHoc below), so a load
  // that takes a while to prepare — e.g. a chat voice message, which is
  // fully downloaded over HTTP before it's handed to the player — can
  // finish *after* the user has navigated elsewhere and started a different
  // load (a Mock Test Listening track, a Speaking Sample). Without this
  // guard, that late completion silently hijacks playback with stale audio.
  // [beginLoad] claims a new generation; [isCurrent] tells a caller whether
  // its generation is still the latest one, i.e. nothing has loaded since.
  int _generation = 0;
  int beginLoad() => ++_generation;
  bool isCurrent(int generation) => generation == _generation;

  bool get hasNext => _currentIndex >= 0 && _currentIndex < _queue.length - 1;
  bool get hasPrevious => _currentIndex > 0;

  void _onIndexChanged(int? index) {
    if (index == null || index < 0 || index >= _queue.length) return;
    if (index == _currentIndex) return;
    _currentIndex = index;
    currentTrack.value = _queue[index];
  }

  Future<void> _onQueueCompleted() async {
    // currentTrack is null for ad-hoc playback (e.g. a chat voice message
    // sharing this player via loadAdHoc) — that's not a podcast completion.
    final finished = currentTrack.value;
    if (finished != null) {
      debugPrint('[Podcast] completed id=${finished.id} title="${finished.title}"');
      FacebookEventsService.logEvent('podcast_completed', parameters: {
        'podcast_id': finished.id,
        'podcast_title': finished.title,
        'auto_advance': false,
      });
    }
    await _player.pause();
    await _player.seek(Duration.zero);
  }

  AudioSource _sourceFor(PodcastTrack track) => AudioSource.uri(
        Uri.parse(track.audioUrl),
        tag: MediaItem(
          id: track.audioUrl,
          title: track.title,
          artUri: track.imageUrl != null ? Uri.parse(track.imageUrl!) : null,
        ),
      );

  /// Sets a playlist and starts playing from [startIndex]. The full queue is
  /// handed to the native player as one playlist so lock-screen/notification
  /// skip-next and skip-previous controls reflect the real queue position.
  Future<void> setQueue(List<PodcastTrack> tracks, int startIndex) async {
    final gen = beginLoad();
    _queue = List.of(tracks);
    if (currentTrack.value?.id == tracks[startIndex].id) {
      // Already playing the requested track; just adopt the new queue and keep
      // the index aligned so auto-advance picks up the right next track.
      _currentIndex = startIndex;
      return;
    }
    _currentIndex = startIndex;
    currentTrack.value = tracks[startIndex];
    await _player.setAudioSources(
      tracks.map(_sourceFor).toList(),
      initialIndex: startIndex,
    );
    if (!isCurrent(gen)) return;
    await _player.play();
  }

  Future<void> next() async {
    if (hasNext) await _player.seekToNext();
  }

  Future<void> previous() async {
    if (hasPrevious) await _player.seekToPrevious();
  }

  /// Loads an arbitrary local/remote audio file (e.g. a chat voice message
  /// or recording preview) into the shared player. just_audio_background
  /// permits only one live AudioPlayer per app, so anything that plays
  /// audio must reuse [player] rather than construct its own — otherwise
  /// the second instance throws "supports only a single player instance".
  /// Clears the podcast queue so the mini player and the queue-completion/
  /// index listeners above don't act on a now-stale podcast track.
  ///
  /// Pass [generation] when the caller already did slow prep (e.g. a
  /// download) before calling this and grabbed its own token via
  /// [beginLoad] beforehand — otherwise a fresh one is claimed here. Always
  /// returns whatever duration the player resolved, even if stale; check
  /// [isCurrent] with the same generation before acting on the result (e.g.
  /// calling play()) since a duration of `null` is also legitimately
  /// possible for formats that report it asynchronously.
  Future<Duration?> loadAdHoc(String id, Uri uri, {String title = '', int? generation}) async {
    final gen = generation ?? beginLoad();
    _queue = [];
    _currentIndex = -1;
    currentTrack.value = null;
    return _player.setAudioSource(
      AudioSource.uri(uri, tag: MediaItem(id: id, title: title)),
    );
  }


  AudioPlayer get player => _player;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;

  Future<void> load(PodcastTrack track) async {
    if (currentTrack.value?.id == track.id) return;
    beginLoad();
    _queue = [track];
    _currentIndex = 0;
    currentTrack.value = track;
    await _player.setAudioSource(_sourceFor(track));
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> togglePlay() =>
      _player.playing ? _player.pause() : _player.play();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  Future<void> stop() async {
    await _player.stop();
    _queue = [];
    _currentIndex = -1;
    currentTrack.value = null;
  }
}
