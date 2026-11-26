// Child video-interests card: loading, success, empty and failure states
// (docs/QUIZ_AND_INTERESTS_FIX_REPORT.md). The deployed API answered
// `GET /api/v1/videos/interests` with 404 because the route was not deployed;
// the card must say that clearly and retry with a real new request.
import 'package:balkavach_app/features/child_profile/presentation/child_interests_and_link_cards.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _path = '/api/v1/videos/interests';
const _requestPath = '/api/v1/videos/interests/request';

const _categories = [
  {'slug': 'science', 'name': 'Science'},
  {'slug': 'stories', 'name': 'Stories'},
  {'slug': 'music', 'name': 'Music'},
];

Map<String, Object?> _body({
  List<String> interests = const ['science'],
  List<String> pending = const [],
  List<Object?> categories = _categories,
}) => {
  'interests': interests,
  'pending_requests': pending,
  'available_categories': categories,
};

Future<Harness> _child() => Harness.create(session: Fx.childSession());

Future<void> _pumpCard(
  WidgetTester tester,
  Harness h, {
  Locale locale = const Locale('en'),
}) => pumpScreen(
  tester,
  const Scaffold(body: SingleChildScrollView(child: ChildInterestsCard())),
  overrides: h.overrides,
  locale: locale,
);

Map<String, Object?> _notFound() => {
  'error': {'code': 'http_error', 'message': 'Not Found'},
};

void main() {
  testWidgets('approved topics and pending requests are shown separately', (
    tester,
  ) async {
    final h = await _child();
    h.backend.reply(
      'GET',
      _path,
      _body(interests: ['science'], pending: ['stories']),
    );
    await _pumpCard(tester, h);

    expect(find.text('Your topics (approved by your parent)'), findsOneWidget);
    expect(
      find.byKey(const Key('child.interests.active.science')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('child.interests.active.stories')),
      findsNothing,
    );
    expect(find.byKey(const Key('child.interests.pending')), findsOneWidget);
    expect(
      find.byKey(const Key('child.interests.pendingItem.stories')),
      findsOneWidget,
    );
    expect(find.text('Waiting for parent approval'), findsOneWidget);
    // Every topic in the catalogue can be asked for.
    for (final slug in ['science', 'stories', 'music']) {
      expect(find.byKey(Key('child.interest.$slug')), findsOneWidget);
    }
    expect(find.text("We couldn't find that."), findsNothing);
  });

  testWidgets('no approved topics yet is said plainly', (tester) async {
    final h = await _child();
    h.backend.reply('GET', _path, _body(interests: []));
    await _pumpCard(tester, h);
    expect(find.byKey(const Key('child.interests.activeNone')), findsOneWidget);
    expect(find.byKey(const Key('child.interests.pending')), findsNothing);
  });

  testWidgets('an empty catalogue is an empty state, not an error', (
    tester,
  ) async {
    final h = await _child();
    h.backend.reply('GET', _path, _body(interests: [], categories: []));
    await _pumpCard(tester, h);
    expect(find.byKey(const Key('child.interests.empty')), findsOneWidget);
    expect(find.text('No topics available yet.'), findsOneWidget);
    expect(find.byKey(const Key('child.interests.error')), findsNothing);
    expect(find.byKey(const Key('child.interests.request')), findsNothing);
  });

  testWidgets('a server without the interests route (404) says so, and Retry '
      'makes a new request that can succeed', (tester) async {
    final h = await _child();
    h.backend.reply('GET', _path, _notFound(), status: 404);
    await _pumpCard(tester, h);

    expect(find.byKey(const Key('child.interests.error')), findsOneWidget);
    expect(
      find.text("Video interests aren't ready yet. Please try again later."),
      findsOneWidget,
    );
    expect(find.text("We couldn't find that."), findsNothing);
    expect(h.backend.requestsTo('GET', _path), hasLength(1));

    h.backend.reply('GET', _path, _body());
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(h.backend.requestsTo('GET', _path), hasLength(2));
    expect(find.byKey(const Key('child.interests.error')), findsNothing);
    expect(
      find.byKey(const Key('child.interests.active.science')),
      findsOneWidget,
    );
  });

  testWidgets('a network failure shows a recoverable offline error', (
    tester,
  ) async {
    final h = await _child();
    h.backend.on(
      'GET',
      _path,
      (_) => const FakeReply.fail(DioExceptionType.connectionError),
    );
    await _pumpCard(tester, h);
    expect(find.byKey(const Key('child.interests.error')), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('an expired session is reported as such, not as not-found', (
    tester,
  ) async {
    final h = await _child();
    h.backend.reply('GET', _path, {
      'error': {'code': 'http_error', 'message': 'Authentication required'},
    }, status: 401);
    await _pumpCard(tester, h);
    expect(find.byKey(const Key('child.interests.error')), findsOneWidget);
    expect(
      find.text('Your session has ended. Please sign in again.'),
      findsOneWidget,
    );
    expect(find.text("We couldn't find that."), findsNothing);
  });

  testWidgets('a request sends only slugs, stays pending, and leaves the '
      'approved topics unchanged', (tester) async {
    final h = await _child();
    h.backend
      ..reply('GET', _path, _body())
      ..reply(
        'POST',
        _requestPath,
        _body(interests: ['science'], pending: ['science', 'music']),
      );
    await _pumpCard(tester, h);

    await tester.tap(find.byKey(const Key('child.interest.music')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('child.interests.request')),
    );
    await tester.tap(find.byKey(const Key('child.interests.request')));
    await tester.pumpAndSettle();

    final request = h.backend.requestsTo('POST', _requestPath).single;
    expect(
      (request.data as Map)['interests'],
      unorderedEquals(['science', 'music']),
    );
    // Approved topics are still only what the parent approved.
    expect(
      find.byKey(const Key('child.interests.active.science')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('child.interests.active.music')), findsNothing);
    expect(
      find.byKey(const Key('child.interests.pendingItem.music')),
      findsOneWidget,
    );
    expect(find.text('Interest request sent to parent'), findsOneWidget);
  });

  testWidgets('a failed request keeps the child\'s selection for another try', (
    tester,
  ) async {
    final h = await _child();
    h.backend
      ..reply('GET', _path, _body())
      ..reply('POST', _requestPath, {
        'error': {'code': 'http_error', 'message': 'boom'},
      }, status: 500);
    await _pumpCard(tester, h);

    await tester.tap(find.byKey(const Key('child.interest.music')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('child.interests.request')),
    );
    await tester.tap(find.byKey(const Key('child.interests.request')));
    await tester.pumpAndSettle();

    final music = tester.widget<FilterChip>(
      find.byKey(const Key('child.interest.music')),
    );
    expect(music.selected, isTrue);
    expect(find.byKey(const Key('child.interests.pending')), findsNothing);
    expect(
      find.byKey(const Key('child.interests.active.science')),
      findsOneWidget,
    );
  });

  for (final (locale, active, ask) in [
    (
      const Locale('hi'),
      'तुम्हारे विषय (माता-पिता द्वारा स्वीकृत)',
      'बदलाव माँगो',
    ),
    (
      const Locale('gu'),
      'તમારા વિષયો (માતા-પિતા દ્વારા મંજૂર)',
      'ફેરફાર માંગો',
    ),
  ]) {
    testWidgets('sections are localised for ${locale.languageCode}', (
      tester,
    ) async {
      final h = await _child();
      h.backend.reply('GET', _path, _body(pending: ['stories']));
      await _pumpCard(tester, h, locale: locale);
      expect(find.text(active), findsOneWidget);
      expect(find.text(ask), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
