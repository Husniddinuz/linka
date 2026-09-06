import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/affiliate_screen.dart';
import '../screens/ai_coach_screen.dart';
import '../screens/article_detail_screen.dart';
import '../screens/articles_list_screen.dart';
import '../screens/course_detail_screen.dart';
import '../screens/courses_list_screen.dart';
import '../screens/ielts_booking_screen.dart';
import '../screens/lessons_screen.dart';
import '../screens/mock_exams_screen.dart';
import '../screens/mock_test_list_screen.dart';
import '../screens/notifications_inbox_screen.dart';
import '../screens/payment_topup_screen.dart';
import '../screens/plus_subscription_screen.dart';
import '../screens/podcasts_list_screen.dart';
import '../screens/speaking_samples_list_screen.dart';
import '../screens/student_progress_screen.dart';
import '../screens/tutor_profile_screen.dart';
import '../screens/writing_prompts_list_screen.dart';
import '../screens/writing_samples_list_screen.dart';

/// Home-screen tabs an announcement can land on, in the order the bottom
/// navigation shows them. The home screen maps these onto its own indices,
/// which differ between the student and tutor layouts.
enum HomeTab { chats, tutors, profile }

/// Resolves an announcement's `target` — the same path scheme the web
/// dashboard uses, minus its `/dashboard` prefix — to a screen.
///
/// The scheme is shared with the backend's admin hint and with
/// `linka-web/src/lib/announcement-target.ts`; add a path in all three.
class AnnouncementTarget {
  AnnouncementTarget._();

  /// Where a path the app has no screen for is sent: the web dashboard,
  /// which has every section this build may predate.
  static const _webDashboard = 'https://linka-ielts.com/dashboard';

  /// Sections that live on the home screen itself. Landing "on" them is
  /// staying where the popup was shown, so they need no navigation.
  static const _homeSections = {'', 'webinars', 'debates', 'home', 'stories'};

  static int? _id(List<String> segments, int at) =>
      segments.length > at ? int.tryParse(segments[at]) : null;

  /// Opens [target]. [selectTab] switches the home screen's bottom tab;
  /// [openSpeakingPractice] is the home screen's own entry into speaking
  /// practice, which shows the terms sheet first.
  static Future<void> open(
    BuildContext context,
    String target, {
    required void Function(HomeTab tab) selectTab,
    required Future<void> Function() openSpeakingPractice,
  }) async {
    final trimmed = target.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      await _launch(trimmed);
      return;
    }

    final uri = Uri.tryParse(trimmed.startsWith('/') ? trimmed : '/$trimmed');
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const <String>[];
    final head = segments.isEmpty ? '' : segments[0];
    final navigator = Navigator.of(context);

    void push(Widget screen) {
      navigator.push(MaterialPageRoute(builder: (_) => screen));
    }

    if (_homeSections.contains(head)) return;

    switch (head) {
      case 'courses':
        final id = _id(segments, 1);
        push(id != null ? CourseDetailScreen(courseId: id) : const CoursesListScreen());
        return;
      case 'mock-tests':
        final kind = segments.length > 1 ? segments[1] : '';
        if (kind == 'listening' || kind == 'reading') {
          push(MockTestListScreen(testType: kind));
        } else if (kind == 'writing') {
          push(const WritingPromptsListScreen());
        } else {
          push(const MockExamsScreen());
        }
        return;
      case 'writing':
        push(const WritingSamplesListScreen());
        return;
      case 'speaking':
        push(const SpeakingSamplesListScreen());
        return;
      case 'ai-coach':
        push(const AiCoachScreen());
        return;
      case 'speaking-practice':
        await openSpeakingPractice();
        return;
      case 'podcasts':
        push(const PodcastsListScreen());
        return;
      case 'articles':
        final id = _id(segments, 1);
        push(id != null ? ArticleDetailScreen(articleId: id) : const ArticlesListScreen());
        return;
      case 'tutors':
      case 'tutor':
        final id = _id(segments, 1);
        if (id != null) {
          push(TutorProfileScreen(tutorId: id));
        } else {
          selectTab(HomeTab.tutors);
        }
        return;
      case 'plus':
        push(const PlusSubscriptionScreen());
        return;
      case 'chats':
        selectTab(HomeTab.chats);
        return;
      case 'profile':
        selectTab(HomeTab.profile);
        return;
      case 'wallet':
        push(const PaymentTopUpScreen());
        return;
      case 'affiliate':
        push(const AffiliateScreen());
        return;
      case 'progress':
        push(const StudentProgressScreen());
        return;
      case 'ielts':
        push(const IeltsBookingScreen());
        return;
      case 'lessons':
        push(const LessonsScreen());
        return;
      case 'notifications':
        push(const NotificationsInboxScreen());
        return;
      default:
        // Movies, typing, anything newer than this build: the web has it.
        await _launch('$_webDashboard${uri?.path ?? '/'}');
    }
  }

  static Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
