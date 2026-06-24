import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

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
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onTrackCompleted();
      }
    });
  }

  static final PodcastPlaybackService instance = PodcastPlaybackService._();

  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<PodcastTrack?> currentTrack = ValueNotifier(null);

  List<PodcastTrack> _queue = [];
  int _currentIndex = -1;

  bool get hasNext => _currentIndex >= 0 && _currentIndex < _queue.length - 1;

  Future<void> _onTrackCompleted() async {
    if (hasNext) {
      await _playIndex(_currentIndex + 1);
    } else {
      await _player.pause();
      await _player.seek(Duration.zero);
    }
  }

  Future<void> _playIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    final track = _queue[index];
    currentTrack.value = track;
    await _player.setAudioSource(AudioSource.uri(Uri.parse(track.audioUrl)));
    await _player.play();
  }

  /// Sets a playlist and starts playing from [startIndex]. Subsequent tracks
  /// play automatically when the current one ends.
  Future<void> setQueue(List<PodcastTrack> tracks, int startIndex) async {
    _queue = List.of(tracks);
    if (currentTrack.value?.id == tracks[startIndex].id) {
      // Already playing the requested track; just adopt the new queue and keep
      // the index aligned so auto-advance picks up the right next track.
      _currentIndex = startIndex;
      return;
    }
    await _playIndex(startIndex);
  }

  Future<void> next() async {
    if (hasNext) await _playIndex(_currentIndex + 1);
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
    _queue = [track];
    _currentIndex = 0;
    currentTrack.value = track;
    await _player.setAudioSource(AudioSource.uri(Uri.parse(track.audioUrl)));
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
