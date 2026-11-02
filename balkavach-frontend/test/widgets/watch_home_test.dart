// Player behaviour here is verified against PLAYER MOCKS (see
// test/helpers/fake_video_players.dart); this is not real playback
// verification.

import 'package:balkavach_app/app.dart';
import 'package:balkavach_app/features/learning/data/video_playback_controller.dart';
import 'package:balkavach_app/features/learning/presentation/shorts_feed.dart';
import 'package:balkavach_app/features/learning/presentation/video_detail_player_screen.dart';
import 'package:balkavach_app/features/learning/presentation/youtube_player_screen.dart';
import 'package:balkavach_app/shared/platform/link_opener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_video_players.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _shortsPath = '/api/v1/videos/shorts';
const _feedPath = '/api/v1/videos/feed';
const _learnPath = '/api/v1/educational-content';
const _categoriesPath = '/api/v1/videos/categories';

String _ytId(int i) => 'abcdefghi${i.toString().padLeft(2, '0')}';

Map<String, Object?> _video({
  required String id,
  required String title,
  String? youtubeId,
  String source = 'youtube',
  int seconds = 40,
  String? categoryId,
}) => {
  'id': id,
  'title': title,
  'description': null,
  'thumbnail_url': null,
  'duration_seconds': seconds,
  'category_id': categoryId,
  'language_code': 'en',
  'content_rating': 'educational',
  'video_source': source,
  'youtube_video_id': source == 'youtube' ? youtubeId : null,
  'channel_name': source == 'youtube' ? 'Kids Channel' : null,
};

Map<String, Object?> _curated({
  required String id,
  required String title,
  required String url,
}) => {
  'id': id,
  'title': title,
  'description': 'Curated by the team.',
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

class _Rig {
  _Rig(this.h, this.embeds, this.players, this.opener);

  final Harness h;
  final EmbedRecorder embeds;
  final PlaybackRegistry players;
  final RecordingLinkOpener opener;
}

Future<_Rig> _pumpHome(
  WidgetTester tester, {
  List<Map<String, Object?>> shorts = const [],
  List<Map<String, Object?>> videos = const [],
  List<Map<String, Object?>> curated = const [],
  List<Map<String, Object?>> categories = const [],
  void Function(FakeBackend backend)? routes,
}) async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  h.backend
    ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
    ..reply('GET', '/api/v1/redemptions/mine', <Object?>[])
    ..reply('GET', _learnPath, curated)
    ..reply('GET', _categoriesPath, categories);
  routes?.call(h.backend);
  if (!h.backend.hasRoute('GET', _shortsPath)) {
    h.backend.reply('GET', _shortsPath, shorts);
  }
  if (!h.backend.hasRoute('GET', _feedPath)) {
    h.backend.reply('GET', _feedPath, videos);
  }
  final rig = _Rig(
    h,
    EmbedRecorder(),
    PlaybackRegistry(),
    RecordingLinkOpener(),
  );
  setWindow(tester, const Size(393, 852));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...h.overrides,
        youtubeEmbedBuilderProvider.overrideWithValue(rig.embeds.build),
        videoPlaybackControllerFactoryProvider.overrideWithValue(
          rig.players.create,
        ),
        linkOpenerProvider.overrideWithValue(rig.opener),
      ],
      retry: (_, _) => null,
      child: const BalKavachApp(),
    ),
  );
  await tester.pumpAndSettle();
  return rig;
}

final _someShorts = [
  for (var i = 0; i < 3; i++)
    _video(id: 's$i', title: 'Short $i', youtubeId: _ytId(i)),
];

final _someVideos = [
  _video(id: 'v1', title: 'Volcano facts', youtubeId: _ytId(50), seconds: 420),
  _video(id: 'v2', title: 'Hosted lesson', source: 'hosted', seconds: 600),
];

