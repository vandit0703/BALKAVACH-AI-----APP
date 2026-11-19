// Phase 7: notification preferences, quiet hours and push deep links.
// Fake backend and a fake push source: this proves the app's logic, not
// Firebase delivery or a real phone.

import 'dart:async';
import 'dart:convert';

import 'package:balkavach_app/core/push/notification_open_source.dart';
import 'package:balkavach_app/core/routing/app_routes.dart';
import 'package:balkavach_app/core/routing/route_guard.dart';
import 'package:balkavach_app/features/authentication/presentation/session_controller.dart';
import 'package:balkavach_app/features/notifications/domain/notification_category.dart';
import 'package:balkavach_app/features/notifications/domain/notification_preferences.dart';
import 'package:balkavach_app/features/notifications/presentation/notification_open_coordinator.dart';
import 'package:balkavach_app/features/notifications/presentation/notification_preferences_controller.dart';
import 'package:balkavach_app/features/notifications/presentation/notification_settings_screen.dart';
import 'package:balkavach_app/features/onboarding/presentation/onboarding_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _prefsPath =
    '/api/v1/settings/families/${Fx.familyId}/notification-preferences';
const _notificationId = '99999999-9999-4999-8999-999999999999';

Map<String, Object?> _prefs({
  Map<String, bool>? categories,
  bool quiet = false,
  String start = '21:00',
  String end = '07:00',
  String zone = 'Asia/Kolkata',
  bool zoneDefault = false,
}) => {
  'family_id': Fx.familyId,
  'categories': {
    'new_missions': true,
    'mission_reviews': true,
    'rewards': true,
    'streaks': true,
    'video_allowance': true,
    'video_time_up': true,
    'safety': true,
    ...?categories,
  },
  'locked_categories': ['safety'],
  'quiet_hours': {'enabled': quiet, 'start': start, 'end': end},
  'quiet_hours_exempt_categories': ['safety'],
  'timezone': zone,
  'timezone_is_default': zoneDefault,
  'updated_at': null,
};

Map<String, dynamic> _body(RequestOptions r) => r.data is String
    ? jsonDecode(r.data as String) as Map<String, dynamic>
    : Map<String, dynamic>.from(r.data as Map);

class _FakeOpenSource implements NotificationOpenSource {
  _FakeOpenSource({this.launch});

  final PushOpen? launch;
  final opened = StreamController<PushOpen>.broadcast();

  @override
  Future<PushOpen?> initial() async => launch;

  @override
  Stream<PushOpen> get onOpened => opened.stream;
}

