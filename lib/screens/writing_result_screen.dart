import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../services/share_service.dart';
import '../widgets/cached_avatar.dart';
import '../widgets/mock_test_styles.dart';

class WritingResultScreen extends StatefulWidget {
  const WritingResultScreen({super.key, required this.attempt});

  final Map<String, dynamic> attempt;

  @override
  State<WritingResultScreen> createState() => _WritingResultScreenState();
}

class _WritingResultScreenState extends State<WritingResultScreen> {
  final _shareCardKey = GlobalKey();
  bool _sharing = false;
  String? _studentName;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final result = await ApiService.get('/student/profile/');
      final profile = (result['data'] is Map<String, dynamic>) ? result['data'] as Map<String, dynamic> : result;
      final name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
      if (!mounted) return;
      setState(() {
        _studentName = name.isEmpty ? null : name;
        _avatarUrl = profile['profile_image'] as String?;
      });
    } catch (_) {
      // Non-fatal — the share card just falls back to a generic name/avatar.
    }
  }

  Future<void> _handleShare() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    ui.Image? image;
    try {
      // The offscreen card is always mounted, but wait a frame to be sure
      // it has actually painted at least once before we capture it.
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _shareCardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/linka_writing_result.png');
      await file.writeAsBytes(bytes, flush: true);

      final overall = _toDouble(widget.attempt['overall_band']);
      final prompt = (widget.attempt['prompt'] as Map?) ?? const {};
      await ShareService.shareWritingResultImage(
        imageFile: file,
        overallBand: overall.toStringAsFixed(1),
        promptTitle: prompt['title']?.toString(),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate the share image. Please try again.')),
        );
      }
    } finally {
      image?.dispose();
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attempt = widget.attempt;
    final status = attempt['status']?.toString() ?? 'pending';
    final failed = status == 'failed';
    final overall = _toDouble(attempt['overall_band']);
    final tier = _bandTier(overall);
    final prompt = (attempt['prompt'] as Map?) ?? const {};
    final essayText = attempt['essay_text']?.toString() ?? '';
    final wordCount = (attempt['word_count'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: _Palette.bg,
      appBar: mtAppBar(context, title: 'Writing Result'),
      body: failed
          ? _FailedView(attempt: attempt)
          : Stack(
              fit: StackFit.expand,
              children: [
                _GradedView(attempt: attempt, onShare: _handleShare, sharing: _sharing),
                // Kept mounted off-screen (rather than Offstage, which
                // skips painting) so it always has a fresh frame ready to
                // capture the moment the share button is tapped.
                Positioned(
                  left: -4000,
                  top: 0,
                  child: RepaintBoundary(
                    key: _shareCardKey,
                    child: _InstagramStoryCard(
                      overall: overall,
                      tier: tier,
                      task: _toDouble(attempt['task_achievement']),
                      coherence: _toDouble(attempt['coherence_cohesion']),
                      lexical: _toDouble(attempt['lexical_resource']),
                      grammar: _toDouble(attempt['grammar_accuracy']),
                      taskNumber: (prompt['task_number'] as num?)?.toInt(),
                      wordCount: wordCount,
                      readingLevel: _readingLevel(essayText, wordCount),
                      studentName: _studentName,
                      avatarUrl: _avatarUrl,
                      dateLabel: _formatDate(attempt['submitted_at']),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _FailedView extends StatelessWidget {
  const _FailedView({required this.attempt});
  final Map<String, dynamic> attempt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: _Palette.red.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.error_outline_rounded, size: 32, color: _Palette.red),
            ),
            const SizedBox(height: 16),
            const Text(
              'Grading is unavailable right now',
              style: TextStyle(fontFamily: 'SF Pro', fontWeight: FontWeight.w700, color: _Palette.primary),
            ),
            const SizedBox(height: 8),
            Text(
              attempt['error_message']?.toString() ?? 'Please try again later.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'SF Pro', color: _Palette.textGrey, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradedView extends StatelessWidget {
  const _GradedView({required this.attempt, required this.onShare, required this.sharing});
  final Map<String, dynamic> attempt;
  final VoidCallback onShare;
  final bool sharing;

  @override
  Widget build(BuildContext context) {
    final overall = _toDouble(attempt['overall_band']);
    final task = _toDouble(attempt['task_achievement']);
    final coherence = _toDouble(attempt['coherence_cohesion']);
    final lexical = _toDouble(attempt['lexical_resource']);
    final grammar = _toDouble(attempt['grammar_accuracy']);
    final feedback = attempt['feedback']?.toString() ?? '';
    final prompt = (attempt['prompt'] as Map?) ?? const {};
    final taskNumber = (prompt['task_number'] as num?)?.toInt();
    final minWords = (prompt['min_words'] as num?)?.toInt() ?? 150;
    final wordCount = (attempt['word_count'] as num?)?.toInt() ?? 0;
    final essayText = attempt['essay_text']?.toString() ?? '';
    final tier = _bandTier(overall);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _FadeSlideIn(child: _HeroCard(overall: overall, tier: tier, onShare: onShare, sharing: sharing)),
        const SizedBox(height: 26),
        _FadeSlideIn(delay: const Duration(milliseconds: 80), child: _sectionTitle('Score Breakdown')),
        const SizedBox(height: 12),
        _CriterionCard(
          title: 'Task Achievement',
          icon: Icons.flag_rounded,
          score: task,
          descriptor: _descriptorFor('task', task),
          delay: const Duration(milliseconds: 120),
        ),
        const SizedBox(height: 12),
        _CriterionCard(
          title: 'Coherence & Cohesion',
          icon: Icons.hub_rounded,
          score: coherence,
          descriptor: _descriptorFor('coherence', coherence),
          delay: const Duration(milliseconds: 180),
        ),
        const SizedBox(height: 12),
        _CriterionCard(
          title: 'Lexical Resource',
          icon: Icons.menu_book_rounded,
          score: lexical,
          descriptor: _descriptorFor('lexical', lexical),
          delay: const Duration(milliseconds: 240),
        ),
        const SizedBox(height: 12),
        _CriterionCard(
          title: 'Grammatical Range & Accuracy',
          icon: Icons.rule_rounded,
          score: grammar,
          descriptor: _descriptorFor('grammar', grammar),
          delay: const Duration(milliseconds: 300),
        ),
        const SizedBox(height: 26),
        _FadeSlideIn(delay: const Duration(milliseconds: 340), child: _sectionTitle('Skill Radar')),
        const SizedBox(height: 12),
        _FadeSlideIn(
          delay: const Duration(milliseconds: 380),
          child: _RadarCard(task: task, coherence: coherence, lexical: lexical, grammar: grammar),
        ),
        const SizedBox(height: 26),
        _FadeSlideIn(delay: const Duration(milliseconds: 420), child: _sectionTitle('AI Coach')),
        const SizedBox(height: 12),
        _FadeSlideIn(
          delay: const Duration(milliseconds: 460),
          child: _AiCoachCard(feedback: feedback.isEmpty ? 'No detailed feedback was returned for this attempt.' : feedback),
        ),
        const SizedBox(height: 26),
        _FadeSlideIn(delay: const Duration(milliseconds: 500), child: _sectionTitle('Essay Statistics')),
        const SizedBox(height: 12),
        _FadeSlideIn(
          delay: const Duration(milliseconds: 540),
          child: _EssayStatsGrid(wordCount: wordCount, essayText: essayText, taskNumber: taskNumber, minWords: minWords),
        ),
        const SizedBox(height: 30),
        _FadeSlideIn(
          delay: const Duration(milliseconds: 580),
          child: MtPrimaryButton(label: 'Practice Another Essay', onPressed: () => Navigator.pop(context)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.overall, required this.tier, required this.onShare, required this.sharing});

  final double overall;
  final _Tier tier;
  final VoidCallback onShare;
  final bool sharing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_Palette.primary, _Palette.primaryLight],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: _Palette.primary.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 14))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      tier.label,
                      style: const TextStyle(fontFamily: 'SF Pro', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: sharing ? null : onShare,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
                  child: sharing
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.ios_share_rounded, color: Colors.white, size: 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '${_heroEmoji(overall)}  ${_heroTitle(overall)}',
            style: const TextStyle(fontFamily: 'SF Pro', fontSize: 21, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 26),
          const Text(
            'OVERALL BAND',
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70, letterSpacing: 1.6),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 176,
            height: 176,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: (overall / 9).clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 1400),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => CustomPaint(
                    size: const Size(176, 176),
                    painter: _ScoreArcPainter(progress: t, track: Colors.white.withValues(alpha: 0.15), color: Colors.white),
                  ),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: overall),
                  duration: const Duration(milliseconds: 1400),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        v.toStringAsFixed(1),
                        style: const TextStyle(fontFamily: 'SF Pro', fontSize: 46, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      const Text('out of 9.0', style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, color: Colors.white60)),
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

class _ScoreArcPainter extends CustomPainter {
  const _ScoreArcPainter({required this.progress, required this.track, required this.color});
  final double progress;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 14.0;
    final rect = Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth, size.height - strokeWidth);
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -pi / 2, 2 * pi, false, trackPaint);
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -pi / 2, 2 * pi * progress, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _ScoreArcPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.color != color;
}

/// A poster used only for the "share to Instagram Story" image — captured
/// via [RepaintBoundary.toImage] rather than shown on screen. Sized to its
/// own content (no fixed height) so nothing clips; Instagram's share sheet
/// drops it in as a resizable sticker rather than a full-bleed background.
class _InstagramStoryCard extends StatelessWidget {
  const _InstagramStoryCard({
    required this.overall,
    required this.tier,
    required this.task,
    required this.coherence,
    required this.lexical,
    required this.grammar,
    required this.taskNumber,
    required this.wordCount,
    required this.readingLevel,
    required this.studentName,
    required this.avatarUrl,
    required this.dateLabel,
  });

  final double overall;
  final _Tier tier;
  final double task;
  final double coherence;
  final double lexical;
  final double grammar;
  final int? taskNumber;
  final int wordCount;
  final String readingLevel;
  final String? studentName;
  final String? avatarUrl;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF181A32), _Palette.primary, _Palette.primaryLight],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 36, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/images/branding/new-logo.png', height: 26),
                    const SizedBox(width: 8),
                    SvgPicture.asset(
                      'assets/images/branding/white-logo.svg',
                      height: 18,
                      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'IELTS WRITING PRACTICE',
                  style: TextStyle(fontFamily: 'SF Pro', fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white60, letterSpacing: 1.6),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 12),
                      const SizedBox(width: 5),
                      Text(
                        tier.label,
                        style: const TextStyle(fontFamily: 'SF Pro', fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${_heroEmoji(overall)}  ${_heroTitle(overall)}',
                  style: const TextStyle(fontFamily: 'SF Pro', fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 16),
                const Text(
                  'OVERALL BAND',
                  style: TextStyle(fontFamily: 'SF Pro', fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white60, letterSpacing: 1.8),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _SideStat(
                      icon: Icons.assignment_rounded,
                      color: _Palette.purple,
                      value: taskNumber != null ? 'Task $taskNumber' : 'Writing',
                      caption: 'IELTS section',
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 132,
                      height: 132,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.22), blurRadius: 30, spreadRadius: 1)],
                            ),
                          ),
                          CustomPaint(
                            size: const Size(132, 132),
                            painter: _ScoreArcPainter(progress: (overall / 9).clamp(0.0, 1.0), track: Colors.white.withValues(alpha: 0.15), color: Colors.white),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                overall.toStringAsFixed(1),
                                style: const TextStyle(fontFamily: 'SF Pro', fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                              const Text('out of 9.0', style: TextStyle(fontFamily: 'SF Pro', fontSize: 10, color: Colors.white60)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SideStat(icon: Icons.trending_up_rounded, color: _Palette.green, value: _levelLabel(overall), caption: 'level of English'),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      Expanded(child: _MiniStat(icon: Icons.short_text_rounded, label: 'Words Written', value: '$wordCount')),
                      Container(width: 1, height: 26, color: Colors.white.withValues(alpha: 0.15)),
                      Expanded(child: _MiniStat(icon: Icons.school_rounded, label: 'Reading Level', value: readingLevel)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'YOUR SKILLS SUMMARY',
                  style: TextStyle(fontFamily: 'SF Pro', fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white60, letterSpacing: 1.4),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _MiniSkillCard(label: 'Task', score: task, color: _Palette.blue, icon: Icons.flag_rounded)),
                    const SizedBox(width: 6),
                    Expanded(child: _MiniSkillCard(label: 'Coherence', score: coherence, color: _Palette.purple, icon: Icons.hub_rounded)),
                    const SizedBox(width: 6),
                    Expanded(child: _MiniSkillCard(label: 'Lexical', score: lexical, color: _Palette.green, icon: Icons.menu_book_rounded)),
                    const SizedBox(width: 6),
                    Expanded(child: _MiniSkillCard(label: 'Grammar', score: grammar, color: _Palette.orange, icon: Icons.rule_rounded)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.rocket_launch_rounded, color: Colors.white70, size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _nextGoalText(overall),
                        style: const TextStyle(fontFamily: 'SF Pro', fontSize: 11, color: Colors.white70, height: 1.3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(height: 1, color: Colors.white.withValues(alpha: 0.14)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipOval(child: CachedAvatar(imageUrl: avatarUrl, size: 20)),
                        const SizedBox(width: 6),
                        Text(
                          studentName ?? 'Linka Student',
                          style: const TextStyle(fontFamily: 'SF Pro', fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white70),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_rounded, color: Colors.white54, size: 11),
                        const SizedBox(width: 5),
                        Text(dateLabel, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 10.5, color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
  }
}

class _SideStat extends StatelessWidget {
  const _SideStat({required this.icon, required this.color, required this.value, required this.caption});
  final IconData icon;
  final Color color;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
              border: Border.all(color: color.withValues(alpha: 0.5), width: 1.2),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(height: 6),
          Text(value, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, height: 1.15)),
          const SizedBox(height: 2),
          Text(caption, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 8, color: Colors.white60, height: 1.15)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white70, size: 12),
            const SizedBox(width: 4),
            Text(value, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 9, color: Colors.white60)),
      ],
    );
  }
}

