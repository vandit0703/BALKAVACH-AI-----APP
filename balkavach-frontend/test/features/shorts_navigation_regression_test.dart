import 'package:balkavach_app/features/learning/data/learning_repository.dart';
import 'package:balkavach_app/features/learning/data/playable_video.dart';
import 'package:balkavach_app/features/learning/data/video_feed_repository.dart';
import 'package:balkavach_app/features/learning/data/video_playback_controller.dart';
import 'package:balkavach_app/features/learning/presentation/shorts_feed.dart';
import 'package:balkavach_app/features/learning/presentation/video_feed_screen.dart';
import 'package:balkavach_app/features/learning/presentation/youtube_player_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:balkavach_app/shared/platform/link_opener.dart';
import 'package:balkavach_app/shared/platform/text_sharer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_video_players.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _shortsPath = '/api/v1/videos/shorts';

String _ytId(int i) => 'abcdefghi${i.toString().padLeft(2, '0')}';

Map<String, Object?> _short(int i) => {
      'id': 'short-$i',
      'title': 'Short $i',
      'description': 'Desc $i',
      'thumbnail_url': 'https://i.ytimg.com/vi/s$i/hqdefault.jpg',
      'duration_seconds': 45,
      'category_id': null,
      'language_code': 'en',
      'content_rating': 'educational',
      'video_source': 'youtube',
      'youtube_video_id': _ytId(i),
      'channel_name': 'Kids',
      'last_position_seconds': 0,
    };

Future<void> _pumpVideosScreen(
  WidgetTester tester, {
  required Harness h,
  required EmbedRecorder embeds,
  Locale locale = const Locale('en'),
}) async {
  h.backend.reply('GET', '/api/v1/videos/feed', <Object?>[]);
  h.backend.reply('GET', _shortsPath, [_short(0), _short(1), _short(2)]);
  h.backend.reply('GET', '/api/v1/video-access/allowance', Fx.allowance());
  h.backend.onPattern(
    'POST',
    RegExp(r'/api/v1/videos/watch-history/[^/]+/progress$'),
    (_) => const FakeReply(200, {
      'remaining_allowance_seconds': 900,
      'is_exhausted': false,
    }),
  );

  await pumpScreen(
    tester,
    const VideoFeedScreen(),
    overrides: [
      ...h.overrides,
      youtubeEmbedBuilderProvider.overrideWithValue(embeds.build),
      videoPlaybackControllerFactoryProvider.overrideWithValue(
        PlaybackRegistry().create,
      ),
      linkOpenerProvider.overrideWithValue(RecordingLinkOpener()),
      textSharerProvider.overrideWithValue(RecordingSharer()),
    ],
    locale: locale,
  );
}

void main() {
  testWidgets(
    'Shorts tab remains visible after pushing and popping a player route',
    (tester) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      final embeds = EmbedRecorder();
      await _pumpVideosScreen(tester, h: h, embeds: embeds);

      await tester.tap(find.byKey(const Key('videos.tab.shorts')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('videos.shorts.pager')), findsOneWidget);
      expect(find.text('Short 0'), findsOneWidget);
      expect(embeds.activeCount, 1);
      expect(tester.takeException(), isNull);

      final nav = Navigator.of(tester.element(find.byType(VideoFeedScreen)));
      nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('player'))));
      await tester.pumpAndSettle();
      expect(find.text('player'), findsOneWidget);

      nav.pop();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('videos.shorts.pager')), findsOneWidget);
      expect(find.text('Short 0'), findsOneWidget);
      expect(find.byType(Scaffold), findsWidgets);
      expect(find.byKey(const Key('videos.shorts.error')), findsNothing);
      expect(find.byKey(const Key('videos.shorts.empty')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Shorts tab survives locale rebuild and keeps current video/position',
    (tester) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      final embeds = EmbedRecorder();
      h.backend.reply('GET', '/api/v1/videos/feed', <Object?>[]);
      h.backend.reply('GET', _shortsPath, [_short(0), _short(1), _short(2)]);
      h.backend.reply('GET', '/api/v1/video-access/allowance', Fx.allowance());
      h.backend.onPattern(
        'POST',
        RegExp(r'/api/v1/videos/watch-history/[^/]+/progress$'),
        (_) => const FakeReply(200, {
          'remaining_allowance_seconds': 900,
          'is_exhausted': false,
        }),
      );

      var locale = const Locale('en');
      late StateSetter setHostState;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return ProviderScope(
              overrides: [
                ...h.overrides,
                youtubeEmbedBuilderProvider.overrideWithValue(embeds.build),
                videoPlaybackControllerFactoryProvider.overrideWithValue(
                  PlaybackRegistry().create,
                ),
                linkOpenerProvider.overrideWithValue(RecordingLinkOpener()),
                textSharerProvider.overrideWithValue(RecordingSharer()),
              ],
              retry: (_, _) => null,
              child: MaterialApp(
                locale: locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                home: const VideoFeedScreen(),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('videos.tab.shorts')));
      await tester.pumpAndSettle();
      expect(find.text('Short 0'), findsOneWidget);

      await tester.drag(find.byKey(const Key('videos.shorts.pager')), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.text('Short 1'), findsOneWidget);

      setHostState(() => locale = const Locale('gu'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('videos.tab.shorts')), findsOneWidget);
      expect(find.byKey(const Key('videos.shorts.pager')), findsOneWidget);
      expect(find.text('Short 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
