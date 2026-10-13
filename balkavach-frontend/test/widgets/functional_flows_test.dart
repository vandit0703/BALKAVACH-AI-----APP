import 'package:balkavach_app/app.dart';
import 'package:balkavach_app/features/approvals/presentation/approvals_screen.dart';
import 'package:balkavach_app/features/authentication/presentation/session_controller.dart';
import 'package:balkavach_app/features/missions/presentation/mission_providers.dart';
import 'package:balkavach_app/features/missions/presentation/missions_screen.dart';
import 'package:balkavach_app/features/missions/presentation/widgets/mission_card.dart';
import 'package:balkavach_app/features/parent_dashboard/presentation/create_mission_screen.dart';
import 'package:balkavach_app/features/settings/presentation/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _submissionsA = '/api/v1/tasks/${Fx.taskId}/submissions';
const _submissionsB = '/api/v1/tasks/${Fx.task2Id}/submissions';
const _notificationIdA = '88888888-8888-4888-8888-88888888888a';
const _notificationIdB = '88888888-8888-4888-8888-88888888888b';
const _submissionB = '77777777-7777-4777-8777-77777777777b';
const _expired = 'Your session has ended. Please sign in again.';

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

Future<Harness> _parent({
  Map<String, Object> prefs = onboardedPrefs,
  bool twoSubmittedTasks = false,
}) async {
  final h = await Harness.create(session: Fx.parentSession(), prefs: prefs);
  h.backend
    ..reply('POST', '/api/v1/settings/families/${Fx.familyId}/consents', {
      ...Fx.consent(),
    }, status: 201)
    ..reply('GET', '/api/v1/notifications', [
      Fx.notification(type: 'task_submitted', id: _notificationIdA),
      if (twoSubmittedTasks)
        Fx.notification(
          type: 'task_submitted',
          id: _notificationIdB,
          taskId: Fx.task2Id,
          submissionId: _submissionB,
        ),
    ])
    ..reply('GET', _submissionsA, [Fx.submission()]);
  return h;
}

Map<String, Object?> _submissionOfB() =>
    Fx.submission(id: _submissionB, taskId: Fx.task2Id);

int _reviewCards(WidgetTester tester) => find
    .byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> &&
          key.value.startsWith('review.') &&
          key.value.length > 30;
    })
    .evaluate()
    .length;

