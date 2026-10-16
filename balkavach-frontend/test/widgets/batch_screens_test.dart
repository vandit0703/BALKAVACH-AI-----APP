import 'package:balkavach_app/app.dart';
import 'package:balkavach_app/features/approvals/presentation/approvals_screen.dart';
import 'package:balkavach_app/features/garden/presentation/garden_screen.dart';
import 'package:balkavach_app/features/progress/presentation/weekly_report_screen.dart';
import 'package:balkavach_app/features/rewards/presentation/rewards_screen.dart';
import 'package:balkavach_app/features/settings/presentation/parent_settings_screen.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _reviewPath = '/api/v1/reviews/submissions/${Fx.submissionId}';
const _childPath = '/api/v1/families/${Fx.familyId}/children/${Fx.childId}';

Future<Harness> _parent() async {
  final h = await Harness.create(
    session: Fx.parentSession(),
    prefs: onboardedPrefs,
  );
  h.backend
    ..reply('POST', '/api/v1/settings/families/${Fx.familyId}/consents', {
      ...Fx.consent(),
    }, status: 201)
    ..reply('GET', '/api/v1/notifications', [
      Fx.notification(type: 'task_submitted'),
    ])
    ..reply('GET', '/api/v1/tasks/${Fx.taskId}/submissions', [Fx.submission()]);
  return h;
}

Future<Harness> _child({
  List<Map<String, Object?>> activityDays = const [],
  List<Map<String, Object?>> badges = const [],
  int longestStreak = 9,
}) async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  h.backend
    ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
    ..reply(
      'GET',
      '/api/v1/progress/children/${Fx.childId}',
      Fx.progress(
        activityDays: activityDays,
        badges: badges,
        longestStreak: longestStreak,
      ),
    )
    ..reply('GET', '/api/v1/redemptions/mine', <Object?>[]);
  return h;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _pumpApp(WidgetTester tester, Harness h) async {
  setWindow(tester, const Size(393, 852));
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      retry: (_, _) => null,
      child: const BalKavachApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, Harness h, Widget screen) =>
    pumpScreen(tester, screen, overrides: h.overrides);

