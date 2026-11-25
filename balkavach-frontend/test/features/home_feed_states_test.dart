// Home (Watch & Learn) feed states, driven by the JSON the REAL backend routes produce.
//
// `test/fixtures/video_feed_contract.json` is generated from the actual `/videos/feed` and `/videos/shorts`
// routes, and balkavach-backend/tests/test_video_feed_real_filters.py fails if it drifts from them. These are
// mock/fake tests: the Flutter app runs against `FakeBackend`; no server, PostgreSQL or device is involved.
import 'dart:convert';
import 'dart:io';

import 'package:balkavach_app/app.dart';
import 'package:balkavach_app/features/learning/data/playable_video.dart';
import 'package:balkavach_app/features/learning/data/video_feed_repository.dart';
import 'package:balkavach_app/l10n/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

final _contract =
    jsonDecode(
          File('test/fixtures/video_feed_contract.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
List<dynamic> get _feed => _contract['feed'] as List<dynamic>;
List<dynamic> get _shorts => _contract['shorts'] as List<dynamic>;

/// What the REAL routes send once today's allowance is used up (same videos, ids withheld).
List<dynamic> get _feedLocked => _contract['feed_locked'] as List<dynamic>;
List<dynamic> get _shortsLocked => _contract['shorts_locked'] as List<dynamic>;

Map<String, Object?> _allowance({bool exhausted = false}) => {
  'child_id': Fx.childId,
  'local_date': '2026-11-21',
  'timezone': 'UTC',
  'total_earned_today_seconds': 900,
  'consumed_today_seconds': exhausted ? 900 : 0,
  'remaining_seconds': exhausted ? 0 : 900,
  'daily_cap_seconds': 3600,
  'is_exhausted': exhausted,
  'active_entitlements_count': 0,
};

Future<Harness> _child({
  List<dynamic>? feed,
  List<dynamic>? shorts,
  bool exhausted = false,
}) async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  h.backend
    ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
    ..reply(
      'GET',
      '/api/v1/video-access/allowance',
      _allowance(exhausted: exhausted),
    )
    ..reply('GET', '/api/v1/videos/feed', feed ?? _feed)
    ..reply('GET', '/api/v1/videos/shorts', shorts ?? _shorts)
    ..reply(
      'GET',
      '/api/v1/videos/watch-history/continue-watching',
      <Object?>[],
    );
  return h;
}

Future<void> _pump(WidgetTester tester, Harness h, {bool settle = true}) async {
  setWindow(tester, const Size(393, 1400));
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      retry: (_, _) => null,
      child: const BalKavachApp(),
    ),
  );
  settle
      ? await tester.pumpAndSettle()
      : await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  test('the backend contract parses into the app models', () {
    final video = FeedVideo.fromJson(_feed.single as Map<String, dynamic>);
    expect(video.title, 'Counting to ten');
    expect(video.isYouTube, isTrue);
    expect(video.youtubeVideoId, 'aaaaaaaaaaa');
    expect(video.channelName, 'Little Learners');
    expect(video.format, VideoFormat.regular);
    expect(video.durationSeconds, 240);
    expect(video.playbackLocked, isFalse);

    final short = FeedVideo.fromJson(_shorts.single as Map<String, dynamic>);
    expect(short.title, 'Clap along');
    expect(short.format, VideoFormat.short);
    expect(short.durationSeconds, 30);
  });

  testWidgets('eligible videos and Shorts from the server are shown, and the '
      'empty state is not', (tester) async {
    final h = await _child();
    await _pump(tester, h);

    expect(find.text('Counting to ten'), findsOneWidget);
    expect(find.text('Clap along'), findsOneWidget);
    expect(find.byKey(const Key('watch.shorts.header')), findsOneWidget);
    expect(find.byKey(const Key('watch.videos.header')), findsOneWidget);
    expect(find.byKey(const Key('watch.empty')), findsNothing);
    expect(h.backend.requestsTo('GET', '/api/v1/videos/shorts'), isNotEmpty);
    expect(h.backend.requestsTo('GET', '/api/v1/videos/feed'), isNotEmpty);
  });

  testWidgets('only Shorts available: the Shorts row shows, the video list '
      'section is hidden', (tester) async {
    final h = await _child(feed: const []);
    await _pump(tester, h);
    expect(find.text('Clap along'), findsOneWidget);
    expect(find.byKey(const Key('watch.videos.header')), findsNothing);
    expect(find.byKey(const Key('watch.empty')), findsNothing);
  });

  testWidgets('only regular videos available: the Shorts section is hidden', (
    tester,
  ) async {
    final h = await _child(shorts: const []);
    await _pump(tester, h);
    expect(find.text('Counting to ten'), findsOneWidget);
    expect(find.byKey(const Key('watch.shorts.header')), findsNothing);
    expect(find.byKey(const Key('watch.empty')), findsNothing);
  });

  testWidgets('the empty state appears only when the server has nothing '
      'eligible, with time left', (tester) async {
    final h = await _child(feed: const [], shorts: const []);
    await _pump(tester, h);

    expect(find.byKey(const Key('watch.empty')), findsOneWidget);
    expect(find.text(AppLocalizationsEn().watchNothingYet), findsOneWidget);
    expect(find.byKey(const Key('watch.allowance.card')), findsOneWidget);
  });

  testWidgets('zero allowance keeps the catalogue on Home: cards are listed '
      'with a lock, never "no videos"', (tester) async {
    final h = await _child(
      feed: _feedLocked,
      shorts: _shortsLocked,
      exhausted: true,
    );
    await _pump(tester, h);

    expect(find.text('Counting to ten'), findsOneWidget);
    expect(find.text('Clap along'), findsOneWidget);
    expect(find.byKey(const Key('watch.video.locked')), findsOneWidget);
    expect(find.byKey(const Key('watch.short.locked')), findsOneWidget);
    expect(find.byKey(const Key('watch.empty')), findsNothing);
    expect(find.text(AppLocalizationsEn().watchNothingYet), findsNothing);

    // Tapping a locked card explains the time limit; nothing plays.
    await tester.tap(find.text('Counting to ten'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('video.lock.panda')), findsOneWidget);
    expect(
      h.backend.requests.where(
        // Video progress reports; the child's own progress summary is a read.
        (r) =>
            r.uri.path.contains('/progress') &&
            !r.uri.path.contains('/progress/children'),
      ),
      isEmpty,
    );
  });

  testWidgets('a locked card reloads the feed once time is earned, instead of '
      'opening a video it cannot play', (tester) async {
    final h = await _child(feed: _feedLocked, exhausted: true);
    await _pump(tester, h);
    final before = h.backend.requestsTo('GET', '/api/v1/videos/feed').length;

    // A grown-up approved a mission: time is back and the server unlocks.
    h.backend
      ..reply('GET', '/api/v1/video-access/allowance', _allowance())
      ..reply('GET', '/api/v1/videos/feed', _feed);
    await tester.tap(find.text('Counting to ten'));
    await tester.pumpAndSettle();

    expect(
      h.backend.requestsTo('GET', '/api/v1/videos/feed').length,
      greaterThan(before),
    );
    expect(find.byKey(const Key('watch.video.locked')), findsNothing);
    expect(find.byKey(const Key('video.lock.panda')), findsNothing);
  });

  testWidgets('Home and Shorts open for a child with no grown-up approval '
      'step or learning-gate check', (tester) async {
    final h = await _child();
    await _pump(tester, h);

    expect(find.text('Counting to ten'), findsOneWidget);
    expect(find.text('Clap along'), findsOneWidget);
    expect(
      h.backend.requests.where((r) => r.uri.path.contains('learning-gate')),
      isEmpty,
    );
    expect(
      find.textContaining(RegExp('grown-up', caseSensitive: false)),
      findsNothing,
    );
  });

  test('a locked item from the server parses as listed but not playable', () {
    final video = FeedVideo.fromJson(
      _feedLocked.single as Map<String, dynamic>,
    );
    expect(video.playbackLocked, isTrue);
    expect(video.youtubeVideoId, isNull);
    final playable = PlayableVideo.fromFeed(video);
    expect(playable.isPlayable, isFalse);
    expect(playable.isTimeLocked, isTrue);
  });

  testWidgets('a failing Shorts request shows an error with retry, and the '
      'videos still show', (tester) async {
    final h = await _child();
    var shortsCalls = 0;
    h.backend.on('GET', '/api/v1/videos/shorts', (_) {
      shortsCalls++;
      return shortsCalls == 1
          ? FakeReply.error(500, 'internal_error', 'boom')
          : FakeReply(200, _shorts);
    });
    await _pump(tester, h);

    expect(find.byKey(const Key('watch.shorts.error')), findsOneWidget);
    expect(find.text('Counting to ten'), findsOneWidget);
    expect(find.byKey(const Key('watch.empty')), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('watch.shorts.error')),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Clap along'), findsOneWidget);
    expect(find.byKey(const Key('watch.shorts.error')), findsNothing);
  });

  testWidgets('when both feeds fail, Home shows errors with retry, never the '
      'empty state', (tester) async {
    final h = await _child();
    for (final path in ['/api/v1/videos/feed', '/api/v1/videos/shorts']) {
      h.backend.on(
        'GET',
        path,
        (_) => FakeReply.error(500, 'internal_error', 'boom'),
      );
    }
    await _pump(tester, h);
    expect(find.byKey(const Key('watch.shorts.error')), findsOneWidget);
    expect(find.byKey(const Key('watch.videos.error')), findsOneWidget);
    expect(find.byKey(const Key('watch.empty')), findsNothing);
    expect(find.text(AppLocalizationsEn().watchNothingYet), findsNothing);
  });

  testWidgets('while the feeds load there are spinners, not the empty state', (
    tester,
  ) async {
    final h = await _child();
    await _pump(tester, h, settle: false);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.byKey(const Key('watch.empty')), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('watch.empty')), findsNothing);
  });

  testWidgets('a cached card cannot start playback once the server says the '
      'allowance is used up', (tester) async {
    final h = await _child();
    await _pump(tester, h);
    // The allowance ran out after the feed was loaded.
    h.backend.reply(
      'GET',
      '/api/v1/video-access/allowance',
      _allowance(exhausted: true),
    );

    await tester.tap(find.text('Counting to ten'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('video.lock.panda')), findsOneWidget);
    expect(
      h.backend.requestsTo('GET', '/api/v1/video-access/allowance'),
      isNotEmpty,
    );
    expect(
      h.backend.requests.where(
        // Video progress reports; the child's own progress summary is a read.
        (r) =>
            r.uri.path.contains('/progress') &&
            !r.uri.path.contains('/progress/children'),
      ),
      isEmpty,
    );
  });

  testWidgets('if the allowance cannot be checked, playback does not start', (
    tester,
  ) async {
    final h = await _child();
    await _pump(tester, h);
    h.backend.on(
      'GET',
      '/api/v1/video-access/allowance',
      (_) => FakeReply.error(500, 'internal_error', 'boom'),
    );
    await tester.tap(find.text('Counting to ten'));
    await tester.pumpAndSettle();
    expect(
      find.text(AppLocalizationsEn().videoTimeCheckFailed),
      findsOneWidget,
    );
    expect(find.byKey(const Key('video.lock.panda')), findsNothing);
  });
}
