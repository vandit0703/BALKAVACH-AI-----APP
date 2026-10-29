import 'package:balkavach_app/app.dart';
import 'package:balkavach_app/features/learning/presentation/youtube_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _shortsPath = '/api/v1/videos/shorts';

Map<String, Object?> _video({
  required String id,
  required String title,
  String? youtubeId = 'dQw4w9WgXcQ',
}) => {
  'id': id,
  'title': title,
  'description': null,
  'thumbnail_url': null,
  'duration_seconds': 40,
  'category_id': null,
  'language_code': 'en',
  'content_rating': 'educational',
  'video_source': youtubeId == null ? 'hosted' : 'youtube',
  'youtube_video_id': youtubeId,
};

List<Map<String, Object?>> _page(int start, int count) => [
  for (var i = start; i < start + count; i++)
    _video(
      id: 'short-$i',
      title: 'Short $i',
      youtubeId: 'dQw4w9WgX${i.toString().padLeft(2, '0')}',
    ),
];

Future<Harness> _child() async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  h.backend
    ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
    ..reply('GET', '/api/v1/redemptions/mine', <Object?>[]);
  return h;
}

Future<void> _pumpHome(
  WidgetTester tester,
  Harness h, {
  List<Map<String, Object?>> shorts = const [],
  bool useDefaultShortsReply = true,
}) async {
  if (useDefaultShortsReply && !h.backend.hasRoute('GET', _shortsPath)) {
    h.backend.reply('GET', _shortsPath, shorts);
  }
  setWindow(tester, const Size(393, 852));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...h.overrides,
        youtubeEmbedBuilderProvider.overrideWithValue(
          (_) => const ColoredBox(
            key: Key('test.youtubeEmbed'),
            color: Colors.black,
          ),
        ),
      ],
      retry: (_, _) => null,
      child: const BalKavachApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Shorts-first Home', () {
    testWidgets('loads the authorized Shorts feed and keeps shell controls', (
      tester,
    ) async {
      final h = await _child();
      await _pumpHome(
        tester,
        h,
        shorts: [_video(id: 's1', title: 'Sky')],
      );

      expect(find.byKey(const Key('videos.shorts.pager')), findsOneWidget);
      expect(find.text('Sky'), findsOneWidget);
      expect(h.backend.requestsTo('GET', _shortsPath), hasLength(1));
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
    });

    testWidgets('vertical swipes advance videos and paginate near the end', (
      tester,
    ) async {
      final h = await _child();
      h.backend.on('GET', _shortsPath, (options) {
        final offset = options.queryParameters['offset'] as int;
        return FakeReply(200, offset == 0 ? _page(0, 10) : _page(10, 1));
      });
      await _pumpHome(tester, h, useDefaultShortsReply: false);

      final pager = find.byKey(const Key('videos.shorts.pager'));
      await tester.drag(pager, const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('Short 1'), findsOneWidget);

      for (var i = 0; i < 8; i++) {
        await tester.drag(pager, const Offset(0, -900));
        await tester.pumpAndSettle();
      }
      expect(find.text('Short 9'), findsOneWidget);
      expect(
        h.backend
            .requestsTo('GET', _shortsPath)
            .map((request) => request.queryParameters['offset'])
            .toList(),
        [0, 10],
      );

      await tester.drag(pager, const Offset(0, 900));
      await tester.pumpAndSettle();
      expect(find.text('Short 8'), findsOneWidget);
    });

    testWidgets('shows a real empty state with a Missions escape hatch', (
      tester,
    ) async {
      final h = await _child();
      await _pumpHome(tester, h);

      expect(find.byKey(const Key('videos.shorts.empty')), findsOneWidget);
      expect(find.byKey(const Key('videos.shorts.toMissions')), findsOneWidget);
      expect(find.text("Videos aren't ready yet"), findsNothing);

      await tester.tap(find.byKey(const Key('videos.shorts.toMissions')));
      await tester.pumpAndSettle();
      expect(find.text('Missions'), findsWidgets);
    });

    testWidgets('retries a failed Shorts request', (tester) async {
      final h = await _child();
      var calls = 0;
      h.backend.on('GET', _shortsPath, (_) {
        calls++;
        return calls == 1
            ? FakeReply.error(500, 'internal_error', 'try again')
            : FakeReply(200, [_video(id: 's2', title: 'After retry')]);
      });
      await _pumpHome(tester, h, useDefaultShortsReply: false);

      expect(find.byKey(const Key('videos.shorts.error')), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('After retry'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('only the active page embeds a player', (tester) async {
      final h = await _child();
      await _pumpHome(
        tester,
        h,
        shorts: [
          _video(id: 's1', title: 'First'),
          _video(id: 's2', title: 'Second', youtubeId: '9bZkp7q19f0'),
        ],
      );

      expect(find.byKey(const Key('test.youtubeEmbed')), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('videos.shorts.pager')),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('test.youtubeEmbed')), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
    });
  });

  testWidgets('Home does not create a standalone player route', (tester) async {
    final h = await _child();
    await _pumpHome(
      tester,
      h,
      shorts: [_video(id: 's1', title: 'One')],
    );

    expect(find.byType(YouTubePlayerScreen), findsNothing);
  });
}
