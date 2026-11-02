// Player behaviour here is verified against PLAYER MOCKS (see
// test/helpers/fake_video_players.dart). These tests prove how the regular
// player screen drives players; they are not real playback verification.

import 'package:balkavach_app/features/learning/data/playable_video.dart';
import 'package:balkavach_app/features/learning/data/video_playback_controller.dart';
import 'package:balkavach_app/features/learning/presentation/video_detail_player_screen.dart';
import 'package:balkavach_app/features/learning/presentation/youtube_player_screen.dart';
import 'package:balkavach_app/shared/platform/link_opener.dart';
import 'package:balkavach_app/shared/platform/text_sharer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_video_players.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

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
  _Rig(this.embeds, this.players, this.opener, this.sharer);

  final EmbedRecorder embeds;
  final PlaybackRegistry players;
  final RecordingLinkOpener opener;
  final RecordingSharer sharer;
}

Future<_Rig> _pump(
  WidgetTester tester,
  PlayableVideo video, {
  List<PlayableVideo> related = const [],
  String? failing,
  Locale locale = const Locale('en'),
  Size size = const Size(393, 852),
}) async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  final rig = _Rig(
    EmbedRecorder(),
    PlaybackRegistry()..failUrlsContaining = failing,
    RecordingLinkOpener(),
    RecordingSharer(),
  );
  await pumpScreen(
    tester,
    VideoDetailPlayerScreen(
      launch: VideoLaunch(video: video, related: related),
    ),
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

void main() {
  group('Regular player: YouTube', () {
    testWidgets('plays inside the app in the official embed', (tester) async {
      final rig = await _pump(tester, youtube('a', _yt, channel: 'Space Kids'));

      final config = rig.embeds.only();
      expect(config.videoId, _yt);
      expect(config.onVerticalSwipe, isNull, reason: 'YouTube fullscreen kept');
      expect(find.text('YouTube a'), findsOneWidget);
      expect(find.text('Learn with a.'), findsOneWidget);
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
}
