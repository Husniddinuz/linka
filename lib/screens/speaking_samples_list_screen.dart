import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/mock_test_service.dart';
import '../widgets/mock_test_styles.dart';
import 'plus_subscription_screen.dart';
import 'speaking_attempts_screen.dart';
import 'speaking_sample_screen.dart';
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
            return _ErrorState(error: snapshot.error);
          }
          final tutors = snapshot.data ?? const [];
          if (tutors.isEmpty) {
            return const _EmptyState(message: 'No speaking samples yet');
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
              _IntroHeader(
                title: 'Listen to real high-band answers',
                subtitle:
                    '$totalTopics recorded topics from ${tutors.length} tutors, with follow-along transcripts',
              ),
              // Their own marked answers, offered where they are already
              // hunting for a question to answer — rather than behind a nav
              // entry of its own that nobody would look for.
              const _YourAnswersRow(),
              _SearchField(
                controller: _searchController,
                hint: 'Search a tutor',
                query: _query,
                onChanged: (value) => setState(() => _query = value),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const _EmptyState(message: 'No tutors match that search.')
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
            _Artwork(imageUrl: imageUrl, size: 82),
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
                      Icon(Icons.headphones_rounded, size: 14, color: colors.textTertiary),
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
                    _Chip(
                      label: 'IELTS SPEAKING $score',
                      color: colors.textPrimary,
                      background: colors.accentYellow.withValues(alpha: 0.25),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 22, color: colors.textTertiary),
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
            return _ErrorState(error: snapshot.error);
          }
          final samples = _Sample.fromResponse(
            snapshot.data ?? const [],
            contentLocked: _isLocked,
          );
          if (samples.isEmpty) {
            return const _EmptyState(message: 'No speaking samples yet');
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
                _SearchField(
                  controller: _searchController,
                  hint: 'Search a topic',
                  query: _query,
                  onChanged: (value) => setState(() => _query = value),
                ),
              Expanded(
                child: visible.isEmpty
                    ? const _EmptyState(message: 'No topics match that search.')
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
          _Artwork(imageUrl: widget.tutorImageUrl, size: 88),
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
                  _Chip(
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
            Icon(Icons.event_available_rounded, size: 15, color: colors.onBrand),
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
              _BandTile(score: sample.bandScore),
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
                          _Chip(
                            label: 'PART ${sample.partNumbers.join(' · ')}',
                            color: colors.accentBlue,
                            background: colors.accentBlue.withValues(alpha: 0.12),
                          ),
                        if (sample.hasTranscript)
                          _Chip(
                            label: 'TRANSCRIPT',
                            icon: Icons.closed_caption_rounded,
                            color: colors.textSecondary,
                            background: colors.surface,
                          ),
                        if (locked)
                          _Chip(
                            label: 'LINKA PLUS',
                            icon: Icons.lock_rounded,
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
                  locked ? Icons.lock_rounded : Icons.play_arrow_rounded,
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

/// A way back to the answers this student has already recorded.
///
/// Always offered rather than only when there are some: a student who has
/// never tried is exactly who should see that trying is possible, and the
/// screen behind it says so itself when the list is empty.
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
              Icon(Icons.mic_rounded, size: 18, color: colors.accentBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Answer a question yourself',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Record any topic and AI marks it against the band descriptors',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 11.5,
                        height: 1.3,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared pieces ──────────────────────────────────────────────────────────

/// Rounded tutor photo, sized by the caller. Falls back to a brand-filled
/// mic tile so a missing or broken image never leaves a grey hole.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.imageUrl, required this.size});
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: SizedBox(
        width: size,
        height: size,
        child: (imageUrl != null && imageUrl!.isNotEmpty)
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _ArtworkFallback(size: size),
              )
            : _ArtworkFallback(size: size),
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.brand, colors.brand.withValues(alpha: 0.78)],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.mic_rounded, size: size * 0.36, color: colors.onBrand),
    );
  }
}

/// A topic row's artwork: the band score the answer earned.
class _BandTile extends StatelessWidget {
  const _BandTile({required this.score});
  final String? score;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.brand, colors.brand.withValues(alpha: 0.78)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (score == null)
            Icon(Icons.mic_rounded, size: 26, color: colors.onBrand)
          else ...[
            Text(
              'BAND',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: colors.onBrand.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              score!,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 21,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: colors.onBrand,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// States outright what the page is. The old grid left students to infer it
/// from tutor photos, which is how it got mistaken for the Tutors directory.
class _IntroHeader extends StatelessWidget {
  const _IntroHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.accentYellow.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.headphones_rounded, size: 20, color: colors.textPrimary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 12,
                    height: 1.3,
                    color: colors.textSecondary,
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

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.query,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontFamily: 'SF Pro', fontSize: 14, color: colors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          hintText: hint,
          hintStyle: TextStyle(fontFamily: 'SF Pro', fontSize: 14, color: colors.textTertiary),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: colors.textTertiary),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: colors.textTertiary),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: colors.surfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.background,
    this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'SF Pro',
            color: context.colors.textSecondary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Failed to load: $error',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'SF Pro',
            color: context.colors.textSecondary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