void main() {
  group('Approvals: partial failures', () {
    testWidgets('one failing task does not hide the others', (tester) async {
      final h = await _parent(twoSubmittedTasks: true);
      h.backend.on(
        'GET',
        _submissionsB,
        (_) => FakeReply.error(500, 'internal_error', 'boom'),
      );
      await pumpScreen(tester, const ApprovalsScreen(), overrides: h.overrides);

      expect(_reviewCards(tester), 1);
      expect(
        find.text(
          '1 mission could not be loaded, so its submissions may be missing.',
        ),
        findsOneWidget,
      );

      // The server recovers; retrying brings the missing submission in.
      h.backend.reply('GET', _submissionsB, [_submissionOfB()]);
      await _tap(tester, find.byKey(const Key('approvals.partial.retry')));

      expect(_reviewCards(tester), 2);
      expect(find.byKey(const Key('approvals.partial')), findsNothing);
    });

    testWidgets('when every task fails the whole inbox shows an error', (
      tester,
    ) async {
      final h = await _parent(twoSubmittedTasks: true);
      for (final path in [_submissionsA, _submissionsB]) {
        h.backend.on(
          'GET',
          path,
          (_) => FakeReply.error(500, 'internal_error', 'boom'),
        );
      }
      await pumpScreen(tester, const ApprovalsScreen(), overrides: h.overrides);

      expect(find.text('Try again'), findsOneWidget);
      expect(find.byKey(const Key('approvals.partial')), findsNothing);
      expect(_reviewCards(tester), 0);
    });

    testWidgets('a removed task (404) is skipped without a warning', (
      tester,
    ) async {
      final h = await _parent(twoSubmittedTasks: true);
      h.backend.on(
        'GET',
        _submissionsB,
        (_) => FakeReply.error(404, 'http_error', 'Task not found'),
      );
      await pumpScreen(tester, const ApprovalsScreen(), overrides: h.overrides);

      expect(_reviewCards(tester), 1);
      expect(find.byKey(const Key('approvals.partial')), findsNothing);
    });

    testWidgets('a full page of notifications warns that older ones may be '
        'missing', (tester) async {
      final h = await _parent();
      h.backend.reply('GET', '/api/v1/notifications', [
        for (var i = 0; i < 100; i++)
          Fx.notification(
            type: i == 0 ? 'task_submitted' : 'badge_unlocked',
            id: '88888888-8888-4888-8888-${i.toString().padLeft(12, '0')}',
            taskId: i == 0 ? Fx.taskId : null,
          ),
      ]);
      await pumpScreen(tester, const ApprovalsScreen(), overrides: h.overrides);

      expect(
        find.text(
          'Showing the most recently submitted missions only. Older submissions '
          'may not appear.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an ended session while loading returns to role selection', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.on(
        'GET',
        _submissionsA,
        (_) => FakeReply.error(
          401,
          'http_error',
          'Invalid or expired access token',
        ),
      );
      await _pumpApp(tester, h);

      await _tap(tester, find.byKey(const Key('parent.approvals')));

      expect(find.text('Who is using Bal Kavach?'), findsOneWidget);
      expect(find.text(_expired), findsOneWidget);
      expect(await h.storage.read(), isNull);
    });
  });

  group('Approvals: notification bookkeeping', () {
    testWidgets('the Parent Hub count needs one request, not one per task', (
      tester,
    ) async {
      final h = await _parent(twoSubmittedTasks: true);
      await _pumpApp(tester, h);

      expect(find.text('2 waiting for review'), findsOneWidget);
      expect(
        h.backend.requestsTo('GET', '/api/v1/notifications'),
        hasLength(1),
      );
      expect(h.backend.requestsTo('GET', _submissionsA), isEmpty);
      expect(h.backend.requestsTo('GET', _submissionsB), isEmpty);
    });

    testWidgets('reviewing marks the submission notification read', (
      tester,
    ) async {
      final h = await _parent();
      const readPath = '/api/v1/notifications/$_notificationIdA/read';
      h.backend
        ..reply(
          'POST',
          '/api/v1/reviews/submissions/${Fx.submissionId}',
          Fx.submission(status: 'approved'),
        )
        ..reply('POST', readPath, {
          ...Fx.notification(type: 'task_submitted', id: _notificationIdA),
          'is_read': true,
        });
      await pumpScreen(tester, const ApprovalsScreen(), overrides: h.overrides);

      await _tap(tester, find.byKey(const Key('review.approve')));

      expect(h.backend.requestsTo('POST', readPath), hasLength(1));
    });

    testWidgets('a failed mark-read does not undo a successful review', (
      tester,
    ) async {
      final h = await _parent();
      h.backend
        ..reply(
          'POST',
          '/api/v1/reviews/submissions/${Fx.submissionId}',
          Fx.submission(status: 'approved'),
        )
        ..on(
          'POST',
          '/api/v1/notifications/$_notificationIdA/read',
          (_) => FakeReply.error(500, 'internal_error', 'boom'),
        );
      await pumpScreen(tester, const ApprovalsScreen(), overrides: h.overrides);

      await _tap(tester, find.byKey(const Key('review.approve')));

      expect(find.text('Approved! 10 stars sent to Aarav.'), findsOneWidget);
      expect(
        find.text('The server had a problem. Please try again soon.'),
        findsNothing,
      );
    });

    testWidgets('the hub count drops after a review', (tester) async {
      final h = await _parent();
      h.backend
        ..reply(
          'POST',
          '/api/v1/reviews/submissions/${Fx.submissionId}',
          Fx.submission(status: 'approved'),
        )
        ..reply(
          'POST',
          '/api/v1/notifications/$_notificationIdA/read',
          Fx.notification(type: 'task_submitted'),
        );
      await _pumpApp(tester, h);
      expect(find.text('1 waiting for review'), findsOneWidget);

      await _tap(tester, find.byKey(const Key('parent.approvals')));
      // From now on the server reports the notification as read.
      h.backend
        ..reply('GET', '/api/v1/notifications', [
          {
            ...Fx.notification(type: 'task_submitted', id: _notificationIdA),
            'is_read': true,
          },
        ])
        ..reply('GET', _submissionsA, [Fx.submission(status: 'approved')]);
      await _tap(tester, find.byKey(const Key('review.approve')));
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();

      expect(find.text('Nothing waiting for review'), findsOneWidget);
    });
  });

  group('Session end and consent', () {
    testWidgets('a rejected token explains why the user was signed out', (
      tester,
    ) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend.reply(
        'GET',
        '/api/v1/auth/me',
        Fx.childSession().user.toJson(),
      );
      await _pumpApp(tester, h);
      h.backend.on(
        'GET',
        '/api/v1/tasks',
        (_) => FakeReply.error(
          401,
          'http_error',
          'Invalid or expired access token',
        ),
      );

      await _tap(tester, find.text('Missions'));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('role.sessionEnded')), findsOneWidget);
      expect(find.text(_expired), findsOneWidget);
    });

    testWidgets('the notice goes away once the user chooses a role', (
      tester,
    ) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend.reply(
        'GET',
        '/api/v1/auth/me',
        Fx.childSession().user.toJson(),
      );
      await _pumpApp(tester, h);
      h.backend.on(
        'GET',
        '/api/v1/tasks',
        (_) => FakeReply.error(401, 'http_error', 'expired'),
      );
      await _tap(tester, find.text('Missions'));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(find.text(_expired), findsOneWidget);

      await _tap(tester, find.byKey(const Key('role.parent')));
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Who is using Bal Kavach?'), findsOneWidget);
      expect(find.text(_expired), findsNothing);
    });

    testWidgets('leaving child mode on purpose shows no expiry notice', (
      tester,
    ) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend.reply(
        'GET',
        '/api/v1/auth/me',
        Fx.childSession().user.toJson(),
      );
      await _pumpApp(tester, h);

      await _tap(tester, find.byKey(const Key('parentGate')));
      await _tap(tester, find.text('Leave'));

      expect(find.text('Who is using Bal Kavach?'), findsOneWidget);
      expect(find.byKey(const Key('role.sessionEnded')), findsNothing);
    });

    testWidgets('a parent with an outdated consent must accept it again', (
      tester,
    ) async {
      final h = await _parent(prefs: const {'app.language_code': 'en'});
      await _pumpApp(tester, h);

      expect(find.text('Parent Safety First'), findsOneWidget);
      expect(h.backend.requestsTo('GET', '/api/v1/families'), isEmpty);

      await _tap(tester, find.byKey(const Key('consent.checkbox')));
      await _tap(tester, find.byKey(const Key('consent.continue')));

      expect(h.prefs.acknowledgedConsentVersion, '2026-10-draft');
      expect(find.text('Hello, Priya Sharma'), findsOneWidget);
    });
  });

  group('Mission editing', () {
    const taskPath = '/api/v1/tasks/${Fx.taskId}';

    Future<Harness> withMission({String? dueAt, String? child}) async {
      final h = await _parent();
      h.backend
        ..reply('GET', '/api/v1/tasks', [
          Fx.task(dueAt: dueAt, assignedChildId: child),
        ])
        ..reply('PATCH', taskPath, Fx.task(title: 'Read two books'));
      return h;
    }

    Future<void> openEditor(WidgetTester tester, Harness h) async {
      await _pumpApp(tester, h);
      await _tap(tester, find.byKey(const Key('mission.tile.${Fx.taskId}')));
    }

    testWidgets('opens pre-filled and saves only what the API accepts', (
      tester,
    ) async {
      final h = await withMission(
        dueAt: '2026-11-03T18:29:00Z',
        child: Fx.childId,
      );
      await openEditor(tester, h);

      expect(find.text('Edit mission'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('mission.title')))
            .controller
            ?.text,
        'Read a Storybook',
      );
      // The saved category and assignee show once their lists have loaded.
      expect(find.text('Learn'), findsOneWidget);
      expect(find.text('Aarav'), findsWidgets);

      await tester.enterText(
        find.byKey(const Key('mission.title')),
        'Read two books',
      );
      await _tap(tester, find.byKey(const Key('mission.submit')));

      expect(h.backend.requestsTo('PATCH', taskPath).single.data, {
        'title': 'Read two books',
        'description': 'Read one story and tell us your favourite part.',
        'category_id': Fx.categoryId,
        'assigned_child_id': Fx.childId,
        'star_reward': 10,
        'xp_reward': 20,
        'due_at': '2026-11-03T18:29:00.000Z',
      });
      expect(find.text('Mission saved'), findsOneWidget);
      expect(find.text('Hello, Priya Sharma'), findsOneWidget);
      expect(
        h.backend.requestsTo('GET', '/api/v1/tasks').length,
        greaterThan(1),
        reason: 'the mission list is refreshed after the edit',
      );
    });

    testWidgets('clearing the due date sends an explicit null', (tester) async {
      final h = await withMission(dueAt: '2026-11-03T18:29:00Z');
      await openEditor(tester, h);

      await _tap(tester, find.byKey(const Key('mission.due.clear')));
      await _tap(tester, find.byKey(const Key('mission.submit')));

      expect(
        h.backend.requestsTo('PATCH', taskPath).single.data,
        containsPair('due_at', null),
      );
    });

    testWidgets('picking a due date sends an end-of-day UTC timestamp', (
      tester,
    ) async {
      final h = await withMission();
      await openEditor(tester, h);

      await _tap(tester, find.byKey(const Key('mission.due')));
      await _tap(tester, find.text('OK'));
      await _tap(tester, find.byKey(const Key('mission.submit')));

      final due =
          (h.backend.requestsTo('PATCH', taskPath).single.data
                  as Map<String, Object?>)['due_at']!
              as String;
      expect(due, endsWith('Z'));
      final local = DateTime.parse(due).toLocal();
      expect((local.hour, local.minute), (23, 59));
    });

    testWidgets('an empty title is rejected before any request', (
      tester,
    ) async {
      final h = await withMission();
      await openEditor(tester, h);

      await tester.enterText(find.byKey(const Key('mission.title')), '');
      await _tap(tester, find.byKey(const Key('mission.submit')));

      expect(h.backend.requestsTo('PATCH', taskPath), isEmpty);
      expect(find.text('Please enter a name.'), findsOneWidget);
    });

    testWidgets('a server error keeps the form open with the edits', (
      tester,
    ) async {
      final h = await withMission();
      h.backend.on(
        'PATCH',
        taskPath,
        (_) => FakeReply.error(500, 'internal_error', 'boom'),
      );
      await openEditor(tester, h);

      await tester.enterText(find.byKey(const Key('mission.title')), 'Edited');
      await _tap(tester, find.byKey(const Key('mission.submit')));

      expect(
        find.text('The server had a problem. Please try again soon.'),
        findsOneWidget,
      );
      expect(find.text('Edit mission'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('mission.title')))
            .controller
            ?.text,
        'Edited',
      );
    });

    testWidgets('removing asks first, then deactivates and refreshes', (
      tester,
    ) async {
      final h = await withMission();
      h.backend.on('DELETE', taskPath, (_) => const FakeReply(204));
      await openEditor(tester, h);

      await _tap(tester, find.byKey(const Key('mission.remove')));
      expect(find.text('Remove this mission?'), findsOneWidget);
      expect(h.backend.requestsTo('DELETE', taskPath), isEmpty);

      h.backend.reply('GET', '/api/v1/tasks', <Object?>[]);
      await _tap(tester, find.byKey(const Key('mission.remove.confirm')));

      expect(h.backend.requestsTo('DELETE', taskPath), hasLength(1));
      expect(find.text('Mission removed'), findsOneWidget);
      expect(
        find.text('No missions yet. Create the first one for your family.'),
        findsOneWidget,
      );
    });

    testWidgets('cancelling the removal changes nothing', (tester) async {
      final h = await withMission();
      await openEditor(tester, h);

      await _tap(tester, find.byKey(const Key('mission.remove')));
      await _tap(tester, find.text('Cancel'));

      expect(h.backend.requestsTo('DELETE', taskPath), isEmpty);
      expect(find.text('Edit mission'), findsOneWidget);
    });

    testWidgets('a failed removal reports the error and keeps the form', (
      tester,
    ) async {
      final h = await withMission();
      h.backend.on(
        'DELETE',
        taskPath,
        (_) => FakeReply.error(500, 'internal_error', 'boom'),
      );
      await openEditor(tester, h);

      await _tap(tester, find.byKey(const Key('mission.remove')));
      await _tap(tester, find.byKey(const Key('mission.remove.confirm')));

      expect(
        find.text('The server had a problem. Please try again soon.'),
        findsOneWidget,
      );
      expect(find.text('Edit mission'), findsOneWidget);
    });

    testWidgets('a mission that no longer exists shows a message', (
      tester,
    ) async {
      final h = await _parent();
      await pumpScreen(
        tester,
        const EditMissionScreen(taskId: 'gone'),
        overrides: h.overrides,
      );

      expect(find.text('This mission is no longer available.'), findsOneWidget);
      expect(find.byKey(const Key('mission.submit')), findsNothing);
    });

    testWidgets('creating a mission with a due date posts due_at', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.reply('POST', '/api/v1/tasks', Fx.task(), status: 201);
      await pumpScreen(
        tester,
        const CreateMissionScreen(),
        overrides: h.overrides,
      );

      await tester.enterText(find.byKey(const Key('mission.title')), 'Water');
      await _tap(tester, find.byKey(const Key('mission.due')));
      await _tap(tester, find.text('OK'));
      await _tap(tester, find.byKey(const Key('mission.submit')));

      final body =
          h.backend.requestsTo('POST', '/api/v1/tasks').single.data
              as Map<String, Object?>;
      expect(body['due_at'], isA<String>());
      expect(body['title'], 'Water');
      expect(body.containsKey('assigned_child_id'), isFalse);
    });

    testWidgets('long mission lists start collapsed and expand on demand', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.reply('GET', '/api/v1/tasks', [
        for (var i = 0; i < 25; i++)
          Fx.task(
            id: '55555555-5555-4555-8555-${i.toString().padLeft(12, '0')}',
            title: 'Mission $i',
          ),
      ]);
      await _pumpApp(tester, h);

      int tiles() => find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('mission.tile.'),
          )
          .evaluate()
          .length;

      await tester.ensureVisible(find.byKey(const Key('missions.showMore')));
      expect(tiles(), 20);
      await _tap(tester, find.byKey(const Key('missions.showMore')));
      expect(tiles(), 25);
      expect(find.byKey(const Key('missions.showMore')), findsNothing);
    });
  });

  group('Duplicate submissions', () {
    test('two quick submits create one submission', () async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
        ..reply(
          'POST',
          '/api/v1/tasks/${Fx.taskId}/submissions',
          Fx.submission(),
          status: 201,
        );
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      final subscription = container.listen(
        missionSubmitControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final controller = container.read(
        missionSubmitControllerProvider.notifier,
      );

      final first = controller.submit(Fx.taskId, note: 'done');
      final second = controller.submit(Fx.taskId, note: 'done');

      expect(await second, isNull);
      expect(await first, isNotNull);
      expect(
        h.backend.requestsTo('POST', '/api/v1/tasks/${Fx.taskId}/submissions'),
        hasLength(1),
      );
    });
  });

  group('Duplicate settings changes', () {
    test('a second change while saving is ignored', () async {
      final h = await Harness.create(
        session: Fx.parentSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..reply('GET', '/api/v1/settings/me', Fx.userSettings())
        ..reply('PATCH', '/api/v1/settings/me', Fx.userSettings(push: false));
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      await container.read(userSettingsProvider.future);
      final controller = container.read(userSettingsProvider.notifier);

      final first = controller.save(pushEnabled: false);
      final second = controller.save(emailNotificationsEnabled: false);
      await Future.wait([first, second]);

      expect(
        h.backend.requestsTo('PATCH', '/api/v1/settings/me'),
        hasLength(1),
      );
      expect(container.read(settingsSavingProvider), isFalse);
    });

    test('a rejected save restores the value and releases the lock', () async {
      final h = await Harness.create(
        session: Fx.parentSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..reply('GET', '/api/v1/settings/me', Fx.userSettings())
        ..on(
          'PATCH',
          '/api/v1/settings/me',
          (_) => FakeReply.error(500, 'internal_error', 'boom'),
        );
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      await container.read(userSettingsProvider.future);
      final controller = container.read(userSettingsProvider.notifier);

      await expectLater(controller.save(pushEnabled: false), throwsA(anything));

      expect(container.read(userSettingsProvider).value?.pushEnabled, isTrue);
      expect(container.read(settingsSavingProvider), isFalse);
    });
  });

  group('Long lists stay lazy', () {
    testWidgets('250 missions load in pages and build only what is visible', (
      tester,
    ) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
        ..on('GET', '/api/v1/tasks', (options) {
          final offset = int.parse(
            options.uri.queryParameters['offset'] ?? '0',
          );
          return FakeReply(200, [
            for (var i = offset; i < (offset + 100).clamp(0, 250); i++)
              Fx.task(
                id: '55555555-5555-4555-8555-${i.toString().padLeft(12, '0')}',
                title: 'Mission $i',
                categoryId: null,
              ),
          ]);
        });
      await pumpScreen(tester, const MissionsScreen(), overrides: h.overrides);

      expect(
        h.backend
            .requestsTo('GET', '/api/v1/tasks')
            .map((r) => r.uri.queryParameters['offset']),
        [null, '100', '200'],
      );
      expect(find.byType(MissionCard).evaluate().length, lessThan(40));

      await tester.scrollUntilVisible(
        find.text('Mission 249'),
        1500,
        maxScrolls: 100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Mission 249'), findsOneWidget);
    });

    testWidgets('60 pending submissions do not all build at once', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.reply('GET', _submissionsA, [
        for (var i = 0; i < 60; i++)
          Fx.submission(
            id: '77777777-7777-4777-8777-${i.toString().padLeft(12, '0')}',
          ),
      ]);
      await pumpScreen(tester, const ApprovalsScreen(), overrides: h.overrides);

      expect(find.text('60'), findsOneWidget, reason: 'tab count');
      expect(_reviewCards(tester), lessThan(20));
    });
  });
}
