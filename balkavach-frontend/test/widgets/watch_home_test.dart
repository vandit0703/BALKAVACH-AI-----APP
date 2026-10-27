import 'package:balkavach_app/app.dart';
import 'package:balkavach_app/features/learning/data/learning_gate_repository.dart';
import 'package:balkavach_app/features/learning/data/video_playback_controller.dart';
import 'package:balkavach_app/features/learning/presentation/video_player_screen.dart';
import 'package:balkavach_app/features/learning/presentation/youtube_player_screen.dart';
import 'package:balkavach_app/shared/platform/link_opener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _gatePath = '/api/v1/learning-gate/today';

/// Fails the test's expectations if anything tries to leave the app.
class _RecordingOpener implements LinkOpener {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

/// Stands in for `video_player`, which needs a platform decoder. Proves the
/// routing and lifecycle only, never real playback.
class _StubPlayback implements VideoPlaybackController {
  final _notifier = ChangeNotifier();
  bool initialised = false;
  bool disposed = false;
  bool _playing = false;

  @override
  Listenable get listenable => _notifier;
  @override
  bool get isInitialised => initialised;
  @override
  bool get isPlaying => _playing;
  @override
  bool get isBuffering => false;
  @override
  String? get errorMessage => null;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => const Duration(minutes: 1);
  @override
  double get aspectRatio => 16 / 9;

