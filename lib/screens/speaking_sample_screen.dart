import 'dart:async';
import 'package:flutter/material.dart';
import '../data/speaking_sample_tutors_mock.dart';
import '../services/podcast_playback_service.dart';
import '../services/subtitle_service.dart';
import '../widgets/mock_test_styles.dart';

/// A tutor's real Speaking sample answer: photo/name/band score, with
/// Part 1/2/3 kept separate. Each part has its own audio player and a
/// live, karaoke-style transcript synced to playback via its SRT file.
/// Read-only reference content — no submission or grading.
class SpeakingSampleTutorScreen extends StatefulWidget {
  const SpeakingSampleTutorScreen({super.key, required this.tutor});

  final SpeakingSampleTutor tutor;

  @override
  State<SpeakingSampleTutorScreen> createState() => _SpeakingSampleTutorScreenState();
}

class _SpeakingSampleTutorScreenState extends State<SpeakingSampleTutorScreen> {
  final _player = PodcastPlaybackService.instance;
  StreamSubscription<Duration>? _positionSub;

  int _selectedPart = 0;
  List<SubtitleCue> _cues = [];
  List<GlobalKey> _cueKeys = [];
  int _activeCue = -1;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.positionStream.listen(_updateActiveCue);
    _loadPart(0);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _player.stop();
    super.dispose();
  }

  Future<void> _loadPart(int index) async {
    final part = widget.tutor.parts[index];
    setState(() {
      _selectedPart = index;
      _cues = [];
      _cueKeys = [];
      _activeCue = -1;
    });
    await _player.loadAdHocAsset(
      'speaking-tutor-${widget.tutor.id}-part${part.part}',
      part.audioAsset,
      title: part.title,
    );
    _player.play();
    final cues = await SubtitleService.fetchCues('asset://${part.subtitleAsset}');
    if (!mounted || _selectedPart != index) return;
    setState(() {
      _cues = cues;
      _cueKeys = List.generate(cues.length, (_) => GlobalKey());
    });
  }

  void _updateActiveCue(Duration pos) {
    if (_cues.isEmpty) return;
    final index = SubtitleService.activeCueIndex(_cues, pos);
    if (index == _activeCue) return;
    setState(() => _activeCue = index);
    _scrollToActiveCue();
  }

  void _scrollToActiveCue() {
    if (_activeCue < 0 || _activeCue >= _cueKeys.length) return;
    final ctx = _cueKeys[_activeCue].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.4,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tutor = widget.tutor;
    final part = tutor.parts[_selectedPart];
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: tutor.name),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _TutorHeader(tutor: tutor),
          const SizedBox(height: 20),
          Row(
            children: [
              for (var i = 0; i < tutor.parts.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _PartChip(
                  label: 'Part ${tutor.parts[i].part}',
                  selected: i == _selectedPart,
                  onTap: () => _loadPart(i),
                )),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: mtSoftCard(color: MockTestColors.chipBg, radius: 14),
            child: Text(
              part.questionText,
              style: const TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 14,
                height: 1.5,
                color: MockTestColors.navy,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _AudioBar(),
          const SizedBox(height: 20),
          const Text(
            'Live transcript',
            style: TextStyle(fontFamily: 'SF Pro', fontWeight: FontWeight.w700, fontSize: 15, color: MockTestColors.navy),
          ),
          const SizedBox(height: 10),
          if (_cues.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(color: MockTestColors.yellow)),
            )
          else
            _Transcript(
              cues: _cues,
              cueKeys: _cueKeys,
              activeCue: _activeCue,
              onSeek: (cue) {
                _player.seek(cue.start);
                if (!_player.isPlaying) _player.play();
              },
            ),
        ],
      ),
    );
  }
}

class _TutorHeader extends StatelessWidget {
  const _TutorHeader({required this.tutor});
  final SpeakingSampleTutor tutor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(tutor.imageAsset, width: 68, height: 68, fit: BoxFit.cover),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tutor.name,
                style: const TextStyle(fontFamily: 'SF Pro', fontSize: 17, fontWeight: FontWeight.w700, color: MockTestColors.navy),
              ),
              const SizedBox(height: 6),
              MtPill(
                background: MockTestColors.navy,
                child: Text(
                  'IELTS ${tutor.bandScore}',
                  style: const TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PartChip extends StatelessWidget {
  const _PartChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? MockTestColors.navy : MockTestColors.chipBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : MockTestColors.navy,
          ),
        ),
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({
    required this.cues,
    required this.cueKeys,
    required this.activeCue,
    required this.onSeek,
  });

  final List<SubtitleCue> cues;
  final List<GlobalKey> cueKeys;
  final int activeCue;
  final void Function(SubtitleCue cue) onSeek;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: mtSoftCard(radius: 14),
      child: Wrap(
        children: [
          for (var i = 0; i < cues.length; i++)
            Padding(
              key: cueKeys[i],
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: GestureDetector(
                onTap: () => onSeek(cues[i]),
                child: Text(
                  '${cues[i].text} ',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: i == activeCue ? 15.5 : 14,
                    height: 1.6,
                    fontWeight: i == activeCue ? FontWeight.w700 : FontWeight.w400,
                    color: i == activeCue ? MockTestColors.navy : MockTestColors.greyLight,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AudioBar extends StatelessWidget {
  const _AudioBar();

  @override
  Widget build(BuildContext context) {
    final player = PodcastPlaybackService.instance;
    return Container(
      decoration: mtSoftCard(radius: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: StreamBuilder(
        stream: player.playerStateStream,
        builder: (context, snapshot) {
          final playing = player.isPlaying;
          return Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: player.togglePlay,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(color: MockTestColors.navy, shape: BoxShape.circle),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (context, posSnap) {
                    final pos = posSnap.data ?? Duration.zero;
                    final dur = player.duration;
                    final max = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
                    final value = pos.inMilliseconds.clamp(0, max.toInt()).toDouble();
                    return SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: MockTestColors.navy,
                        inactiveTrackColor: MockTestColors.divider,
                        thumbColor: MockTestColors.navy,
                        overlayColor: MockTestColors.navy.withValues(alpha: 0.12),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: value,
                        max: max,
                        onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
