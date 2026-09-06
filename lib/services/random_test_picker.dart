import 'dart:math';

import '../models/mock_test.dart';
import '../widgets/mock_test_access.dart';
import 'mock_test_service.dart';

/// What "Try a random test" resolved to.
sealed class RandomPick {
  const RandomPick();
}

class RandomMockTestPick extends RandomPick {
  const RandomMockTestPick(this.test, this.testType);
  final MockTest test;
  final String testType; // 'reading' | 'listening'
}

class RandomWritingPick extends RandomPick {
  const RandomWritingPick(this.prompt);
  final Map<String, dynamic> prompt;
}

/// Every test the student could have been sent to is behind the Plus gate.
class RandomPickLocked extends RandomPick {
  const RandomPickLocked();
}

/// Nothing published yet, or every list failed to load.
class RandomPickEmpty extends RandomPick {
  const RandomPickEmpty();
}

/// Chooses a test for the student. The list screens pick from what they have
/// already loaded via [pick]; the Mock Exams hub, which has nothing loaded,
/// uses [pickAnySkill].
class RandomTestPicker {
  RandomTestPicker({Random? random}) : _random = random ?? Random();

  final Random _random;

  T pick<T>(List<T> items) {
    assert(items.isNotEmpty, 'pick() needs at least one candidate');
    return items[_random.nextInt(items.length)];
  }

  /// A random test from Reading, Listening or Writing.
  ///
  /// Picks the skill first and only then a test within it, so a student is
  /// not funnelled into Writing just because it has hundreds of prompts while
  /// Reading has thirty. Reading/Listening candidates respect the free
  /// window: once it is spent only retakes qualify. Writing is open to
  /// everyone, so the gate only wins ([RandomPickLocked]) when nothing at all
  /// is left to open.
  Future<RandomPick> pickAnySkill() async {
    final results = await Future.wait<Object?>([
      mtOpenableMockTestIds(),
      MockTestService.fetchTests('reading').catchError((_) => <MockTest>[]),
      MockTestService.fetchTests('listening').catchError((_) => <MockTest>[]),
      MockTestService.fetchWritingPrompts().catchError((_) => <Map<String, dynamic>>[]),
    ]);
    final openable = results[0] as Set<int>?;
    final reading = results[1] as List<MockTest>;
    final listening = results[2] as List<MockTest>;
    final prompts = results[3] as List<Map<String, dynamic>>;

    var sawLocked = false;
    List<RandomPick> mockCandidates(List<MockTest> tests, String testType) {
      final open = <RandomPick>[];
      for (final test in tests) {
        if (openable == null || openable.contains(test.id)) {
          open.add(RandomMockTestPick(test, testType));
        } else {
          sawLocked = true;
        }
      }
      return open;
    }

    final skills = <List<RandomPick>>[
      mockCandidates(reading, 'reading'),
      mockCandidates(listening, 'listening'),
      [for (final prompt in prompts) RandomWritingPick(prompt)],
    ].where((candidates) => candidates.isNotEmpty).toList();

    if (skills.isEmpty) return sawLocked ? const RandomPickLocked() : const RandomPickEmpty();
    return pick(pick(skills));
  }
}
