import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/features/learning/data/video_feed_repository.dart';
import 'package:balkavach_app/features/learning/data/youtube_embed_policy.dart';
import 'package:balkavach_app/features/learning/presentation/video_feed_screen.dart';
import 'package:balkavach_app/features/learning/presentation/youtube_player_screen.dart';
import 'package:balkavach_app/shared/platform/link_opener.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _ytId = 'dQw4w9WgXcQ';

Map<String, Object?> _video({
  String id = 'v1',
  String title = 'Why is the sky blue?',
  String source = 'youtube',
  String? youtubeId = _ytId,
  int duration = 125,
}) => {
  'id': id,
  'title': title,
  'description': null,
  'thumbnail_url': null,
  'duration_seconds': duration,
  'category_id': null,
  'language_code': 'en',
  'content_rating': 'educational',
  'video_source': source,
  'youtube_video_id': youtubeId,
};

List<Map<String, Object?>> _page(int start, int count) => [
  for (var i = start; i < start + count; i++)
    _video(id: 'v$i', title: 'Video $i'),
];

class _FakeOpener implements LinkOpener {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

class _FakeRepository implements VideoFeedRepository {
  _FakeRepository(this.pages);

  /// Replies by offset; a missing offset throws a network error.
  final Map<int, List<FeedVideo>> pages;
  final offsets = <int>[];

  @override
  Future<List<FeedVideo>> page(
    VideoFeedKind kind, {
    required int limit,
    required int offset,
  }) async {
    offsets.add(offset);
    final page = pages[offset];
    if (page == null) throw const NetworkException();
    return page;
  }