  @override
  Future<void> initialise() async {
    initialised = true;
    _notifier.notifyListeners();
  }

  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  Widget? buildSurface() => initialised ? const SizedBox() : null;
}

Future<Harness> _child() async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  h.backend
    ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
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

void main() {
  group('Video-first Home', () {
    testWidgets('Home is the watch experience, not the dashboard', (
      tester,
    ) async {
      final h = await _child();
      await _pumpApp(tester, h);

      expect(find.text('Watch & Learn'), findsOneWidget);
      expect(find.byKey(const Key('watch.session')), findsOneWidget);
      expect(find.text('Hello Aarav! 👋'), findsNothing);
    });

    testWidgets('bottom navigation is Home, Missions, Rewards, Garden, '
        'Profile', (tester) async {
      final h = await _child();
      await _pumpApp(tester, h);

      for (final label in [
        'Home',
        'Missions',
        'Rewards',
        'Garden',
        'Profile',
      ]) {
        expect(find.text(label), findsWidgets, reason: '$label destination');
      }
      // Learn is no longer a tab, but must remain reachable from Home.
      expect(find.byKey(const Key('watch.openLearn')), findsOneWidget);
    });

    testWidgets('the dashboard is intact under Profile', (tester) async {
      final h = await _child();
      await _pumpApp(tester, h);

      await _tap(tester, find.text('Profile'));

      expect(find.text('Hello Aarav! 👋'), findsOneWidget);
      // Stars, streak and XP came across with it.
      expect(find.text('240'), findsOneWidget);
      expect(find.text('5 Day'), findsOneWidget);
      expect(find.text('420'), findsOneWidget);
      expect(find.byKey(const Key('profile.language')), findsOneWidget);
    });

    testWidgets('an unavailable gate is stated and missions stay reachable', (
      tester,
    ) async {
      final h = await _child();
      await _pumpApp(tester, h);

      expect(find.byKey(const Key('watch.unavailable')), findsOneWidget);
      // The gate cannot be satisfied, so it must not block missions.
      await _tap(tester, find.byKey(const Key('watch.toMissions')));
      expect(find.text('Missions'), findsWidgets);
    });

    testWidgets('no progress bar is shown when nothing is being measured', (
      tester,
    ) async {
      final h = await _child();
      await _pumpApp(tester, h);

      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a locked first session shows the minutes needed', (
      tester,
    ) async {
      final h = await _child();
      h.backend.reply(
        'GET',
        _gatePath,
        Fx.learningGate(
          phase: 'first_session',
          videoGateAvailable: true,
          playbackConfigured: true,
          missionsUnlocked: false,
          watchedSecondsToday: 120,
          blockers: const ['first_session_incomplete'],
        ),
      );
      await _pumpApp(tester, h);

      expect(
        find.text("Watch 10 min to unlock today's missions"),
        findsOneWidget,
      );
      expect(find.byKey(const Key('watch.toMissions')), findsNothing);
    });

    testWidgets('a satisfied first session unlocks missions', (tester) async {
      final h = await _child();
      h.backend.reply(
        'GET',
        _gatePath,
        Fx.learningGate(
          phase: 'missions',
          videoGateAvailable: true,
          playbackConfigured: true,
          firstSessionComplete: true,
          watchedSecondsToday: 600,
          blockers: const [],
        ),
      );
      await _pumpApp(tester, h);

      expect(find.text('Missions unlocked. Nice work!'), findsOneWidget);
      expect(find.byKey(const Key('watch.toMissions')), findsOneWidget);
    });

    testWidgets('submitted-but-unreviewed work says a grown-up is checking', (
      tester,
    ) async {
      final h = await _child();
      h.backend.reply(
        'GET',
        _gatePath,
        Fx.learningGate(
          phase: 'awaiting_approval',
          videoGateAvailable: true,
          playbackConfigured: true,
          firstSessionComplete: true,
          watchedSecondsToday: 600,
          missionsPendingApproval: 2,
          blockers: const ['missions_awaiting_approval'],
        ),
      );
      await _pumpApp(tester, h);

      expect(
        find.text('Your grown-up is checking your missions'),
        findsOneWidget,
      );
      // Submitting is not completing: the second session stays shut.
      expect(find.text('Bonus videos unlocked!'), findsNothing);
    });

    testWidgets('video switched off by a parent is reported as such', (
      tester,
    ) async {
      final h = await _child();
      h.backend.reply(
        'GET',
        _gatePath,
        Fx.learningGate(
          videoEnabled: false,
          blockers: const ['video_disabled_by_parent'],
        ),
      );
      await _pumpApp(tester, h);

      expect(find.text('Videos are switched off'), findsOneWidget);
    });

    testWidgets('a failed gate request shows an error, not a false unlock', (
      tester,
    ) async {
      final h = await _child();
      h.backend.reply('GET', _gatePath, {'detail': 'boom'}, status: 500);
      await _pumpApp(tester, h);

      expect(find.byKey(const Key('watch.session')), findsNothing);
      expect(find.text('Missions unlocked. Nice work!'), findsNothing);
    });
  });

  group('Tapping a video on Home', () {
    Map<String, Object?> video(String id, String url) => {
      'id': id,
      'title': 'KIDS CONTENT',
      'description': null,
      'content_type': 'video',
      'category_id': null,
      'language_code': 'en',
      'content_url': url,
      'thumbnail_url': null,
      'video_id': null,
      'collection_id': null,
      'requires_entitlement': false,
      'is_active': true,
    };

    Future<(_RecordingOpener, _StubPlayback, List<YouTubeEmbedConfig>)> pump(
      WidgetTester tester,
      Map<String, Object?> item,
    ) async {
      final h = await _child();
      h.backend.reply('GET', '/api/v1/educational-content', [item]);
      final opener = _RecordingOpener();
      final playback = _StubPlayback();
      final embeds = <YouTubeEmbedConfig>[];
      setWindow(tester, const Size(393, 852));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...h.overrides,
            linkOpenerProvider.overrideWithValue(opener),
            videoPlaybackControllerFactoryProvider.overrideWithValue(
              (_) => playback,
            ),
            youtubeEmbedBuilderProvider.overrideWithValue((config) {
              embeds.add(config);
              return const ColoredBox(
                key: Key('fake.embed'),
                color: Colors.black,
              );
            }),
          ],
          retry: (_, _) => null,
          child: const BalKavachApp(),
        ),
      );
      await tester.pumpAndSettle();
      return (opener, playback, embeds);
    }

    testWidgets('a direct MP4 opens the in-app player straight away', (
      tester,
    ) async {
      final (opener, playback, embeds) = await pump(
        tester,
        video('mp4', 'https://cdn.example.org/kids.mp4'),
      );

      await _tap(tester, find.byKey(const Key('watch.video.mp4')));

      expect(find.byType(VideoPlayerScreen), findsOneWidget);
      expect(find.byKey(const Key('learn.open')), findsNothing);
      expect(playback.initialised, isTrue);
      expect(embeds, isEmpty);
      expect(opener.opened, isEmpty);
    });

