// Player behaviour here is verified against PLAYER MOCKS (see
// test/helpers/fake_video_players.dart). These tests prove how the Shorts
// screens drive players; they are not real playback verification.

import 'package:balkavach_app/core/network/access_token_store.dart';
import 'package:balkavach_app/features/learning/data/learning_repository.dart';
import 'package:balkavach_app/features/learning/data/playable_video.dart';
import 'package:balkavach_app/features/learning/data/video_feed_repository.dart';
import 'package:balkavach_app/features/learning/data/video_playback_controller.dart';
import 'package:balkavach_app/features/learning/presentation/shorts_feed.dart';
import 'package:balkavach_app/features/learning/presentation/youtube_player_screen.dart';
import 'package:balkavach_app/shared/platform/link_opener.dart';
import 'package:balkavach_app/shared/platform/text_sharer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_video_players.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _shortsPath = '/api/v1/videos/shorts';

Map<String, Object?> _short({
  required String id,
  required String title,
  String? youtubeId,
  String source = 'youtube',
  String? channel = 'Kids Science Club',
  String? description,
}) => {
  'id': id,
  'title': title,
  'description': description,
  'thumbnail_url': 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
  'duration_seconds': 45,
  'category_id': null,
  'language_code': 'en',
  'content_rating': 'educational',
  'video_source': source,
  'youtube_video_id': source == 'youtube' ? youtubeId : null,
  'channel_name': channel,
};

String _ytId(int i) => 'abcdefghi${i.toString().padLeft(2, '0')}';

List<Map<String, Object?>> _page(int start, int count) => [
  for (var i = start; i < start + count; i++)
    _short(id: 'short-$i', title: 'Short $i', youtubeId: _ytId(i)),
];

class _Rig {
  _Rig(this.h, this.embeds, this.players, this.opener, this.sharer);

  final Harness h;
  final EmbedRecorder embeds;
  final PlaybackRegistry players;
  final RecordingLinkOpener opener;
  final RecordingSharer sharer;
}

Future<_Rig> _pumpFeed(
  WidgetTester tester, {
  List<Map<String, Object?>>? shorts,
  FakeReply Function(int offset)? reply,
  ShortsLaunch launch = const ShortsLaunch(),
  Locale locale = const Locale('en'),
  Size size = const Size(393, 852),
}) async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  if (reply != null) {
    h.backend.on(
      'GET',
      _shortsPath,
      (options) => reply(options.queryParameters['offset'] as int),
    );
  } else {
    h.backend.reply('GET', _shortsPath, shorts ?? const <Object?>[]);
  }
  final rig = _Rig(
    h,
    EmbedRecorder(),
    PlaybackRegistry(),
    RecordingLinkOpener(),
    RecordingSharer(),
  );
  await pumpScreen(
    tester,
    ShortsFeedScreen(launch: launch),
    overrides: [
      ...h.overrides,
      youtubeEmbedBuilderProvider.overrideWithValue(rig.embeds.build),
      videoPlaybackControllerFactoryProvider.overrideWithValue(
        rig.players.create,
      ),
      linkOpenerProvider.overrideWithValue(rig.opener),
      textSharerProvider.overrideWithValue(rig.sharer),
    ],
    locale: locale,
    size: size,
  );
  return rig;
}

Finder get _pager => find.byKey(const Key('videos.shorts.pager'));

Future<void> _swipeUp(WidgetTester tester) async {
  await tester.drag(_pager, const Offset(0, -700));
  await tester.pumpAndSettle();
}

Future<void> _swipeDown(WidgetTester tester) async {
  await tester.drag(_pager, const Offset(0, 700));
  await tester.pumpAndSettle();
}

