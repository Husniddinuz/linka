import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import 'writing_sample_upload_screen.dart'
    show bandScoreInputFormatters, fieldDecoration;

/// Form for a tutor to record and submit their own IELTS Speaking sample
/// against an admin-curated topic. The tutor first picks a [_SpeakingTopic],
/// which supplies the title/question for whichever parts it defines; the
/// tutor records audio in-app or uploads an existing audio file from the
/// phone for those parts. Submission first creates the
/// parent sample, then uploads each recorded part. On full success, pops
/// with `true` so the caller can refresh its list.
class SpeakingSampleUploadScreen extends StatefulWidget {
  const SpeakingSampleUploadScreen({super.key});

  @override
  State<SpeakingSampleUploadScreen> createState() =>
      _SpeakingSampleUploadScreenState();
}

class _SpeakingSampleUploadScreenState
    extends State<SpeakingSampleUploadScreen> {
  final _bandController = TextEditingController();

  List<_SpeakingTopic> _topics = [];
  bool _loadingTopics = true;
  bool _topicsFailed = false;
  _SpeakingTopic? _selectedTopic;
  List<_PartFormState> _parts = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  @override
  void dispose() {
    _bandController.dispose();
    super.dispose();
  }

  Future<void> _loadTopics() async {
    setState(() {
      _loadingTopics = true;
      _topicsFailed = false;
    });
    try {
      final list = await ApiService.getList('/tutor/samples/speaking/topics/');
      if (!mounted) return;
      setState(() {
        _topics = list
            .map((e) => _SpeakingTopic.fromJson(e as Map<String, dynamic>))
            .toList();
        _loadingTopics = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _topics = [];
        _loadingTopics = false;
        _topicsFailed = true;
      });
    }
  }

  void _selectTopic(_SpeakingTopic topic) {
    if (_selectedTopic?.id == topic.id) return;
    // A different topic defines different parts — discard any audio
    // recorded for the previous topic's parts.
    for (final p in _parts) {
      final path = p.recordedPath;
      if (path != null) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
    }
    setState(() {
      _selectedTopic = topic;
      _parts = topic.parts.map((tp) => _PartFormState(tp)).toList();
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final topic = _selectedTopic;
    if (topic == null) {
      AppNotify.show(context, message: 'Please select a topic first.');
      return;
    }
    final recordedParts = _parts.where((p) => p.recordedPath != null).toList();
    if (recordedParts.isEmpty) {
      AppNotify.show(context,
          message: 'Please record at least one part before submitting.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final band = _bandController.text.trim();
      final created = await ApiService.postMultipart(
        '/tutor/samples/speaking/',
        fields: {
          'topic': topic.id.toString(),
          if (band.isNotEmpty) 'band_score': band,
        },
      );
      final id = (created['id'] as num?)?.toInt();
      if (id == null) {
        throw const ApiException(
            'Something went wrong creating the sample. Please try again.');
      }

      for (final p in recordedParts) {
        final path = p.recordedPath;
        if (path == null) continue;
        await ApiService.postMultipart(
          '/tutor/samples/speaking/$id/parts/',
          files: {'audio_file': File(path)},
          fields: {
            'part': p.partNumber.toString(),
          },
        );
      }

      if (!mounted) return;
      AppNotify.show(context,
          message: 'Speaking sample published!',
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

  void _showTopicPicker() {
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final topic in _topics)
                ListTile(
                  title: Text(
                    topic.title,
                    style: TextStyle(
                        color: colors.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Part${topic.parts.length > 1 ? 's' : ''} '
                    '${topic.parts.map((p) => p.part).join(', ')}',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
                  ),
                  trailing: _selectedTopic?.id == topic.id
                      ? Icon(Icons.check_rounded, color: colors.brand)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _selectTopic(topic);
                  },
                ),
            ],
          ),
        ),
      ),
    );
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
              _FieldLabel('Topic'),
              const SizedBox(height: 6),
              _buildTopicPicker(colors),
              const SizedBox(height: 20),
              _FieldLabel('Band score (optional)'),
              const SizedBox(height: 6),
              TextField(
                controller: _bandController,
                enabled: !_submitting,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: bandScoreInputFormatters(),
                style: TextStyle(fontSize: 14, color: colors.textPrimary),
                decoration: fieldDecoration(context, hint: 'e.g. 7.5'),
              ),
              if (_selectedTopic != null) ...[
                const SizedBox(height: 20),
                if (_parts.isEmpty)
                  Text(
                    'This topic has no parts configured yet.',
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  )
                else ...[
                  Text(
                    'Record or upload audio for at least one part before submitting.',
                    style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  for (int i = 0; i < _parts.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    _PartSection(
                      key: ValueKey(
                          'topic_${_selectedTopic!.id}_part_${_parts[i].partNumber}'),
                      part: _parts[i],
                      enabled: !_submitting,
                    ),
                  ],
                ],
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      (_submitting || _selectedTopic == null) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.brand,
                    foregroundColor: colors.onBrand,
                    disabledBackgroundColor: colors.surfaceAlt,
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
                          'Submit',
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

  Widget _buildTopicPicker(AppColors colors) {
    if (_loadingTopics) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: colors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: colors.textPrimary),
        ),
      );
    }
    if (_topicsFailed || _topics.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: colors.errorBg, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _topicsFailed
                    ? 'Failed to load topics.'
                    : 'No speaking topics are available yet.',
                style: TextStyle(fontSize: 13, color: colors.error),
              ),
            ),
            TextButton(onPressed: _loadTopics, child: const Text('Retry')),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: _submitting ? null : _showTopicPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedTopic?.title ?? 'Select a topic',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color:
                      _selectedTopic != null ? colors.textPrimary : colors.textTertiary,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ─── Topic models ───────────────────────────────────────────────────────────