class _MiniSkillCard extends StatelessWidget {
  const _MiniSkillCard({required this.label, required this.score, required this.color, required this.icon});
  final String label;
  final double score;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.22)),
            child: Icon(icon, color: color, size: 11),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'SF Pro', fontSize: 8.5, fontWeight: FontWeight.w600, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(score.toStringAsFixed(1), style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 3,
              width: 26,
              color: Colors.white.withValues(alpha: 0.15),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (score / 9).clamp(0.0, 1.0),
                child: Container(color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Score breakdown
// ---------------------------------------------------------------------------

class _CriterionCard extends StatelessWidget {
  const _CriterionCard({
    required this.title,
    required this.icon,
    required this.score,
    required this.descriptor,
    required this.delay,
  });

  final String title;
  final IconData icon;
  final double score;
  final String descriptor;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(score);
    return _FadeSlideIn(
      delay: delay,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: _Palette.softShadow),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontFamily: 'SF Pro', fontSize: 15, fontWeight: FontWeight.w700, color: _Palette.primary),
                  ),
                ),
                Text(
                  score.toStringAsFixed(1),
                  style: const TextStyle(fontFamily: 'SF Pro', fontSize: 22, fontWeight: FontWeight.w800, color: _Palette.primary),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 8,
                color: color.withValues(alpha: 0.12),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: (score / 9).clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: t,
                    child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              descriptor,
              style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13, height: 1.45, color: _Palette.textGrey),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Radar chart
