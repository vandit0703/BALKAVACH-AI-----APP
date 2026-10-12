import 'package:balkavach_app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

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

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fresh install: language → consent → role selection', (
    tester,
  ) async {
    final h = await Harness.create();
    await _pumpApp(tester, h);

    expect(find.text('Select App Language'), findsOneWidget);

    // Picking Gujarati switches the UI immediately.
    await _pump(tester, find.text('ગુજરાતી'));
    expect(find.text('શરૂ કરો'), findsOneWidget);
    expect(h.prefs.languageCode, 'gu');

    await _pump(tester, find.text('English'));
    await _tap(tester, find.byKey(const Key('welcome.getStarted')));
    expect(find.text('Parent Safety First'), findsOneWidget);

    // Consent is required.
    await _tap(tester, find.byKey(const Key('consent.continue')));
    expect(
      find.text(
        'Please confirm you are the parent or legal guardian to continue.',
      ),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(const Key('consent.checkbox')));
    await _tap(tester, find.byKey(const Key('consent.continue')));

    expect(find.text('Who is using Bal Kavach?'), findsOneWidget);
    expect(h.prefs.acknowledgedConsentVersion, '2026-10-draft');
    expect(
      h.backend.requests,
      isEmpty,
      reason: 'onboarding is local until a family exists',
    );

    await _tap(tester, find.byKey(const Key('role.child')));
    expect(find.text('Ask a parent to help'), findsOneWidget);
  });

  testWidgets('parent home lists children and starts child mode', (
    tester,
  ) async {
    final h = await Harness.create(
      session: Fx.parentSession(),
      prefs: onboardedPrefs,
    );
    h.backend
      ..reply('POST', '/api/v1/settings/families/${Fx.familyId}/consents', {
        'id': 'c1',
        'family_id': Fx.familyId,
        'child_id': null,
        'parent_user_id': Fx.parentUserId,
        'consent_type': 'parent_guardian_terms',
        'document_version': '2026-10-draft',
        'accepted': true,
        'accepted_at': '2026-10-12T09:00:00Z',
        'revoked_at': null,
        'created_at': '2026-10-12T09:00:00Z',
      }, status: 201)
      ..reply(
        'POST',
        '/api/v1/auth/children/${Fx.childId}/session',
        Fx.childToken(),
      );
    await _pumpApp(tester, h);

    expect(find.text('Hello, Priya Sharma'), findsOneWidget);
    expect(find.text('Aarav'), findsOneWidget);
    expect(find.text('Read a Storybook'), findsOneWidget);
    expect(
      h.backend.requestsTo(
        'POST',
        '/api/v1/settings/families/${Fx.familyId}/consents',
      ),
      hasLength(1),
      reason: 'onboarding consent is recorded once the family is known',
    );

    // Switch the device to the child's session.
    h.backend.reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson());
    await _tap(tester, find.byKey(const Key('child.start.${Fx.childId}')));
    await _tap(tester, find.text('Start'));

    expect(find.text('Hello Aarav! 👋'), findsOneWidget);
    expect(find.text('240'), findsOneWidget);
    expect(find.text('5 Day'), findsOneWidget);
    expect((await h.storage.read())?.isChild, isTrue);
  });

  testWidgets('parent with no family is asked to create one', (tester) async {
    final h = await Harness.create(
      session: Fx.parentSession(),
      prefs: onboardedPrefs,
    );
    h.backend
      ..reply('GET', '/api/v1/families', <Object?>[])
      ..reply('POST', '/api/v1/families', Fx.family(), status: 201);
    await _pumpApp(tester, h);

    expect(find.text('Create your family'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('family.name')),
      'Sharma Family',
    );
    await _tap(tester, find.byKey(const Key('family.create')));

    expect(h.backend.requestsTo('POST', '/api/v1/families').single.data, {
      'family_name': 'Sharma Family',
    });
    expect(find.text('Your children'), findsOneWidget);
  });

  testWidgets('child completes a mission and sees the approval', (
    tester,
  ) async {
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
    await _pumpApp(tester, h);

    await _tap(tester, find.text('Missions'));
    expect(find.text('Child Missions'), findsOneWidget);
    expect(find.text('Play Outdoors or Yoga'), findsOneWidget);

    await _tap(tester, find.byKey(const Key('mission.${Fx.taskId}')));
    expect(
      find.text('Read one story and tell us your favourite part.'),
      findsOneWidget,
    );

    await _tap(tester, find.byKey(const Key('mission.start')));
    expect(
      find.text(
        'Photo proof isn\'t available yet. Tell your parent what you did instead.',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('submit.note')),
      'I read about a lion!',
    );
    await _tap(tester, find.byKey(const Key('submit.button')));

    expect(
      h.backend
          .requestsTo('POST', '/api/v1/tasks/${Fx.taskId}/submissions')
          .single
          .data,
      {'proof_type': 'note', 'proof_note': 'I read about a lion!'},
    );
    expect(find.text('Sent to your parent!'), findsOneWidget);

    // Parent approves; the child checks again.
    h.backend.reply('GET', '/api/v1/notifications', [
      Fx.notification(type: 'task_approved'),
    ]);
    await _tap(tester, find.byKey(const Key('waiting.check')));
    expect(find.text('Approved! 🎉'), findsOneWidget);
    expect(
      find.text('+10 stars added to your treasure chest.'),
      findsOneWidget,
    );

    await _tap(tester, find.text('Back to missions'));
    expect(find.text('Approved'), findsOneWidget);
  });

  testWidgets('submission failure keeps the child on the form with an error', (
    tester,
  ) async {
    final h = await Harness.create(
      session: Fx.childSession(),
      prefs: onboardedPrefs,
    );
    h.backend.reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson());
    // No POST handler → fake backend answers 404 task_not_found-like error.
    await _pumpApp(tester, h);

    await _tap(tester, find.text('Missions'));
    await _tap(tester, find.byKey(const Key('mission.${Fx.taskId}')));
    await _tap(tester, find.byKey(const Key('mission.start')));
    await _tap(tester, find.byKey(const Key('submit.button')));

    expect(find.byKey(const Key('submit.error')), findsOneWidget);
    expect(find.text('Sent to your parent!'), findsNothing);
  });

  testWidgets('Parent Gate signs the child out', (tester) async {
    final h = await Harness.create(
      session: Fx.childSession(),
      prefs: onboardedPrefs,
    );
    h.backend.reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson());
    await _pumpApp(tester, h);

    await _tap(tester, find.byKey(const Key('parentGate')));
    await _tap(tester, find.text('Leave'));
    expect(find.text('Who is using Bal Kavach?'), findsOneWidget);
    expect(await h.storage.read(), isNull);
  });

  testWidgets('a 401 mid-session returns to role selection', (tester) async {
    final h = await Harness.create(
      session: Fx.childSession(),
      prefs: onboardedPrefs,
    );
    h.backend.reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson());
    await _pumpApp(tester, h);

    h.backend.on(
      'GET',
      '/api/v1/tasks',
      (_) =>
          FakeReply.error(401, 'http_error', 'Invalid or expired access token'),
    );
    await _tap(tester, find.text('Missions'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('Who is using Bal Kavach?'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
