// Phase 3 completion: the low-time warning, the lock page (Panda, how to earn
// more, live refresh after a parent's approval, errors), across sizes,
// languages and reduced motion. The server stays the only authority.

import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/features/learning/data/playback_guard.dart';
import 'package:balkavach_app/features/learning/presentation/video_lock_screen.dart';
import 'package:balkavach_app/features/learning/presentation/widgets/low_time_notice.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _allowancePath = '/api/v1/video-access/allowance';

Map<String, Object?> allowance({required int remaining, int earned = 1800}) => {
  'child_id': Fx.childId,
  'local_date': '2026-11-19',
  'timezone': 'Asia/Kolkata',
  'total_earned_today_seconds': earned,
  'consumed_today_seconds': earned - remaining,
  'remaining_seconds': remaining,
  'daily_cap_seconds': 4500,
  'is_exhausted': remaining <= 0,
  'active_entitlements_count': remaining > 0 ? 1 : 0,
};

Future<Map<String, dynamic>?> answer(int remaining) async => {
  'remaining_allowance_seconds': remaining,
  'is_exhausted': remaining <= 0,
};

void main() {
  group('low-time warning (PlaybackGuard)', () {
    test('fires once when the server figure crosses two minutes', () async {
      final warned = <int>[];
      final guard = PlaybackGuard(onLowTime: warned.add);
      for (final r in [600, 300, 130]) {
        expect((await guard.report(() => answer(r))).lowTime, isFalse);
      }
      expect((await guard.report(() => answer(110))).lowTime, isTrue);
      // More reports from the same or another video, or after a resume.
      for (final r in [100, 70, 40, 10]) {
        expect((await guard.report(() => answer(r))).lowTime, isFalse);
      }
      expect(warned, [110]);
    });

    test('a network failure never triggers or consumes the warning', () async {
      final warned = <int>[];
      final guard = PlaybackGuard(onLowTime: warned.add);
      await guard.report(() async => throw const NetworkException());
      expect(warned, isEmpty);
      await guard.report(() => answer(90));
      expect(warned, [90]);
    });

    test('new time (a parent approval or a new day) re-arms it', () async {
      final warned = <int>[];
      final guard = PlaybackGuard(onLowTime: warned.add);
      await guard.report(() => answer(100));
      final done = await guard.report(() => answer(0));
      expect(done.verdict, PlaybackVerdict.exhausted);
      // A small partial grant near the cap still gets its own warning.
      await guard.report(() => answer(60));
      // A full grant goes above the threshold and comes back down later.
      await guard.report(() => answer(900));
      await guard.report(() => answer(115));
      expect(warned, [100, 60, 115]);
    });

    test('a 403 refusal also re-arms (the server said time is up)', () async {
      final warned = <int>[];
      final guard = PlaybackGuard(onLowTime: warned.add);
      await guard.report(() => answer(100));
      final refused = await guard.report(
        () async => throw const ForbiddenException(
          message: 'x',
          code: 'video_time_exhausted',
        ),
      );
      expect(refused.verdict, PlaybackVerdict.exhausted);
      await guard.report(() => answer(80));
      expect(warned, [100, 80]);
    });

    test('notice minutes round up and stay small', () {
      expect(const LowTimeNotice(remainingSeconds: 95, serial: 1).minutes, 2);
      expect(const LowTimeNotice(remainingSeconds: 40, serial: 1).minutes, 1);
      expect(const LowTimeNotice(remainingSeconds: 120, serial: 1).minutes, 2);
    });
  });

  group('low-time notice in the app shell', () {
    for (final (code, needle) in [
      ('en', 'About 2 minutes'),
      ('hi', 'लगभग 2 मिनट'),
      ('gu', 'લગભગ 2 મિનિટ'),
    ]) {
      testWidgets('shows Panda\'s gentle notice once per crossing ($code)', (
        tester,
      ) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              scaffoldMessengerKey: rootMessengerKey,
              locale: Locale(code),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              builder: (context, child) => LowTimeNoticeListener(child: child!),
              home: const Scaffold(body: SizedBox()),
            ),
          ),
        );
        final guard = container.read(playbackGuardProvider);
        await guard.report(() => answer(95));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byKey(const Key('video.lowTime.notice')), findsOneWidget);
        expect(find.textContaining(needle), findsOneWidget);

        // Hidden after a while; the next report below the line does not repeat.
        await tester.pump(const Duration(seconds: 8));
        await tester.pumpAndSettle();
        await guard.report(() => answer(60));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byKey(const Key('video.lowTime.notice')), findsNothing);
      });
    }
  });

  group('lock page', () {
    late Harness h;
    late int remaining;
    var failing = false;

    Future<void> open(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      Size size = const Size(393, 852),
      double scale = 1,
      int start = 0,
    }) async {
      remaining = start;
      failing = false;
      h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend.on(
        'GET',
        _allowancePath,
        (_) => failing
            ? const FakeReply.fail(DioExceptionType.connectionError)
            : FakeReply(200, allowance(remaining: remaining)),
      );
      await pumpScreen(
        tester,
        const VideoLockScreen(),
        overrides: h.overrides,
        locale: locale,
        size: size,
        textScale: scale,
      );
    }

    testWidgets('explains kindly and shows the way back via a grown-up', (
      tester,
    ) async {
      await open(tester);
      expect(find.byKey(const Key('video.lock.title')), findsOneWidget);
      expect(find.byKey(const Key('panda.bubble')), findsOneWidget);
      expect(find.byKey(const Key('video.lock.panda')), findsOneWidget);
      expect(find.byKey(const Key('video.lock.steps')), findsOneWidget);
      expect(find.textContaining('approves'), findsOneWidget);
      expect(find.byKey(const Key('video.lock.summary')), findsOneWidget);
      expect(find.byKey(const Key('video.lock.toMissions')), findsOneWidget);
      expect(find.byKey(const Key('video.lock.watchNow')), findsNothing);
      // Never says a mission alone unlocks time.
      expect(find.textContaining('unlock'), findsNothing);
    });

    testWidgets('time a parent approves shows up while the child waits', (
      tester,
    ) async {
      await open(tester);
      expect(find.byKey(const Key('video.lock.toMissions')), findsOneWidget);

      remaining = 900; // the parent approved a mission on their phone
      await tester.pump(VideoLockScreen.refreshEvery);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('video.lock.timeBack')), findsOneWidget);
      expect(find.textContaining('15 minutes'), findsWidgets);
      expect(find.byKey(const Key('video.lock.watchNow')), findsOneWidget);
      expect(find.byKey(const Key('video.lock.steps')), findsNothing);
    });

    testWidgets('returning to the app checks again at once', (tester) async {
      await open(tester);
      final before = h.backend.requestsTo('GET', _allowancePath).length;
      remaining = 900;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        h.backend.requestsTo('GET', _allowancePath).length,
        greaterThan(before),
      );
      expect(find.byKey(const Key('video.lock.timeBack')), findsOneWidget);
    });

    testWidgets('no refreshing while the app is in the background', (
      tester,
    ) async {
      await open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final before = h.backend.requestsTo('GET', _allowancePath).length;
      await tester.pump(VideoLockScreen.refreshEvery * 3);
      expect(h.backend.requestsTo('GET', _allowancePath).length, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    });

    testWidgets('a failed check offers a retry and never unlocks', (
      tester,
    ) async {
      await open(tester);
      failing = true;
      remaining = 900; // even if time existed, an unanswered check is not a yes
      await tester.ensureVisible(
        find.byKey(const Key('video.lock.checkAgain')),
      );
      await tester.tap(find.byKey(const Key('video.lock.checkAgain')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('video.lock.checkFailed')), findsOneWidget);
      expect(find.byKey(const Key('video.lock.watchNow')), findsNothing);

      failing = false;
      await tester.ensureVisible(find.byKey(const Key('video.lock.retry')));
      await tester.tap(find.byKey(const Key('video.lock.retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('video.lock.checkFailed')), findsNothing);
      expect(find.byKey(const Key('video.lock.timeBack')), findsOneWidget);
    });

    testWidgets('less than a minute back is not shown as "time is back"', (
      tester,
    ) async {
      await open(tester, start: 30);
      expect(find.byKey(const Key('video.lock.timeBack')), findsNothing);
      expect(find.byKey(const Key('video.lock.toMissions')), findsOneWidget);
    });

    testWidgets('reduced motion: Panda stays still', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await open(tester);
      expect(tester.hasRunningAnimations, isFalse);
    });

    for (final (code, title) in [
      ('hi', 'आज का वीडियो समय पूरा हुआ'),
      ('gu', 'આજનો વીડિયો સમય પૂરો થયો'),
    ]) {
      testWidgets('localised: $code', (tester) async {
        await open(tester, locale: Locale(code));
        expect(find.text(title), findsOneWidget);
        expect(find.byKey(const Key('video.lock.steps')), findsOneWidget);
      });
    }

    for (final (size, scale, locale) in [
      (const Size(320, 568), 2.0, const Locale('en')),
      (const Size(360, 640), 2.0, const Locale('hi')),
      (const Size(390, 844), 1.3, const Locale('gu')),
      (const Size(740, 360), 1.0, const Locale('gu')),
      (const Size(1024, 768), 1.0, const Locale('en')),
    ]) {
      testWidgets('no overflow $size @ ${scale}x $locale', (tester) async {
        await open(tester, size: size, scale: scale, locale: locale);
        expect(tester.takeException(), isNull);
        remaining = 900;
        await tester.pump(VideoLockScreen.refreshEvery);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