void main() {
  group('domain', () {
    test('quiet hours know when they run overnight', () {
      expect(QuietHours.defaults.overnight, isTrue);
      expect(
        const QuietHours(
          enabled: true,
          start: TimeOfDay(hour: 13, minute: 0),
          end: TimeOfDay(hour: 15, minute: 0),
        ).overnight,
        isFalse,
      );
      expect(parseHhMm('22:05'), const TimeOfDay(hour: 22, minute: 5));
      expect(parseHhMm('24:00'), isNull);
      expect(parseHhMm('7:00'), isNull);
      expect(formatHhMm(const TimeOfDay(hour: 7, minute: 5)), '07:05');
    });

    test('safety is always on even if the server sent false', () {
      final p = NotificationPreferences.fromJson(
        _prefs(categories: {'safety': false, 'streaks': false}),
      );
      expect(p.isOn(PreferenceCategory.safety), isTrue);
      expect(p.isLocked(PreferenceCategory.safety), isTrue);
      expect(p.isOn(PreferenceCategory.streaks), isFalse);
    });

    test('a push payload is validated before it is trusted', () {
      expect(PushOpen.fromData({}), isNull);
      expect(
        PushOpen.fromData({'notification_id': '../../parent', 'type': 'x'}),
        isNull,
      );
      final ok = PushOpen.fromData({
        'notification_id': _notificationId,
        'type': 'Task Approved; drop',
      })!;
      expect(ok.notificationId, _notificationId);
      expect(ok.type, isNull);
    });
  });

  group('locationFor (deep-link targets)', () {
    test('a mission review opens that mission for the child', () {
      expect(
        locationFor(
          type: 'task_approved',
          audience: NotificationAudience.child,
          relatedTaskId: Fx.taskId,
        ),
        AppRoutes.childMission(Fx.taskId),
      );
      expect(
        locationFor(
          type: 'task_resubmission_requested',
          audience: NotificationAudience.child,
          relatedTaskId: Fx.taskId,
        ),
        AppRoutes.childMission(Fx.taskId),
      );
    });

    test('a forged or missing id falls back to the list, never a path', () {
      for (final id in [null, '', '../../parent/settings', 'abc']) {
        expect(
          locationFor(
            type: 'task_approved',
            audience: NotificationAudience.child,
            relatedTaskId: id,
          ),
          AppRoutes.childMissions,
          reason: '$id',
        );
      }
    });

    test('new missions, streaks, video time and the security alert', () {
      expect(
        locationFor(
          type: 'task_assigned',
          audience: NotificationAudience.child,
          relatedTaskId: Fx.taskId,
        ),
        AppRoutes.childMissions,
      );
      expect(
        locationFor(
          type: 'streak_at_risk',
          audience: NotificationAudience.child,
          childId: Fx.childId,
        ),
        '${AppRoutes.streakScreen}?childId=${Fx.childId}',
      );
      expect(
        locationFor(
          type: 'video_time_exhausted',
          audience: NotificationAudience.child,
        ),
        AppRoutes.childWatch,
      );
      expect(
        locationFor(
          type: 'parent_mode_locked',
          audience: NotificationAudience.parent,
        ),
        AppRoutes.parentSettings,
      );
    });

    test('roles never cross, whatever the type says', () {
      for (final type in [
        'parent_mode_locked',
        'task_submitted',
        'reward_requested',
        'bad type!',
      ]) {
        expect(
          locationFor(type: type, audience: NotificationAudience.child),
          startsWith('/child'),
          reason: type,
        );
      }
      for (final type in ['task_approved', 'streak_at_risk', 'bad type!']) {
        expect(
          locationFor(
            type: type,
            audience: NotificationAudience.parent,
            relatedTaskId: Fx.taskId,
            childId: Fx.childId,
          ),
          startsWith('/parent'),
          reason: type,
        );
      }
    });

    test('the router keeps a child out of parent settings', () {
      final redirect = resolveRedirect(
        location: AppRoutes.parentNotificationSettings,
        sessionResolved: true,
        onboarding: const OnboardingState(
          languageCode: 'en',
          consentAcknowledged: true,
        ),
        session: Fx.childSession(),
      );
      expect(redirect, AppRoutes.childHome);
    });
  });

  group('NotificationSettingsScreen', () {
    Future<Harness> pump(
      WidgetTester tester, {
      Map<String, Object?>? prefs,
      FakeReply Function(RequestOptions)? patch,
      Locale locale = const Locale('en'),
      bool child = false,
      Size size = const Size(393, 852),
    }) async {
      final h = await Harness.create(
        session: child ? Fx.childSession() : Fx.parentSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..reply('GET', _prefsPath, prefs ?? _prefs())
        ..on(
          'PATCH',
          _prefsPath,
          patch ??
              (r) {
                final body = _body(r);
                final base = _prefs();
                return FakeReply(200, {
                  ...base,
                  'categories': {
                    ...base['categories']! as Map,
                    ...?body['categories'] as Map?,
                  },
                  if (body['quiet_hours'] != null)
                    'quiet_hours': body['quiet_hours'],
                });
              },
        );
      await pumpScreen(
        tester,
        const NotificationSettingsScreen(),
        overrides: h.overrides,
        locale: locale,
        size: size,
      );
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('loads and shows every group with safety locked on', (
      tester,
    ) async {
      await pump(tester);
      for (final c in PreferenceCategory.values) {
        await tester.scrollUntilVisible(
          find.byKey(Key('notifPrefs.category.${c.key}')),
          200,
        );
        final tile = tester.widget<SwitchListTile>(
          find.byKey(Key('notifPrefs.category.${c.key}')),
        );
        expect(tile.value, isTrue, reason: c.key);
        expect(
          tile.onChanged == null,
          c == PreferenceCategory.safety,
          reason: c.key,
        );
      }
      expect(find.textContaining('Always on'), findsOneWidget);
      // No Firebase in tests: the screen says push cannot arrive here.
      expect(find.byKey(const Key('notifPrefs.pushNotice')), findsOneWidget);
    });

    testWidgets('a toggle shows at once and saves only that category', (
      tester,
    ) async {
      final h = await pump(tester);
      final key = find.byKey(const Key('notifPrefs.category.streaks'));
      await tester.scrollUntilVisible(key, 200);
      await tester.tap(key);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(key).value, isFalse);
      await tester.pumpAndSettle();
      final sent = h.backend.requestsTo('PATCH', _prefsPath);
      expect(sent, hasLength(1));
      expect(_body(sent.single), {
        'categories': {'streaks': false},
      });
      expect(tester.widget<SwitchListTile>(key).value, isFalse);
    });

    testWidgets('a rejected change is rolled back and explained', (
      tester,
    ) async {
      await pump(
        tester,
        patch: (_) => FakeReply.error(500, 'internal_error', 'boom'),
      );
      final key = find.byKey(const Key('notifPrefs.category.rewards'));
      await tester.scrollUntilVisible(key, 200);
      await tester.tap(key);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(key).value, isTrue);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('turning quiet hours on saves the overnight default', (
      tester,
    ) async {
      final h = await pump(tester);
      final toggle = find.byKey(const Key('notifPrefs.quiet.enabled'));
      await tester.scrollUntilVisible(toggle, 200);
      expect(find.byKey(const Key('notifPrefs.quiet.overnight')), findsNothing);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(_body(h.backend.requestsTo('PATCH', _prefsPath).single), {
        'quiet_hours': {'enabled': true, 'start': '21:00', 'end': '07:00'},
      });
      await tester.scrollUntilVisible(
        find.byKey(const Key('notifPrefs.quiet.overnight')),
        200,
      );
      expect(
        find.byKey(const Key('notifPrefs.quiet.overnight')),
        findsOneWidget,
      );
      expect(find.textContaining('Asia/Kolkata'), findsOneWidget);
    });

    testWidgets('quiet hours explain a missing family time zone', (
      tester,
    ) async {
      await pump(tester, prefs: _prefs(zone: 'UTC', zoneDefault: true));
      final notice = find.byKey(const Key('notifPrefs.quiet.zoneDefault'));
      await tester.scrollUntilVisible(notice, 200);
      expect(notice, findsOneWidget);
    });

    testWidgets('a load failure offers a retry', (tester) async {
      final h = await Harness.create(
        session: Fx.parentSession(),
        prefs: onboardedPrefs,
      );
      var calls = 0;
      h.backend.on('GET', _prefsPath, (_) {
        calls++;
        return calls == 1
            ? FakeReply.error(500, 'internal_error', 'boom')
            : FakeReply(200, _prefs());
      });
      await pumpScreen(
        tester,
        const NotificationSettingsScreen(),
        overrides: h.overrides,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('notifPrefs.category.new_missions')),
        findsNothing,
      );
      await tester.tap(find.byType(FilledButton).first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('notifPrefs.category.new_missions')),
        findsOneWidget,
      );
    });

    testWidgets('a child account sees no parent controls', (tester) async {
      final h = await pump(tester, child: true);
      expect(
        find.byKey(const Key('notifPrefs.category.new_missions')),
        findsNothing,
      );
      expect(h.backend.requestsTo('GET', _prefsPath), isEmpty);
    });

    for (final (locale, title) in [
      (const Locale('hi'), 'सूचना प्राथमिकताएँ'),
      (const Locale('gu'), 'સૂચના પસંદગીઓ'),
    ]) {
      testWidgets('is translated (${locale.languageCode}) and fits 320 px', (
        tester,
      ) async {
        await pump(tester, locale: locale, size: const Size(320, 640));
        expect(find.text(title), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('NotificationPreferencesController', () {
    test('saves run one at a time and the newest answer wins', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend
        ..reply('GET', _prefsPath, _prefs())
        ..on('PATCH', _prefsPath, (r) {
          final body = _body(r);
          return FakeReply(
            200,
            _prefs(
              categories: {
                'streaks': false,
                if ((body['categories'] as Map?)?['rewards'] == false)
                  'rewards': false,
              },
            ),
          );
        });
      final container = h.container();
      final provider = notificationPreferencesProvider(Fx.familyId);
      await container.read(sessionControllerProvider.future);
      await container.read(provider.future);
      final notifier = container.read(provider.notifier);
      final a = notifier.setCategory(PreferenceCategory.streaks, false);
      final b = notifier.setCategory(PreferenceCategory.rewards, false);
      // Both visible before either answer arrives.
      final now = container.read(provider).value!;
      expect(now.isOn(PreferenceCategory.streaks), isFalse);
      expect(now.isOn(PreferenceCategory.rewards), isFalse);
      await Future.wait([a, b]);
      expect(h.backend.requestsTo('PATCH', _prefsPath), hasLength(2));
      final saved = container.read(provider).value!;
      expect(saved.isOn(PreferenceCategory.rewards), isFalse);
      expect(saved.isOn(PreferenceCategory.streaks), isFalse);
    });

    test('a locked category is never sent', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.reply('GET', _prefsPath, _prefs());
      final container = h.container();
      final provider = notificationPreferencesProvider(Fx.familyId);
      await container.read(sessionControllerProvider.future);
      await container.read(provider.future);
      await container
          .read(provider.notifier)
          .setCategory(PreferenceCategory.safety, false);
      expect(h.backend.requestsTo('PATCH', _prefsPath), isEmpty);
    });
  });

  group('NotificationOpenCoordinator (push deep links)', () {
    Future<(Harness, ProviderContainer, List<String>, _FakeOpenSource)> setUp({
      bool child = true,
      bool signedIn = true,
      PushOpen? launch,
      FakeReply Function(RequestOptions)? lookup,
      DateTime Function()? clock,
    }) async {
      final h = await Harness.create(
        session: signedIn
            ? (child ? Fx.childSession() : Fx.parentSession())
            : null,
        prefs: onboardedPrefs,
      );
      h.backend
        ..on(
          'GET',
          '/api/v1/notifications/$_notificationId',
          lookup ??
              (_) => FakeReply(
                200,
                Fx.notification(type: 'task_approved', id: _notificationId),
              ),
        )
        ..reply('POST', '/api/v1/notifications/$_notificationId/read', {});
      final source = _FakeOpenSource(launch: launch);
      final visited = <String>[];
      final container = ProviderContainer(
        overrides: [
          ...h.overrides,
          notificationOpenSourceProvider.overrideWithValue(source),
          notificationNavigatorProvider.overrideWithValue(visited.add),
          if (clock != null) pushClockProvider.overrideWithValue(clock),
        ],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);
      addTearDown(source.opened.close);
      container.listen(notificationOpenCoordinatorProvider, (_, _) {});
      return (h, container, visited, source);
    }

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    const push = PushOpen(
      notificationId: _notificationId,
      type: 'task_approved',
    );

    test('cold start: waits for the session, then opens the mission', () async {
      final (_, container, visited, _) = await setUp(launch: push);
      // Nothing happens while the stored session is still being restored.
      expect(visited, isEmpty);
      await container.read(sessionControllerProvider.future);
      await settle();
      expect(visited, [AppRoutes.childMission(Fx.taskId)]);
    });

    test('app running: a tapped push navigates and is marked read', () async {
      final (h, container, visited, source) = await setUp();
      await container.read(sessionControllerProvider.future);
      source.opened.add(push);
      await settle();
      expect(visited, [AppRoutes.childMission(Fx.taskId)]);
      expect(
        h.backend.requestsTo(
          'POST',
          '/api/v1/notifications/$_notificationId/read',
        ),
        hasLength(1),
      );
    });

    test('the same push opened twice navigates once', () async {
      final (_, container, visited, source) = await setUp(launch: push);
      await container.read(sessionControllerProvider.future);
      source.opened
        ..add(push)
        ..add(push);
      await settle();
      source.opened.add(push);
      await settle();
      expect(visited, hasLength(1));
    });

    test('a deleted or foreign notification lands on home', () async {
      final (_, container, visited, source) = await setUp(
        lookup: (_) =>
            FakeReply.error(404, 'not_found', 'Notification not found'),
      );
      await container.read(sessionControllerProvider.future);
      source.opened.add(push);
      await settle();
      expect(visited, [AppRoutes.childHome]);
    });

    test('offline: the push type still picks the category screen', () async {
      final (_, container, visited, source) = await setUp(
        lookup: (_) => const FakeReply.fail(DioExceptionType.connectionError),
      );
      await container.read(sessionControllerProvider.future);
      source.opened.add(
        const PushOpen(
          notificationId: _notificationId,
          type: 'video_time_exhausted',
        ),
      );
      await settle();
      expect(visited, [AppRoutes.childWatch]);
    });

    test('a parent push opens the parent screen', () async {
      final (_, container, visited, source) = await setUp(
        child: false,
        lookup: (_) => FakeReply(
          200,
          Fx.notification(type: 'parent_mode_locked', id: _notificationId),
        ),
      );
      await container.read(sessionControllerProvider.future);
      source.opened.add(push);
      await settle();
      expect(visited, [AppRoutes.parentSettings]);
    });

    test(
      'signed out (expired session): waits, then opens after sign-in',
      () async {
        final (h, container, visited, source) = await setUp(signedIn: false);
        await container.read(sessionControllerProvider.future);
        source.opened.add(push);
        await settle();
        expect(visited, isEmpty);
        expect(
          h.backend.requestsTo('GET', '/api/v1/notifications/$_notificationId'),
          isEmpty,
        );
        h.backend
          ..reply('POST', '/api/v1/auth/login', Fx.token())
          ..reply('GET', '/api/v1/auth/me', Fx.parentSession().user.toJson())
          ..on(
            'GET',
            '/api/v1/notifications/$_notificationId',
            (_) => FakeReply.error(404, 'not_found', 'Notification not found'),
          );
        await container
            .read(sessionControllerProvider.notifier)
            .signIn(email: 'parent@example.com', password: 'secret-123');
        await settle();
        // The push belonged to the child; the parent who signed in gets home.
        expect(visited, [AppRoutes.parentHome]);
      },
    );

    test('a push left pending too long is dropped', () async {
      var now = DateTime(2026, 11, 19, 8);
      final (h, container, visited, source) = await setUp(
        signedIn: false,
        clock: () => now,
      );
      await container.read(sessionControllerProvider.future);
      source.opened.add(push);
      await settle();
      now = now.add(pendingPushLifetime + const Duration(minutes: 1));
      h.backend
        ..reply('POST', '/api/v1/auth/login', Fx.childToken())
        ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson());
      await container
          .read(sessionControllerProvider.notifier)
          .signIn(identifier: 'aarav', password: 'secret-123');
      await settle();
      expect(visited, isEmpty);
    });
  });
}