// ---------------------------------------------------------------------------

class _RadarCard extends StatelessWidget {
  const _RadarCard({required this.task, required this.coherence, required this.lexical, required this.grammar});
  final double task;
  final double coherence;
  final double lexical;
  final double grammar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: _Palette.softShadow),
      child: SizedBox(
        height: 260,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1200),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => CustomPaint(
            painter: _RadarChartPainter(
              values: [task, coherence, lexical, grammar],
              labels: const ['Task\nAchievement', 'Coherence', 'Vocabulary', 'Grammar'],
              progress: t,
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarChartPainter extends CustomPainter {
  _RadarChartPainter({required this.values, required this.labels, required this.progress});

  final List<double> values;
  final List<String> labels;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = (size.shortestSide / 2) - 34;
    final sides = values.length;
    final angleStep = (2 * pi) / sides;

    final gridPaint = Paint()
      ..color = const Color(0xFFEDEEF3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final frac in [0.34, 0.67, 1.0]) {
      final ringPath = Path();
      for (int i = 0; i < sides; i++) {
        final angle = -pi / 2 + i * angleStep;
        final p = center + Offset(cos(angle), sin(angle)) * maxRadius * frac;
        if (i == 0) {
          ringPath.moveTo(p.dx, p.dy);
        } else {
          ringPath.lineTo(p.dx, p.dy);
        }
      }
      ringPath.close();
      canvas.drawPath(ringPath, gridPaint);
    }

    for (int i = 0; i < sides; i++) {
      final angle = -pi / 2 + i * angleStep;
      final p = center + Offset(cos(angle), sin(angle)) * maxRadius;
      canvas.drawLine(center, p, gridPaint);
    }

    final dataPath = Path();
    final points = <Offset>[];
    for (int i = 0; i < sides; i++) {
      final angle = -pi / 2 + i * angleStep;
      final r = maxRadius * (values[i] / 9).clamp(0.0, 1.0) * progress;
      final p = center + Offset(cos(angle), sin(angle)) * r;
      points.add(p);
      if (i == 0) {
        dataPath.moveTo(p.dx, p.dy);
      } else {
        dataPath.lineTo(p.dx, p.dy);
      }
    }
    dataPath.close();
    canvas.drawPath(dataPath, Paint()..color = _Palette.blue.withValues(alpha: 0.18));
    canvas.drawPath(
      dataPath,
      Paint()
        ..color = _Palette.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );
    for (final p in points) {
      canvas.drawCircle(p, 4, Paint()..color = _Palette.blue);
      canvas.drawCircle(
        p,
        4,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }

    for (int i = 0; i < sides; i++) {
      final angle = -pi / 2 + i * angleStep;
      final labelPoint = center + Offset(cos(angle), sin(angle)) * (maxRadius + 24);
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: const TextStyle(fontFamily: 'SF Pro', fontSize: 11.5, fontWeight: FontWeight.w600, color: _Palette.primary, height: 1.2),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 76);
      tp.paint(canvas, labelPoint - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.values != values;
}

// ---------------------------------------------------------------------------
// AI coach
// ---------------------------------------------------------------------------

class _AiCoachCard extends StatefulWidget {
  const _AiCoachCard({required this.feedback});
  final String feedback;

  @override
  State<_AiCoachCard> createState() => _AiCoachCardState();
}

class _AiCoachCardState extends State<_AiCoachCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final canCollapse = widget.feedback.length > 220;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: _Palette.softShadow,
        border: Border.all(color: _Palette.blue.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_Palette.blue, _Palette.primary]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Coach', style: TextStyle(fontFamily: 'SF Pro', fontSize: 15, fontWeight: FontWeight.w700, color: _Palette.primary)),
                    Text(
                      'Personalized feedback on your essay',
                      style: TextStyle(fontFamily: 'SF Pro', fontSize: 12, color: _Palette.textGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            widget.feedback,
            maxLines: !canCollapse || _expanded ? null : 4,
            overflow: !canCollapse || _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14, height: 1.55, color: _Palette.primary),
          ),
          if (canCollapse) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _expanded ? 'Show less' : 'View Full Feedback',
                    style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13, fontWeight: FontWeight.w700, color: _Palette.blue),
                  ),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: _Palette.blue,
                    size: 18,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Essay statistics
// ---------------------------------------------------------------------------

class _EssayStatsGrid extends StatelessWidget {
  const _EssayStatsGrid({required this.wordCount, required this.essayText, required this.taskNumber, required this.minWords});

  final int wordCount;
  final String essayText;
  final int? taskNumber;
  final int minWords;

  @override
  Widget build(BuildContext context) {
    final target = _wordTarget(taskNumber, minWords);
    final onTarget = wordCount >= minWords;
    final paragraphs = _paragraphCount(essayText);
    final sentences = _sentenceCount(essayText);
    final avgSentenceLen = wordCount == 0 ? 0.0 : wordCount / sentences;
    final level = _readingLevel(essayText, wordCount);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        _StatTile(icon: Icons.short_text_rounded, value: '$wordCount', label: 'Words', sub: target, color: onTarget ? _Palette.green : _Palette.orange),
        _StatTile(icon: Icons.view_agenda_rounded, value: '$paragraphs', label: 'Paragraphs', color: _Palette.blue),
        _StatTile(icon: Icons.linear_scale_rounded, value: avgSentenceLen.toStringAsFixed(1), label: 'Avg Sentence Length', sub: 'words/sentence', color: _Palette.blue),
        _StatTile(icon: Icons.school_rounded, value: level, label: 'Reading Level', sub: 'estimated', color: _Palette.primary),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.value, required this.label, this.sub, required this.color});

  final IconData icon;
  final String value;
  final String label;
  final String? sub;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: _Palette.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 20, fontWeight: FontWeight.w800, color: _Palette.primary)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 12, fontWeight: FontWeight.w600, color: _Palette.primary)),
          if (sub != null)
            Text(sub!, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 10.5, color: _Palette.textGrey)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _Palette {
  static const primary = Color(0xFF2E3154);
  static const primaryLight = Color(0xFF454875);
  static const blue = Color(0xFF4F7CFF);
  static const purple = Color(0xFF8B5CF6);
  static const green = Color(0xFF30C48D);
  static const orange = Color(0xFFF5A623);
  static const red = Color(0xFFFF5C5C);
  static const bg = Color(0xFFF6F7FB);
  static const textGrey = Color(0xFF7A7E92);
  static final softShadow = [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8))];
}

