import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/models/announcement.dart';
import 'package:linka/theme/app_colors.dart';
import 'package:linka/widgets/announcement_popup.dart';
import 'package:material_symbols_icons/symbols.dart';

MaterialApp _app(Widget child, {bool dark = false}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      extensions: [dark ? AppColors.dark : AppColors.light],
    ),
    home: Scaffold(body: child),
  );
}

Map<String, dynamic> _json({String? image, int? course}) => <String, dynamic>{
      'id': 7,
      'title': 'AI Coach is here',
      'body': 'Practise speaking with an AI tutor, any time.',
      'cta_label': 'Try it',
      'target': '/ai-coach',
      'image_url': image,
      'audience': 'students',
      'course': course,
      'created_at': '2026-09-06T10:00:00Z',
    };

Map<String, dynamic> _releaseNotes() => _json()
  ..['title'] = "What's new in 1.9"
  ..['body'] = 'Here is what changed:\n\n- Video calls in chats\n• Dark mode fixes\n'
  ..['cta_label'] = 'Got it'
  ..['target'] = '/'
  ..['min_app_version'] = '1.9.0';

void main() {
  group('Announcement.fromJson', () {
    test('reads the wire shape and defaults the button label', () {
      final a = Announcement.fromJson(_json());
      expect(a.id, 7);
      expect(a.target, '/ai-coach');
      expect(a.ctaLabel, 'Try it');
      expect(a.imageUrl, isNull);
      expect(a.isCourse, isFalse);

      final blank = Announcement.fromJson(_json()..['cta_label'] = '  ');
      expect(blank.ctaLabel, 'Check it out');
    });

    test('a course card knows its course', () {
      final a = Announcement.fromJson(_json(course: 12));
      expect(a.isCourse, isTrue);
      expect(a.courseId, 12);
    });

    test('release notes split into prose and checklist lines', () {
      final a = Announcement.fromJson(_releaseNotes());
      expect(a.isReleaseNotes, isTrue);
      expect(a.dismissOnly, isTrue);
      expect(a.hasChecklist, isTrue);
      expect(a.bodyLines.map((l) => (l.bullet, l.text)), [
        (false, 'Here is what changed:'),
        (true, 'Video calls in chats'),
        (true, 'Dark mode fixes'),
      ]);

      final plain = Announcement.fromJson(_json());
      expect(plain.isReleaseNotes, isFalse);
      expect(plain.dismissOnly, isFalse);
      expect(plain.hasChecklist, isFalse);
    });
  });

  group('showAnnouncementPopup', () {
    testWidgets('renders title, body, badge and the CTA; CTA resolves true',
        (tester) async {
      bool? result;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showAnnouncementPopup(
              context,
              Announcement.fromJson(_json()),
            );
          },
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('AI Coach is here'), findsOneWidget);
      expect(find.text('Practise speaking with an AI tutor, any time.'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
      expect(find.text('Try it'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);

      await tester.tap(find.text('Try it'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(find.text('AI Coach is here'), findsNothing);
    });

    testWidgets('release notes show a checklist and a single button',
        (tester) async {
      bool? result;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showAnnouncementPopup(
              context,
              Announcement.fromJson(_releaseNotes()),
            );
          },
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text("What's new in 1.9"), findsOneWidget);
      expect(find.text('Video calls in chats'), findsOneWidget);
      expect(find.text('Dark mode fixes'), findsOneWidget);
      expect(find.byIcon(Symbols.check_circle_rounded), findsNWidgets(2));
      expect(find.text('Maybe later'), findsNothing);
      expect(find.byIcon(Symbols.arrow_forward), findsNothing);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('"Maybe later" and the close control both resolve false',
        (tester) async {
      for (final dismiss in ['Maybe later', 'close']) {
        bool? result;
        await tester.pumpWidget(_app(Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showAnnouncementPopup(
                context,
                Announcement.fromJson(_json()),
              );
            },
            child: const Text('open'),
          ),
        ), dark: true));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        if (dismiss == 'close') {
          await tester.tap(find.byIcon(Symbols.close_rounded));
        } else {
          await tester.tap(find.text(dismiss));
        }
        await tester.pumpAndSettle();
        expect(result, isFalse, reason: dismiss);
      }
    });
  });
}
