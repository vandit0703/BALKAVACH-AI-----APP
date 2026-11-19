// Responsive audit of the video screens: phone widths, tablet, landscape, 1x
// and 2x text, Hindi and Gujarati, and the loading / empty / offline /
// locked states. Widget tests only: they prove no overflow or exception, not
// how the screens look on a real phone.

import 'package:balkavach_app/features/learning/data/playable_video.dart';
import 'package:balkavach_app/features/learning/data/video_feed_repository.dart';
import 'package:balkavach_app/features/learning/data/video_playback_controller.dart';
import 'package:balkavach_app/features/learning/presentation/shorts_feed.dart';
import 'package:balkavach_app/features/learning/presentation/video_detail_player_screen.dart';
import 'package:balkavach_app/features/learning/presentation/watch_home_screen.dart';
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

const _shorts = '/api/v1/videos/shorts';
const _feed = '/api/v1/videos/feed';
const _learn = '/api/v1/educational-content';
const _categories = '/api/v1/videos/categories';
const _allowance = '/api/v1/video-access/allowance';
final _progress = RegExp(r'/api/v1/videos/watch-history/[^/]+/progress$');

final _sizes = <(String, Size)>[
  ('320 phone', const Size(320, 568)),
  ('360 phone', const Size(360, 640)),
  ('390 phone', const Size(390, 844)),
  ('tablet', const Size(820, 1180)),
  ('landscape phone', const Size(740, 360)),
  ('small landscape', const Size(568, 320)),
];

final _variants = <(double, Locale)>[
  (1.0, const Locale('en')),
  (2.0, const Locale('en')),
  (2.0, const Locale('hi')),
  (2.0, const Locale('gu')),
];

Map<String, Object?> _item(int i, {String source = 'youtube'}) => {
  'id': 'v$i',
  'title':
      'A fairly long video title number $i about volcanoes and the planets',
  'description': null,
  'thumbnail_url': null,
  'duration_seconds': source == 'youtube' && i < 3 ? 40 : 420,
  'category_id': null,
  'language_code': 'en',
  'content_rating': 'educational',
  'video_source': source,
  'youtube_video_id': 'abcdefghi${i.toString().padLeft(2, '0')}',
  'channel_name': 'A channel with a quite long name',
};

enum _Feed { data, empty, offline, locked }

Future<Harness> _home(
  WidgetTester tester,
  _Feed feed,
  Size size,
  double scale,
  Locale locale,
) async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  h.backend
    ..reply('GET', _learn, <Object?>[])
    ..reply('GET', _categories, <Object?>[])
    ..reply(
      'GET',
      '/api/v1/videos/watch-history/continue-watching',
      <Object?>[],
    );
  switch (feed) {
    case _Feed.data:
      h.backend
        ..reply('GET', _shorts, [for (var i = 0; i < 3; i++) _item(i)])
        ..reply('GET', _feed, [for (var i = 3; i < 6; i++) _item(i)])
        ..reply('GET', _allowance, Fx.allowance());
    case _Feed.empty:
      h.backend
        ..reply('GET', _shorts, <Object?>[])
        ..reply('GET', _feed, <Object?>[])
        ..reply('GET', _allowance, Fx.allowance());
    case _Feed.locked:
      h.backend
        ..reply('GET', _shorts, <Object?>[])
        ..reply('GET', _feed, <Object?>[])
        ..reply('GET', _allowance, Fx.allowance(remaining: 0));
    case _Feed.offline:
      for (final path in [_shorts, _feed, _allowance]) {
        h.backend.on(
          'GET',
          path,
          (_) => const FakeReply.fail(DioExceptionType.connectionError),
        );
      }
  }
  await pumpScreen(
    tester,
    const WatchHomeScreen(),
    overrides: [
      ...h.overrides,
      youtubeEmbedBuilderProvider.overrideWithValue(EmbedRecorder().build),
      videoPlaybackControllerFactoryProvider.overrideWithValue(
        PlaybackRegistry().create,
      ),
      linkOpenerProvider.overrideWithValue(RecordingLinkOpener()),
    ],
    size: size,
    textScale: scale,
    locale: locale,
    settle: false,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  return h;
}

