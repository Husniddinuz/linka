import 'package:flutter/material.dart';
import '../services/podcast_playback_service.dart';
import '../widgets/mock_test_styles.dart';

/// Read-only view of a real Speaking sample answer: the cue card/question,
/// an audio player for the sample recording, its transcript, achieved band
/// score, and examiner commentary. No submission or grading.
class SpeakingSampleScreen extends StatefulWidget {
  const SpeakingSampleScreen({super.key, required this.sample});

  final Map<String, dynamic> sample;

  @override
  State<SpeakingSampleScreen> createState() => _SpeakingSampleScreenState();
}

class _SpeakingSampleScreenState extends State<SpeakingSampleScreen> {
  bool _hasAudio = false;

  @override
  void initState() {
    super.initState();
    final audioUrl = widget.sample['audio_url'] as String?;
    if (audioUrl != null && audioUrl.isNotEmpty) {
      _hasAudio = true;
      PodcastPlaybackService.instance.loadAdHoc(
        'speaking-sample-${widget.sample['id']}',
        Uri.parse(audioUrl),
        title: widget.sample['title']?.toString() ?? 'Speaking sample',
      );
    }
  }

  @override
  void dispose() {
    if (_hasAudio) {
      PodcastPlaybackService.instance.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final band = widget.sample['band_score']?.toString();
    final transcript = widget.sample['transcript_html']?.toString() ?? '';
    final examinerComment = widget.sample['examiner_comment']?.toString() ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: widget.sample['title']?.toString() ?? 'Speaking sample'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: mtSoftCard(color: MockTestColors.chipBg, radius: 14),
            child: Text(
              widget.sample['question_text']?.toString() ?? '',
              style: const TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 14,
                height: 1.5,
                color: MockTestColors.navy,
              ),
            ),
          ),
          if (_hasAudio) ...[
            const SizedBox(height: 16),
            const _AudioBar(),
          ],
          const SizedBox(height: 20),
          if (band != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(color: MockTestColors.navy, borderRadius: BorderRadius.circular(20)),
              child: Column(
                children: [
                  const Text(
                    'BAND SCORE',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    band,
                    style: const TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          if (transcript.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Transcript',
              style: TextStyle(fontFamily: 'SF Pro', fontWeight: FontWeight.w700, fontSize: 15, color: MockTestColors.navy),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: mtSoftCard(radius: 14),
              child: Text(
                transcript,
                style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14, height: 1.5, color: MockTestColors.navy),
              ),
            ),
          ],
          if (examinerComment.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Why this scores well',
              style: TextStyle(fontFamily: 'SF Pro', fontWeight: FontWeight.w700, fontSize: 15, color: MockTestColors.navy),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: mtSoftCard(color: MockTestColors.chipBg, radius: 14),
              child: Text(
                examinerComment,
                style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14, height: 1.5, color: MockTestColors.navy),
              ),
            ),
          ],
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