  @override
  Future<void> report(
    String videoId,
    VideoReportReason reason, {
    String? details,
  }) async {}
}

List<FeedVideo> _feed(int start, int count) =>
    _page(start, count).map(FeedVideo.fromJson).toList();

void main() {
  group('FeedVideo', () {
    test('only a YouTube item with a well-formed id is playable', () {
      expect(FeedVideo.fromJson(_video()).isYouTube, isTrue);
      expect(FeedVideo.fromJson(_video(youtubeId: 'bad')).isYouTube, isFalse);
      expect(FeedVideo.fromJson(_video(youtubeId: null)).isYouTube, isFalse);
      expect(
        FeedVideo.fromJson(_video(source: 'hosted', youtubeId: null)).isYouTube,
        isFalse,
      );
      expect(
        FeedVideo.fromJson(
          _video(youtubeId: 'https://evil.example/watch?v=x'),
        ).isYouTube,
        isFalse,
      );
    });
  });

  group('repository', () {
    test('learn and shorts call their own endpoints with paging', () async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend
        ..reply('GET', '/api/v1/videos/feed', [_video()])
        ..reply('GET', '/api/v1/videos/shorts', <Object?>[]);
      final repo = h.container().read(videoFeedRepositoryProvider);
      final learn = await repo.page(VideoFeedKind.learn, limit: 20, offset: 40);
      final shorts = await repo.page(
        VideoFeedKind.shorts,
        limit: 20,
        offset: 0,
      );
      expect(learn.single.youtubeVideoId, _ytId);
      expect(shorts, isEmpty);
      expect(
        h.backend
            .requestsTo('GET', '/api/v1/videos/feed')
            .single
            .queryParameters,
        {'limit': 20, 'offset': 40},
      );
    });

    test('report sends only the video, reason and trimmed details', () async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply('POST', '/api/v1/videos/report', {
        'id': 'r1',
        'status': 'open',
      }, status: 201);
      await h
          .container()
          .read(videoFeedRepositoryProvider)
          .report('v1', VideoReportReason.scary, details: '  loud noises ');
      expect(
        h.backend.requestsTo('POST', '/api/v1/videos/report').single.data,
        {'video_id': 'v1', 'reason': 'scary', 'details': 'loud noises'},
      );
    });

    test('no YouTube API call or key ever leaves the app', () async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply('GET', '/api/v1/videos/feed', [_video()]);
      await h
          .container()
          .read(videoFeedRepositoryProvider)
          .page(VideoFeedKind.learn, limit: 20, offset: 0);
      for (final request in h.backend.requests) {
        expect(request.uri.host, isNot(contains('googleapis')));
        expect(request.uri.queryParameters.keys, isNot(contains('key')));
        expect(request.headers.keys, isNot(contains('X-Goog-Api-Key')));
      }
    });
  });

  group('VideoFeedPager', () {
    test('pages forward, de-duplicates and stops on a short page', () async {
      final repo = _FakeRepository({
        0: _feed(0, 3),
        // The server shifted by one: v2 comes back again.
        3: _feed(2, 3),
        6: _feed(5, 1),
      });
      final pager = VideoFeedPager(repo, VideoFeedKind.learn, pageSize: 3);
      await pager.loadMore();
      await pager.loadMore();
      expect(pager.items.map((v) => v.id), ['v0', 'v1', 'v2', 'v3', 'v4']);
      expect(pager.hasMore, isTrue);
      await pager.loadMore();
      expect(pager.status, PagerStatus.done);
      await pager.loadMore();
      expect(repo.offsets, [0, 3, 6]);
    });

    test('a failed page can be retried without losing earlier items', () async {
      final repo = _FakeRepository({0: _feed(0, 2)});
      final pager = VideoFeedPager(repo, VideoFeedKind.shorts, pageSize: 2);
      await pager.loadMore();
      await pager.loadMore();
      expect(pager.status, PagerStatus.error);
      expect(pager.error, isA<NetworkException>());
      expect(pager.items, hasLength(2));
      repo.pages[2] = _feed(2, 1);
      await pager.retry();
      expect(pager.items, hasLength(3));
      expect(pager.status, PagerStatus.done);
    });

    test('concurrent loads collapse into one request', () async {
      final repo = _FakeRepository({0: _feed(0, 2)});
      final pager = VideoFeedPager(repo, VideoFeedKind.learn, pageSize: 2);
      await Future.wait([pager.loadMore(), pager.loadMore()]);
      expect(repo.offsets, [0]);
    });
  });

  group('player navigation policy', () {
    const base = 'https://www.youtube-nocookie.com';

    PlayerNavigation decide(String url, {bool mainFrame = true}) =>
        decidePlayerNavigation(url, isMainFrame: mainFrame, baseUrl: base);

    test('the player page and its frames load', () {
      expect(decide(base), PlayerNavigation.allow);
      expect(decide('$base/'), PlayerNavigation.allow);
      expect(decide('about:blank'), PlayerNavigation.allow);
      expect(
        decide('$base/embed/$_ytId', mainFrame: false),
        PlayerNavigation.allow,
      );
    });

    test('related videos, title, logo and ads leave only after a gate', () {
      for (final url in [
        'https://www.youtube.com/watch?v=aaaaaaaaaaa&feature=emb_rel_end',
        'https://www.youtube.com/watch?v=$_ytId&feature=emb_title',
        'https://www.youtube.com/channel/UC123',
        'https://www.googleadservices.com/pagead/aclk?x=1',
        '$base/watch?v=aaaaaaaaaaa',
      ]) {
        expect(decide(url), PlayerNavigation.openOutsideAfterGate, reason: url);
      }
    });

    test('other schemes are blocked', () {
      for (final url in [
        'intent://evil#Intent;end',
        'javascript:alert(1)',
        'http://example.com',
        'market://details?id=x',
      ]) {
        expect(decide(url), PlayerNavigation.block, reason: url);
      }
    });
  });

  group('feed screen', () {
    Future<Harness> pump(
      WidgetTester tester, {
      required FakeReply Function(RequestOptions) learn,
      List<Map<String, Object?>> shorts = const [],
    }) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..on('GET', '/api/v1/videos/feed', learn)
        ..reply('GET', '/api/v1/videos/shorts', shorts);
      await pumpScreen(tester, const VideoFeedScreen(), overrides: h.overrides);
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('lists approved videos and asks for shorts separately', (
      tester,
    ) async {
      final h = await pump(
        tester,
        learn: (_) => FakeReply(200, [_video(title: 'Sky')]),
        shorts: [_video(id: 's1', title: 'Quick frog', duration: 40)],
      );
      expect(find.text('Sky'), findsOneWidget);
      expect(find.text('2:05'), findsOneWidget);

      await tester.tap(find.byKey(const Key('videos.tab.shorts')));
      await tester.pumpAndSettle();
      expect(find.text('Quick frog'), findsOneWidget);
      expect(
        h.backend.requestsTo('GET', '/api/v1/videos/shorts'),
        hasLength(1),
      );
    });

    testWidgets('empty feed explains that grown-ups check videos', (
      tester,
    ) async {
      await pump(tester, learn: (_) => const FakeReply(200, <Object?>[]));
      expect(find.byKey(const Key('videos.learn.empty')), findsOneWidget);
      expect(
        find.text(
          'No videos here yet. A grown-up checks every video before it appears.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('error state retries', (tester) async {
      var calls = 0;
      await pump(
        tester,
        learn: (_) {
          calls++;
          return calls == 1
              ? FakeReply.error(500, 'internal_error', 'x')
              : const FakeReply(200, <Object?>[]);
        },
      );
      expect(find.byKey(const Key('videos.learn.error')), findsOneWidget);

      await tester.tap(find.text('Try again').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('videos.learn.empty')), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('scrolling to the end loads the next page once', (
      tester,
    ) async {
      final h = await pump(
        tester,
        learn: (options) {
          final offset = options.queryParameters['offset'] as int;
          return FakeReply(200, offset == 0 ? _page(0, 20) : _page(20, 2));
        },
      );
      await tester.drag(
        find.byKey(const Key('videos.learn.list')),
        const Offset(0, -6000),
      );
      await tester.pumpAndSettle();
      final offsets = h.backend
          .requestsTo('GET', '/api/v1/videos/feed')
          .map((r) => r.queryParameters['offset'])
          .toList();
      expect(offsets, [0, 20]);
      await tester.drag(
        find.byKey(const Key('videos.learn.list')),
        const Offset(0, -6000),
      );
      await tester.pumpAndSettle();
      expect(find.text('Video 21'), findsOneWidget);
      expect(h.backend.requestsTo('GET', '/api/v1/videos/feed'), hasLength(2));
    });
  });

  group('YouTube player screen', () {
    Future<(Harness, _FakeOpener, List<YouTubeEmbedConfig>)> pump(
      WidgetTester tester, {
      Map<String, Object?>? video,
    }) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      final opener = _FakeOpener();
      final configs = <YouTubeEmbedConfig>[];
      await pumpScreen(
        tester,
        YouTubePlayerScreen(video: FeedVideo.fromJson(video ?? _video())),
        overrides: [
          ...h.overrides,
          linkOpenerProvider.overrideWithValue(opener),
          youtubeEmbedBuilderProvider.overrideWithValue((config) {
            configs.add(config);
            return const ColoredBox(
              key: Key('fake.embed'),
              color: Colors.black,
            );
          }),
        ],
      );
      await tester.pumpAndSettle();
      return (h, opener, configs);
    }

    testWidgets('embeds only the approved id and says ads may appear', (
      tester,
    ) async {
      final (_, _, configs) = await pump(tester);
      expect(find.byKey(const Key('fake.embed')), findsOneWidget);
      expect(configs.last.videoId, _ytId);
      expect(
        find.text(
          "Videos from YouTube play in YouTube's own player and may show ads.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('leaving the player needs a grown-up', (tester) async {
      final (_, opener, configs) = await pump(tester);
      final link = Uri.parse('https://www.youtube.com/watch?v=aaaaaaaaaaa');

      configs.last.onLeaveRequested(link);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('youtube.leaveGate')), findsOneWidget);
      await tester.tap(find.byKey(const Key('youtube.leaveStay')));
      await tester.pumpAndSettle();
      expect(opener.opened, isEmpty);

      configs.last.onLeaveRequested(link);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('youtube.leaveOpen')));
      await tester.pumpAndSettle();
      expect(opener.opened, [link]);
    });

    testWidgets('a foreign video is announced and errors show a message', (
      tester,
    ) async {
      final (_, _, configs) = await pump(tester);
      configs.last.onForeignVideo();
      await tester.pump();
      expect(
        find.text("That video isn't in Bal Kavach, so it can't play here."),
        findsOneWidget,
      );
      configs.last.onError();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('youtube.error')), findsOneWidget);
      expect(find.byKey(const Key('fake.embed')), findsNothing);
    });

    testWidgets('a malformed id never reaches the embed', (tester) async {
      final (_, _, configs) = await pump(tester, video: _video(youtubeId: 'x'));
      expect(configs, isEmpty);
      expect(find.byKey(const Key('youtube.error')), findsOneWidget);
    });

    testWidgets('a grown-up can report the video', (tester) async {
      final (h, _, _) = await pump(tester);
      h.backend.reply('POST', '/api/v1/videos/report', {
        'id': 'r1',
        'status': 'open',
      }, status: 201);
      await tester.ensureVisible(find.byKey(const Key('youtube.report')));
      await tester.tap(find.byKey(const Key('youtube.report')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('youtube.reportDialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('youtube.reason.scary')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('youtube.reportSend')));
      await tester.pumpAndSettle();
      expect(
        h.backend.requestsTo('POST', '/api/v1/videos/report').single.data,
        {'video_id': 'v1', 'reason': 'scary'},
      );
      expect(
        find.text('Thank you. Our team will review this video.'),
        findsOneWidget,
      );
    });
  });
}