class _SpeakingTopic {
  final int id;
  final String title;
  final List<_TopicPart> parts;

  const _SpeakingTopic({required this.id, required this.title, required this.parts});

  factory _SpeakingTopic.fromJson(Map<String, dynamic> j) {
    final partsJson = (j['parts'] as List?) ?? const [];
    final parts = partsJson
        .map((p) => _TopicPart.fromJson(p as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.part.compareTo(b.part));
    return _SpeakingTopic(
      id: (j['id'] as num?)?.toInt() ?? 0,
      title: j['title']?.toString() ?? '',
      parts: parts,
    );
  }
}

class _TopicPart {
  final int id;
  final int part;
  final String title;
  final String questionText;

  const _TopicPart({
    required this.id,
    required this.part,
    required this.title,
    required this.questionText,
  });

  factory _TopicPart.fromJson(Map<String, dynamic> j) {
    return _TopicPart(
      id: (j['id'] as num?)?.toInt() ?? 0,
      part: (j['part'] as num?)?.toInt() ?? 0,
      title: j['title']?.toString() ?? '',
      questionText: j['question_text']?.toString() ?? '',
    );
  }
}

// ─── Per-part form state ────────────────────────────────────────────────────

class _PartFormState {
  final _TopicPart topicPart;
  String? recordedPath;
  int recordedDuration = 0;

  /// Original file name when the audio came from the file picker rather
  /// than an in-app recording; null for recordings.
  String? pickedFileName;

  _PartFormState(this.topicPart);

