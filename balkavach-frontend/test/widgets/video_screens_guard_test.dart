// Exhaustion / offline / resume behaviour of the regular and YouTube player
// screens, against PLAYER MOCKS and a FAKE BACKEND. Not real playback
// verification: a real YouTube iframe on a device is still to be checked.

import 'package:balkavach_app/features/learning/data/playable_video.dart';
import 'package:balkavach_app/features/learning/data/video_feed_repository.dart';
import 'package:balkavach_app/features/learning/data/video_playback_controller.dart';
import 'package:balkavach_app/features/learning/presentation/video_detail_player_screen.dart';
import 'package:balkavach_app/features/learning/presentation/youtube_player_screen.dart';
import 'package:balkavach_app/shared/platform/link_opener.dart';
import 'package:balkavach_app/shared/platform/text_sharer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_video_players.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _yt = 'abcdefghi01';

final _progressPath = RegExp(r'/api/v1/videos/watch-history/[^/]+/progress$');

const _okReply = FakeReply(200, {
  'remaining_allowance_seconds': 600,
  'is_exhausted': false,
});

FakeReply _exhausted(RequestOptions _) => FakeReply.error(
  403,
  'video_time_exhausted',
  'Video access time has been exhausted.',
);

PlayableVideo _video() => const PlayableVideo(
  key: 'a',
  title: 'YouTube a',
  reportVideoId: 'row-a',
  source: YouTubeVideoSource(_yt),
);

Future<(Harness, EmbedRecorder, List<int>)> _pumpDetail(
  WidgetTester tester,
  FakeReply Function(RequestOptions) progress,
) async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  final calls = <int>[];
  h.backend.onPattern('POST', _progressPath, (o) {
    calls.add(calls.length);
    return progress(o);
  });
  h.backend
    ..reply('GET', '/api/v1/video-access/allowance', Fx.allowance())
    ..onPattern(
      'GET',
      RegExp(r'/api/v1/videos/[^/]+/next$'),
      (_) => const FakeReply(200, <Object?>[]),
    );
  final embeds = EmbedRecorder();
  await pumpScreen(
    tester,
    VideoDetailPlayerScreen(
      launch: VideoLaunch(video: _video(), related: const []),
    ),
    overrides: [
      ...h.overrides,
      youtubeEmbedBuilderProvider.overrideWithValue(embeds.build),
      videoPlaybackControllerFactoryProvider.overrideWithValue(
        PlaybackRegistry().create,
      ),
      linkOpenerProvider.overrideWithValue(RecordingLinkOpener()),
      textSharerProvider.overrideWithValue(RecordingSharer()),
    ],
  );
  return (h, embeds, calls);
}

Future<(Harness, List<YouTubeEmbedConfig>, List<int>)> _pumpYouTube(
  WidgetTester tester,
  FakeReply Function(RequestOptions) progress,
) async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  final calls = <int>[];
  h.backend.onPattern('POST', _progressPath, (o) {
    calls.add(calls.length);
    return progress(o);
  });
  final configs = <YouTubeEmbedConfig>[];
  await pumpScreen(
    tester,
    YouTubePlayerScreen(
      video: FeedVideo.fromJson({
        'id': 'v1',
        'title': 'Why is the sky blue?',
        'description': null,
        'thumbnail_url': null,
        'duration_seconds': 125,
        'category_id': null,
        'language_code': 'en',
        'content_rating': 'educational',
        'video_source': 'youtube',
        'youtube_video_id': _yt,
      }),
    ),
    overrides: [
      ...h.overrides,
      linkOpenerProvider.overrideWithValue(RecordingLinkOpener()),
      youtubeEmbedBuilderProvider.overrideWithValue((config) {
        configs.add(config);
        return const ColoredBox(key: Key('fake.embed'), color: Colors.black);
      }),
    ],
  );
  return (h, configs, calls);
}

void main() {
  group('Regular player screen', () {
    testWidgets('exhaustion stops the player and opens the lock page', (
      tester,
    ) async {
      final (_, embeds, _) = await _pumpDetail(tester, _exhausted);
      expect(embeds.mounted, isNotEmpty);
      embeds.mounted.values.first.onPlayingChanged!(true);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('video.lock.screen')), findsOneWidget);
      expect(embeds.mounted, isEmpty, reason: 'nothing may keep playing');
    });

    testWidgets('two failed reports pause it as offline; retry needs the '
        'server to answer', (tester) async {
      var online = false;
      final (_, embeds, _) = await _pumpDetail(
        tester,
        (_) => online
            ? _okReply
            : const FakeReply.fail(DioExceptionType.connectionError),
      );
      embeds.mounted.values.first.onPlayingChanged!(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail.offline')), findsNothing);

      embeds.mounted.values.first.onPlayingChanged!(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail.offline')), findsOneWidget);
      expect(embeds.mounted, isEmpty);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail.offline')), findsOneWidget);

      online = true;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail.offline')), findsNothing);
      expect(embeds.mounted, isNotEmpty);
    });

    testWidgets('returning from the background asks the server again', (
      tester,
    ) async {
      final (_, _, calls) = await _pumpDetail(tester, (_) => _okReply);
      final before = calls.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls.length, greaterThan(before));
    });
  });

  group('YouTube player screen', () {
    testWidgets('exhaustion removes the embed and opens the lock page', (
      tester,
    ) async {
      final (_, configs, _) = await _pumpYouTube(tester, _exhausted);
      expect(find.byKey(const Key('fake.embed')), findsOneWidget);
      configs.last.onPlayingChanged!(true);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('video.lock.screen')), findsOneWidget);
      await tester.tap(find.byKey(const Key('video.lock.close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake.embed')), findsNothing);
      expect(find.byKey(const Key('youtube.retry')), findsNothing);
    });

    testWidgets('offline pauses it and only a server answer brings it back', (
      tester,
    ) async {
      var online = false;
      final (_, configs, _) = await _pumpYouTube(
        tester,
        (_) => online
            ? _okReply
            : const FakeReply.fail(DioExceptionType.connectionError),
      );
      configs.last.onPlayingChanged!(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake.embed')), findsOneWidget);

      configs.last.onPlayingChanged!(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake.embed')), findsNothing);
      expect(
        find.text('Video paused: we can’t reach the internet.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('youtube.retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake.embed')), findsNothing);

      online = true;
      await tester.tap(find.byKey(const Key('youtube.retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake.embed')), findsOneWidget);
    });

    testWidgets('returning from the background asks the server again', (
      tester,
    ) async {
      final (_, _, calls) = await _pumpYouTube(tester, (_) => _okReply);
      final before = calls.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls.length, greaterThan(before));
    });
  });
}
