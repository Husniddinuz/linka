import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import 'writing_sample_upload_screen.dart' show fieldDecoration;

/// Form for a tutor to record and submit their own IELTS Speaking sample
/// (Part 1 required, Parts 2 & 3 optional) for review. Submission first
/// creates the parent sample, then uploads each recorded part. On full
/// success, pops with `true` so the caller can refresh its list.
class SpeakingSampleUploadScreen extends StatefulWidget {
  const SpeakingSampleUploadScreen({super.key});

  @override
  State<SpeakingSampleUploadScreen> createState() =>
      _SpeakingSampleUploadScreenState();
}

class _SpeakingSampleUploadScreenState
    extends State<SpeakingSampleUploadScreen> {
  final _bandController = TextEditingController();
  final List<_PartInput> _parts = [_PartInput(1), _PartInput(2), _PartInput(3)];
  bool _submitting = false;

  @override
  void dispose() {
    _bandController.dispose();
    for (final p in _parts) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final part1 = _parts[0];
    if (part1.recordedPath == null) {
      AppNotify.show(context,
          message: 'Part 1 audio is required before submitting.');
      return;
    }
    for (final p in _parts) {
      if (p.recordedPath == null) continue;
      if (p.titleController.text.trim().isEmpty ||
          p.questionController.text.trim().isEmpty) {
        AppNotify.show(context,
            message: 'Please add a title and question for Part ${p.partNumber}.');
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final band = _bandController.text.trim();
      final created = await ApiService.postMultipart(
        '/tutor/samples/speaking/',
        fields: {
          if (band.isNotEmpty) 'band_score': band,
        },
      );
      final id = (created['id'] as num?)?.toInt();
      if (id == null) {
        throw const ApiException(
            'Something went wrong creating the sample. Please try again.');
      }

      for (final p in _parts) {
        final path = p.recordedPath;
        if (path == null) continue;
        await ApiService.postMultipart(
          '/tutor/samples/speaking/$id/parts/',
          files: {'audio_file': File(path)},
          fields: {
            'part': p.partNumber.toString(),
            'title': p.titleController.text.trim(),
            'question_text': p.questionController.text.trim(),
          },
        );
      }

      if (!mounted) return;
      AppNotify.show(context,
          message: 'Speaking sample submitted for review!',
          type: NotifyType.success);
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    } catch (_) {
      if (!mounted) return;
      AppNotify.show(context,
          message: 'Failed to submit sample. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _handleBack() {
    if (_submitting) {
      AppNotify.show(context, message: 'Submitting — please keep the app open');
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope(
      canPop: !_submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_submitting) return;
        AppNotify.show(context, message: 'Submitting — please keep the app open');
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: colors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            iconTheme: IconThemeData(color: colors.textPrimary),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
              onPressed: _handleBack,
            ),
            title: Text(
              'New speaking sample',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _FieldLabel('Band score (optional)'),
              const SizedBox(height: 6),
              TextField(
                controller: _bandController,
                enabled: !_submitting,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(fontSize: 14, color: colors.textPrimary),
                decoration: fieldDecoration(context, hint: 'e.g. 7.5'),
              ),
              const SizedBox(height: 20),
              _PartSection(part: _parts[0], required: true, enabled: !_submitting),
              const SizedBox(height: 16),
              _PartSection(part: _parts[1], required: false, enabled: !_submitting),
              const SizedBox(height: 16),
              _PartSection(part: _parts[2], required: false, enabled: !_submitting),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.brand,
                    foregroundColor: colors.onBrand,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape:
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: colors.onBrand),
                        )
                      : const Text(
                          'Submit for review',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Per-part form state ────────────────────────────────────────────────────

class _PartInput {
  final int partNumber;
  final TextEditingController titleController = TextEditingController();
  final TextEditingController questionController = TextEditingController();
  String? recordedPath;
  int recordedDuration = 0;

  _PartInput(this.partNumber);

  void dispose() {
    titleController.dispose();
    questionController.dispose();
  }
}

// ─── Part section ───────────────────────────────────────────────────────────

class _PartSection extends StatelessWidget {
  final _PartInput part;
  final bool required;
  final bool enabled;
  const _PartSection({required this.part, required this.required, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Part ${part.partNumber}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: required ? colors.errorBg : colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  required ? 'Required' : 'Optional',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: required ? colors.error : colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _FieldLabel('Title'),
          const SizedBox(height: 6),
          TextField(
            controller: part.titleController,
            enabled: enabled,
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
            decoration:
                fieldDecoration(context, hint: 'e.g. Describe a memorable trip'),
          ),
          const SizedBox(height: 12),
          _FieldLabel('Question'),
          const SizedBox(height: 6),
          TextField(
            controller: part.questionController,
            enabled: enabled,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
            decoration:
                fieldDecoration(context, hint: 'Enter the exact examiner question'),
          ),
          const SizedBox(height: 12),
          _FieldLabel('Recording'),
          const SizedBox(height: 6),
          _AudioRecorderControl(
            enabled: enabled,
            initialPath: part.recordedPath,
            initialDuration: part.recordedDuration,
            onPathChanged: (p) => part.recordedPath = p,
            onDurationChanged: (d) => part.recordedDuration = d,
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: context.colors.textSecondary,
      ),
    );
  }
}

// ─── Audio recorder control ─────────────────────────────────────────────────
//
// Adapted from the voice-message recorder in `channel_chat_screen.dart`
// (start → stop → preview, using `record` for capture and `audioplayers`
// for local playback) — the only recording UX in the app today.

class _AudioRecorderControl extends StatefulWidget {
  final bool enabled;
  final String? initialPath;
  final int initialDuration;
  final ValueChanged<String?> onPathChanged;
  final ValueChanged<int> onDurationChanged;

  const _AudioRecorderControl({
    required this.enabled,
    required this.initialPath,
    required this.initialDuration,
    required this.onPathChanged,
    required this.onDurationChanged,
  });

  @override
  State<_AudioRecorderControl> createState() => _AudioRecorderControlState();
}

class _AudioRecorderControlState extends State<_AudioRecorderControl> {
  final _recorder = AudioRecorder();
  ap.AudioPlayer? _previewPlayer;
  StreamSubscription? _previewCompleteSub;
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String? _recordedPath;
  int _recordedDuration = 0;
  bool _previewPlaying = false;

  @override
  void initState() {
    super.initState();
    _recordedPath = widget.initialPath;
    _recordedDuration = widget.initialDuration;
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    _previewCompleteSub?.cancel();
    _previewPlayer?.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        AppNotify.show(context,
            message: 'Microphone permission is required to record.');
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/speaking_sample_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100),
      path: path,
    );
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _recordSeconds = 0;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Generous cap for a full Speaking-part answer.
      if (_recordSeconds >= 300) {
        _stopRecording();
        return;
      }
      setState(() => _recordSeconds++);
    });
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final duration = _recordSeconds;
    setState(() {
      _isRecording = false;
      _recordSeconds = 0;
    });
    final path = await _recorder.stop();
    if (duration < 1 || path == null || !mounted) return;
    setState(() {
      _recordedPath = path;
      _recordedDuration = duration;
    });
    widget.onPathChanged(path);
    widget.onDurationChanged(duration);
  }

  Future<void> _discardRecording() async {
    await _disposePreviewPlayer();
    final oldPath = _recordedPath;
    setState(() {
      _recordedPath = null;
      _recordedDuration = 0;
      _previewPlaying = false;
    });
    widget.onPathChanged(null);
    widget.onDurationChanged(0);
    if (oldPath != null) {
      try {
        File(oldPath).deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _disposePreviewPlayer() async {
    await _previewCompleteSub?.cancel();
    _previewCompleteSub = null;
    final player = _previewPlayer;
    _previewPlayer = null;
    await player?.dispose();
  }

  Future<void> _togglePreviewPlay() async {
    final path = _recordedPath;
    if (path == null) return;

    if (_previewPlaying) {
      await _previewPlayer?.pause();
      if (mounted) setState(() => _previewPlaying = false);
      return;
    }

    try {
      var player = _previewPlayer;
      if (player == null) {
        player = ap.AudioPlayer();
        _previewPlayer = player;
        _previewCompleteSub = player.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _previewPlaying = false);
        });
      }
      if (player.state == ap.PlayerState.paused) {
        await player.resume();
      } else {
        await player.play(ap.DeviceFileSource(path));
      }
      if (mounted) setState(() => _previewPlaying = true);
    } catch (_) {
      if (mounted) setState(() => _previewPlaying = false);
    }
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (_recordedPath != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration:
            BoxDecoration(color: colors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            GestureDetector(
              onTap: widget.enabled ? _togglePreviewPlay : null,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: colors.brand, shape: BoxShape.circle),
                child: Icon(
                  _previewPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: colors.onBrand,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Recorded · ${_fmt(_recordedDuration)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            GestureDetector(
              onTap: widget.enabled ? _discardRecording : null,
              child: Icon(Icons.delete_outline_rounded, color: colors.error, size: 20),
            ),
          ],
        ),
      );
    }

    if (_isRecording) {
      return GestureDetector(
        onTap: widget.enabled ? _stopRecording : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration:
              BoxDecoration(color: colors.errorBg, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Icon(Icons.stop_circle_rounded, color: colors.error, size: 24),
              const SizedBox(width: 10),
              Text(
                'Recording ${_fmt(_recordSeconds)} · tap to stop',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.error,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.enabled ? _startRecording : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.mic_none_rounded, color: colors.textPrimary, size: 22),
            const SizedBox(width: 10),
            Text(
              'Tap to record audio',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