class _Tier {
  const _Tier(this.label);
  final String label;
}

/// Fades and slides its [child] up shortly after [delay], giving the page a
/// gentle staggered-reveal feel without a shared AnimationController.
class _FadeSlideIn extends StatefulWidget {
  const _FadeSlideIn({required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide =
      Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fade, child: SlideTransition(position: _slide, child: widget.child));
  }
}

Widget _sectionTitle(String text) => Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(text, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 19, fontWeight: FontWeight.w800, color: _Palette.primary)),
    );

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

_Tier _bandTier(double band) {
  if (band >= 8.5) return const _Tier('Excellent Writer');
  if (band >= 7) return const _Tier('Strong Writer');
  if (band >= 6) return const _Tier('Competent Writer');
  if (band >= 5) return const _Tier('Developing Writer');
  return const _Tier('Beginner Writer');
}

String _heroEmoji(double band) {
  if (band >= 8.5) return '🎉';
  if (band >= 7) return '👏';
  if (band >= 6) return '💪';
  return '📈';
}

String _heroTitle(double band) {
  if (band >= 8.5) return 'Excellent Work!';
  if (band >= 7) return 'Great Job!';
  if (band >= 6) return 'Good Progress!';
  return 'Keep Practicing!';
}

String _levelLabel(double band) {
  if (band >= 8.5) return 'Excellent';
  if (band >= 7) return 'Very Good';
  if (band >= 6) return 'Good';
  if (band >= 5) return 'Fair';
  return 'Developing';
}

