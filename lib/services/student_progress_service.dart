import '../models/mock_test.dart';
import '../models/student_progress.dart';
import 'api_service.dart';
import 'mock_test_service.dart';

/// Where the student stands, across every skill.
///
/// There is no single progress endpoint: the backend knows writing history
/// through `/writing-attempts/insights/`, reading and listening through
/// `/mock-tests/attempts/`, speaking through `/speaking-attempts/` and lesson
/// time through `/bookings/my/`. This pulls the four in parallel and folds
/// them into one [StudentProgress] — the same assembly the website does on
/// its dashboard — so the screen has one future to wait on.
///
/// Each source fails independently: a student whose speaking list times out
/// still sees their reading bands. Only when every source fails does the
/// fetch throw, since then there is genuinely nothing to show.
class StudentProgressService {
  static Future<StudentProgress> fetch() async {
    final results = await Future.wait<Object?>([
      _guard(MockTestService.fetchWritingInsights()),
      _guard(MockTestService.fetchAttempts()),
      _guard(MockTestService.fetchSpeakingAttempts()),
      _guard(ApiService.getList('/bookings/my/')),
    ]);

    if (results.every((r) => r == null)) {
      throw ApiException('Progress could not be loaded');
    }

    final insights = results[0] as Map<String, dynamic>?;
    final attempts = (results[1] as List<MockTestAttempt>?) ?? const [];
    final speaking = (results[2] as List<Map<String, dynamic>>?) ?? const [];
    final bookings = ((results[3] as List<dynamic>?) ?? const []).whereType<Map>().map((b) => b.cast<String, dynamic>()).toList();

    return StudentProgress(
      writing: insights != null ? SkillProgress.fromWritingInsights(insights) : SkillProgress.empty,
      listening: SkillProgress.fromMockAttempts(attempts, 'listening'),
      reading: SkillProgress.fromMockAttempts(attempts, 'reading'),
      speaking: SkillProgress.fromSpeakingAttempts(speaking),
      lessons: LessonProgress.fromBookings(bookings),
      writingInsights: insights,
    );
  }

  static Future<T?> _guard<T>(Future<T> future) => future.then<T?>((v) => v).catchError((_) => null);
}