void main() {
  group('Watch home', () {
    for (final feed in _Feed.values) {
      for (final (label, size) in _sizes) {
        for (final (scale, locale) in _variants) {
          testWidgets('${feed.name} · $label · ${scale}x · $locale', (
            tester,
          ) async {
            await _home(tester, feed, size, scale, locale);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('loading state shows without overflow at 320 px 2x', (
      tester,
    ) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      await pumpScreen(
        tester,
        const WatchHomeScreen(),
        overrides: h.overrides,
        size: const Size(320, 568),
        textScale: 2,
        settle: false,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('YouTube player screen', () {
    for (final (label, size) in _sizes) {
      for (final (scale, locale) in _variants) {
        testWidgets('$label · ${scale}x · $locale (offline pause)', (
          tester,
        ) async {
          final h = await Harness.create(
            session: Fx.childSession(),
            prefs: onboardedPrefs,
          );
          h.backend.onPattern(
            'POST',
            _progress,
            (_) => const FakeReply.fail(DioExceptionType.connectionError),
          );
          final configs = <YouTubeEmbedConfig>[];
          await pumpScreen(
            tester,
            YouTubePlayerScreen(video: FeedVideo.fromJson(_item(7))),
            overrides: [
              ...h.overrides,
              linkOpenerProvider.overrideWithValue(RecordingLinkOpener()),
              youtubeEmbedBuilderProvider.overrideWithValue((config) {
                configs.add(config);
                return const ColoredBox(color: Colors.black);
              }),
            ],
            size: size,
            textScale: scale,
            locale: locale,
          );
          expect(tester.takeException(), isNull);
          configs.last.onPlayingChanged!(true);
          await tester.pumpAndSettle();
          configs.last.onPlayingChanged!(true);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('youtube.retry')), findsOneWidget);
        });
      }
    }
  });

  group('Shorts feed', () {
    for (final (label, size) in _sizes) {
      for (final (scale, locale) in _variants) {
        testWidgets('$label · ${scale}x · $locale (empty and with data)', (
          tester,
        ) async {
          for (final withData in [false, true]) {
            final h = await Harness.create(
              session: Fx.childSession(),
              prefs: onboardedPrefs,
            );
            h.backend
              ..reply(
                'GET',
                _shorts,
                withData ? [for (var i = 0; i < 3; i++) _item(i)] : <Object?>[],
              )
              ..reply('GET', _allowance, Fx.allowance())
              ..onPattern(
                'POST',
                _progress,
                (_) => const FakeReply(200, {
                  'remaining_allowance_seconds': 600,
                  'is_exhausted': false,
                }),
              );
            await pumpScreen(
              tester,
              const ShortsFeedScreen(),
              overrides: [
                ...h.overrides,
                youtubeEmbedBuilderProvider.overrideWithValue(
                  EmbedRecorder().build,
                ),
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
            expect(tester.takeException(), isNull, reason: 'data=$withData');
          }
        });
      }
    }
  });

  group('Regular player screen', () {
    for (final (label, size) in _sizes) {
      testWidgets('$label · 2x (native stream, controls)', (tester) async {
        final h = await Harness.create(
          session: Fx.childSession(),
          prefs: onboardedPrefs,
        );
        await pumpScreen(
          tester,
          VideoDetailPlayerScreen(
            launch: VideoLaunch(
              video: PlayableVideo(
                key: 's',
                title: 'A hosted lesson with quite a long title indeed',
                description: 'About it.',
                source: DirectStreamSource(
                  Uri.parse('https://cdn.example.org/a.mp4'),
                ),
              ),
              related: const [],
            ),
          ),
          overrides: [
            ...h.overrides,
            youtubeEmbedBuilderProvider.overrideWithValue(
              EmbedRecorder().build,
            ),
            videoPlaybackControllerFactoryProvider.overrideWithValue(
              PlaybackRegistry().create,
            ),
            linkOpenerProvider.overrideWithValue(RecordingLinkOpener()),
            textSharerProvider.overrideWithValue(RecordingSharer()),
          ],
          size: size,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
