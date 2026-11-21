// Player behaviour here is verified against PLAYER MOCKS (see
// test/helpers/fake_video_players.dart). These tests prove how the regular
// player screen drives players; they are not real playback verification.

import 'dart:async';

import 'package:balkavach_app/features/learning/data/playable_video.dart';
import 'package:balkavach_app/features/learning/data/video_feed_repository.dart';
import 'package:balkavach_app/features/learning/data/video_playback_controller.dart';
import 'package:balkavach_app/features/learning/presentation/video_detail_player_screen.dart';
import 'package:balkavach_app/features/learning/presentation/youtube_player_screen.dart';
import 'package:balkavach_app/shared/platform/link_opener.dart';
import 'package:balkavach_app/shared/platform/text_sharer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_video_players.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';
import '../helpers/orientation_recorder.dart';

const _mp4 = 'https://cdn.example.org/curated/planets.mp4';
const _mp4b = 'https://cdn.example.org/curated/oceans.mp4';
const _yt = 'abcdefghi01';

PlayableVideo stream(String key, String url, {String? title}) => PlayableVideo(
  key: key,
  title: title ?? 'Stream $key',
  description: 'About $key.',
  source: DirectStreamSource(Uri.parse(url)),
);

PlayableVideo youtube(String key, String id, {String? channel}) =>
    PlayableVideo(
      key: key,
      title: 'YouTube $key',
      description: 'Learn with $key.',
      channelName: channel,
      duration: const Duration(minutes: 4, seconds: 5),
      reportVideoId: 'row-$key',
      source: YouTubeVideoSource(id),
    );

class _Rig {
  _Rig(this.embeds, this.players, this.opener, this.sharer, this.backend);

  final EmbedRecorder embeds;
  final PlaybackRegistry players;
  final RecordingLinkOpener opener;
  final RecordingSharer sharer;
  final FakeBackend backend;
}

Future<_Rig> _pump(
  WidgetTester tester,
  PlayableVideo video, {
  List<PlayableVideo> related = const [],
  String? failing,
  String? missionTaskId,
  Locale locale = const Locale('en'),
  Size size = const Size(393, 852),
  void Function(FakeBackend backend)? routes,
  List<Override> extraOverrides = const [],
  bool settle = true,
}) async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  h.backend
    ..reply('GET', '/api/v1/video-access/allowance', Fx.allowance())
    ..onPattern(
      'GET',
      RegExp(r'/api/v1/videos/[^/]+/next$'),
      (_) => const FakeReply(200, <Object?>[]),
    )
    ..onPattern(
      'POST',
      RegExp(r'/api/v1/videos/watch-history/[^/]+/progress$'),
      (_) => const FakeReply(200, {
        'remaining_allowance_seconds': 600,
        'is_exhausted': false,
      }),
    );
  routes?.call(h.backend);
  final rig = _Rig(
    EmbedRecorder(),
    PlaybackRegistry()..failUrlsContaining = failing,
    RecordingLinkOpener(),
    RecordingSharer(),
    h.backend,
  );
  await pumpScreen(
    tester,
    VideoDetailPlayerScreen(
      launch: VideoLaunch(
        video: video,
        related: related,
        missionTaskId: missionTaskId,
      ),
    ),
    overrides: [
      ...h.overrides,
      ...extraOverrides,
      youtubeEmbedBuilderProvider.overrideWithValue(rig.embeds.build),
      videoPlaybackControllerFactoryProvider.overrideWithValue(
        rig.players.create,
      ),
      linkOpenerProvider.overrideWithValue(rig.opener),
      textSharerProvider.overrideWithValue(rig.sharer),
    ],
    locale: locale,
    size: size,
    settle: settle,
  );
  return rig;
}

