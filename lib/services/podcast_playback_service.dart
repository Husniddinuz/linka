import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class PodcastTrack {
  final int id;
  final String title;
  final String audioUrl;
  final String? imageUrl;
  const PodcastTrack({
    required this.id,
    required this.title,
    required this.audioUrl,
    this.imageUrl,
  });
}

class PodcastPlaybackService {
  PodcastPlaybackService._() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
      }
    });
  }

  static final PodcastPlaybackService instance = PodcastPlaybackService._();

  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<PodcastTrack?> currentTrack = ValueNotifier(null);

  AudioPlayer get player => _player;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;

  Future<void> load(PodcastTrack track) async {
    if (currentTrack.value?.id == track.id) return;
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
    currentTrack.value = null;
  }
}
