import 'package:balkavach_app/features/learning/data/learning_repository.dart';
import 'package:balkavach_app/features/learning/presentation/learning_screen.dart';
import 'package:balkavach_app/shared/platform/link_opener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _learningCat = '90000000-0000-4000-8000-000000000001';
const _storiesCat = '90000000-0000-4000-8000-000000000002';

Map<String, Object?> _item({
  String id = 'item-1',
  String title = 'Counting song',
  String type = 'link',
  String? url = 'https://example.com/song',
  String? category = _learningCat,
  bool locked = false,
  String? videoId,
  String? description = 'Sing along with numbers.',
}) => {
  'id': id,
  'title': title,
  'description': description,
  'content_type': type,
  'category_id': category,
  'language_code': 'en',
  'content_url': url,
  'thumbnail_url': null,
  'video_id': videoId,
  'collection_id': null,
  'requires_entitlement': locked,
  'is_active': true,
};

final _categories = [
  {
    'id': _learningCat,
    'name': 'Learning',
    'slug': 'learning',
    'description': null,
    'icon_url': null,
    'display_order': 1,
  },
  {
    'id': _storiesCat,
    'name': 'Stories',
    'slug': 'stories',
    'description': null,
    'icon_url': null,
    'display_order': 2,
  },
];

class _FakeOpener implements LinkOpener {
  _FakeOpener({this.succeeds = true});

  final bool succeeds;
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return succeeds;
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('LearningItem', () {
    test('only an https link is openable', () {
      LearningItem item(String? url) => LearningItem.fromJson(_item(url: url));
      expect(item('https://example.com/a').openableUri, isNotNull);
      expect(item('http://example.com/a').openableUri, isNull);
      expect(item('javascript:alert(1)').openableUri, isNull);
      expect(item('intent://evil').openableUri, isNull);
      expect(item(null).openableUri, isNull);
    });

    test('hosted videos are recognised', () {
      expect(LearningItem.fromJson(_item(videoId: 'v1')).isHosted, isTrue);
      expect(LearningItem.fromJson(_item()).isHosted, isFalse);
    });
  });

