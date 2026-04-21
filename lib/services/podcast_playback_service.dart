import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';

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

/// App-wide podcast player. Survives screen navigation so playback continues
/// while the user browses other tabs.
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

  Uri? _cachedIconUri;

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
    final artUri = (track.imageUrl != null && track.imageUrl!.isNotEmpty)
        ? Uri.parse(track.imageUrl!)
        : await _appIconUri();
    final source = AudioSource.uri(
      Uri.parse(track.audioUrl),
      tag: MediaItem(
        id: track.id.toString(),
        album: 'Linka',
        title: track.title.isNotEmpty ? track.title : 'Podcast',
        artUri: artUri,
      ),
    );
    await _player.setAudioSource(source);
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

  Future<Uri?> _appIconUri() async {
    if (_cachedIconUri != null) return _cachedIconUri;
    try {
      final bytes =
          await rootBundle.load('assets/images/branding/app-icon.png');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/linka-app-icon.png');
      if (!await file.exists()) {
        await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      }
      _cachedIconUri = Uri.file(file.path);
      return _cachedIconUri;
    } catch (_) {
      return null;
    }
  }
}