void main() {
  group('Approvals', () {
    testWidgets('shows the submission with its note, mission and stars', (
      tester,
    ) async {
      final h = await _parent();
      await _pump(tester, h, const ApprovalsScreen());

      expect(find.text('Mission Approvals'), findsOneWidget);
      expect(find.text('1 Action'), findsOneWidget);
      expect(find.text('Aarav'), findsWidgets);
      expect(find.text('Mission: Read a Storybook'), findsOneWidget);
      expect(find.text('“I read it!”'), findsOneWidget);
      expect(find.text('Approve & Award +10 ⭐'), findsOneWidget);
    });

    testWidgets('approving posts the decision and refreshes the inbox', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.reply('POST', _reviewPath, Fx.submission(status: 'approved'));
      await _pump(tester, h, const ApprovalsScreen());

      // The server now reports the submission as approved.
      h.backend.reply('GET', '/api/v1/tasks/${Fx.taskId}/submissions', [
        Fx.submission(status: 'approved'),
      ]);
      await _tap(tester, find.byKey(const Key('review.approve')));

      expect(h.backend.requestsTo('POST', _reviewPath).single.data, {
        'decision': 'approved',
      });
      expect(find.text('Approved! 10 stars sent to Aarav.'), findsOneWidget);
      expect(find.byKey(const Key('review.approve')), findsNothing);
      expect(
        find.text(
          'Nothing to review right now. New submissions will appear here.',
        ),
        findsOneWidget,
      );

      await _tap(tester, find.byKey(const Key('approvals.tab.approved')));
      expect(find.text('Read a Storybook'), findsOneWidget);
      expect(find.text('+10 Stars credited'), findsOneWidget);
    });

    testWidgets('asking for a retry sends the note', (tester) async {
      final h = await _parent();
      h.backend.reply(
        'POST',
        _reviewPath,
        Fx.submission(status: 'resubmission_requested'),
      );
      await _pump(tester, h, const ApprovalsScreen());

      await _tap(tester, find.byKey(const Key('review.retry')));
      expect(find.text('Ask Aarav to try again?'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('review.note')),
        'add colour',
      );
      await _tap(tester, find.byKey(const Key('review.note.confirm')));

      expect(h.backend.requestsTo('POST', _reviewPath).single.data, {
        'decision': 'resubmission_requested',
        'review_note': 'add colour',
      });
      expect(find.text('Aarav will be asked to try again.'), findsOneWidget);
    });

    testWidgets('cancelling the note dialog sends nothing', (tester) async {
      final h = await _parent();
      await _pump(tester, h, const ApprovalsScreen());

      await _tap(tester, find.byKey(const Key('review.decline')));
      await _tap(tester, find.text('Cancel'));

      expect(h.backend.requestsTo('POST', _reviewPath), isEmpty);
      expect(find.byKey(const Key('review.approve')), findsOneWidget);
    });

    testWidgets('a conflict explains and refreshes instead of crashing', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.on(
        'POST',
        _reviewPath,
        (_) => FakeReply.error(
          409,
          'submission_already_reviewed',
          'This submission has already been reviewed',
        ),
      );
      await _pump(tester, h, const ApprovalsScreen());
      final before = h.backend
          .requestsTo('GET', '/api/v1/tasks/${Fx.taskId}/submissions')
          .length;

      await _tap(tester, find.byKey(const Key('review.approve')));

      expect(
        find.text(
          'This submission was already reviewed. The list has been refreshed.',
        ),
        findsOneWidget,
      );
      expect(
        h.backend
            .requestsTo('GET', '/api/v1/tasks/${Fx.taskId}/submissions')
            .length,
        greaterThan(before),
      );
    });

    testWidgets('a server error keeps the card and shows an error', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.on(
        'POST',
        _reviewPath,
        (_) => FakeReply.error(500, 'internal_error', 'boom'),
      );
      await _pump(tester, h, const ApprovalsScreen());

      await _tap(tester, find.byKey(const Key('review.approve')));

      expect(
        find.text('The server had a problem. Please try again soon.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('review.approve')), findsOneWidget);
    });

    testWidgets('empty inbox shows the empty state', (tester) async {
      final h = await _parent();
      h.backend.reply('GET', '/api/v1/notifications', <Object?>[]);
      await _pump(tester, h, const ApprovalsScreen());

      expect(
        find.text(
          'Nothing to review right now. New submissions will appear here.',
        ),
        findsOneWidget,
      );
      expect(find.text('1 Action'), findsNothing);
    });

    testWidgets('a failing inbox offers a retry', (tester) async {
      final h = await _parent();
      h.backend.on(
        'GET',
        '/api/v1/notifications',
        (_) => const FakeReply.fail(DioExceptionType.connectionError),
      );
      await _pump(tester, h, const ApprovalsScreen());

      expect(find.text('Try again'), findsOneWidget);
      expect(find.byKey(const Key('review.approve')), findsNothing);
    });

    testWidgets('parent home links to the inbox with the pending count', (
      tester,
    ) async {
      final h = await _parent();
      await _pumpApp(tester, h);

      expect(find.text('1 waiting for review'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('parent.approvals')));
      expect(find.text('Mission Approvals'), findsOneWidget);
      expect(find.byKey(const Key('review.approve')), findsOneWidget);
    });
  });

  group('Weekly report', () {
    testWidgets('summarises approved missions for the last seven days', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.reply(
        'GET',
        '/api/v1/progress/children/${Fx.childId}',
        Fx.progress(
          activityDays: [
            Fx.activityDay('2026-10-12', tasks: 2, stars: 20, xp: 40),
            Fx.activityDay('2026-10-10'),
          ],
        ),
      );
      final handle = tester.ensureSemantics();
      await _pump(tester, h, const WeeklyReportScreen());

      expect(find.text('Welcome, Priya Sharma'), findsOneWidget);
      expect(find.text('Oct 6 – Oct 12'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^3 Missions Done')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^30 Stars Awarded')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^60 XP Earned')), findsOneWidget);
      expect(find.text('Best day: Monday (2 completed)'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a quiet week says so', (tester) async {
      final h = await _parent();
      await _pump(tester, h, const WeeklyReportScreen());

      expect(find.text('No approved missions this week yet.'), findsOneWidget);
      expect(
        find.text('No badges yet. They unlock as missions are approved.'),
        findsOneWidget,
      );
    });

    testWidgets('lists unlocked badges', (tester) async {
      final h = await _parent();
      h.backend.reply(
        'GET',
        '/api/v1/progress/children/${Fx.childId}',
        Fx.progress(badges: [Fx.badge(name: 'Bookworm')]),
      );
      await _pump(tester, h, const WeeklyReportScreen());

      expect(find.text('Bookworm'), findsOneWidget);
      expect(find.text('1 Unlocked'), findsOneWidget);
    });

    testWidgets('copies the weekly summary to the clipboard', (tester) async {
      final h = await _parent();
      h.backend.reply(
        'GET',
        '/api/v1/progress/children/${Fx.childId}',
        Fx.progress(
          activityDays: [Fx.activityDay('2026-10-12', tasks: 2, stars: 20)],
        ),
      );
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pump(tester, h, const WeeklyReportScreen());

      await _tap(tester, find.byKey(const Key('reports.copy')));

      expect(find.text('Weekly summary copied'), findsOneWidget);
      expect(copied, contains('Aarav'));
      expect(copied, contains('2 missions approved'));
      expect(copied, contains('20 stars'));
    });

    testWidgets('a failing progress request offers a retry', (tester) async {
      final h = await _parent();
      h.backend.on(
        'GET',
        '/api/v1/progress/children/${Fx.childId}',
        (_) => FakeReply.error(500, 'internal_error', 'boom'),
      );
      await _pump(tester, h, const WeeklyReportScreen());

      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Child profile', () {
    Future<void> openProfile(WidgetTester tester, Harness h) async {
      await _pumpApp(tester, h);
      await _tap(tester, find.text('Aarav'));
    }

    testWidgets('opens from the parent home with real progress', (
      tester,
    ) async {
      final h = await _parent();
      await openProfile(tester, h);

      expect(find.text('Family Management'), findsOneWidget);
      expect(find.text('Level 4 Explorer'), findsOneWidget);
      expect(find.text('240 Available Stars'), findsOneWidget);
      expect(find.text('Age: 7 yrs'), findsOneWidget);
    });

    testWidgets(
      'retrieves credentials on demand, masks password, and clears on close',
      (tester) async {
        final h = await _parent();
        h.backend.reply('GET', '$_childPath/credentials', {
          'username': 'aarav7',
          'password': 'a-secure-child-password',
        });
        await openProfile(tester, h);

        expect(find.byKey(const Key('profile.credentials')), findsOneWidget);
        await _tap(tester, find.byKey(const Key('profile.credentials')));
        expect(find.text('aarav7'), findsOneWidget);
        expect(
          tester
              .widget<SelectableText>(
                find.byKey(const Key('credential.value.Password')),
              )
              .data,
          '••••••••',
        );

        await _tap(
          tester,
          find.byKey(const Key('credentials.password.toggle')),
        );
        expect(find.text('a-secure-child-password'), findsOneWidget);
        await _tap(tester, find.text('Close'));
        expect(find.text('a-secure-child-password'), findsNothing);
        expect(
          h.backend.requestsTo('GET', '$_childPath/credentials'),
          hasLength(1),
        );
      },
    );

    testWidgets('editing saves the name and keeps the avatar on device', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.reply('PATCH', _childPath, Fx.child(name: 'Aarav S'));
      await openProfile(tester, h);

      await _tap(tester, find.byKey(const Key('profile.edit')));
      await tester.enterText(find.byKey(const Key('edit.name')), 'Aarav S');
      await _tap(tester, find.byKey(const Key('avatar.cap')));
      await _tap(tester, find.byKey(const Key('edit.save')));

      expect(h.backend.requestsTo('PATCH', _childPath).single.data, {
        'display_name': 'Aarav S',
        'date_of_birth': '2019-05-04',
      });
      expect(h.prefs.childAvatarKey(Fx.childId), 'cap');
      expect(find.text('Profile saved'), findsOneWidget);
    });

    testWidgets('an empty name is rejected before any request', (tester) async {
      final h = await _parent();
      await openProfile(tester, h);

      await _tap(tester, find.byKey(const Key('profile.edit')));
      await tester.enterText(find.byKey(const Key('edit.name')), '');
      await _tap(tester, find.byKey(const Key('edit.save')));

      expect(h.backend.requestsTo('PATCH', _childPath), isEmpty);
      expect(find.text('Please enter a name.'), findsOneWidget);
    });

    testWidgets('removing asks first, then deactivates and returns home', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.on('DELETE', _childPath, (_) => const FakeReply(204));
      await openProfile(tester, h);

      await _tap(tester, find.byKey(const Key('profile.remove')));
      expect(find.text("Remove Aarav's profile?"), findsOneWidget);
      expect(h.backend.requestsTo('DELETE', _childPath), isEmpty);

      await _tap(tester, find.byKey(const Key('profile.remove.confirm')));

      expect(h.backend.requestsTo('DELETE', _childPath), hasLength(1));
      expect(find.text("Aarav's profile was removed."), findsOneWidget);
      expect(find.text('Your children'), findsOneWidget);
    });

    testWidgets('a parent can sign the child out on every device', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.on(
        'DELETE',
        '/api/v1/auth/children/${Fx.childId}/sessions',
        (_) => const FakeReply(204),
      );
      await openProfile(tester, h);

      await _tap(tester, find.byKey(const Key('profile.devices')));
      expect(
        h.backend.requestsTo(
          'DELETE',
          '/api/v1/auth/children/${Fx.childId}/sessions',
        ),
        isEmpty,
        reason: 'asks before ending anything',
      );
      await _tap(tester, find.byKey(const Key('profile.devices.confirm')));

      expect(
        h.backend.requestsTo(
          'DELETE',
          '/api/v1/auth/children/${Fx.childId}/sessions',
        ),
        hasLength(1),
      );
      expect(find.text('Signed out on all devices'), findsOneWidget);
      expect(
        h.backend.requestsTo('DELETE', _childPath),
        isEmpty,
        reason: 'signing out must not remove the profile',
      );
    });

    testWidgets('cancelling the removal keeps the profile', (tester) async {
      final h = await _parent();
      await openProfile(tester, h);

      await _tap(tester, find.byKey(const Key('profile.remove')));
      await _tap(tester, find.text('Cancel'));

      expect(h.backend.requestsTo('DELETE', _childPath), isEmpty);
      expect(find.text('Family Management'), findsOneWidget);
    });

    testWidgets('a failed removal shows an error and stays on the profile', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.on(
        'DELETE',
        _childPath,
        (_) => FakeReply.error(500, 'internal_error', 'boom'),
      );
      await openProfile(tester, h);

      await _tap(tester, find.byKey(const Key('profile.remove')));
      await _tap(tester, find.byKey(const Key('profile.remove.confirm')));

      expect(
        find.text('The server had a problem. Please try again soon.'),
        findsOneWidget,
      );
      expect(find.text('Family Management'), findsOneWidget);
    });

    testWidgets('child mode can be started from the profile', (tester) async {
      final h = await _parent();
      h.backend.reply(
        'POST',
        '/api/v1/auth/children/${Fx.childId}/session',
        Fx.childToken(),
      );
      await openProfile(tester, h);

      h.backend.reply(
        'GET',
        '/api/v1/auth/me',
        Fx.childSession().user.toJson(),
      );
      await _tap(tester, find.byKey(const Key('profile.childMode')));
      await _tap(tester, find.text('Start'));

      expect(find.text('Hello Aarav! 👋'), findsOneWidget);
      expect((await h.storage.read())?.isChild, isTrue);
    });
  });

  group('Parent settings', () {
    Future<Harness> settingsHarness() async {
      final h = await _parent();
      h.backend
        ..reply('GET', '/api/v1/settings/me', Fx.userSettings())
        ..reply('GET', '/api/v1/settings/families/${Fx.familyId}/consents', [
          Fx.consent(),
        ]);
      return h;
    }

    testWidgets('shows the account, children and consent record', (
      tester,
    ) async {
      final h = await settingsHarness();
      await _pump(tester, h, const ParentSettingsScreen());

      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(find.text('priya@example.com'), findsOneWidget);
      expect(find.text('FAMILY OWNER'), findsOneWidget);
      expect(find.text('Aarav'), findsOneWidget);
      expect(find.textContaining('version 2026-10-draft'), findsOneWidget);
      // Controls the backend cannot honour must not appear.
      expect(find.textContaining('PIN'), findsNothing);
      expect(find.textContaining('Bedtime'), findsNothing);
    });

    testWidgets('toggling a notification preference patches only that field', (
      tester,
    ) async {
      final h = await settingsHarness();
      h.backend.reply(
        'PATCH',
        '/api/v1/settings/me',
        Fx.userSettings(push: false),
      );
      await _pump(tester, h, const ParentSettingsScreen());

      await _tap(tester, find.byKey(const Key('settings.push')));

      expect(h.backend.requestsTo('PATCH', '/api/v1/settings/me').single.data, {
        'push_enabled': false,
      });
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('settings.push')))
            .value,
        isFalse,
      );
    });

    testWidgets('a rejected change is rolled back and reported', (
      tester,
    ) async {
      final h = await settingsHarness();
      h.backend.on(
        'PATCH',
        '/api/v1/settings/me',
        (_) => FakeReply.error(500, 'internal_error', 'boom'),
      );
      await _pump(tester, h, const ParentSettingsScreen());

      await _tap(tester, find.byKey(const Key('settings.push')));

      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('settings.push')))
            .value,
        isTrue,
        reason: 'the optimistic change must be undone',
      );
      expect(
        find.text('The server had a problem. Please try again soon.'),
        findsOneWidget,
      );
    });

    testWidgets('changing the language applies it and saves it', (
      tester,
    ) async {
      final h = await settingsHarness();
      h.backend.reply('PATCH', '/api/v1/settings/me', {
        ...Fx.userSettings(),
        'language_code': 'gu',
      });
      await _pump(tester, h, const ParentSettingsScreen());

      await _tap(tester, find.byKey(const Key('settings.language')));
      await _tap(tester, find.byKey(const Key('settings.language.gu')));

      expect(h.prefs.languageCode, 'gu');
      expect(h.backend.requestsTo('PATCH', '/api/v1/settings/me').single.data, {
        'language_code': 'gu',
      });
    });

    testWidgets('log out clears the session', (tester) async {
      final h = await settingsHarness();
      await _pump(tester, h, const ParentSettingsScreen());

      await _tap(tester, find.byKey(const Key('settings.logout')));

      expect(await h.storage.read(), isNull);
    });

    testWidgets('opens from the parent home', (tester) async {
      final h = await settingsHarness();
      await _pumpApp(tester, h);

      await _tap(tester, find.byKey(const Key('parent.settings')));
      expect(find.text('Family Account'), findsOneWidget);
    });
  });

  group('Rewards', () {
    testWidgets('shows the real balance, streak and badges', (tester) async {
      final h = await _child(badges: [Fx.badge()]);
      await _pump(tester, h, const RewardsScreen());

      expect(find.text('240'), findsOneWidget);
      expect(find.text('Bookworm'), findsOneWidget);
      expect(find.text('1 Unlocked'), findsOneWidget);
      expect(find.text('5 Days Streak!'), findsOneWidget);
    });

    testWidgets('opening the shop never creates a request', (tester) async {
      final h = await _child();
      h.backend.reply('GET', '/api/v1/rewards', [Fx.reward()]);
      await _pump(tester, h, const RewardsScreen());

      expect(find.text('Ice cream'), findsOneWidget);
      expect(h.backend.requestsTo('GET', '/api/v1/rewards'), hasLength(1));
      expect(
        h.backend.requestsTo('POST', '/api/v1/redemptions'),
        isEmpty,
        reason: 'only an explicit, confirmed tap may ask for a reward',
      );
    });

    testWidgets('a server that still hides the catalog shows "coming soon"', (
      tester,
    ) async {
      final h = await _child();
      h.backend.on(
        'GET',
        '/api/v1/rewards',
        (_) => FakeReply.error(403, 'http_error', 'Parent access required'),
      );
      await _pump(tester, h, const RewardsScreen());

      expect(find.text('The treasure shop is coming soon'), findsOneWidget);
      expect(find.byKey(const Key('reward.ask')), findsNothing);
    });

    testWidgets('lists the child\'s own reward requests', (tester) async {
      final h = await _child();
      h.backend.reply('GET', '/api/v1/redemptions/mine', [
        Fx.redemption(cost: 50),
        {
          ...Fx.redemption(status: 'fulfilled'),
          'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        },
      ]);
      await _pump(tester, h, const RewardsScreen());

      expect(find.text('Reward request'), findsNWidgets(2));
      expect(find.text('Pending Approval ⏳'), findsOneWidget);
      expect(find.text('Ready to enjoy'), findsOneWidget);
    });

    testWidgets('a failing request list does not hide the balance', (
      tester,
    ) async {
      final h = await _child();
      h.backend.on(
        'GET',
        '/api/v1/redemptions/mine',
        (_) => FakeReply.error(500, 'internal_error', 'boom'),
      );
      await _pump(tester, h, const RewardsScreen());

      expect(find.text('240'), findsOneWidget);
      expect(
        find.text("Couldn't load your reward requests right now."),
        findsOneWidget,
      );
    });

    testWidgets('an empty badge shelf encourages the child', (tester) async {
      final h = await _child();
      await _pump(tester, h, const RewardsScreen());

      expect(
        find.text('Finish missions to unlock your first badge!'),
        findsOneWidget,
      );
    });
  });

  group('Garden', () {
    testWidgets('stage and milestones come from real progress', (tester) async {
      final h = await _child(
        activityDays: [Fx.activityDay('2026-10-12', tasks: 4)],
        longestStreak: 9,
      );
      await _pump(tester, h, const GardenScreen());

      expect(find.text("Aarav's Mindful Garden"), findsOneWidget);
      expect(find.text('Stage: Happy Mango Sapling'), findsOneWidget);
      expect(
        find.text('2 more approved missions to reach Blooming Tree'),
        findsWidgets,
      );
      expect(find.text('4 Missions'), findsOneWidget);
      expect(find.text('2 / 4 Collected'), findsOneWidget);
      expect(find.text('Reach a 14-day streak to unlock'), findsOneWidget);
    });

    testWidgets('decorations unlock with badges and the size follows XP', (
      tester,
    ) async {
      final h = await _child();
      h.backend.reply(
        'GET',
        '/api/v1/progress/children/${Fx.childId}',
        Fx.progress(
          garden: {
            'stage': 3,
            'stage_key': 'sapling',
            'xp_to_next_stage': 280,
            'items': [
              {
                'key': 'first-mission',
                'badge': 'First Mission',
                'unlocked': true,
              },
              {
                'key': 'week-warrior',
                'badge': 'Week Warrior',
                'unlocked': false,
              },
            ],
          },
        ),
      );
      await _pump(tester, h, const GardenScreen());
      final collection = find.byKey(const Key('garden.collection'));
      await tester.ensureVisible(collection);
      await tester.pumpAndSettle();

      expect(collection, findsOneWidget);
      expect(find.text('1 of 2 unlocked'), findsOneWidget);
      expect(find.text('Garden size: Happy Mango Sapling'), findsOneWidget);
      expect(find.text('280 XP until it grows again'), findsOneWidget);
      expect(find.text('Little fence'), findsOneWidget);
      expect(find.text('Fountain'), findsOneWidget);
      expect(
        find.text('Earn the “Week Warrior” badge to unlock'),
        findsOneWidget,
      );
    });

    testWidgets('a server without a garden still shows the weekly garden', (
      tester,
    ) async {
      final h = await _child();
      await _pump(tester, h, const GardenScreen());
      expect(find.byKey(const Key('garden.collection')), findsNothing);
      expect(find.text('Stage: Little Seed'), findsOneWidget);
    });

    testWidgets('a new garden starts as a seed', (tester) async {
      final h = await _child(longestStreak: 0);
      await _pump(tester, h, const GardenScreen());

      expect(find.text('Stage: Little Seed'), findsOneWidget);
      expect(find.text('0 / 4 Collected'), findsOneWidget);
    });

    testWidgets('a busy week reaches full bloom', (tester) async {
      final h = await _child(
        activityDays: [Fx.activityDay('2026-10-12', tasks: 6)],
      );
      await _pump(tester, h, const GardenScreen());

      expect(find.text('Stage: Blooming Tree'), findsOneWidget);
      expect(
        find.text('Your garden is in full bloom this week! 🌳'),
        findsOneWidget,
      );
    });

    testWidgets('a failing progress request shows a retry', (tester) async {
      final h = await _child();
      h.backend.on(
        'GET',
        '/api/v1/progress/children/${Fx.childId}',
        (_) => FakeReply.error(500, 'internal_error', 'boom'),
      );
      await _pump(tester, h, const GardenScreen());

      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Child navigation', () {
    testWidgets('bottom bar reaches rewards and garden', (tester) async {
      final h = await _child();
      await _pumpApp(tester, h);

      await _tap(tester, find.text('Rewards'));
      expect(find.text('Child Rewards'), findsOneWidget);

      await _tap(tester, find.text('Garden'));
      expect(find.text('Mindful Garden'), findsOneWidget);

      await _tap(tester, find.text('Home'));
      expect(find.text('Hello Aarav! 👋'), findsOneWidget);
    });
  });
}
