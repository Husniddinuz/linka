import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/mock_test_service.dart';
import '../theme/app_colors.dart';
import '../widgets/mock_test_styles.dart';
import '../widgets/sample_list_widgets.dart';
import 'plus_subscription_screen.dart';
import 'speaking_answer_screen.dart';
import 'speaking_attempts_screen.dart';
import 'speaking_sample_screen.dart';

/// Level 1 of the topic bank: every Speaking topic, answerable directly.
///
/// The samples library ([SpeakingSamplesListScreen]) starts from a tutor —
/// which is right for listening, and wrong for practising: a student who wants
/// to answer a question about music does not care whose voice is on the
/// recording, and making them pick one first hides most of the question bank
/// behind a face. This screen is the same content indexed by the thing they
/// actually chose: the topic.
///
/// Tapping a topic opens [SpeakingTopicScreen].
class SpeakingTopicsScreen extends StatefulWidget {
  const SpeakingTopicsScreen({super.key});

  @override
  State<SpeakingTopicsScreen> createState() => _SpeakingTopicsScreenState();
}

class _SpeakingTopicsScreenState extends State<SpeakingTopicsScreen> {
  final Future<List<Map<String, dynamic>>> _future =
      MockTestService.fetchSpeakingTopics();
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: mtAppBar(context, title: 'Speaking Topics'),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: CircularProgressIndicator(color: context.colors.accentYellow),
            );
          }
          if (snapshot.hasError) {
            return SampleErrorState(error: snapshot.error);
          }
          final topics = [
            for (final json in snapshot.data ?? const <Map<String, dynamic>>[])
              _Topic.fromJson(json),
          ];
          if (topics.isEmpty) {
            return const SampleEmptyState(message: 'No speaking topics yet');
          }

          final query = _query.trim().toLowerCase();
          final visible = query.isEmpty
              ? topics
              : topics.where((t) => t.matches(query)).toList();
          final questions = topics.fold<int>(0, (sum, t) => sum + t.parts.length);

          return Column(
            children: [
              _IntroHeader(
                title: 'Answer any IELTS Speaking question',
                subtitle: '$questions questions across ${topics.length} topics, '
                    'marked against the band descriptors',
              ),
              const _YourAnswersRow(),
              SampleSearchField(
                controller: _searchController,
                hint: 'Search a topic or question',
                query: _query,
                onChanged: (value) => setState(() => _query = value),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const SampleEmptyState(message: 'No topics match that search.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _TopicRow(topic: visible[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One topic in the level-1 list.
class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.topic});
  final _Topic topic;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SpeakingTopicScreen(topic: topic.raw)),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: mtSoftCard(context, radius: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: colors.accentBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Symbols.forum_rounded, size: 21, color: colors.accentBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      if (topic.partNumbers.isNotEmpty)
                        SampleChip(
                          label: 'PART ${topic.partNumbers.join(' · ')}',
                          color: colors.accentBlue,
                          background: colors.accentBlue.withValues(alpha: 0.12),
                        ),
                      if (topic.sampleCount > 0)
                        SampleChip(
                          label: '${topic.sampleCount} TUTOR '
                              'ANSWER${topic.sampleCount == 1 ? '' : 'S'}',
                          icon: Symbols.headphones_rounded,
                          color: colors.textSecondary,
                          background: colors.surface,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Symbols.chevron_right_rounded, size: 22, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ─── Level 2: one topic's questions ─────────────────────────────────────────

/// The questions of a single topic, each with its own record button.
///
/// Part 1/2/3 are laid out together rather than behind tabs: they are one
/// topic's three questions and a student working through a topic answers all
/// of them, so the screen is a list, not a player.
class SpeakingTopicScreen extends StatelessWidget {
  const SpeakingTopicScreen({super.key, required this.topic});

  /// One entry from `/speaking-topics/`: `{id, title, parts, sample_count}`.
  final Map<String, dynamic> topic;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final model = _Topic.fromJson(topic);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: mtAppBar(context, title: 'Topic'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            model.title,
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 21,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${model.parts.length} question${model.parts.length == 1 ? '' : 's'} · '
            'record an answer and AI marks it against the band descriptors',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 12.5,
              height: 1.4,
              color: colors.textSecondary,
            ),
          ),
          // Hearing a band-8 answer first turns the recording into recall
          // rather than speaking, so listening is offered as the other way
          // through the topic — not as a warm-up above the record buttons.
          if (model.sampleCount > 0) ...[
            const SizedBox(height: 14),
            _ListenRow(topic: model),
          ],
          const SizedBox(height: 18),
          for (final part in model.parts) ...[
            _QuestionCard(part: part),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// A way into the tutors who recorded this same topic.
class _ListenRow extends StatelessWidget {
  const _ListenRow({required this.topic});
  final _Topic topic;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => _TopicSamplesScreen(topic: topic)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: mtSoftCard(context, radius: 14),
        child: Row(
          children: [
            Icon(Symbols.headphones_rounded, size: 18, color: colors.accentBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hear how ${topic.sampleCount} tutor'
                    '${topic.sampleCount == 1 ? '' : 's'} answered this',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Real high-band answers with follow-along transcripts',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Symbols.chevron_right_rounded, size: 20, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// One question of the topic, with the button that starts answering it.
class _QuestionCard extends StatefulWidget {
  const _QuestionCard({required this.part});
  final Map<String, dynamic> part;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  /// Part 1 questions are long numbered lists — ten of them is most of a
  /// screen — so a question starts clamped and opens on tap.
  bool _expanded = false;

  static const _clampedLines = 6;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final part = widget.part;
    final number = (part['part'] as num?)?.toInt() ?? 1;
    final title = part['title']?.toString().trim() ?? '';
    final question = part['question_text']?.toString().trim() ?? '';
    final long = '\n'.allMatches(question).length + 1 > _clampedLines;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: mtSoftCard(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SampleChip(
            label: 'PART $number',
            color: colors.accentBlue,
            background: colors.accentBlue.withValues(alpha: 0.12),
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1.3,
                color: colors.textPrimary,
              ),
            ),
          ],
          if (question.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: long ? () => setState(() => _expanded = !_expanded) : null,
              child: Text(
                question,
                maxLines: _expanded ? null : _clampedLines,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 14,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
            ),
            if (long)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _expanded ? 'Show less' : 'Show all questions',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: colors.accentBlue,
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 14),
          MtPrimaryButton(
            label: 'Answer this yourself',
            onPressed: (part['id'] as num?) == null
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SpeakingAnswerScreen.fromTopic(part: part),
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

// ─── Level 3: the tutors who answered this topic ────────────────────────────

/// Every tutor's recorded answer to one topic.
///
/// The mirror image of [SpeakingSampleTutorTopicsScreen]: that one is one
/// tutor's many topics, this is one topic's many tutors, so the row leads with
/// the face and the band rather than with the title they all share.
class _TopicSamplesScreen extends StatefulWidget {
  const _TopicSamplesScreen({required this.topic});
  final _Topic topic;

  @override
  State<_TopicSamplesScreen> createState() => _TopicSamplesScreenState();
}

class _TopicSamplesScreenState extends State<_TopicSamplesScreen> {
  late final Future<List<Map<String, dynamic>>> _future =
      MockTestService.fetchSpeakingSamples(topicId: widget.topic.id);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: mtAppBar(context, title: widget.topic.title),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: CircularProgressIndicator(color: context.colors.accentYellow),
            );
          }
          if (snapshot.hasError) {
            return SampleErrorState(error: snapshot.error);
          }
          final samples = snapshot.data ?? const [];
          if (samples.isEmpty) {
            return const SampleEmptyState(message: 'No tutor answers on this topic yet');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            itemCount: samples.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _SampleRow(sample: samples[i]),
          );
        },
      ),
    );
  }
}

class _SampleRow extends StatelessWidget {
  const _SampleRow({required this.sample});
  final Map<String, dynamic> sample;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The server strips a locked sample's parts, so there is nothing to play
    // and the row is a teaser that routes to the paywall instead.
    final locked = sample['locked'] == true;
    final name = sample['tutor_name']?.toString() ?? '';
    final band = sample['band_score']?.toString();
    final score = sample['tutor_speaking_score']?.toString();

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => locked
              ? const PlusSubscriptionScreen()
              : SpeakingSampleTutorScreen(tutor: sample),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: mtSoftCard(context, radius: 16),
        child: Opacity(
          opacity: locked ? 0.6 : 1,
          child: Row(
            children: [
              SampleArtwork(
                imageUrl: sample['tutor_image_url'] as String?,
                size: 62,
                fallbackIcon: Symbols.mic_rounded,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        if (score != null)
                          SampleChip(
                            label: 'IELTS SPEAKING $score',
                            color: colors.textPrimary,
                            background: colors.accentYellow.withValues(alpha: 0.25),
                          ),
                        if (locked)
                          SampleChip(
                            label: 'LINKA PLUS',
                            icon: Symbols.lock_rounded,
                            color: colors.textPrimary,
                            background: colors.accentYellow.withValues(alpha: 0.25),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (locked)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: colors.surface, shape: BoxShape.circle),
                  child: Icon(Symbols.lock_rounded, size: 17, color: colors.textTertiary),
                )
              else
                SampleBandTile(score: band, emptyIcon: Symbols.mic_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared pieces ──────────────────────────────────────────────────────────

class _IntroHeader extends StatelessWidget {
  const _IntroHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 19,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 12.5,
              height: 1.4,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A way back to the answers this student has already recorded — the same row
/// the samples library carries, for the same reason.
class _YourAnswersRow extends StatelessWidget {
  const _YourAnswersRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SpeakingAttemptsScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: mtSoftCard(context, radius: 14),
          child: Row(
            children: [
              Icon(Symbols.history_rounded, size: 18, color: colors.accentBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your marked answers',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Icon(Symbols.chevron_right_rounded, size: 20, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Model ──────────────────────────────────────────────────────────────────

/// One curated topic, flattened out of `/speaking-topics/`.
class _Topic {
  _Topic({
    required this.raw,
    required this.id,
    required this.title,
    required this.parts,
    required this.sampleCount,
  });

  final Map<String, dynamic> raw;
  final int id;
  final String title;
  final List<Map<String, dynamic>> parts;

  /// How many tutors have published a recorded answer to this topic. Zero is
  /// ordinary — the question is the exam's, not the tutor's, and a topic
  /// nobody has recorded is still worth answering.
  final int sampleCount;

  factory _Topic.fromJson(Map<String, dynamic> json) {
    final parts = ((json['parts'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return _Topic(
      raw: json,
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString().trim() ?? '',
      parts: parts,
      sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
    );
  }

  List<int> get partNumbers => [
        for (final part in parts)
          if ((part['part'] as num?) != null) (part['part'] as num).toInt(),
      ]..sort();

  /// Searches the questions as well as the title: a student hunting for "public
  /// transport" is as likely to remember the cue card as the topic name.
  bool matches(String query) {
    if (title.toLowerCase().contains(query)) return true;
    return parts.any((part) =>
        (part['title']?.toString().toLowerCase() ?? '').contains(query) ||
        (part['question_text']?.toString().toLowerCase() ?? '').contains(query));
  }
}