  group('repository', () {
    test('lists a page for the child', () async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply('GET', '/api/v1/educational-content', [_item()]);
      final items = await h
          .container()
          .read(learningRepositoryProvider)
          .list(limit: 30, offset: 0);
      expect(items.single.title, 'Counting song');
      expect(
        h.backend
            .requestsTo('GET', '/api/v1/educational-content')
            .single
            .queryParameters,
        {'limit': 30, 'offset': 0},
      );
    });

    test('categories failing does not break the list', () async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.on(
        'GET',
        '/api/v1/videos/categories',
        (_) => FakeReply.error(500, 'internal_error', 'x'),
      );
      expect(
        await h.container().read(learningCategoriesProvider.future),
        isEmpty,
      );
    });
  });

  group('screen', () {
    Future<(Harness, _FakeOpener)> pump(
      WidgetTester tester, {
      List<Map<String, Object?>>? items,
      bool opens = true,
    }) async {
      final opener = _FakeOpener(succeeds: opens);
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..reply('GET', '/api/v1/educational-content', items ?? [_item()])
        ..reply('GET', '/api/v1/videos/categories', _categories);
      await pumpScreen(
        tester,
        const Scaffold(body: LearningScreen()),
        overrides: [
          ...h.overrides,
          linkOpenerProvider.overrideWithValue(opener),
        ],
      );
      return (h, opener);
    }

    testWidgets('lists content with its type and category', (tester) async {
      await pump(
        tester,
        items: [
          _item(),
          _item(
            id: 'i2',
            title: 'Bedtime tale',
            type: 'article',
            category: _storiesCat,
          ),
        ],
      );
      expect(find.text('Counting song'), findsOneWidget);
      expect(find.text('Bedtime tale'), findsOneWidget);
      expect(find.text('Link'), findsOneWidget);
      expect(find.text('Article'), findsOneWidget);
    });

    testWidgets('filters by category', (tester) async {
      await pump(
        tester,
        items: [
          _item(),
          _item(id: 'i2', title: 'Bedtime tale', category: _storiesCat),
        ],
      );
      await _tap(tester, find.byKey(const Key('learn.filter.stories')));
      expect(find.text('Bedtime tale'), findsOneWidget);
      expect(find.text('Counting song'), findsNothing);
      await _tap(tester, find.byKey(const Key('learn.filter.all')));
      expect(find.text('Counting song'), findsOneWidget);
    });

    testWidgets('an empty list is friendly', (tester) async {
      await pump(tester, items: <Map<String, Object?>>[]);
      expect(
        find.text('Nothing to learn here yet. Check back soon!'),
        findsOneWidget,
      );
    });

    testWidgets('a server error offers retry', (tester) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend.on(
        'GET',
        '/api/v1/educational-content',
        (_) => FakeReply.error(500, 'internal_error', 'x'),
      );
      await pumpScreen(
        tester,
        const Scaffold(body: LearningScreen()),
        overrides: h.overrides,
      );
      expect(
        find.text('The server had a problem. Please try again soon.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('details', () {
    Future<_FakeOpener> pump(
      WidgetTester tester,
      Map<String, Object?> json, {
      bool opens = true,
    }) async {
      final opener = _FakeOpener(succeeds: opens);
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      await pumpScreen(
        tester,
        LearningDetailScreen(item: LearningItem.fromJson(json)),
        overrides: [
          ...h.overrides,
          linkOpenerProvider.overrideWithValue(opener),
        ],
      );
      return opener;
    }

    testWidgets('opens the link outside the app', (tester) async {
      final opener = await pump(tester, _item());
      expect(find.text('Sing along with numbers.'), findsOneWidget);
      expect(
        find.text('Opens in your browser or the video app.'),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const Key('learn.open')));
      expect(opener.opened, [Uri.parse('https://example.com/song')]);
    });

    testWidgets('says so when nothing can open the link', (tester) async {
      await pump(tester, _item(), opens: false);
      await _tap(tester, find.byKey(const Key('learn.open')));
      expect(find.byKey(const Key('learn.failed')), findsOneWidget);
    });

    testWidgets('reward-locked content explains how to unlock it', (
      tester,
    ) async {
      final opener = await pump(
        tester,
        _item(locked: true, url: null, videoId: 'v1'),
      );
      expect(find.byKey(const Key('learn.open')), findsNothing);
      expect(
        find.text('Ask your parent to unlock this with a reward.'),
        findsOneWidget,
      );
      expect(opener.opened, isEmpty);
    });

    testWidgets('a hosted video without a link is not offered', (tester) async {
      await pump(tester, _item(url: null, videoId: 'v1', type: 'video'));
      expect(find.byKey(const Key('learn.open')), findsNothing);
      expect(find.text("This one isn't ready to play yet."), findsOneWidget);
    });

    testWidgets('an insecure link is never offered', (tester) async {
      await pump(tester, _item(url: 'http://example.com/a'));
      expect(find.byKey(const Key('learn.open')), findsNothing);
    });

    testWidgets('a curated video plays in the app, not the browser', (
      tester,
    ) async {
      final opener = await pump(
        tester,
        _item(type: 'video', url: 'https://cdn.example.org/a.mp4'),
      );
      expect(find.byKey(const Key('learn.play')), findsOneWidget);
      // The external-browser path must not be offered for playable content.
      expect(find.byKey(const Key('learn.open')), findsNothing);
      expect(opener.opened, isEmpty);
    });

    testWidgets('a non-video link still opens outside the app', (tester) async {
      await pump(tester, _item());
      expect(find.byKey(const Key('learn.open')), findsOneWidget);
      expect(find.byKey(const Key('learn.play')), findsNothing);
    });
  });
}