void main() {
  group('Watch & Learn Home', () {
    testWidgets('shows Shorts, videos and picks; keeps the shell', (
      tester,
    ) async {
      final rig = await _pumpHome(
        tester,
        shorts: _someShorts,
        videos: _someVideos,
        curated: [
          _curated(
            id: 'c1',
            title: 'Counting song',
            url: 'https://cdn.example.org/counting.mp4',
          ),
        ],
      );

      expect(find.text('What shall we watch today?'), findsOneWidget);
      expect(find.byKey(const Key('watch.shorts.row')), findsOneWidget);
      expect(find.text('Short 0'), findsOneWidget);
      expect(find.text('Volcano facts'), findsOneWidget);
      // No player of any kind lives on Home.
      expect(rig.embeds.history, isEmpty);
      expect(rig.players.created, isEmpty);
      expect(find.byKey(const Key('parentGate')), findsOneWidget);
      for (final label in [
        'Home',
        'Missions',
        'Rewards',
        'Garden',
        'Profile',
      ]) {
        expect(find.text(label), findsWidgets);
      }

      await tester.scrollUntilVisible(
        find.text('Counting song'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('watch.picked.header')), findsOneWidget);
    });

    testWidgets('a Short opens the full-screen feed at that Short', (
      tester,
    ) async {
      final rig = await _pumpHome(tester, shorts: _someShorts);

      await tester.tap(find.byKey(const Key('watch.short.feed:s1')));
      await tester.pumpAndSettle();

      expect(find.byType(ShortsFeedScreen), findsOneWidget);
      expect(rig.embeds.only().videoId, _ytId(1));
      // Opened from what Home already had: page 0 was not fetched again.
      expect(
        rig.h.backend
            .requestsTo('GET', _shortsPath)
            .map((r) => r.queryParameters['offset']),
        [0],
      );
      // The player covers the bottom navigation.
      expect(find.byType(NavigationBar), findsNothing);

      // Android back returns Home and tears the player down.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ShortsFeedScreen), findsNothing);
      expect(rig.embeds.mounted, isEmpty);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('the Shorts back button returns Home', (tester) async {
      final rig = await _pumpHome(tester, shorts: _someShorts);

      await tester.tap(find.byKey(const Key('watch.short.feed:s0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('videos.shorts.back')));
      await tester.pumpAndSettle();
      expect(find.byType(ShortsFeedScreen), findsNothing);
      expect(find.byKey(const Key('watch.scroll')), findsOneWidget);
      expect(rig.embeds.mounted, isEmpty);
    });

    testWidgets('"See all" opens Shorts from the first one', (tester) async {
      final rig = await _pumpHome(tester, shorts: _someShorts);

      await tester.tap(find.byKey(const Key('watch.shorts.seeAll')));
      await tester.pumpAndSettle();
      expect(rig.embeds.only().videoId, _ytId(0));
    });

    testWidgets('a regular YouTube video plays in the in-app player', (
      tester,
    ) async {
      final rig = await _pumpHome(tester, videos: _someVideos);

      await tester.tap(find.text('Volcano facts'));
      await tester.pumpAndSettle();
      expect(find.byType(VideoDetailPlayerScreen), findsOneWidget);
      expect(rig.embeds.only().videoId, _ytId(50));
      expect(rig.opener.opened, isEmpty, reason: 'never the YouTube app');
      // "Up next" offers the rest of the list.
      await tester.scrollUntilVisible(
        find.byKey(const Key('detail.upNext.feed:v2')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    });

    testWidgets('a hosted video is shown locked and is never played', (
      tester,
    ) async {
      final rig = await _pumpHome(tester, videos: _someVideos);

      await tester.scrollUntilVisible(
        find.text('Hosted lesson'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Hosted lesson'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hosted lesson'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail.unavailable')), findsOneWidget);
      expect(rig.players.created, isEmpty);
      expect(rig.embeds.history, isEmpty);
    });

    testWidgets('a curated MP4 plays in the native in-app player', (
      tester,
    ) async {
      final rig = await _pumpHome(
        tester,
        curated: [
          _curated(
            id: 'c1',
            title: 'Counting song',
            url: 'https://cdn.example.org/counting.mp4',
          ),
          _curated(
            id: 'c2',
            title: 'Alphabet on YouTube',
            url: 'https://www.youtube.com/watch?v=${_ytId(9)}',
          ),
        ],
      );

      await tester.tap(find.text('Counting song'));
      await tester.pumpAndSettle();
      final controller = rig.players.created.single;
      expect(controller.uri.toString(), 'https://cdn.example.org/counting.mp4');
      expect(controller.isPlaying, isTrue);
      expect(rig.embeds.history, isEmpty);
    });

    testWidgets('topics filter the regular videos on the server', (
      tester,
    ) async {
      final rig = await _pumpHome(
        tester,
        videos: _someVideos,
        categories: [
          {'id': 'cat-sci', 'name': 'Science', 'slug': 'science'},
        ],
      );

      await tester.tap(find.byKey(const Key('watch.topic.science')));
      await tester.pumpAndSettle();
      final requests = rig.h.backend.requestsTo('GET', _feedPath);
      expect(requests.last.queryParameters['category_id'], 'cat-sci');
      await tester.tap(find.byKey(const Key('watch.topic.all')));
      await tester.pumpAndSettle();
      expect(
        rig.h.backend
            .requestsTo('GET', _feedPath)
            .last
            .queryParameters
            .containsKey('category_id'),
        isFalse,
      );
    });

    testWidgets('scrolling the list loads the next page', (tester) async {
      final rig = await _pumpHome(
        tester,
        routes: (backend) => backend.on('GET', _feedPath, (options) {
          final offset = options.queryParameters['offset'] as int;
          return FakeReply(200, [
            if (offset == 0)
              for (var i = 0; i < 20; i++)
                _video(id: 'p$i', title: 'Page video $i', youtubeId: _ytId(i)),
          ]);
        }),
      );

      await tester.scrollUntilVisible(
        find.text('Page video 19'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        rig.h.backend
            .requestsTo('GET', _feedPath)
            .map((r) => r.queryParameters['offset']),
        [0, 20],
      );
    });

    testWidgets('nothing approved yet: a friendly way to Missions', (
      tester,
    ) async {
      await _pumpHome(tester);

      expect(find.byKey(const Key('watch.empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('watch.toMissions')));
      await tester.pumpAndSettle();
      expect(find.text('Missions'), findsWidgets);
    });

    testWidgets('a Shorts failure can be retried without losing videos', (
      tester,
    ) async {
      var calls = 0;
      await _pumpHome(
        tester,
        videos: _someVideos,
        routes: (backend) => backend.on('GET', _shortsPath, (_) {
          calls++;
          return calls == 1
              ? FakeReply.error(500, 'internal_error', 'try again')
              : FakeReply(200, _someShorts);
        }),
      );

      expect(find.byKey(const Key('watch.shorts.error')), findsOneWidget);
      expect(find.text('Volcano facts'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('watch.shorts.error')),
          matching: find.text('Try again'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Short 0'), findsOneWidget);
    });

    testWidgets('a bare player deep link has nothing to play', (tester) async {
      final rig = await _pumpHome(tester, shorts: _someShorts);
      final context = tester.element(find.byKey(const Key('watch.scroll')));

      GoRouter.of(context).go('/child/watch');
      await tester.pumpAndSettle();
      expect(find.byType(VideoDetailPlayerScreen), findsNothing);
      expect(find.byKey(const Key('watch.scroll')), findsOneWidget);
      expect(rig.embeds.history, isEmpty);
      expect(rig.players.created, isEmpty);
    });
  });
}
