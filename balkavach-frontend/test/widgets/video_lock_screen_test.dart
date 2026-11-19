import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/features/learning/data/video_feed_repository.dart';
import 'package:balkavach_app/features/learning/presentation/video_lock_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

VideoAllowance _allowance({required int remaining}) => VideoAllowance(
  childId: 'c',
  localDate: '2026-11-19',
  timezone: 'UTC',
  totalEarnedTodaySeconds: 1800,
  consumedTodaySeconds: 1800 - remaining,
  remainingSeconds: remaining,
  dailyCapSeconds: 4500,
  isExhausted: remaining <= 0,
  activeEntitlementsCount: 2,
);

class _FakeRepo implements VideoFeedRepository {
  _FakeRepo(this._allowance);

  final Future<VideoAllowance> Function() _allowance;

  @override
  Future<VideoAllowance> getAllowance() => _allowance();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Gate extends ConsumerWidget {
  const _Gate(this.onResult);

  final void Function(bool) onResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: TextButton(
        key: const Key('gate.open'),
        onPressed: () async =>
            onResult(await ensureVideoAllowance(context, ref)),
        child: const Text('open'),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Future<VideoAllowance> Function() allowance,
  void Function(bool) onResult,
) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => _Gate(onResult)),
      GoRoute(
        path: '/child/missions',
        builder: (_, _) => const Scaffold(body: Text('MISSIONS PAGE')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        videoFeedRepositoryProvider.overrideWithValue(_FakeRepo(allowance)),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('time remaining: the gate opens and no lock appears', (
    tester,
  ) async {
    bool? result;
    await _pump(
      tester,
      () async => _allowance(remaining: 600),
      (r) => result = r,
    );
    await tester.tap(find.byKey(const Key('gate.open')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byKey(const Key('video.lock.screen')), findsNothing);
  });

  testWidgets('exhausted: playback refused; lock page shows server figures '
      'and a Go to Missions button', (tester) async {
    bool? result;
    await _pump(
      tester,
      () async => _allowance(remaining: 0),
      (r) => result = r,
    );
    await tester.tap(find.byKey(const Key('gate.open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('video.lock.screen')), findsOneWidget);
    expect(find.text('You watched 30 of 30 minutes today.'), findsOneWidget);
    expect(find.text('Go to Missions'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('video.lock.toMissions')));
    await tester.tap(find.byKey(const Key('video.lock.toMissions')));
    await tester.pumpAndSettle();
    expect(find.text('MISSIONS PAGE'), findsOneWidget);
    expect(result, isFalse);
  });

  testWidgets('closing the lock page does not grant playback', (tester) async {
    bool? result;
    await _pump(
      tester,
      () async => _allowance(remaining: 0),
      (r) => result = r,
    );
    await tester.tap(find.byKey(const Key('gate.open')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('video.lock.close')));
    await tester.tap(find.byKey(const Key('video.lock.close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('video.lock.screen')), findsNothing);
    expect(result, isFalse);
  });

  testWidgets('network error: refused with a message, never free playback', (
    tester,
  ) async {
    bool? result;
    await _pump(
      tester,
      () async => throw const NetworkException(),
      (r) => result = r,
    );
    await tester.tap(find.byKey(const Key('gate.open')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.byKey(const Key('video.lock.screen')), findsNothing);
    expect(
      find.text('We couldn’t check your video time. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('lock page fits a small phone at 2x text and in landscape', (
    tester,
  ) async {
    for (final size in [const Size(320, 568), const Size(740, 360)]) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: VideoLockScreen(allowance: _allowance(remaining: 0)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      expect(find.byKey(const Key('video.lock.toMissions')), findsOneWidget);
    }
  });
}
