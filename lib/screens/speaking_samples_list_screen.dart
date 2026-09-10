import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/api_service.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import '../widgets/sample_list_widgets.dart';
import 'plus_subscription_screen.dart';
import 'speaking_sample_screen.dart';
import 'speaking_topics_screen.dart';
import 'tutor_profile_screen.dart';
import '../theme/app_colors.dart';

/// How many of a tutor's topics a non-Plus user can open for free; the rest
/// stay visible but locked and route to the Plus subscription screen.
const int _freeSamples = 3;

/// Level 1: the tutors who have recorded Speaking answers.
///
/// Deliberately a list of rows, not the photo grid it used to be — that grid
/// was visually indistinguishable from the Tutors directory, so students
/// opened it expecting to book someone. Rows plus an explicit "listen to"
/// header and per-tutor topic counts make it read as a library index.
///
/// Tapping a tutor opens their topics (see
/// [SpeakingSampleTutorTopicsScreen]).
class SpeakingSamplesListScreen extends StatefulWidget {
  const SpeakingSamplesListScreen({super.key});

  @override
  State<SpeakingSamplesListScreen> createState() => _SpeakingSamplesListScreenState();
}

class _SpeakingSamplesListScreenState extends State<SpeakingSamplesListScreen> {
  final Future<List<Map<String, dynamic>>> _future =
      MockTestService.fetchSpeakingSampleTutors();
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
      appBar: mtAppBar(context, title: 'Speaking Samples'),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.accentYellow));
          }
          if (snapshot.hasError) {
            return SampleErrorState(error: snapshot.error);
          }
          final tutors = snapshot.data ?? const [];
          if (tutors.isEmpty) {
            return const SampleEmptyState(message: 'No speaking samples yet');
          }

          final query = _query.trim().toLowerCase();
          final visible = query.isEmpty
              ? tutors
              : tutors
                  .where((t) => (t['tutor_name']?.toString() ?? '')
                      .toLowerCase()
                      .contains(query))
                  .toList();
          final totalTopics = tutors.fold<int>(
            0,
            (sum, t) => sum + ((t['sample_count'] as num?)?.toInt() ?? 0),
          );

          return Column(
            children: [
              SampleIntroHeader(
                icon: Symbols.headphones_rounded,
                title: 'Listen to real high-band answers',
                subtitle:
                    '$totalTopics recorded topics from ${tutors.length} tutors, with follow-along transcripts',
              ),
              // The way out of listening and into answering, offered where
              // students already are when they go looking for a question — but
              // it leads to the topic bank rather than to one tutor's
              // questions: the same questions, none of them behind a face.
              SampleCtaRow(
                icon: Symbols.mic_rounded,
                title: 'Answer a question yourself',
                subtitle:
                    'Pick any topic and AI marks your answer against the band descriptors',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SpeakingTopicsScreen()),
                ),
              ),
              SampleSearchField(
                controller: _searchController,
                hint: 'Search a tutor',
                query: _query,
                onChanged: (value) => setState(() => _query = value),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const SampleEmptyState(message: 'No tutors match that search.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _TutorRow(tutor: visible[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One tutor in the level-1 list: big photo, name, how many topics they have
/// recorded, and their own IELTS Speaking credential.
class _TutorRow extends StatelessWidget {
  const _TutorRow({required this.tutor});
  final Map<String, dynamic> tutor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = tutor['tutor_name']?.toString() ?? '';
    final imageUrl = tutor['tutor_image_url'] as String?;
    final score = tutor['tutor_speaking_score']?.toString();
    final count = (tutor['sample_count'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SpeakingSampleTutorTopicsScreen(
            tutorId: (tutor['tutor_id'] as num?)?.toInt(),
            tutorName: name,
            tutorImageUrl: imageUrl,
            tutorSpeakingScore: score,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: mtSoftCard(context, radius: 16),
        child: Row(
          children: [
            SampleArtwork(imageUrl: imageUrl, size: 82, fallbackIcon: Symbols.mic_rounded),
            const SizedBox(width: 13),
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
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(Symbols.headphones_rounded, size: 14, color: colors.textTertiary),
                      const SizedBox(width: 5),
                      Text(
                        '$count topic${count == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (score != null) ...[
                    const SizedBox(height: 8),
                    SampleChip(
                      label: 'IELTS SPEAKING $score',
                      color: colors.textPrimary,
                      background: colors.accentYellow.withValues(alpha: 0.25),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Symbols.chevron_right_rounded, size: 22, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ─── Level 2: one tutor's topics ────────────────────────────────────────────

/// The topics a single tutor has recorded. The tutor is already chosen, so
/// their photo sits once in the header and each row leads with the band score
/// the answer earned instead of repeating the same face down the page.
class SpeakingSampleTutorTopicsScreen extends StatefulWidget {
  const SpeakingSampleTutorTopicsScreen({
    super.key,
    required this.tutorId,
    required this.tutorName,
    required this.tutorImageUrl,
    required this.tutorSpeakingScore,
  });

  final int? tutorId;
  final String tutorName;
  final String? tutorImageUrl;
  final String? tutorSpeakingScore;

  @override
  State<SpeakingSampleTutorTopicsScreen> createState() =>
      _SpeakingSampleTutorTopicsScreenState();
}

class _SpeakingSampleTutorTopicsScreenState extends State<SpeakingSampleTutorTopicsScreen> {
  late final Future<List<Map<String, dynamic>>> _future;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _isLocked = false;

  /// The tutor's catalogue entry, when they have one. It is what decides
  /// whether this voice can actually be booked: an admin-authored sample has
  /// no account behind it at all, and an id that no longer resolves is a tutor
  /// who has stopped teaching. Null in both cases, and the CTA stays off.
  Map<String, dynamic>? _bookable;

  @override
  void initState() {
    super.initState();
    _future = MockTestService.fetchSpeakingSamples(
      tutorId: widget.tutorId,
      tutorName: widget.tutorId == null ? widget.tutorName : null,
    );
    _checkPlusStatus();
    _loadBookable();
  }

  /// The id to offer a lesson with, or null when there is nothing to offer:
  /// no tutor account, an outage, or a tutor who is not taking students.
  int? get _bookableTutorId =>
      _bookable?['is_enrollable'] == true ? widget.tutorId : null;

  Future<void> _loadBookable() async {
    final id = widget.tutorId;
    if (id == null) return;
    try {
      final tutor = await ApiService.get('/tutors/$id/');
      if (!mounted) return;
      setState(() => _bookable = tutor);
    } catch (_) {
      // The samples are the screen; a catalogue outage costs the CTA, not the
      // list.
    }
  }

  Future<void> _checkPlusStatus() async {
    final locked = await mtCheckContentLocked();
    if (!mounted) return;
    setState(() => _isLocked = locked);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: mtAppBar(context, title: widget.tutorName),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: context.colors.accentYellow));
          }
          if (snapshot.hasError) {
            return SampleErrorState(error: snapshot.error);
          }
          final samples = _Sample.fromResponse(
            snapshot.data ?? const [],
            contentLocked: _isLocked,
          );
          if (samples.isEmpty) {
            return const SampleEmptyState(message: 'No speaking samples yet');
          }

          final query = _query.trim().toLowerCase();
          final visible = query.isEmpty
              ? samples
              : samples
                  .where((s) => s.topicTitle.toLowerCase().contains(query))
                  .toList();

          return Column(
            children: [
              _buildTutorHeader(samples.length),
              if (samples.length > 6)
                SampleSearchField(
                  controller: _searchController,
                  hint: 'Search a topic',
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
                        itemBuilder: (context, i) =>
                            _TopicRow(sample: visible[i], tutorId: _bookableTutorId),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTutorHeader(int count) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        children: [
          SampleArtwork(
            imageUrl: widget.tutorImageUrl,
            size: 88,
            fallbackIcon: Symbols.mic_rounded,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.tutorName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: colors.textPrimary,
                  ),
                ),
                if (widget.tutorSpeakingScore != null) ...[
                  const SizedBox(height: 7),
                  SampleChip(
                    label: 'IELTS SPEAKING ${widget.tutorSpeakingScore}',
                    color: colors.textPrimary,
                    background: colors.accentYellow.withValues(alpha: 0.25),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '$count recorded topic${count == 1 ? '' : 's'} · tap one to listen',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 12.5,
                    color: colors.textSecondary,
                  ),
                ),
                // A student who has spent ten minutes listening to someone has
                // already decided whether they like how they teach. Offering
                // the lesson here saves them going back out to the tutors
                // directory to find the same face again.
                if (_bookableTutorId != null) ...[
                  const SizedBox(height: 10),
                  _BookTutorButton(tutorId: _bookableTutorId!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Takes the student from a tutor's recorded answers to their booking page.
class _BookTutorButton extends StatelessWidget {
  const _BookTutorButton({required this.tutorId});
  final int tutorId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TutorProfileScreen(tutorId: tutorId)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: colors.brand,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.event_available_rounded, size: 15, color: colors.onBrand),
            const SizedBox(width: 6),
            Text(
              'Book a lesson',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.onBrand,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One recorded topic. The band score is the artwork here — it varies per
/// answer and is the reason to pick one, unlike the tutor's photo which is
/// the same for every row on this screen.
class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.sample, this.tutorId});
  final _Sample sample;

  /// Carried down so the player can offer a lesson with the voice being
  /// studied — the sample payload has no tutor id of its own.
  final int? tutorId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final locked = sample.locked;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => locked
              ? const PlusSubscriptionScreen()
              : SpeakingSampleTutorScreen(tutor: sample.raw, tutorId: tutorId),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: mtSoftCard(context, radius: 16),
        child: Opacity(
          opacity: locked ? 0.6 : 1,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SampleBandTile(score: sample.bandScore, emptyIcon: Symbols.mic_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sample.topicTitle,
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
                        if (sample.partNumbers.isNotEmpty)
                          SampleChip(
                            label: 'PART ${sample.partNumbers.join(' · ')}',
                            color: colors.accentBlue,
                            background: colors.accentBlue.withValues(alpha: 0.12),
                          ),
                        if (sample.hasTranscript)
                          SampleChip(
                            label: 'TRANSCRIPT',
                            icon: Symbols.closed_caption_rounded,
                            color: colors.textSecondary,
                            background: colors.surface,
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
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: locked ? colors.surface : colors.brand,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  locked ? Symbols.lock_rounded : Symbols.play_arrow_rounded,
                  size: locked ? 17 : 22,
                  color: locked ? colors.textTertiary : colors.onBrand,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Model ──────────────────────────────────────────────────────────────────

/// One recorded topic, flattened out of the API response with its lock state
/// already resolved.
class _Sample {
  _Sample({
    required this.raw,
    required this.topicTitle,
    required this.bandScore,
    required this.partNumbers,
    required this.hasTranscript,
    required this.locked,
  });

  final Map<String, dynamic> raw;
  final String topicTitle;
  final String? bandScore;
  final List<int> partNumbers;
  final bool hasTranscript;
  final bool locked;

  /// The backend is the source of truth for locking ('locked' items arrive
  /// with their parts stripped); the index check is a fallback for backends
  /// that predate server-side gating. [data] is always one tutor's samples,
  /// so a plain index is the per-tutor count.
  static List<_Sample> fromResponse(
    List<Map<String, dynamic>> data, {
    required bool contentLocked,
  }) {
    final result = <_Sample>[];
    for (var i = 0; i < data.length; i++) {
      final json = data[i];
      final parts = ((json['parts'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final id = json['id']?.toString() ?? '';
      final title = json['topic_title']?.toString().trim() ?? '';

      result.add(_Sample(
        raw: json,
        topicTitle: title.isNotEmpty ? title : 'Sample #$id',
        bandScore: json['band_score']?.toString(),
        partNumbers: [
          for (final part in parts)
            if ((part['part'] as num?) != null) (part['part'] as num).toInt(),
        ]..sort(),
        hasTranscript: parts.any(
          (part) => (part['subtitle_url'] as String?)?.trim().isNotEmpty == true,
        ),
        locked: json['locked'] == true || (contentLocked && i >= _freeSamples),
      ));
    }
    return result;
  }
}