  int get partNumber => topicPart.part;
}

// ─── Part section ───────────────────────────────────────────────────────────

class _PartSection extends StatelessWidget {
  final _PartFormState part;
  final bool enabled;
  const _PartSection({super.key, required this.part, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final topicPart = part.topicPart;
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
          Text(
            'Part ${topicPart.part}'
            '${topicPart.title.isNotEmpty ? ' · ${topicPart.title}' : ''}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          if (topicPart.questionText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                topicPart.questionText,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _FieldLabel('Audio'),
          const SizedBox(height: 6),
          _AudioRecorderControl(
            enabled: enabled,
            initialPath: part.recordedPath,
            initialDuration: part.recordedDuration,
            initialFileName: part.pickedFileName,
            onPathChanged: (p) => part.recordedPath = p,
            onDurationChanged: (d) => part.recordedDuration = d,
            onFileNameChanged: (n) => part.pickedFileName = n,
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
// for local playback). Alternatively the tutor can pick an existing audio
// file from the phone; the pick is copied into our temp dir so its
// lifecycle matches a recording (safe to delete on discard/topic change).

class _AudioRecorderControl extends StatefulWidget {
  final bool enabled;
  final String? initialPath;
  final int initialDuration;
  final String? initialFileName;
  final ValueChanged<String?> onPathChanged;
  final ValueChanged<int> onDurationChanged;
  final ValueChanged<String?> onFileNameChanged;

  const _AudioRecorderControl({
    required this.enabled,
    required this.initialPath,
    required this.initialDuration,
    required this.initialFileName,
    required this.onPathChanged,
    required this.onDurationChanged,
    required this.onFileNameChanged,
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
  String? _pickedName;
  // Static: only one native picker session may exist app-wide — a second
  // pickFiles call while one is open makes the plugin reject it
  // (multiple_request), so gate across all part controls, not per control.
  static bool _picking = false;
  bool _previewPlaying = false;

  @override
  void initState() {
    super.initState();
    _recordedPath = widget.initialPath;
    _recordedDuration = widget.initialDuration;
    _pickedName = widget.initialFileName;
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

  // Below this, the file is effectively silent/empty — e.g. the iOS
  // Simulator has no real microphone and some encoders write a near-empty
  // container (~28 bytes) instead of failing outright. A real recording of
  // even a couple of seconds is comfortably larger than this.
  static const _minRecordingBytes = 2000;

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final duration = _recordSeconds;
    setState(() {
      _isRecording = false;
      _recordSeconds = 0;
    });
    final path = await _recorder.stop();
    if (duration < 1 || path == null || !mounted) return;

    final file = File(path);
    final bytes = await file.length();
    if (bytes < _minRecordingBytes) {
      try {
        await file.delete();
      } catch (_) {}
      if (mounted) {
        AppNotify.show(context,
            message: 'Recording came out empty — try again (on a simulator, '
                'make sure a microphone input is configured, or test on a '
                'real device).');
      }
      return;
    }

    setState(() {
      _recordedPath = path;
      _recordedDuration = duration;
      _pickedName = null;
    });
    widget.onPathChanged(path);
    widget.onDurationChanged(duration);
    widget.onFileNameChanged(null);
  }

  // Matches the certificate-upload cap in `profile_setup_screen.dart`;
  // a 5-minute AAC answer is only a few MB, so this only rejects
  // pathological picks (e.g. long uncompressed WAVs).
  static const _maxPickedBytes = 50 * 1024 * 1024;

  Future<void> _pickAudioFile() async {
    if (_picking) return;
    _picking = true;
    try {
      // Not FileType.audio: on iOS that opens the Apple Music library
      // picker (MPMediaPickerController), which can't browse the Files app
      // at all — recordings saved there appear unselectable. Custom
      // extensions route through the document picker instead.
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp3', 'm4a', 'aac', 'wav', 'aiff', 'caf', 'ogg', 'opus', 'flac',
          'wma', 'amr',
        ],
      );
      if (result == null ||
          result.files.isEmpty ||
          result.files.first.path == null ||
          !mounted) {
        return;
      }
      final picked = result.files.first;
      final sourcePath = picked.path!;

      final bytes = await File(sourcePath).length();
      if (bytes < _minRecordingBytes) {
        if (mounted) {
          AppNotify.show(context,
              message: 'This audio file appears to be empty. '
                  'Please choose another one.');
        }
        return;
      }
      if (bytes > _maxPickedBytes) {
        if (mounted) {
          AppNotify.show(context,
              message: 'Audio file must be under 50 MB.');
        }
        return;
      }

      // Copy into our own uniquely-named temp file: the picker's cache path
      // is reused per file name, so two parts picking the same file would
      // share a path — and discarding one part would delete the other's
      // audio out from under it.
      final dir = await getTemporaryDirectory();
      final destPath =
          '${dir.path}/speaking_sample_pick_${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
      await File(sourcePath).copy(destPath);

      // Probe duration for the "Recorded · mm:ss" label; a failed probe is
      // not fatal — the file name is still shown.
      int duration = 0;
      final probe = ap.AudioPlayer();
      try {
        await probe.setSource(ap.DeviceFileSource(destPath));
        duration = (await probe.getDuration())?.inSeconds ?? 0;
      } catch (_) {
      } finally {
        await probe.dispose();
      }

      if (!mounted) {
        try {
          File(destPath).deleteSync();
        } catch (_) {}
        return;
      }
      setState(() {
        _recordedPath = destPath;
        _recordedDuration = duration;
        _pickedName = picked.name;
      });
      widget.onPathChanged(destPath);
      widget.onDurationChanged(duration);
      widget.onFileNameChanged(picked.name);
    } on PlatformException catch (e) {
      // A previous native picker session never completed (e.g. dismissed
      // without a callback); the plugin stays stuck until app restart.
      if (mounted) {
        AppNotify.show(context,
            message: e.code == 'multiple_request'
                ? 'The file picker is stuck from an earlier attempt — '
                    'please fully close and reopen the app.'
                : 'Could not open the file picker. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        AppNotify.show(context,
            message: 'Could not load that audio file. Please try another.');
      }
    } finally {
      _picking = false;
    }
  }

  Future<void> _discardRecording() async {
    await _disposePreviewPlayer();
    final oldPath = _recordedPath;
    setState(() {
      _recordedPath = null;
      _recordedDuration = 0;
      _pickedName = null;
      _previewPlaying = false;
    });
    widget.onPathChanged(null);
    widget.onDurationChanged(0);
    widget.onFileNameChanged(null);
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
                _pickedName != null
                    ? (_recordedDuration > 0
                        ? '$_pickedName · ${_fmt(_recordedDuration)}'
                        : _pickedName!)
                    : 'Recorded · ${_fmt(_recordedDuration)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

    return Row(
      children: [
        Expanded(
          child: _idleAction(
            colors,
            icon: Icons.mic_none_rounded,
            label: 'Record',
            onTap: widget.enabled ? _startRecording : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _idleAction(
            colors,
            icon: Icons.upload_file_rounded,
            label: 'Upload file',
            onTap: widget.enabled ? _pickAudioFile : null,
          ),
        ),
      ],
    );
  }

  Widget _idleAction(
    AppColors colors, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: colors.textPrimary, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
