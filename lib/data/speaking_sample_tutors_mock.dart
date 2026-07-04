/// One Speaking part: its cue-card/question text plus the matching audio
/// clip and SRT transcript, all bundled as Flutter assets.
class SpeakingSamplePart {
  const SpeakingSamplePart({
    required this.part,
    required this.title,
    required this.questionText,
    required this.audioAsset,
    required this.subtitleAsset,
  });

  final int part;
  final String title;
  final String questionText;
  final String audioAsset;
  final String subtitleAsset;
}

/// A tutor's real Speaking sample answer, covering Part 1/2/3 separately.
class SpeakingSampleTutor {
  const SpeakingSampleTutor({
    required this.id,
    required this.name,
    required this.imageAsset,
    required this.bandScore,
    required this.parts,
  });

  final String id;
  final String name;
  final String imageAsset;
  final double bandScore;
  final List<SpeakingSamplePart> parts;
}

const _nodirbekParts = [
  SpeakingSamplePart(
    part: 1,
    title: 'Part 1 — Friends',
    questionText: 'Do you have a lot of friends? How often do you see them? '
        'Is there anything special about your friends?',
    audioAsset: 'assets/audio/speaking_samples/part1.mp3',
    subtitleAsset: 'assets/subtitles/speaking_samples/part1.srt',
  ),
  SpeakingSamplePart(
    part: 2,
    title: 'Part 2 — Describe a friend of yours',
    questionText: 'Describe a friend of yours.\n\nYou should say:\n'
        '• how you met\n• how long you have known each other\n'
        '• what makes them special\n\nand explain why this friendship is important to you.',
    audioAsset: 'assets/audio/speaking_samples/part2.mp3',
    subtitleAsset: 'assets/subtitles/speaking_samples/part2.srt',
  ),
  SpeakingSamplePart(
    part: 3,
    title: 'Part 3 — Friendship in society',
    questionText: 'Do you think friendship is important nowadays? '
        'What is the best time to make new friends? '
        'Is it important to stay in touch with your friends throughout the years?',
    audioAsset: 'assets/audio/speaking_samples/part3.mp3',
    subtitleAsset: 'assets/subtitles/speaking_samples/part3.srt',
  ),
];

/// Local mock data used until the backend speaking-samples endpoint ships —
/// repeats the same tutor sample so the grid UI can be previewed.
final List<SpeakingSampleTutor> mockSpeakingSampleTutors = List.generate(
  6,
  (i) => SpeakingSampleTutor(
    id: 'nodirbek-$i',
    name: 'Nodirbek Aliyev',
    imageAsset: 'assets/images/tutors/nodirbek_aliyev.png',
    bandScore: 8.5,
    parts: _nodirbekParts,
  ),
);