void main() {
  group('Mission-scoped playback', () {
    testWidgets('starts a server session and meters only mission heartbeats', (
      tester,
    ) async {
      const taskId = '55555555-5555-4555-8555-555555555555';
      const sessionId = '88888888-8888-4888-8888-888888888888';
      final rig = await _pump(
        tester,
        youtube('mission', _yt),
        missionTaskId: taskId,
        routes: (backend) {
          backend.reply('POST', '/api/v1/tasks/$taskId/video-watch/sessions', {
            'task_id': taskId,
            'session_id': sessionId,
            'required_video_seconds': 900,
            'verified_video_seconds': 0,
            'remaining_video_seconds': 900,
            'is_complete': false,
            'accepted_seconds': 0,
            'status': 'active',
          }, status: 201);
          backend.onPattern(
            'POST',
            RegExp(r'/api/v1/tasks/video-watch/sessions/.+/heartbeats$'),
            (_) => const FakeReply(200, {
              'task_id': taskId,
              'session_id': sessionId,
              'required_video_seconds': 900,
              'verified_video_seconds': 0,
              'remaining_video_seconds': 900,
              'is_complete': false,
              'accepted_seconds': 0,
              'status': 'active',
            }),
          );
        },
      );
      await tester.pumpAndSettle();

      expect(rig.embeds.only().videoId, _yt);
      final startRequest = rig.backend
          .requestsTo('POST', '/api/v1/tasks/$taskId/video-watch/sessions')
          .single;
      final startBody = startRequest.data as Map<String, dynamic>;
      expect(startBody['video_id'], 'row-mission');
      expect(
        startBody['client_session_id'],
        matches(RegExp(r'^[a-f0-9]{32}$')),
      );

      rig.embeds.only().onPlayingChanged?.call(true);
      await tester.pumpAndSettle();
      final heartbeats = rig.backend.requests
          .where((request) => request.uri.path.endsWith('/heartbeats'))
          .toList();
      expect(heartbeats, hasLength(1));
      final heartbeatBody = heartbeats.single.data as Map<String, dynamic>;
      expect(heartbeatBody, {
        'sequence': 0,
        'position_seconds': 0,
        'is_playing': true,
      });
      expect(
        rig.backend.requests.where(
          (request) =>
              request.uri.path.contains('/watch-history/') &&
              request.uri.path.endsWith('/progress'),
        ),
        isEmpty,
      );
    });
  });

  group('Regular player: YouTube', () {
    testWidgets('plays inside the app in the official embed', (tester) async {
      final rig = await _pump(tester, youtube('a', _yt, channel: 'Space Kids'));

      final config = rig.embeds.only();
      expect(config.videoId, _yt);
      expect(config.onVerticalSwipe, isNull, reason: 'YouTube fullscreen kept');
      expect(find.text('YouTube a'), findsOneWidget);
      expect(
        find.text('Learn with a.'),
        findsNothing,
        reason: 'descriptions stay hidden until the child taps more',
      );
      expect(find.text('Space Kids'), findsOneWidget);
      expect(find.text('4:05'), findsOneWidget);
      expect(
        find.text(
          "Videos from YouTube play in YouTube's own player and may show ads.",
        ),
        findsOneWidget,
      );
      expect(rig.players.created, isEmpty);
      expect(rig.opener.opened, isEmpty);
    });

    testWidgets('a refused embed explains itself; a failure retries', (
      tester,
    ) async {
      final rig = await _pump(tester, youtube('a', _yt));

      rig.embeds.only().onError();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail.error')), findsOneWidget);
      await tester.tap(find.byKey(const Key('detail.retry')));
      await tester.pumpAndSettle();
      expect(rig.embeds.history, hasLength(2));

      rig.embeds.only().onBlocked!();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail.blocked')), findsOneWidget);
      expect(find.byKey(const Key('detail.retry')), findsNothing);
    });

    testWidgets('links in the player need a grown-up', (tester) async {
      final rig = await _pump(tester, youtube('a', _yt));

      rig.embeds.only().onLeaveRequested(Uri.parse('https://youtube.com/x'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('youtube.leaveGate')), findsOneWidget);
      await tester.tap(find.byKey(const Key('youtube.leaveStay')));
      await tester.pumpAndSettle();
      expect(rig.opener.opened, isEmpty);
    });

    testWidgets('a grown-up can report it', (tester) async {
      await _pump(tester, youtube('a', _yt));
      await tester.ensureVisible(find.byKey(const Key('detail.report')));
      await tester.tap(find.byKey(const Key('detail.report')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('youtube.reportDialog')), findsOneWidget);
    });
  });

  group('Regular player: hosted stream', () {
    testWidgets('plays inside the app with seek, time and sound', (
      tester,
    ) async {
      final rig = await _pump(tester, stream('p', _mp4, title: 'Planets'));

      final controller = rig.players.forUrl(_mp4).single;
      expect(controller.isPlaying, isTrue);
      expect(rig.embeds.history, isEmpty);
      expect(find.text('0:15 / 1:00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('detail.playPause')));
      await tester.pumpAndSettle();
      expect(controller.isPlaying, isFalse);
      await tester.tap(find.byKey(const Key('detail.playPause')));
      await tester.pumpAndSettle();
      expect(controller.isPlaying, isTrue);

      // Drag the seek bar to the end: the controller is asked to seek.
      final seek = find.byKey(const Key('detail.seek'));
      await tester.drag(seek, const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(controller.seeks, isNotEmpty);
      expect(controller.seeks.last, greaterThan(const Duration(seconds: 15)));

      await tester.tap(find.byKey(const Key('detail.mute')));
      await tester.pumpAndSettle();
      expect(controller.volume, 0);
    });

    testWidgets('fullscreen toggles, and back leaves fullscreen first', (
      tester,
    ) async {
      final rig = await _pump(tester, stream('p', _mp4));

      await tester.tap(find.byKey(const Key('detail.fullscreen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail.list')), findsNothing);
      expect(find.byTooltip('Exit full screen'), findsOneWidget);

      // Android back: exits fullscreen, does not leave the player.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail.list')), findsOneWidget);
      expect(rig.players.forUrl(_mp4).single.disposed, isFalse);
    });

    testWidgets('a failure shows retry, which starts a fresh player', (
      tester,
    ) async {
      final rig = await _pump(tester, stream('p', _mp4), failing: 'planets');

      expect(find.byKey(const Key('detail.error')), findsOneWidget);
      rig.players.failUrlsContaining = null;
      await tester.tap(find.byKey(const Key('detail.retry')));
      await tester.pumpAndSettle();
      final created = rig.players.forUrl(_mp4);
      expect(created, hasLength(2));
      expect(created.first.disposed, isTrue);
      expect(created.last.isPlaying, isTrue);
    });

    testWidgets('backgrounding pauses playback', (tester) async {
      final rig = await _pump(tester, stream('p', _mp4));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(rig.players.forUrl(_mp4).single.isPlaying, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('leaving the screen disposes the player', (tester) async {
      final rig = await _pump(tester, stream('p', _mp4));
      await tester.pumpWidget(const SizedBox());
      expect(rig.players.live, isEmpty);
    });
  });

  group('Up next', () {
    testWidgets('next video switches players in place', (tester) async {
      final rig = await _pump(
        tester,
        stream('p', _mp4, title: 'Planets'),
        related: [
          youtube('y', _yt),
          stream('o', _mp4b, title: 'Oceans'),
        ],
      );
      final first = rig.players.forUrl(_mp4).single;

      await tester.scrollUntilVisible(
        find.byKey(const Key('detail.next')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('detail.next')));
      await tester.pumpAndSettle();
      expect(first.disposed, isTrue, reason: 'previous audio stops');
      expect(rig.embeds.only().videoId, _yt);
      expect(find.byKey(const Key('detail.title')), findsOneWidget);
      expect(find.text('YouTube y'), findsWidgets);

      await tester.scrollUntilVisible(
        find.byKey(const Key('detail.upNext.o')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('detail.upNext.o')));
      await tester.pumpAndSettle();
      expect(rig.embeds.mounted, isEmpty);
      expect(rig.players.forUrl(_mp4b).single.isPlaying, isTrue);
    });

    testWidgets('a locked video is listed but never played', (tester) async {
      final rig = await _pump(
        tester,
        const PlayableVideo(
          key: 'feed:h',
          title: 'Hosted lesson',
          source: UnavailableSource(VideoUnavailableReason.needsGrownUp),
        ),
      );
      expect(find.byKey(const Key('detail.unavailable')), findsOneWidget);
      expect(rig.players.created, isEmpty);
      expect(rig.embeds.history, isEmpty);
      expect(find.byKey(const Key('detail.share')), findsNothing);
    });
  });

  for (final (code, label) in [('hi', 'अगला वीडियो'), ('gu', 'આગળનો વિડિઓ')]) {
    testWidgets('is translated and fits 320 px in $code', (tester) async {
      await _pump(
        tester,
        stream('p', _mp4),
        related: [youtube('y', _yt)],
        locale: Locale(code),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const Key('detail.next')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(label), findsOneWidget);
    });
  }

  testWidgets('fits a landscape phone', (tester) async {
    await _pump(tester, stream('p', _mp4), size: const Size(740, 360));
    expect(tester.takeException(), isNull);
  });

  group('Regular player: description and layout', () {
    testWidgets('the description is collapsed behind more, like YouTube', (
      tester,
    ) async {
      await _pump(tester, youtube('a', _yt));
      expect(find.byKey(const Key('detail.description')), findsNothing);
      expect(find.text('more'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('detail.descriptionToggle')),
      );
      await tester.tap(find.byKey(const Key('detail.descriptionToggle')));
      await tester.pumpAndSettle();
      expect(find.text('Learn with a.'), findsOneWidget);
      expect(find.text('less'), findsOneWidget);

      await tester.tap(find.byKey(const Key('detail.descriptionToggle')));
      await tester.pumpAndSettle();
      expect(find.text('Learn with a.'), findsNothing);
    });

    testWidgets('a video without a description shows no toggle', (
      tester,
    ) async {
      await _pump(
        tester,
        const PlayableVideo(
          key: 'n',
          title: 'No words',
          reportVideoId: 'row-n',
          source: YouTubeVideoSource(_yt),
        ),
      );
      expect(find.byKey(const Key('detail.descriptionToggle')), findsNothing);
    });

    for (final (size, scale, locale) in [
      (const Size(320, 568), 2.0, const Locale('en')),
      (const Size(360, 640), 1.0, const Locale('hi')),
      (const Size(390, 844), 2.0, const Locale('gu')),
      (const Size(740, 360), 1.0, const Locale('en')),
      (const Size(820, 1180), 1.0, const Locale('en')),
    ]) {
      testWidgets('a very long title fits $size @ ${scale}x in $locale', (
        tester,
      ) async {
        final h = await Harness.create(
          session: Fx.childSession(),
          prefs: onboardedPrefs,
        );
        final embeds = EmbedRecorder();
        await pumpScreen(
          tester,
          VideoDetailPlayerScreen(
            launch: VideoLaunch(
              video: PlayableVideo(
                key: 'long',
                title:
                    'Why do the planets travel around the Sun and what '
                        'keeps the Moon from falling down to the Earth? ' *
                    2,
                description: 'x',
                channelName: 'A channel with quite a long name indeed',
                duration: const Duration(minutes: 12, seconds: 3),
                reportVideoId: 'row-long',
                source: const YouTubeVideoSource(_yt),
              ),
              related: const [],
            ),
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
          size: size,
          textScale: scale,
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('detail.title')), findsOneWidget);
      });
    }
  });

  group('Regular player: fullscreen and rotation', () {
    testWidgets(
      'native fullscreen asks for landscape and gives rotation back',
      (tester) async {
        final orientations = OrientationRecorder(tester);
        await _pump(tester, stream('p', _mp4));

        await tester.tap(find.byKey(const Key('detail.fullscreen')));
        await tester.pumpAndSettle();
        expect(orientations.last, ['landscapeLeft', 'landscapeRight']);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(orientations.last, isEmpty, reason: 'normal rotation restored');
      },
    );

    testWidgets('leaving the screen while fullscreen restores rotation', (
      tester,
    ) async {
      final orientations = OrientationRecorder(tester);
      await _pump(tester, stream('p', _mp4));
      await tester.tap(find.byKey(const Key('detail.fullscreen')));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(orientations.last, isEmpty);
    });

    testWidgets('the app is never locked to landscape outside fullscreen', (
      tester,
    ) async {
      final orientations = OrientationRecorder(tester);
      await _pump(tester, stream('p', _mp4));
      expect(
        orientations.calls.where((c) => c.contains('landscapeLeft')),
        isEmpty,
      );
    });

    testWidgets('a YouTube video enters fullscreen when the phone is rotated', (
      tester,
    ) async {
      final rig = await _pump(tester, youtube('a', _yt));
      expect(rig.embeds.only().autoFullScreen, isTrue);
    });

    testWidgets('the player is removed (so nothing plays on) when leaving', (
      tester,
    ) async {
      final rig = await _pump(tester, stream('p', _mp4));
      final controller = rig.players.forUrl(_mp4).single;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(controller.disposed, isTrue);
    });
  });

  group('Regular player: up next', () {
    Map<String, Object?> feedItem(String id, String title) => {
      'id': id,
      'title': title,
      'description': null,
      'thumbnail_url': null,
      'duration_seconds': 300,
      'category_id': null,
      'language_code': 'en',
      'content_rating': 'educational',
      'video_source': 'youtube',
      'youtube_video_id': 'abcdefghi07',
    };

    testWidgets('shows the server’s suggestions, not just the opening list', (
      tester,
    ) async {
      await _pump(
        tester,
        youtube('a', _yt),
        related: [youtube('z', 'zzzzzzzzz01')],
        routes: (b) => b.onPattern(
          'GET',
          RegExp(r'/api/v1/videos/[^/]+/next$'),
          (_) => FakeReply(200, [feedItem('n1', 'Server pick')]),
        ),
      );
      expect(find.text('Server pick'), findsOneWidget);
      expect(find.text('YouTube z'), findsNothing);
    });

    testWidgets('while loading it shows a spinner, not an empty list', (
      tester,
    ) async {
      final pending = Completer<List<FeedVideo>>();
      await _pump(
        tester,
        youtube('a', _yt),
        extraOverrides: [
          nextVideosProvider.overrideWith((ref, id) => pending.future),
        ],
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('detail.upNext.loading')), findsOneWidget);
      expect(find.byKey(const Key('detail.upNext.empty')), findsNothing);
    });

    testWidgets('an error offers retry and keeps the opening list usable', (
      tester,
    ) async {
      await _pump(
        tester,
        youtube('a', _yt),
        routes: (b) => b.onPattern(
          'GET',
          RegExp(r'/api/v1/videos/[^/]+/next$'),
          (_) => FakeReply.error(500, 'server_error', 'boom'),
        ),
      );
      expect(find.byKey(const Key('detail.upNext.error')), findsOneWidget);
      expect(find.byKey(const Key('detail.upNext.retry')), findsOneWidget);
    });

    testWidgets('an error with an opening list still shows those videos', (
      tester,
    ) async {
      await _pump(
        tester,
        youtube('a', _yt),
        related: [youtube('z', 'zzzzzzzzz01')],
        routes: (b) => b.onPattern(
          'GET',
          RegExp(r'/api/v1/videos/[^/]+/next$'),
          (_) => FakeReply.error(500, 'server_error', 'boom'),
        ),
      );
      expect(find.text('YouTube z'), findsOneWidget);
      expect(find.byKey(const Key('detail.upNext.error')), findsNothing);
    });

    testWidgets('nothing to suggest says so', (tester) async {
      await _pump(tester, youtube('a', _yt));
      expect(find.byKey(const Key('detail.upNext.empty')), findsOneWidget);
      expect(
        find.text('No more videos right now. Check back soon!'),
        findsOneWidget,
      );
    });

    testWidgets('when a video ends the overlay offers the next one', (
      tester,
    ) async {
      final rig = await _pump(
        tester,
        youtube('a', _yt),
        related: [youtube('z', 'zzzzzzzzz01'), youtube('y', 'yyyyyyyyy01')],
      );
      expect(find.byKey(const Key('detail.endOverlay')), findsNothing);
      rig.embeds.only().onEnded!(const Duration(seconds: 245));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail.endOverlay')), findsOneWidget);

      await tester.tap(find.byKey(const Key('detail.end.z')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail.endOverlay')), findsNothing);
      expect(rig.embeds.only().videoId, 'zzzzzzzzz01');
    });

    testWidgets('the next video does not start when the allowance is used up', (
      tester,
    ) async {
      final rig = await _pump(
        tester,
        youtube('a', _yt),
        related: [youtube('z', 'zzzzzzzzz01')],
        routes: (b) => b.reply(
          'GET',
          '/api/v1/video-access/allowance',
          Fx.allowance(remaining: 0),
        ),
      );
      rig.embeds.only().onEnded!(const Duration(seconds: 245));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detail.end.z')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('video.lock.screen')), findsOneWidget);
      expect(rig.embeds.mounted.keys, isNot(contains('zzzzzzzzz01')));
    });
  });
}
