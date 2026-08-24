/// The AI coach's payloads.
///
/// The endpoints live at `/ai/` on the API host rather than under `/api/v1/`,
/// which is why they are reached through [AiCoachService] rather than the
/// usual relative paths — see `lib/services/ai_coach_service.dart`.
library;

/// One of the five characters the server ships.
class CoachPersona {
  const CoachPersona({
    required this.slug,
    required this.name,
    required this.emoji,
    required this.tagline,
    required this.color,
    required this.strictness,
  });

  final String slug;

  /// Russian, as the server stores it. Only a fallback: the five known
  /// characters are named in the app, which ships in one language at a time
  /// and not necessarily that one.
  final String name;
  final String emoji;
  final String tagline;

  /// Accent colour as `#rrggbb`, chosen server-side.
  final String color;

  /// 0–1, how picky the character is.
  final double strictness;

  factory CoachPersona.fromJson(Map<String, dynamic> json) => CoachPersona(
        slug: json['slug']?.toString() ?? 'classic',
        name: json['name']?.toString() ?? '',
        emoji: json['emoji']?.toString() ?? '',
        tagline: json['tagline']?.toString() ?? '',
        color: json['color']?.toString() ?? '#2563eb',
        strictness: (json['strictness'] as num?)?.toDouble() ?? 0.5,
      );
}

/// A conversation, as it comes back from `POST /ai/session/`.
class CoachSession {
  const CoachSession({
    required this.id,
    required this.persona,
    required this.greetingText,
    required this.greetingAudio,
  });

  final int id;
  final String persona;
  final String greetingText;

  /// base64 mp3, or null when the coach was asked not to greet.
  final String? greetingAudio;

  factory CoachSession.fromJson(Map<String, dynamic> json) => CoachSession(
        id: (json['session_id'] as num?)?.toInt() ?? 0,
        persona: json['persona']?.toString() ?? 'classic',
        greetingText: json['greeting_text']?.toString() ?? '',
        greetingAudio: (json['greeting_audio'] as String?)?.isEmpty ?? true
            ? null
            : json['greeting_audio'] as String,
      );
}

class PronouncedWord {
  const PronouncedWord({
    required this.word,
    required this.accuracy,
    required this.errorType,
  });

  final String word;
  final double accuracy;

  /// `None`, `Mispronunciation`, `Omission` or `Insertion`.
  final String errorType;

  factory PronouncedWord.fromJson(Map<String, dynamic> json) => PronouncedWord(
        word: json['word']?.toString() ?? '',
        accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
        errorType: json['error_type']?.toString() ?? 'None',
      );
}

class Pronunciation {
  const Pronunciation({
    required this.overall,
    required this.accuracy,
    required this.fluency,
    required this.completeness,
    required this.prosody,
    required this.words,
    required this.weakSounds,
  });

  final double overall;
  final double accuracy;
  final double fluency;
  final double completeness;
  final double prosody;
  final List<PronouncedWord> words;

  /// Sound → the words it failed in. The most useful field in the payload:
  /// one entry means one thing to practise, however many words it spans.
  final Map<String, List<String>> weakSounds;

  factory Pronunciation.fromJson(Map<String, dynamic> json) {
    final sounds = <String, List<String>>{};
    final raw = json['weak_sounds'];
    if (raw is Map) {
      raw.forEach((key, value) {
        sounds[key.toString()] = value is List
            ? value.map((word) => word.toString()).toList()
            : <String>[];
      });
    }
    return Pronunciation(
      overall: (json['overall'] as num?)?.toDouble() ?? 0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
      fluency: (json['fluency'] as num?)?.toDouble() ?? 0,
      completeness: (json['completeness'] as num?)?.toDouble() ?? 0,
      prosody: (json['prosody'] as num?)?.toDouble() ?? 0,
      words: (json['words'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(PronouncedWord.fromJson)
              .toList() ??
          const [],
      weakSounds: sounds,
    );
  }

  /// Words worth showing back, worst first. A clean take yields none.
  List<PronouncedWord> get weakWords {
    final picked = words
        .where((word) => word.errorType != 'None' || word.accuracy < 60)
        .toList()
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    return picked.take(8).toList();
  }
}

class Correction {
  const Correction({
    required this.type,
    required this.original,
    required this.corrected,
    required this.rule,
    required this.explanation,
  });

  /// `grammar`, `vocabulary`, `collocation` or `fluency`.
  final String type;
  final String original;
  final String corrected;

  /// A generalisation ("past simple"), which is what makes it a topic.
  final String rule;
  final String explanation;

  factory Correction.fromJson(Map<String, dynamic> json) => Correction(
        type: json['type']?.toString() ?? 'grammar',
        original: json['original']?.toString() ?? '',
        corrected: json['corrected']?.toString() ?? '',
        rule: json['rule']?.toString() ?? '',
        explanation: json['explanation']?.toString() ?? '',
      );
}

/// One turn's answer: what the coach said, and what it made of what it heard.
class CoachTurn {
  const CoachTurn({
    required this.replyText,
    required this.replyAudio,
    required this.pronunciation,
    required this.corrections,
  });

  final String replyText;

  /// base64 mp3. Null if speech synthesis failed — the text still stands.
  final String? replyAudio;

  /// Null whenever the take could not be scored: a typed turn, a take over a
  /// minute, no Azure key on the server, or Azure muted after repeated
  /// failures. Every screen showing this must survive all four.
  final Pronunciation? pronunciation;

  final List<Correction> corrections;

  factory CoachTurn.fromJson(Map<String, dynamic> json) {
    final reply = json['reply'];
    final audio = reply is Map ? reply['audio'] as String? : null;
    final scored = json['pronunciation'];
    return CoachTurn(
      replyText: reply is Map ? reply['text']?.toString() ?? '' : '',
      replyAudio: (audio?.isEmpty ?? true) ? null : audio,
      pronunciation: scored is Map<String, dynamic>
          ? Pronunciation.fromJson(scored)
          : null,
      corrections: (json['corrections'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(Correction.fromJson)
              .toList() ??
          const [],
    );
  }
}

/// A mistake the coach is tracking across conversations.
class TrackedMistake {
  const TrackedMistake({
    required this.kind,
    required this.key,
    required this.correction,
    required this.occurrences,
  });

  /// `pronunciation_phoneme`, `pronunciation_word`, `grammar`, `vocabulary`,
  /// `collocation` or `fluency`.
  final String kind;

  /// The generalisation itself: `/θ/`, `past simple`.
  final String key;

  /// The student's own sentence, put right.
  ///
  /// Shown instead of `explanation`, which is written by whichever half of the
  /// server found the mistake — Russian for the phoneme entries, English from
  /// the model for the grammar ones — and so reads as two languages at once.
  final String correction;
  final int occurrences;

  factory TrackedMistake.fromJson(Map<String, dynamic> json) => TrackedMistake(
        kind: json['kind']?.toString() ?? 'grammar',
        key: json['key']?.toString() ?? '',
        correction: json['correction']?.toString() ?? '',
        occurrences: (json['occurrences'] as num?)?.toInt() ?? 0,
      );
}

class CoachStats {
  const CoachStats({
    required this.active,
    required this.resolved,
    required this.top,
  });

  final int active;
  final int resolved;

  /// Busiest first, twenty at most.
  final List<TrackedMistake> top;

  factory CoachStats.fromJson(Map<String, dynamic> json) => CoachStats(
        active: (json['active'] as num?)?.toInt() ?? 0,
        resolved: (json['resolved'] as num?)?.toInt() ?? 0,
        top: (json['top'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(TrackedMistake.fromJson)
                .toList() ??
            const [],
      );
}
