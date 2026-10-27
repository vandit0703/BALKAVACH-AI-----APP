import 'package:balkavach_app/features/learning/data/learning_repository.dart';
import 'package:balkavach_app/features/learning/data/video_playback_controller.dart';
import 'package:balkavach_app/features/learning/presentation/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

/// A stand-in for `video_player`, which needs a platform decoder and so cannot
/// run in a widget test.
///
/// This proves the SCREEN behaves correctly. It is never evidence that a child
/// watched anything: real viewing is only ever established by server-accepted
/// heartbeats, which this screen does not send.
class FakePlaybackController implements VideoPlaybackController {
  FakePlaybackController({this.failOnInitialise = false});

  final ChangeNotifier _notifier = ChangeNotifier();

  void notifyListeners() => _notifier.notifyListeners();

  bool failOnInitialise;
  int initialiseCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  bool disposed = false;
  bool _initialised = false;
  bool _playing = false;
  String? _error;

  @override
  Listenable get listenable => _notifier;

  @override
  bool get isInitialised => _initialised;

  @override
  bool get isPlaying => _playing;

  @override
  bool get isBuffering => false;

  @override
  String? get errorMessage => _error;

  @override
  Duration get position => const Duration(seconds: 30);

  @override
  Duration get duration => const Duration(minutes: 2);

  @override
  double get aspectRatio => 16 / 9;

  @override
  Future<void> initialise() async {
    initialiseCount++;
    if (failOnInitialise) {
      _error = 'decoder failed';
      _initialised = false;
    } else {
      _error = null;
      _initialised = true;
    }
    notifyListeners();
  }

  @override
  Future<void> play() async {
    playCount++;
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    _playing = false;
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    // Only records the call: the test still reads counters afterwards, which a
    // real (discarded) controller would not need to support.
    disposed = true;
  }

  @override
  Widget? buildSurface() =>
      _initialised ? const SizedBox(key: Key('fake.surface')) : null;
}

LearningItem _video({
  String id = 'video-1',
  String contentType = 'video',
  String? url = 'https://cdn.example.org/curated/alphabet.mp4',
  bool requiresEntitlement = false,
  String? videoId,
}) => LearningItem(
  id: id,
  title: 'Alphabet Song',
  description: 'Sing along with the letters.',
  contentType: contentType,
  contentUrl: url,
  requiresEntitlement: requiresEntitlement,
  videoId: videoId,
);

Future<FakePlaybackController> _pumpPlayer(
  WidgetTester tester, {
  bool failOnInitialise = false,
  LearningItem? item,
  Locale locale = const Locale('en'),
}) async {
  final created = <FakePlaybackController>[];
  final fake = FakePlaybackController(failOnInitialise: failOnInitialise);
  created.add(fake);
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  await pumpScreen(
    tester,
    VideoPlayerScreen(item: item ?? _video()),
    overrides: [
      ...h.overrides,
      videoPlaybackControllerFactoryProvider.overrideWithValue((_) {
        if (created.length == 1) return created.first;
        return created.last;
      }),
    ],
    locale: locale,
  );
  return fake;
}