    testWidgets('a YouTube link opens the embedded player, not YouTube', (
      tester,
    ) async {
      final (opener, playback, embeds) = await pump(
        tester,
        video('yt', 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
      );

      await _tap(tester, find.byKey(const Key('watch.video.yt')));

      expect(find.byType(YouTubePlayerScreen), findsOneWidget);
      expect(find.byKey(const Key('fake.embed')), findsOneWidget);
      expect(embeds.single.videoId, 'dQw4w9WgXcQ');
      // The native decoder is never handed a web page.
      expect(playback.initialised, isFalse);
      expect(opener.opened, isEmpty);
    });

    testWidgets('back returns Home and releases the player', (tester) async {
      final (_, playback, _) = await pump(
        tester,
        video('mp4', 'https://cdn.example.org/kids.mp4'),
      );
      await _tap(tester, find.byKey(const Key('watch.video.mp4')));
      expect(playback.disposed, isFalse);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(VideoPlayerScreen), findsNothing);
      expect(find.byKey(const Key('watch.session')), findsOneWidget);
      expect(playback.disposed, isTrue);
    });
  });

  group('Localisation', () {
    // The gate's own strings must localise, not just the shell chrome.
    const unavailable = {
      'hi': 'वीडियो अभी तैयार नहीं हैं',
      'gu': 'વીડિયો હજી તૈયાર નથી',
    };

    for (final code in ['hi', 'gu']) {
      testWidgets('Home renders in $code', (tester) async {
        final h = await Harness.create(
          session: Fx.childSession(),
          prefs: {...onboardedPrefs, 'app.language_code': code},
        );
        h.backend
          ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
          ..reply('GET', '/api/v1/redemptions/mine', <Object?>[]);
        await _pumpApp(tester, h);

        expect(find.text(unavailable[code]!), findsOneWidget);
        // The English copy must not leak through.
        expect(find.text("Videos aren't ready yet"), findsNothing);
      });
    }

    testWidgets('language can be changed from Profile', (tester) async {
      final h = await _child();
      await _pumpApp(tester, h);

      await _tap(tester, find.text('Profile'));
      await _tap(tester, find.byKey(const Key('profile.language.hi')));

      expect(h.prefs.languageCode, 'hi');
    });
  });

  group('LearningGate parsing', () {
    test('a malformed response still leaves missions reachable', () {
      final gate = LearningGate.fromJson(const {});

      expect(gate.missionsUnlocked, isTrue);
      expect(gate.videoGateAvailable, isFalse);
      expect(gate.phase, LearningPhase.videoUnavailable);
      expect(gate.sessionProgress, isNull);
    });

    test('progress is null while the gate is unavailable', () {
      final gate = LearningGate.fromJson({
        ...Fx.learningGate(watchedSecondsToday: 300),
      });

      expect(gate.sessionProgress, isNull);
      expect(gate.secondsRemainingInSession, 0);
    });

    test('progress measures the first session before it is complete', () {
      final gate = LearningGate.fromJson({
        ...Fx.learningGate(
          videoGateAvailable: true,
          playbackConfigured: true,
          watchedSecondsToday: 300,
        ),
      });

      expect(gate.sessionProgress, closeTo(0.5, 0.001));
      expect(gate.secondsRemainingInSession, 300);
    });

    test('progress measures the second session once the first is done', () {
      final gate = LearningGate.fromJson({
        ...Fx.learningGate(
          videoGateAvailable: true,
          playbackConfigured: true,
          firstSessionComplete: true,
          watchedSecondsToday: 1050,
        ),
      });

      // 450s into a 900s second session.
      expect(gate.sessionProgress, closeTo(0.5, 0.001));
      expect(gate.secondsRemainingInSession, 450);
    });

    test('progress never exceeds a full bar', () {
      final gate = LearningGate.fromJson({
        ...Fx.learningGate(
          videoGateAvailable: true,
          playbackConfigured: true,
          watchedSecondsToday: 99999,
        ),
      });

      expect(gate.sessionProgress, 1.0);
      expect(gate.secondsRemainingInSession, 0);
    });
  });
}
