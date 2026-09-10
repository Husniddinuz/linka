import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/models/social.dart';
import 'package:linka/screens/follow_list_screen.dart';
import 'package:linka/theme/app_colors.dart';

MaterialApp _app(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.light,
      extensions: const [AppColors.light],
    ),
    home: child,
  );
}

SocialUserCard _card(int id, {bool following = false, String role = 'student'}) =>
    SocialUserCard.fromJson({
      'user_id': id,
      'role': role,
      'display_name': 'Person $id',
      'english_level': 'B2',
      'ielts_score': role == 'tutor' ? 8.0 : null,
      'is_following': following,
    });

void main() {
  group('FollowListScreen', () {
    testWidgets('shows each tab with its total and a follow button per row',
        (tester) async {
      await tester.pumpWidget(_app(FollowListScreen(
        userId: 1,
        title: 'Ali Valiyev',
        followersCount: 2,
        followingCount: 0,
        loadPage: (tab, offset) async => tab == FollowListTab.followers
            ? SocialUserPage(
                results: [_card(2, following: true), _card(3, role: 'tutor')],
                count: 2,
              )
            : const SocialUserPage(results: [], count: 0),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Followers (2)'), findsOneWidget);
      expect(find.text('Following (0)'), findsOneWidget);
      expect(find.text('Person 2'), findsOneWidget);
      expect(find.text('Student · B2'), findsOneWidget);
      expect(find.text('Tutor · IELTS 8.0'), findsOneWidget);
      // One you follow, one you do not.
      expect(find.text('Following'), findsWidgets);
      expect(find.text('Follow'), findsOneWidget);

      await tester.tap(find.text('Following (0)'));
      await tester.pumpAndSettle();
      expect(find.text('Not following anyone'), findsOneWidget);
    });

    testWidgets('opens on the tab it was asked for', (tester) async {
      await tester.pumpWidget(_app(FollowListScreen(
        userId: 1,
        title: 'Ali',
        initialTab: FollowListTab.following,
        loadPage: (tab, offset) async => SocialUserPage(
          results: [_card(tab == FollowListTab.following ? 9 : 8)],
          count: 1,
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Person 9'), findsOneWidget);
      expect(find.text('Person 8'), findsNothing);
    });

    testWidgets('pages in more rows on scroll without repeating any',
        (tester) async {
      final offsets = <int>[];
      await tester.pumpWidget(_app(FollowListScreen(
        userId: 1,
        title: 'Ali',
        loadPage: (tab, offset) async {
          if (tab == FollowListTab.following) {
            return const SocialUserPage(results: [], count: 0);
          }
          offsets.add(offset);
          // The second page overlaps the first by one row, as it does when
          // someone follows mid-scroll and shifts the offset.
          return offset == 0
              ? SocialUserPage(
                  results: List.generate(30, (i) => _card(100 + i)),
                  count: 45,
                  nextOffset: 30,
                )
              : SocialUserPage(
                  results: List.generate(16, (i) => _card(129 + i)),
                  count: 45,
                );
        },
      )));
      await tester.pumpAndSettle();
      expect(offsets, [0]);

      await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(offsets, [0, 30]);

      await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text('Person 144'), findsOneWidget);
      expect(find.text('Person 129'), findsNothing); // scrolled past, once
      expect(find.text('Followers (45)'), findsOneWidget);
    });
  });
}