void main() {
  group('In-app video player', () {
    testWidgets('initialises and starts playing a curated video', (
      tester,
    ) async {
      final fake = await _pumpPlayer(tester);

      expect(fake.initialiseCount, 1);
      expect(fake.playCount, 1);
      expect(find.byKey(const Key('fake.surface')), findsOneWidget);
      expect(find.byKey(const Key('player.error')), findsNothing);
    });

    testWidgets('shows the title and description', (tester) async {
      await _pumpPlayer(tester);

      expect(find.text('Alphabet Song'), findsWidgets);
      expect(find.text('Sing along with the letters.'), findsOneWidget);
    });

    testWidgets('pause then resume drives the controller', (tester) async {
      final fake = await _pumpPlayer(tester);

      await tester.tap(find.byKey(const Key('player.playPause')));
      await tester.pumpAndSettle();
      expect(fake.pauseCount, 1);
      expect(fake.isPlaying, isFalse);

      await tester.tap(find.byKey(const Key('player.playPause')));
      await tester.pumpAndSettle();
      expect(fake.playCount, 2);
      expect(fake.isPlaying, isTrue);
    });

    testWidgets('elapsed and total time are shown', (tester) async {
      await _pumpPlayer(tester);

      expect(find.text('0:30 / 2:00'), findsOneWidget);
    });

    testWidgets('a failed load shows an error and no surface', (tester) async {
      final fake = await _pumpPlayer(tester, failOnInitialise: true);

      expect(find.byKey(const Key('player.error')), findsOneWidget);
      expect(find.byKey(const Key('fake.surface')), findsNothing);
      // A failed video must never autoplay.
      expect(fake.playCount, 0);
      // Controls are meaningless without a working decoder.
      expect(find.byKey(const Key('player.playPause')), findsNothing);
    });

    testWidgets('retry disposes the old controller and tries again', (
      tester,
    ) async {
      final fake = await _pumpPlayer(tester, failOnInitialise: true);

      await tester.tap(find.byKey(const Key('player.retry')));
      await tester.pumpAndSettle();

      expect(fake.disposed, isTrue);
      // The same fake is returned by the overridden factory, so a second
      // initialise proves the retry path ran.
      expect(fake.initialiseCount, 2);
    });

    testWidgets('leaving the screen disposes the controller', (tester) async {
      final fake = await _pumpPlayer(tester);
      expect(fake.disposed, isFalse);

      // Replace the screen: the player's State is disposed.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(fake.disposed, isTrue);
    });

    testWidgets('backgrounding the app pauses playback', (tester) async {
      final fake = await _pumpPlayer(tester);
      expect(fake.isPlaying, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      expect(fake.pauseCount, greaterThanOrEqualTo(1));
      expect(fake.isPlaying, isFalse);
    });

    testWidgets('an item with no playable URL never builds a controller', (
      tester,
    ) async {
      final fake = await _pumpPlayer(tester, item: _video(url: null));

      expect(fake.initialiseCount, 0);
      expect(find.byKey(const Key('fake.surface')), findsNothing);
      // A dead spinner would be wrong: say so instead.
      expect(find.byKey(const Key('player.noSource')), findsOneWidget);
      expect(find.byKey(const Key('player.loading')), findsNothing);
    });
  });

  group('Localisation', () {
    const pauseLabel = {'hi': 'रोको', 'gu': 'થોભાવો'};
    const failedLabel = {
      'hi': 'हम यह वीडियो नहीं चला सके।',
      'gu': 'અમે આ વીડિયો ચલાવી શક્યા નહીં.',
    };

    for (final code in ['hi', 'gu']) {
      testWidgets('player controls are translated in $code', (tester) async {
        await _pumpPlayer(tester, locale: Locale(code));

        final button = tester.widget<IconButton>(
          find.byKey(const Key('player.playPause')),
        );
        expect(button.tooltip, pauseLabel[code]);
      });

      testWidgets('the error state is translated in $code', (tester) async {
        await _pumpPlayer(tester, failOnInitialise: true, locale: Locale(code));

        expect(find.text(failedLabel[code]!), findsOneWidget);
        expect(find.text("We couldn't play this video."), findsNothing);
      });
    }
  });

  group('Responsive layout', () {
    for (final size in [const Size(320, 640), const Size(412, 915)]) {
      testWidgets('no overflow at ${size.width.toInt()} px', (tester) async {
        final fake = FakePlaybackController();
        final h = await Harness.create(
          session: Fx.childSession(),
          prefs: onboardedPrefs,
        );
        await pumpScreen(
          tester,
          VideoPlayerScreen(item: _video()),
          overrides: [
            ...h.overrides,
            videoPlaybackControllerFactoryProvider.overrideWithValue(
              (_) => fake,
            ),
          ],
          size: size,
        );

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Playability rules', () {
    test('a curated direct video link is playable in app', () {
      expect(_video().isPlayableInApp, isTrue);
    });

    test('an entitlement-gated video is never played by this screen', () {
      // The server withholds the URL for these; they belong to the authorised
      // playback-session API, which needs a configured provider.
      expect(
        _video(requiresEntitlement: true, url: null).isPlayableInApp,
        isFalse,
      );
    });

    test('a hosted video is never played by this screen', () {
      expect(_video(videoId: Fx.childId, url: null).isPlayableInApp, isFalse);
    });

    test('a non-video item is not playable', () {
      expect(_video(contentType: 'article').isPlayableInApp, isFalse);
    });

    test('a non-https link is rejected', () {
      expect(
        _video(url: 'http://insecure.example/a.mp4').isPlayableInApp,
        isFalse,
      );
    });

    test('a direct MP4 goes to the native player, not the YouTube embed', () {
      final item = _video();
      expect(item.isYouTubeLink, isFalse);
      expect(item.youtubeVideoId, isNull);
      expect(item.isYouTubeEmbeddable, isFalse);
      expect(item.playsInApp, isTrue);
    });

    const id = 'dQw4w9WgXcQ';
    for (final url in [
      'https://www.youtube.com/watch?v=$id',
      'https://youtube.com/watch?v=$id&t=42s',
      'https://m.youtube.com/watch?v=$id',
      'https://youtu.be/$id',
      'https://youtu.be/$id?si=abc',
      'https://www.youtube.com/shorts/$id',
      'https://www.youtube.com/embed/$id',
      'https://www.youtube.com/live/$id',
      'https://www.youtube-nocookie.com/embed/$id',
    ]) {
      test('$url plays in the YouTube embed, never the native player', () {
        final item = _video(url: url);
        expect(item.youtubeVideoId, id);
        expect(item.isYouTubeEmbeddable, isTrue);
        expect(item.isPlayableInApp, isFalse);
        expect(item.playsInApp, isTrue);
      });
    }

    for (final url in [
      'https://www.youtube.com/@SomeChannel',
      'https://www.youtube.com/playlist?list=PL123',
      'https://www.youtube.com/watch?v=tooShort',
      'https://www.youtube.com/results?search_query=abc',
    ]) {
      test('$url is YouTube but not one embeddable video', () {
        final item = _video(url: url);
        expect(item.isYouTubeLink, isTrue);
        expect(item.youtubeVideoId, isNull);
        expect(item.playsInApp, isFalse);
      });
    }

    test('a YouTube link on a non-video item is not played', () {
      final item = _video(contentType: 'link', url: 'https://youtu.be/$id');
      expect(item.isYouTubeEmbeddable, isFalse);
      expect(item.playsInApp, isFalse);
    });

    test('a look-alike host is not treated as YouTube', () {
      final item = _video(url: 'https://notyoutube.com/watch?v=$id');
      expect(item.isYouTubeLink, isFalse);
      expect(item.isYouTubeEmbeddable, isFalse);
      // It is just a direct link, so the native player gets it (and shows
      // its error state if it is not media).
      expect(item.isPlayableInApp, isTrue);
    });
  });

  group('Time formatting', () {
    test('formats under an hour as m:ss', () {
      expect(formatPlaybackTime(const Duration(seconds: 5)), '0:05');
      expect(
        formatPlaybackTime(const Duration(minutes: 12, seconds: 7)),
        '12:07',
      );
    });

    test('formats an hour or more as h:mm:ss', () {
      expect(
        formatPlaybackTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('a negative position never renders as negative time', () {
      expect(formatPlaybackTime(const Duration(seconds: -5)), '0:00');
    });
  });
}