/// Suggests the next 0.5-step band goal above [overall] — plain arithmetic
/// on the real score, not a separate prediction.
String _nextGoalText(double overall) {
  if (overall >= 9.0) return "You've reached the top band — outstanding work! 🏆";
  final next = (((overall * 2).floor() + 1) / 2.0).clamp(0.0, 9.0);
  return "Keep practicing! You're on track to reach Band ${next.toStringAsFixed(1)}+";
}

String _formatDate(dynamic iso) {
  final date = DateTime.tryParse(iso?.toString() ?? '')?.toLocal() ?? DateTime.now();
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

Color _scoreColor(double score) {
  if (score >= 7.5) return _Palette.green;
  if (score >= 6) return _Palette.blue;
  if (score >= 5) return _Palette.orange;
  return _Palette.red;
}

/// Short paraphrases of the public IELTS Writing band descriptors, bucketed
/// by score — general guidance for that band, not a claim about this essay
/// specifically (the backend only returns a numeric score per criterion).
const Map<String, List<String>> _descriptors = {
  'task': [
    'Fully addresses all parts of the task with a clear, well-developed position and relevant, well-supported ideas.',
    'Addresses all parts of the task with a clear position, supported by relevant ideas, though some points may be underdeveloped.',
    'Addresses the task, though some parts may be covered more fully than others; main ideas are relevant but could be extended.',
    'Addresses the task only partially; ideas are present but limited and not well supported.',
    'Response has limited relevance to the task and needs significant development.',
  ],
  'coherence': [
    'Information and ideas are logically sequenced with skilful use of cohesive devices and paragraphing.',
    'Logically organises information with a clear progression throughout; cohesive devices used effectively.',
    'Arranges information coherently with a clear overall progression, though cohesion may be imperfect at times.',
    'Presents information with some organisation, but overall progression is not always clear.',
    'Ideas are not arranged coherently and there is little sense of progression.',
  ],
  'lexical': [
    'Wide range of vocabulary used fluently and flexibly to convey precise meaning, with only occasional inaccuracies.',
    'Sufficient range of vocabulary to allow flexibility and precision, with some awareness of style and collocation.',
    'Adequate range of vocabulary for the task; attempts less common items with some inaccuracy.',
    'Limited range of vocabulary that is only minimally adequate for the task.',
    'Vocabulary is very limited, which restricts communication of ideas.',
  ],
  'grammar': [
    'Wide range of structures used with full flexibility and accuracy; only rare, non-systematic errors.',
    'Variety of complex structures with frequent error-free sentences; good control of grammar and punctuation.',
    'Mix of simple and complex sentence forms; errors occur but rarely reduce clarity.',
    'Limited range of structures; errors are frequent and may cause the reader some difficulty.',
    'Very limited range of structures with frequent errors that often obscure meaning.',
  ],
};

String _descriptorFor(String criterion, double score) {
  final tiers = _descriptors[criterion]!;
  final index = score >= 8
      ? 0
      : score >= 7
          ? 1
          : score >= 6
              ? 2
              : score >= 5
                  ? 3
                  : 4;
  return tiers[index];
}

String _wordTarget(int? taskNumber, int minWords) {
  if (taskNumber == 1) return 'Aim for 150–190 words';
  if (taskNumber == 2) return 'Aim for 250–290 words';
  return 'Minimum $minWords words';
}

int _paragraphCount(String text) {
  final parts = text.trim().split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty);
  final count = parts.length;
  return count == 0 ? (text.trim().isEmpty ? 0 : 1) : count;
}

int _sentenceCount(String text) {
  final count = RegExp(r'[.!?]+').allMatches(text).length;
  return count == 0 ? 1 : count;
}

int _syllableCount(String word) {
  final w = word.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  if (w.isEmpty) return 1;
  var count = RegExp(r'[aeiouy]+').allMatches(w).length;
  if (w.endsWith('e') && count > 1) count -= 1;
  return count < 1 ? 1 : count;
}

/// Rough Flesch–Kincaid grade-level estimate computed from the actual essay
/// text — a heuristic, so the UI labels it "estimated".
String _readingLevel(String text, int wordCount) {
  if (wordCount == 0) return '-';
  final words = RegExp(r"[A-Za-z']+").allMatches(text).map((m) => m.group(0)!).toList();
  if (words.isEmpty) return '-';
  final sentences = _sentenceCount(text);
  final syllables = words.fold<int>(0, (sum, w) => sum + _syllableCount(w));
  final grade = 0.39 * (words.length / sentences) + 11.8 * (syllables / words.length) - 15.59;
  if (grade >= 13) return 'Advanced';
  if (grade >= 9) return 'Upper-Int.';
  if (grade >= 6) return 'Intermediate';
  return 'Basic';
}
