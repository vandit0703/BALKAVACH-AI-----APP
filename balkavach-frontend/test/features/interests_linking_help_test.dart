import 'package:balkavach_app/features/authentication/presentation/child_login_screen.dart';
import 'package:balkavach_app/features/child_profile/presentation/child_interests_and_link_cards.dart';
import 'package:balkavach_app/features/settings/presentation/help_support_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

void main() {
  testWidgets('parent can view and approve pending child interest requests', (
    tester,
  ) async {
    final h = await Harness.create(session: Fx.parentSession());
    h.backend
      ..reply('GET', '/api/v1/families/fam-1/children/child-1/interests', {
        'child_id': 'child-1',
        'interests': ['science'],
        'pending_requests': ['stories'],
        'available_categories': [
          {'slug': 'science', 'name': 'Science'},
          {'slug': 'stories', 'name': 'Stories'},
        ],
      })
      ..reply('PUT', '/api/v1/families/fam-1/children/child-1/interests', {
        'child_id': 'child-1',
        'interests': ['science', 'stories'],
        'pending_requests': <String>[],
        'available_categories': [
          {'slug': 'science', 'name': 'Science'},
          {'slug': 'stories', 'name': 'Stories'},
        ],
      });

    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: ParentChildInterestsCard(
            familyId: 'fam-1',
            childId: 'child-1',
          ),
        ),
      ),
      overrides: h.overrides,
    );

    expect(find.byKey(const Key('parent.interests.pending')), findsOneWidget);
    await tester.tap(find.byKey(const Key('parent.interests.approve')));
    await tester.pumpAndSettle();

    final put = h.backend
        .requestsTo('PUT', '/api/v1/families/fam-1/children/child-1/interests')
        .single;
    expect((put.data as Map)['interests'], containsAll(['science', 'stories']));
    expect(find.byKey(const Key('parent.interests.pending')), findsNothing);
  });

  testWidgets('child can request interest changes without altering active list', (
    tester,
  ) async {
    final h = await Harness.create(session: Fx.childSession());
    h.backend
      ..reply('GET', '/api/v1/videos/interests', {
        'interests': ['science'],
        'pending_requests': <String>[],
        'available_categories': [
          {'slug': 'science', 'name': 'Science'},
          {'slug': 'stories', 'name': 'Stories'},
        ],
      })
      ..reply('POST', '/api/v1/videos/interests/request', {
        'interests': ['science'],
        'pending_requests': ['stories'],
        'available_categories': [
          {'slug': 'science', 'name': 'Science'},
          {'slug': 'stories', 'name': 'Stories'},
        ],
      });

    await pumpScreen(
      tester,
      const Scaffold(body: SingleChildScrollView(child: ChildInterestsCard())),
      overrides: h.overrides,
    );

    await tester.tap(find.byKey(const Key('child.interest.stories')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('child.interests.request')));
    await tester.pumpAndSettle();

    expect(
      h.backend.requestsTo('POST', '/api/v1/videos/interests/request'),
      hasLength(1),
    );
    expect(find.text('Waiting for parent approval'), findsOneWidget);
  });

  testWidgets('parent can generate a link code and child can redeem it', (
    tester,
  ) async {
    final h = await Harness.create(session: Fx.parentSession());
    h.backend.reply(
      'POST',
      '/api/v1/families/fam-1/children/child-1/link-code',
      {
        'code': 'AB12CD34',
        'qr_payload': 'balkavach://link?code=AB12CD34',
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
      },
    );

    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: ParentChildLinkCard(familyId: 'fam-1', childId: 'child-1'),
        ),
      ),
      overrides: h.overrides,
    );

    await tester.tap(find.byKey(const Key('parent.link.generate')));
    await tester.pumpAndSettle();
    expect(find.text('AB12CD34'), findsOneWidget);
    expect(find.text('balkavach://link?code=AB12CD34'), findsOneWidget);
  });

  testWidgets('child can enter link code and see error on invalid code', (
    tester,
  ) async {
    final hChild = await Harness.create();
    hChild.backend.on(
      'POST',
      '/api/v1/auth/child-link/redeem',
      (_) => FakeReply.error(
        400,
        'invalid_or_expired_link_code',
        'This linking code is invalid or expired',
      ),
    );
    await pumpScreen(
      tester,
      const ChildLoginScreen(),
      overrides: hChild.overrides,
    );
    await tester.enterText(
      find.byKey(const Key('child.login.linkCode')),
      'AB12CD34',
    );
    await tester.ensureVisible(find.byKey(const Key('child.login.linkSubmit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('child.login.linkSubmit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('child.login.linkConfirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('child.login.linkConfirm')));
    await tester.pumpAndSettle();
    expect(
      hChild.backend.requestsTo('POST', '/api/v1/auth/child-link/redeem'),
      hasLength(1),
    );
  });

  testWidgets('Help & Support renders localized FAQs in en, gu, and hi', (
    tester,
  ) async {
    for (final lang in ['en', 'gu', 'hi']) {
      final h = await Harness.create();
      await pumpScreen(
        tester,
        const HelpSupportScreen(),
        overrides: h.overrides,
        locale: Locale(lang),
      );
      expect(find.byKey(const Key('help.intro')), findsOneWidget);
      expect(find.byKey(const Key('help.faq.0')), findsOneWidget);
      expect(find.byKey(const Key('help.faq.6')), findsOneWidget);
    }
  });
}
