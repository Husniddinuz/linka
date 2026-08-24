import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_constants.dart';
import 'token_service.dart';

/// The live half of the AI coach: an open microphone, and a server that
/// decides when you have finished a sentence.
///
/// The other mode uploads a finished recording and waits. This one streams,
/// and the difference is not only latency — the server owns end-of-utterance
/// detection, so neither this nor the web client needs a voice-activity
/// detector of its own, and the two behave identically for free.
///
/// The wire format is raw PCM, signed 16-bit little-endian, 16 kHz, mono,
/// base64 in a JSON frame. `record` produces exactly that in `pcm16bits`, so
/// unlike the browser — which has to convert in an `AudioWorklet` — there is
/// nothing to transcode here.
class CoachSocket {
  CoachSocket({
    required this.onEvent,
    required this.onLevel,
    required this.onClosed,
  });

  /// One decoded frame from the server: `ready`, `speech_started`,
  /// `speech_ended`, `processing`, `pronunciation`, `reply`, `corrections`,
  /// `cancelled` or `error`.
  final void Function(Map<String, dynamic> event) onEvent;

  /// Microphone loudness, 0–1, for the meter.
  final void Function(double level) onLevel;

  /// The socket closed on its own. 4401 is a stale token, 4404 a conversation
  /// that is gone; anything else is the network.
  final void Function(int? code) onClosed;

  static final String _wsBase =
      apiBaseUrl.replaceFirst(RegExp(r'^https'), 'wss').replaceFirst(
            RegExp(r'/api/v\d+/?$'),
            '',
          );

  /// 100 ms at 16 kHz, 16-bit mono. Inside the 20–200 ms the server asks for,
  /// and few enough frames a second that the JSON framing costs nothing worth
  /// measuring.
  static const _frameBytes = 3200;

  final _recorder = AudioRecorder();
  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription<dynamic>? _socketSub;
  final _pending = BytesBuilder();
  bool _muted = false;
  bool _closing = false;

  bool get isOpen => _channel != null;

  /// Opens the microphone, then the socket. Returns false if the microphone
  /// was refused — the caller falls back to typing, which is a conversation
  /// this student can still have.
  Future<bool> connect(int sessionId) async {
    if (!await _recorder.hasPermission()) return false;

    final token = await TokenService.getAccessToken();
    final uri = Uri.parse('$_wsBase/ws/ai/coach/$sessionId/?token=$token');
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;

    _socketSub = channel.stream.listen(
      (frame) {
        try {
          final decoded = jsonDecode(frame as String);
          if (decoded is Map<String, dynamic>) onEvent(decoded);
        } catch (_) {
          // A frame that is not JSON is not something this screen can act on.
        }
      },
      onDone: () {
        if (_closing) return;
        onClosed(channel.closeCode);
        stop();
      },
      onError: (_) {
        if (_closing) return;
        onClosed(null);
        stop();
      },
      cancelOnError: true,
    );

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        // The coach answers out loud through the same speaker this microphone
        // is pointed at.
        echoCancel: true,
        noiseSuppress: true,
      ),
    );

    _audioSub = stream.listen(_onChunk);
    return true;
  }

  /// Batches what the recorder hands over into frames the server likes, and
  /// reports the loudness of each one.
  ///
  /// The platform's chunk size is its own business — a few hundred bytes on
  /// one device, four kilobytes on another — so it is buffered here rather
  /// than trusted to already be a sensible frame.
  void _onChunk(Uint8List chunk) {
    if (_muted) {
      onLevel(0);
      return;
    }
    _pending.add(chunk);
    while (_pending.length >= _frameBytes) {
      final buffered = _pending.takeBytes();
      final frame = Uint8List.sublistView(buffered, 0, _frameBytes);
      if (buffered.length > _frameBytes) {
        _pending.add(Uint8List.sublistView(buffered, _frameBytes));
      }
      onLevel(_levelOf(frame));
      _channel?.sink.add(jsonEncode({
        'type': 'audio',
        'data': base64Encode(frame),
      }));
    }
  }

  /// Root mean square over the frame, scaled the way the app's own recorder
  /// meter scales it: speech sits well below full scale, and a meter that only
  /// twitches in the bottom tenth reads as a dead microphone.
  double _levelOf(Uint8List frame) {
    final samples = Int16List.sublistView(frame);
    var sum = 0.0;
    for (final sample in samples) {
      final normalised = sample / 32768.0;
      sum += normalised * normalised;
    }
    return math.min(1.0, math.sqrt(sum / samples.length) * 4);
  }

  /// Stops sending while the coach is working or speaking.
  ///
  /// The server already ignores input while it is busy, so this is not about
  /// the bytes — it is about the meter. A level that keeps moving while the
  /// coach thinks says the student is being heard when they are not. It also
  /// covers the part the server cannot: its idea of busy ends when it has sent
  /// the reply, seconds before that reply has finished playing out loud and
  /// back into the microphone.
  void setMuted(bool muted) {
    _muted = muted;
    if (muted) {
      _pending.clear();
      onLevel(0);
    }
  }

  /// "I have finished", for a room too noisy for the silence detector.
  void commit() {
    _channel?.sink.add(jsonEncode({'type': 'commit'}));
  }

  Future<void> stop() async {
    _closing = true;
    await _audioSub?.cancel();
    _audioSub = null;
    if (await _recorder.isRecording()) await _recorder.stop();
    await _socketSub?.cancel();
    _socketSub = null;
    await _channel?.sink.close();
    _channel = null;
    _pending.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}
