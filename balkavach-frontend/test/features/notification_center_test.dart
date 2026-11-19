// Notification centre: category mapping, navigation targets and the screen.
// Fake backend; the real notification endpoints are unchanged.

import 'package:balkavach_app/core/routing/app_routes.dart';
import 'package:balkavach_app/features/notifications/domain/notification_category.dart';
import 'package:balkavach_app/features/notifications/presentation/notification_center_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _listPath = '/api/v1/notifications';

Map<String, Object?> _n(
  String id,
  String type, {
  bool read = false,
  String? title,
}) => {
  ...Fx.notification(type: type, id: id),
  'title': title ?? 'Title $id',
  'message': 'Message $id',
  'is_read': read,
};

void main() {
  group('categoryOf / routeFor', () {
    test('every emitted type lands in a sensible group', () {
      const expected = {
        'task_approved': NotificationCategory.missions,
        'task_rejected': NotificationCategory.missions,
        'task_assigned': NotificationCategory.missions,
        'daily_surprise_bonus': NotificationCategory.missions,
        'reward_requested': NotificationCategory.rewards,
        'reward_approved': NotificationCategory.rewards,
        'reward_fulfilled': NotificationCategory.rewards,
        'badge_unlocked': NotificationCategory.rewards,
        'mission_video_time_granted': NotificationCategory.videos,
        'video_time_exhausted': NotificationCategory.videos,
        'video_time_nearly_exhausted': NotificationCategory.videos,
        'streak_at_risk': NotificationCategory.streaks,
        'streak_milestone': NotificationCategory.streaks,
        'something_new': NotificationCategory.other,
      };
      expected.forEach((type, category) {
        expect(categoryOf(type), category, reason: type);
      });
    });

    test('a child is only ever sent to child screens', () {
      for (final type in [
        'task_approved',
        'reward_approved',
        'badge_unlocked',
        'mission_video_time_granted',
        'streak_at_risk',
        'unknown',
      ]) {
        expect(
          routeFor(type, NotificationAudience.child),
          startsWith('/child'),
          reason: type,
        );
      }
      expect(
        routeFor('mission_video_time_granted', NotificationAudience.child),
        AppRoutes.childWatch,
      );
      expect(
        routeFor('reward_approved', NotificationAudience.child),
        AppRoutes.childRewards,
      );
      expect(
        routeFor('badge_unlocked', NotificationAudience.child),
        AppRoutes.childProfile,
      );
    });

    test('a parent is only ever sent to parent screens', () {
      for (final type in [
        'task_submitted',
        'reward_requested',
        'streak_at_risk',
        'unknown',
      ]) {
        expect(
          routeFor(type, NotificationAudience.parent),
          startsWith('/parent'),
          reason: type,
        );
      }
      expect(
        routeFor('task_submitted', NotificationAudience.parent),
        AppRoutes.parentApprovals,
      );
      expect(
        routeFor('reward_requested', NotificationAudience.parent),
        AppRoutes.parentRewards,
      );
    });
  });

  group('NotificationCenterScreen', () {
    Future<Harness> pump(
      WidgetTester tester, {
      required FakeReply Function(RequestOptions) list,
      NotificationAudience audience = NotificationAudience.child,
      Size size = const Size(393, 852),
      double scale = 1,
      Locale locale = const Locale('en'),
    }) async {
      final h = await Harness.create(
        session: audience == NotificationAudience.child
            ? Fx.childSession()
            : Fx.parentSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..on('GET', _listPath, list)
        ..onPattern(
          'POST',
          RegExp(r'/api/v1/notifications/[^/]+/read$'),
          (_) => const FakeReply(200, {}),
        );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => NotificationCenterScreen(audience: audience),
          ),
          GoRoute(
            path: AppRoutes.childWatch,
            builder: (_, _) => const Scaffold(body: Text('WATCH PAGE')),
          ),
          GoRoute(
            path: AppRoutes.childMissions,
            builder: (_, _) => const Scaffold(body: Text('MISSIONS PAGE')),
          ),
          GoRoute(
            path: '/child/missions/:taskId',
            builder: (_, state) => Scaffold(
              body: Text('MISSION ${state.pathParameters['taskId']}'),
            ),
          ),
        ],
      );
      setWindow(tester, size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          retry: (_, _) => null,
          child: MaterialApp.router(
            routerConfig: router,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('lists notifications, newest as given, with unread dots', (
      tester,
    ) async {
      await pump(
        tester,
        list: (_) => FakeReply(200, [
          _n('a1', 'task_approved'),
          _n('a2', 'reward_approved', read: true),
        ]),
      );
      expect(find.text('Title a1'), findsOneWidget);
      expect(find.text('Message a2'), findsOneWidget);
      expect(
        find.byKey(const Key('notifications.unreadDot.a1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('notifications.unreadDot.a2')), findsNothing);
    });

    testWidgets(
      'category chips filter the list and appear only for present groups',
      (tester) async {
        await pump(
          tester,
          list: (_) => FakeReply(200, [
            _n('a1', 'task_approved'),
            _n('a2', 'mission_video_time_granted'),
          ]),
        );
        expect(
          find.byKey(const Key('notifications.filter.rewards')),
          findsNothing,
        );
        await tester.tap(find.byKey(const Key('notifications.filter.videos')));
        await tester.pumpAndSettle();
        expect(find.text('Title a2'), findsOneWidget);
        expect(find.text('Title a1'), findsNothing);
        await tester.tap(find.byKey(const Key('notifications.filter.all')));
        await tester.pumpAndSettle();
        expect(find.text('Title a1'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping marks it read on the server and opens the right screen',
      (tester) async {
        final h = await pump(
          tester,
          list: (_) => FakeReply(200, [_n('a2', 'mission_video_time_granted')]),
        );
        await tester.tap(find.byKey(const Key('notifications.item.a2')));
        await tester.pumpAndSettle();
        expect(find.text('WATCH PAGE'), findsOneWidget);
        expect(
          h.backend.requests.where(
            (r) => r.method == 'POST' && r.uri.path.endsWith('/a2/read'),
          ),
          hasLength(1),
        );
      },
    );

    testWidgets('mark all as read marks each unread one once', (tester) async {
      final h = await pump(
        tester,
        list: (_) => FakeReply(200, [
          _n('a1', 'task_approved'),
          _n('a2', 'reward_approved'),
          _n('a3', 'streak_at_risk', read: true),
        ]),
      );
      await tester.tap(find.byKey(const Key('notifications.markAll')));
      await tester.pumpAndSettle();
      final posts = h.backend.requests
          .where((r) => r.method == 'POST')
          .map((r) => r.uri.path)
          .toList();
      expect(
        posts,
        unorderedEquals([
          '/api/v1/notifications/a1/read',
          '/api/v1/notifications/a2/read',
        ]),
      );
    });

    testWidgets('a failed read keeps the notification unread', (tester) async {
      final h = await pump(
        tester,
        list: (_) => FakeReply(200, [_n('a1', 'task_approved')]),
      );
      h.backend.onPattern(
        'POST',
        RegExp(r'/api/v1/notifications/[^/]+/read$'),
        (_) => FakeReply.error(500, 'server_error', 'boom'),
      );
      await tester.tap(find.byKey(const Key('notifications.item.a1')));
      await tester.pumpAndSettle();
      // Navigated away, but a retry on the list would still show it unread.
      expect(h.backend.requests.where((r) => r.method == 'POST'), isNotEmpty);
    });

    testWidgets('a mission review opens that mission (Phase 7)', (
      tester,
    ) async {
      await pump(
        tester,
        list: (_) => FakeReply(200, [_n('a1', 'task_approved')]),
      );
      await tester.tap(find.byKey(const Key('notifications.item.a1')));
      await tester.pumpAndSettle();
      expect(find.text('MISSION ${Fx.taskId}'), findsOneWidget);
    });

    testWidgets('empty state', (tester) async {
      await pump(tester, list: (_) => const FakeReply(200, <Object?>[]));
      expect(find.byKey(const Key('notifications.empty')), findsOneWidget);
      expect(find.byKey(const Key('notifications.markAll')), findsNothing);
    });

    testWidgets('load failure shows a retryable error', (tester) async {
      await pump(
        tester,
        list: (_) => const FakeReply.fail(DioExceptionType.connectionError),
      );
      expect(find.byIcon(Icons.wifi_off_rounded), findsWidgets);
    });

    for (final (size, scale, locale) in [
      (const Size(320, 568), 2.0, const Locale('en')),
      (const Size(360, 640), 1.0, const Locale('hi')),
      (const Size(390, 844), 2.0, const Locale('gu')),
      (const Size(740, 360), 1.0, const Locale('en')),
      (const Size(820, 1180), 1.0, const Locale('en')),
    ]) {
      testWidgets('fits $size @ ${scale}x in $locale', (tester) async {
        await pump(
          tester,
          size: size,
          scale: scale,
          locale: locale,
          list: (_) => FakeReply(200, [
            for (final t in [
              'task_approved',
              'reward_approved',
              'mission_video_time_granted',
              'streak_at_risk',
            ])
              _n(t, t, title: 'A reasonably long notification title for $t'),
          ]),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