void main() {
  group('Shorts feed with server data', () {
    testWidgets('plays the first approved Short inside the app', (
      tester,
    ) async {
      final rig = await _pumpFeed(
        tester,
        shorts: [
          _short(
            id: 's1',
            title: 'Why is the sky blue?',
            youtubeId: _ytId(1),
            description: 'Light scatters in the air.',
          ),
        ],
      );

      expect(find.text('Why is the sky blue?'), findsOneWidget);
      expect(find.text('Kids Science Club'), findsOneWidget);
      expect(find.text('Light scatters in the air.'), findsOneWidget);
      final config = rig.embeds.only();
      expect(config.videoId, _ytId(1));
      expect(config.autoplay, isTrue);
      expect(config.onVerticalSwipe, isNotNull);
      // In-app only: nothing was opened outside, and no native stream exists.
      expect(rig.opener.opened, isEmpty);
      expect(rig.players.created, isEmpty);
      expect(rig.h.backend.requestsTo('GET', _shortsPath), hasLength(1));
    });

    testWidgets('swiping up and down changes video, one player at a time', (
      tester,
    ) async {
      final rig = await _pumpFeed(tester, shorts: _page(0, 3));

      expect(rig.embeds.only().videoId, _ytId(0));
      await _swipeUp(tester);
      expect(find.text('Short 1'), findsOneWidget);
      // The previous embed was torn down, not merely hidden.
      expect(rig.embeds.only().videoId, _ytId(1));

      await _swipeUp(tester);
      expect(rig.embeds.only().videoId, _ytId(2));

      await _swipeDown(tester);
      expect(find.text('Short 1'), findsOneWidget);
      expect(rig.embeds.only().videoId, _ytId(1));
    });

    testWidgets('a vertical fling on the video itself changes the Short', (
      tester,
    ) async {
      final rig = await _pumpFeed(tester, shorts: _page(0, 2));

      rig.embeds.only().onVerticalSwipe!(-1200);
      await tester.pumpAndSettle();
      expect(rig.embeds.only().videoId, _ytId(1));

      rig.embeds.only().onVerticalSwipe!(1200);
      await tester.pumpAndSettle();
      expect(rig.embeds.only().videoId, _ytId(0));
    });

    testWidgets('rapid swipes settle on one page with one player', (
      tester,
    ) async {
      final rig = await _pumpFeed(tester, shorts: _page(0, 6));

      for (var i = 0; i < 3; i++) {
        await tester.drag(_pager, const Offset(0, -700));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      expect(rig.embeds.mounted, hasLength(1));
      final settled = rig.embeds.only().videoId;
      final index = int.parse(settled.substring(settled.length - 2));
      expect(find.text('Short $index'), findsOneWidget);
      // Pages skimmed mid-fling never all got a player.
      expect(rig.embeds.history.length, lessThan(5));
    });

    testWidgets('loads the next page near the end, then shows the end page', (
      tester,
    ) async {
      final rig = await _pumpFeed(
        tester,
        reply: (offset) =>
            FakeReply(200, offset == 0 ? _page(0, 10) : _page(10, 1)),
      );

      for (var i = 0; i < 8; i++) {
        await _swipeUp(tester);
      }
      expect(find.text('Short 8'), findsOneWidget);
      expect(
        rig.h.backend
            .requestsTo('GET', _shortsPath)
            .map((r) => r.queryParameters['offset'])
            .toList(),
        [0, 10],
      );

      for (var i = 0; i < 3; i++) {
        await _swipeUp(tester);
      }
      expect(find.byKey(const Key('videos.shorts.end')), findsOneWidget);
      expect(rig.embeds.mounted, isEmpty);
    });

    testWidgets('an empty feed explains that grown-ups check videos', (
      tester,
    ) async {
      final rig = await _pumpFeed(tester);

      expect(find.byKey(const Key('videos.shorts.empty')), findsOneWidget);
      expect(rig.embeds.history, isEmpty);
      expect(rig.players.created, isEmpty);
    });

    testWidgets('an API failure offers a retry that loads the feed', (
      tester,
    ) async {
      var calls = 0;
      final rig = await _pumpFeed(
        tester,
        reply: (_) {
          calls++;
          return calls == 1
              ? FakeReply.error(500, 'internal_error', 'boom')
              : FakeReply(200, _page(0, 1));
        },
      );

      expect(find.byKey(const Key('videos.shorts.error')), findsOneWidget);
      expect(rig.embeds.history, isEmpty);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Short 0'), findsOneWidget);
      expect(rig.embeds.only().videoId, _ytId(0));
    });

    testWidgets('a failed next page keeps earlier Shorts and can retry', (
      tester,
    ) async {
      var failNext = true;
      await _pumpFeed(
        tester,
        reply: (offset) {
          if (offset == 0) return FakeReply(200, _page(0, 10));
          if (failNext) {
            failNext = false;
            return FakeReply.error(503, 'unavailable', 'later');
          }
          return FakeReply(200, _page(10, 2));
        },
      );
      for (var i = 0; i < 10; i++) {
        await _swipeUp(tester);
      }
      expect(find.byKey(const Key('videos.shorts.pageError')), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Short 10'), findsOneWidget);
    });

    testWidgets('a hosted Short is shown locked and never played', (
      tester,
    ) async {
      final rig = await _pumpFeed(
        tester,
        shorts: [_short(id: 'h1', title: 'Hosted one', source: 'hosted')],
      );

      expect(
        find.byKey(const Key('videos.shorts.unavailable')),
        findsOneWidget,
      );
      expect(
        find.text('This video unlocks with a reward from your grown-up.'),
        findsOneWidget,
      );
      expect(rig.embeds.history, isEmpty);
      expect(rig.players.created, isEmpty);
      // Hosted media has no link, so nothing can be shared.
      expect(find.byKey(const Key('videos.shorts.share')), findsNothing);
    });

    testWidgets('a video YouTube refuses to embed says so, without retry', (
      tester,
    ) async {
      final rig = await _pumpFeed(tester, shorts: _page(0, 2));

      rig.embeds.only().onBlocked!();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('videos.shorts.blocked')), findsOneWidget);
      expect(find.byKey(const Key('videos.shorts.retry')), findsNothing);
      expect(rig.embeds.mounted, isEmpty);

      // The child can still move on.
      await _swipeUp(tester);
      expect(rig.embeds.only().videoId, _ytId(1));
    });

    testWidgets('a load failure can be retried with a fresh embed', (
      tester,
    ) async {
      final rig = await _pumpFeed(tester, shorts: _page(0, 1));

      rig.embeds.only().onError();
      await tester.pumpAndSettle();
      expect(rig.embeds.mounted, isEmpty);
      await tester.tap(find.byKey(const Key('videos.shorts.retry')));
      await tester.pumpAndSettle();
      expect(rig.embeds.only().videoId, _ytId(0));
      expect(rig.embeds.history, hasLength(2));
    });

    testWidgets('links inside the player never leave without a grown-up', (
      tester,
    ) async {
      final rig = await _pumpFeed(tester, shorts: _page(0, 1));
      final link = Uri.parse('https://www.youtube.com/watch?v=${_ytId(0)}');

      rig.embeds.only().onLeaveRequested(link);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('youtube.leaveGate')), findsOneWidget);
      await tester.tap(find.byKey(const Key('youtube.leaveStay')));
      await tester.pumpAndSettle();
      expect(rig.opener.opened, isEmpty);

      rig.embeds.only().onLeaveRequested(link);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('youtube.leaveOpen')));
      await tester.pumpAndSettle();
      expect(rig.opener.opened, [link]);
    });

    testWidgets('the sound button mutes the active player', (tester) async {
      final rig = await _pumpFeed(tester, shorts: _page(0, 2));

      expect(rig.embeds.only().muted, isFalse);
      await tester.tap(find.byKey(const Key('videos.shorts.mute')));
      await tester.pumpAndSettle();
      expect(rig.embeds.only().muted, isTrue);

      // The choice carries over to the next Short.
      await _swipeUp(tester);
      expect(rig.embeds.only().muted, isTrue);
    });

    testWidgets('sharing asks a grown-up first and shares the watch link', (
      tester,
    ) async {
      final rig = await _pumpFeed(tester, shorts: _page(0, 1));

      await tester.tap(find.byKey(const Key('videos.shorts.share')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('video.shareGate')), findsOneWidget);
      await tester.tap(find.byKey(const Key('video.shareCancel')));
      await tester.pumpAndSettle();
      expect(rig.sharer.shared, isEmpty);

      await tester.tap(find.byKey(const Key('videos.shorts.share')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('video.shareConfirm')));
      await tester.pumpAndSettle();
      expect(
        rig.sharer.shared.single,
        contains('youtube.com/watch?v=${_ytId(0)}'),
      );
    });

    testWidgets('a grown-up can report the Short', (tester) async {
      await _pumpFeed(tester, shorts: _page(0, 1));

      await tester.tap(find.byKey(const Key('videos.shorts.report')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('youtube.reportDialog')), findsOneWidget);
    });

    testWidgets('opens at the Short tapped on Home without refetching it', (
      tester,
    ) async {
      final seeded = [for (final json in _page(0, 3)) FeedVideo.fromJson(json)];
      final rig = await _pumpFeed(
        tester,
        shorts: _page(3, 2),
        launch: ShortsLaunch(
          initialVideos: seeded,
          initialIndex: 2,
          nextOffset: 3,
        ),
      );

      expect(find.text('Short 2'), findsOneWidget);
      expect(rig.embeds.only().videoId, _ytId(2));
      // Close to the end of the seeded list, so the NEXT page is fetched.
      expect(
        rig.h.backend
            .requestsTo('GET', _shortsPath)
            .map((r) => r.queryParameters['offset']),
        [3],
      );
    });

    testWidgets('leaving the screen disposes the player', (tester) async {
      final rig = await _pumpFeed(tester, shorts: _page(0, 2));
      expect(rig.embeds.mounted, hasLength(1));

      await tester.pumpWidget(const SizedBox());
      expect(rig.embeds.mounted, isEmpty);
    });

    for (final (code, title) in [('hi', 'शॉर्ट्स'), ('gu', 'શોર્ટ્સ')]) {
      testWidgets('is translated and fits 320 px in $code', (tester) async {
        await _pumpFeed(
          tester,
          shorts: [
            _short(
              id: 's1',
              title: 'A rather long title that needs to wrap on a phone',
              youtubeId: _ytId(1),
              description: 'A description long enough to need two lines.',
            ),
            _short(id: 's2', title: 'Second', youtubeId: _ytId(2)),
          ],
          locale: Locale(code),
          size: const Size(320, 640),
        );

        expect(find.text(title), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('fits a landscape phone', (tester) async {
      await _pumpFeed(tester, shorts: _page(0, 2), size: const Size(740, 360));
      expect(tester.takeException(), isNull);
      expect(find.text('Short 0'), findsOneWidget);
    });
  });

  group('Mixed YouTube and hosted-stream pager', () {
    const a = 'https://cdn.example.org/a.mp4';
    const c = 'https://cdn.example.org/c.mp4';
    const d = 'https://cdn.example.org/d.mp4';

    PlayableVideo stream(String key, String url) => PlayableVideo(
      key: key,
      title: 'Stream $key',
      source: DirectStreamSource(Uri.parse(url)),
    );

    final mixed = [
      stream('a', a),
      PlayableVideo(
        key: 'b',
        title: 'YouTube b',
        source: YouTubeVideoSource(_ytId(7)),
      ),
      stream('c', c),
      stream('d', d),
    ];

    Future<(EmbedRecorder, PlaybackRegistry)> pumpPager(
      WidgetTester tester, {
      List<PlayableVideo>? videos,
      String? failing,
      double aspect = 9 / 16,
      Size size = const Size(393, 852),
    }) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      final embeds = EmbedRecorder();
      final players = PlaybackRegistry()
        ..failUrlsContaining = failing
        ..aspect = aspect;
      await pumpScreen(
        tester,
        Scaffold(body: ShortsPlayerPager(videos: videos ?? mixed)),
        overrides: [
          ...h.overrides,
          youtubeEmbedBuilderProvider.overrideWithValue(embeds.build),
          videoPlaybackControllerFactoryProvider.overrideWithValue(
            players.create,
          ),
        ],
        size: size,
      );
      return (embeds, players);
    }

    int activePlayers(EmbedRecorder e, PlaybackRegistry p) =>
        e.mounted.length + p.playing.length;

    testWidgets('only the settled page plays; the next stream is prepared', (
      tester,
    ) async {
      final (embeds, players) = await pumpPager(tester);

      expect(players.forUrl(a).single.isPlaying, isTrue);
      expect(embeds.mounted, isEmpty);
      expect(activePlayers(embeds, players), 1);
      // Page b is YouTube: no web view is created until it is on screen.
      expect(embeds.history, isEmpty);
    });

    testWidgets('swiping pauses and releases the previous player', (
      tester,
    ) async {
      final (embeds, players) = await pumpPager(tester);
      final first = players.forUrl(a).single;

      await _swipeUp(tester); // to b (YouTube)
      expect(first.disposed, isTrue);
      expect(embeds.only().videoId, _ytId(7));
      final next = players.forUrl(c).single;
      expect(next.isInitialised, isTrue, reason: 'next stream is preloaded');
      expect(next.isPlaying, isFalse);
      expect(activePlayers(embeds, players), 1);

      await _swipeUp(tester); // to c (stream)
      expect(embeds.mounted, isEmpty);
      expect(next.isPlaying, isTrue);
      expect(players.forUrl(c), hasLength(1), reason: 'preloaded one reused');
      final after = players.forUrl(d).single;
      expect(after.isPlaying, isFalse);
      expect(activePlayers(embeds, players), 1);

      await _swipeDown(tester); // back to b
      expect(next.isPlaying, isFalse);
      expect(after.disposed, isTrue);
      expect(embeds.only().videoId, _ytId(7));
      expect(activePlayers(embeds, players), 1);
    });

    testWidgets('never more than two stream controllers are alive', (
      tester,
    ) async {
      final videos = [
        for (var i = 0; i < 8; i++)
          stream('s$i', 'https://cdn.example.org/$i.mp4'),
      ];
      final (_, players) = await pumpPager(tester, videos: videos);

      for (var i = 0; i < 7; i++) {
        await _swipeUp(tester);
        expect(players.live.length, lessThanOrEqualTo(2));
        expect(players.playing, hasLength(1));
      }
    });

    testWidgets('backgrounding pauses the stream and returning resumes it', (
      tester,
    ) async {
      final (_, players) = await pumpPager(tester);
      final first = players.forUrl(a).single;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(first.isPlaying, isFalse);
      expect(first.disposed, isFalse, reason: 'position is kept');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(first.isPlaying, isTrue);
    });

    testWidgets('tapping a stream pauses it and tapping again resumes', (
      tester,
    ) async {
      final (_, players) = await pumpPager(tester);
      final first = players.forUrl(a).single;

      await tester.tap(find.byKey(const Key('videos.shorts.tapToPause')));
      await tester.pumpAndSettle();
      expect(first.isPlaying, isFalse);
      expect(find.byKey(const Key('videos.shorts.paused')), findsOneWidget);

      await tester.tap(find.byKey(const Key('videos.shorts.tapToPause')));
      await tester.pumpAndSettle();
      expect(first.isPlaying, isTrue);
    });

    testWidgets('a stream that fails can be retried', (tester) async {
      final (_, players) = await pumpPager(tester, failing: 'a.mp4');

      expect(find.byKey(const Key('videos.shorts.retry')), findsOneWidget);
      expect(players.playing, isEmpty);
      players.failUrlsContaining = null;
      await tester.tap(find.byKey(const Key('videos.shorts.retry')));
      await tester.pumpAndSettle();
      expect(players.forUrl(a), hasLength(2));
      expect(players.forUrl(a).first.disposed, isTrue);
      expect(players.forUrl(a).last.isPlaying, isTrue);
    });

    testWidgets('a network drop mid-playback shows retry', (tester) async {
      final (_, players) = await pumpPager(tester);

      players.forUrl(a).single.failNow();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('videos.shorts.retry')), findsOneWidget);
    });

    testWidgets('a portrait stream fills the page edge to edge', (
      tester,
    ) async {
      await pumpPager(tester, aspect: 9 / 16);
      expect(find.byKey(const Key('videos.shorts.fit.cover')), findsOneWidget);
      final stage = tester.getRect(
        find.byKey(const Key('videos.shorts.fit.cover')),
      );
      expect(stage.size, const Size(393, 852));
    });

    testWidgets('a landscape stream is shown whole, never cropped', (
      tester,
    ) async {
      await pumpPager(tester, aspect: 16 / 9);
      expect(
        find.byKey(const Key('videos.shorts.fit.contain')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('videos.shorts.fit.cover')), findsNothing);
    });

    testWidgets('a landscape phone shows a portrait stream whole', (
      tester,
    ) async {
      await pumpPager(tester, size: const Size(740, 360));
      expect(
        find.byKey(const Key('videos.shorts.fit.contain')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping an action never pauses or swipes the video', (
      tester,
    ) async {
      final (_, players) = await pumpPager(
        tester,
        videos: [
          PlayableVideo(
            key: 'a',
            title: 'Stream a',
            description: 'All about a.',
            source: DirectStreamSource(Uri.parse(a)),
          ),
        ],
      );
      final first = players.forUrl(a).single;
      // The details toggle sits over the video; tapping it must not reach
      // the tap-to-pause layer underneath.
      await tester.tap(find.byKey(const Key('videos.shorts.more')));
      await tester.pumpAndSettle();
      expect(first.isPlaying, isTrue);
      expect(find.text('Stream a'), findsOneWidget);
    });

    testWidgets('removing the pager disposes every controller', (tester) async {
      final (embeds, players) = await pumpPager(tester);
      await _swipeUp(tester);
      expect(players.live, isNotEmpty);

      await tester.pumpWidget(const SizedBox());
      expect(players.live, isEmpty);
      expect(embeds.mounted, isEmpty);
    });
  });

  group('PlayableVideo source mapping', () {
    FeedVideo feed(String source, {String? youtubeId}) => FeedVideo(
      id: 'v1',
      title: 'T',
      durationSeconds: 30,
      source: source,
      youtubeVideoId: youtubeId,
    );

    test('an approved YouTube feed video plays in the official embed', () {
      final video = PlayableVideo.fromFeed(
        feed('youtube', youtubeId: _ytId(1)),
      );
      expect(video.source, YouTubeVideoSource(_ytId(1)));
      expect(video.reportVideoId, 'v1');
      expect(
        video.shareUri.toString(),
        'https://www.youtube.com/watch?v=${_ytId(1)}',
      );
    });

    test('a hosted feed video is never played from a feed', () {
      final video = PlayableVideo.fromFeed(feed('hosted'));
      expect(
        video.source,
        const UnavailableSource(VideoUnavailableReason.needsGrownUp),
      );
      expect(video.isPlayable, isFalse);
      expect(video.shareUri, isNull);
    });

    test('a malformed YouTube id is not playable', () {
      final video = PlayableVideo.fromFeed(feed('youtube', youtubeId: 'bad'));
      expect(video.isPlayable, isFalse);
    });

    LearningItem item({String? url, bool locked = false, String? videoId}) =>
        LearningItem(
          id: 'l1',
          title: 'L',
          contentType: 'video',
          contentUrl: url,
          requiresEntitlement: locked,
          videoId: videoId,
        );

    test('a curated YouTube page is never treated as a media stream', () {
      for (final url in [
        'https://www.youtube.com/watch?v=${_ytId(3)}',
        'https://youtu.be/${_ytId(3)}',
        'https://www.youtube.com/shorts/${_ytId(3)}',
      ]) {
        final video = PlayableVideo.fromLearning(item(url: url));
        expect(video.source, YouTubeVideoSource(_ytId(3)), reason: url);
      }
      final channel = PlayableVideo.fromLearning(
        item(url: 'https://www.youtube.com/@somechannel'),
      );
      expect(channel.source, isNot(isA<DirectStreamSource>()));
      expect(channel.isPlayable, isFalse);
    });

    test('a curated direct link is a stream', () {
      final video = PlayableVideo.fromLearning(
        item(url: 'https://cdn.example.org/a.mp4'),
      );
      expect(
        video.source,
        DirectStreamSource(Uri.parse('https://cdn.example.org/a.mp4')),
      );
    });

    test('reward-locked and hosted items keep their entitlement rules', () {
      expect(
        PlayableVideo.fromLearning(
          item(url: 'https://cdn.example.org/a.mp4', locked: true),
        ).source,
        const UnavailableSource(VideoUnavailableReason.needsGrownUp),
      );
      expect(
        PlayableVideo.fromLearning(item(videoId: 'hosted-row')).source,
        const UnavailableSource(VideoUnavailableReason.needsGrownUp),
      );
    });

    test('an insecure link is never played', () {
      expect(
        PlayableVideo.fromLearning(
          item(url: 'http://cdn.example.org/a.mp4'),
        ).isPlayable,
        isFalse,
      );
    });
  });

  group('Paging helpers', () {
    test('a seeded pager continues from the given offset', () {
      final pager = VideoFeedPager(
        VideoFeedRepository(createTestDio(FakeBackend(), AccessTokenStore())),
        VideoFeedKind.shorts,
        initialItems: [
          for (final json in _page(0, 2)) FeedVideo.fromJson(json),
        ],
        initialOffset: 5,
      );
      expect(pager.items, hasLength(2));
      expect(pager.nextOffset, 5);
      expect(pager.status, PagerStatus.idle);
      pager.dispose();
    });

    test('the category filter is sent only when chosen', () async {
      final backend = FakeBackend()
        ..reply('GET', '/api/v1/videos/feed', <Object?>[]);
      final repository = VideoFeedRepository(
        createTestDio(backend, AccessTokenStore()),
      );

      await repository.page(VideoFeedKind.learn, limit: 5, offset: 0);
      await repository.page(
        VideoFeedKind.learn,
        limit: 5,
        offset: 0,
        categoryId: 'cat-1',
      );
      final requests = backend.requestsTo('GET', '/api/v1/videos/feed');
      expect(
        requests.first.queryParameters.containsKey('category_id'),
        isFalse,
      );
      expect(requests.last.queryParameters['category_id'], 'cat-1');
    });
  });

  group('Immersive Shorts layout', () {
    testWidgets('the YouTube player fills the screen below the top bar', (
      tester,
    ) async {
      final rig = await _pumpFeed(tester, shorts: _page(0, 2));

      final config = rig.embeds.only();
      // Not the 16:9 landscape player any more: the box is the page's shape.
      expect(config.aspectRatio, isNotNull);
      expect(config.aspectRatio!, lessThan(1));
      final player = tester.getRect(
        find.byKey(Key('test.youtubeEmbed.${_ytId(0)}')),
      );
      expect(player.width, 393);
      expect(player.height, greaterThan(852 * 0.85));
      expect(player.bottom, closeTo(852, 1));
    });

    testWidgets('details and actions sit on the video, not in a panel', (
      tester,
    ) async {
      final rig = await _pumpFeed(
        tester,
        shorts: [
          _short(
            id: 's1',
            title: 'Rainbows',
            youtubeId: _ytId(1),
            description: 'Light bends in raindrops. #science #weather',
          ),
        ],
      );
      expect(rig.embeds.mounted, hasLength(1));
      final player = tester.getRect(
        find.byKey(Key('test.youtubeEmbed.${_ytId(1)}')),
      );
      for (final key in [
        'videos.shorts.title',
        'videos.shorts.channel',
        'videos.shorts.share',
        'videos.shorts.report',
        'videos.shorts.mute',
      ]) {
        final finder = find.byKey(Key(key));
        expect(
          find.descendant(
            of: find.byKey(Key('test.youtubeEmbed.${_ytId(1)}')),
            matching: finder,
          ),
          findsOneWidget,
          reason: '$key is drawn over the video',
        );
        expect(player.contains(tester.getCenter(finder)), isTrue);
      }
      // Actions are a right-hand column; details are bottom left.
      final share = tester.getCenter(
        find.byKey(const Key('videos.shorts.share')),
      );
      final title = tester.getRect(
        find.byKey(const Key('videos.shorts.title')),
      );
      expect(share.dx, greaterThan(393 * 0.8));
      expect(title.left, lessThan(393 * 0.2));
      expect(title.bottom, greaterThan(player.top + player.height * 0.6));
      // YouTube's own control bar keeps its strip at the bottom.
      final progress = tester.getRect(
        find.byKey(const Key('videos.shorts.progress')),
      );
      expect(
        player.bottom - progress.bottom,
        closeTo(kYouTubeControlsReserve, 0.5),
      );
    });

    testWidgets('hashtags show separately; the description expands', (
      tester,
    ) async {
      await _pumpFeed(
        tester,
        shorts: [
          _short(
            id: 's1',
            title: 'Rainbows',
            youtubeId: _ytId(1),
            description: 'Light bends in raindrops. #science #weather',
          ),
        ],
      );

      expect(find.text('#science #weather'), findsOneWidget);
      expect(find.text('Light bends in raindrops.'), findsOneWidget);
      expect(find.text('more'), findsOneWidget);
      await tester.tap(find.byKey(const Key('videos.shorts.more')));
      await tester.pumpAndSettle();
      expect(find.text('less'), findsOneWidget);
      expect(
        find.text(
          "Videos from YouTube play in YouTube's own player and may show ads.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('a short shows its duration only when the server knows it', (
      tester,
    ) async {
      await _pumpFeed(
        tester,
        shorts: [
          {..._short(id: 'k', title: 'Known', youtubeId: _ytId(1))},
          {
            ..._short(id: 'u', title: 'Unknown', youtubeId: _ytId(2)),
            'duration_seconds': null,
            'video_format': 'unknown',
          },
        ],
      );
      expect(find.byKey(const Key('videos.shorts.duration')), findsOneWidget);
      await _swipeUp(tester);
      expect(find.text('Unknown'), findsOneWidget);
      expect(find.byKey(const Key('videos.shorts.duration')), findsNothing);
    });

    testWidgets('the back button leaves the feed', (tester) async {
      final rig = await _pumpFeed(tester, shorts: _page(0, 1));
      expect(find.byKey(const Key('videos.shorts.back')), findsOneWidget);
      // The top bar is outside the player so YouTube's title bar stays clear.
      final back = tester.getRect(find.byKey(const Key('videos.shorts.back')));
      final player = tester.getRect(
        find.byKey(Key('test.youtubeEmbed.${_ytId(0)}')),
      );
      expect(back.bottom, lessThanOrEqualTo(player.top));
      expect(rig.embeds.mounted, hasLength(1));
    });
  });

  group('Fit rule', () {
    const phone = 393 / 852;
    test('portrait close to the screen shape fills it', () {
      expect(shortsFitFor(videoAspect: 9 / 16, boxAspect: phone), BoxFit.cover);
      expect(shortsFitFor(videoAspect: 3 / 4, boxAspect: 0.6), BoxFit.cover);
    });

    test('landscape, square and odd shapes are shown whole', () {
      expect(
        shortsFitFor(videoAspect: 16 / 9, boxAspect: phone),
        BoxFit.contain,
      );
      expect(shortsFitFor(videoAspect: 1, boxAspect: phone), BoxFit.contain);
      expect(
        shortsFitFor(videoAspect: 9 / 32, boxAspect: phone),
        BoxFit.contain,
      );
      expect(
        shortsFitFor(videoAspect: 9 / 16, boxAspect: 740 / 360),
        BoxFit.contain,
      );
      expect(shortsFitFor(videoAspect: 0, boxAspect: phone), BoxFit.contain);
    });
  });

  group('Server classification label', () {
    Map<String, Object?> json(Object? format, Object? seconds) => {
      ..._short(id: 'x', title: 'X', youtubeId: _ytId(1)),
      'video_format': format,
      'duration_seconds': seconds,
    };

    test('the app shows exactly what the server decided', () {
      expect(FeedVideo.fromJson(json('short', 45)).format, VideoFormat.short);
      expect(
        FeedVideo.fromJson(json('regular', 61)).format,
        VideoFormat.regular,
      );
      final unknown = PlayableVideo.fromFeed(
        FeedVideo.fromJson(json('unknown', null)),
      );
      expect(unknown.format, VideoFormat.unknown);
      expect(unknown.duration, isNull);
    });

    test('an older server without labels is treated as regular', () {
      final legacy = FeedVideo.fromJson(json(null, 30)..remove('video_format'));
      expect(legacy.format, VideoFormat.regular);
    });

    test('hashtags keep Hindi and Gujarati vowel signs', () {
      const video = PlayableVideo(
        key: 'k',
        title: 't',
        description: 'देखो #विज्ञान और #ગણિત #science #Science',
        source: UnavailableSource(VideoUnavailableReason.noSource),
      );
      expect(video.hashtags, ['#विज्ञान', '#ગણિત', '#science']);
      expect(video.descriptionWithoutHashtags, 'देखो और');
    });
  });
}
