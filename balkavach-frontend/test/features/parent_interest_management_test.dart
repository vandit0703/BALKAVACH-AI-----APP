// Parent interest management (Parent Account and Parent Mode) and the child's
// change request (docs/PARENT_INTEREST_MANAGEMENT_FIX_REPORT.md).
//
// Parent Mode (`/auth/parent-mode/enter` from the child's device) adopts an
// ordinary parent session, and both entry points open the same
// ChildProfileScreen -> ParentChildInterestsCard, so the parent cases below
// cover both; the session tests check which token and ids reach the server.
import 'package:balkavach_app/features/authentication/presentation/session_controller.dart';
import 'package:balkavach_app/features/child_profile/presentation/child_interests_and_link_cards.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

String _parentPath(String family, String child) =>
    '/api/v1/families/$family/children/$child/interests';
const _childPath = '/api/v1/videos/interests';
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

/// Answers the PUT like the server: echoes the stored interests and clears
/// pending only when asked to.
FakeReply _echoPut(RequestOptions r, {List<String> pending = const []}) {
  final data = r.data as Map;
  return FakeReply(200, {
    'interests': List<String>.from(data['interests'] as List),
    'pending_requests': data['clear_pending'] == true ? <String>[] : pending,
    'available_categories': _categories,
  });
}

/// Waits for the stored session like the app's router does before any
/// signed-in screen is shown, so requests carry the session's bearer token.
class _SignedIn extends ConsumerWidget {
  const _SignedIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(sessionControllerProvider).hasValue
      ? Scaffold(body: SingleChildScrollView(child: child))
      : const SizedBox.shrink();
}

class _Host extends StatefulWidget {
  const _Host({required this.childId});

  final String childId;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late String childId = widget.childId;

  void show(String id) => setState(() => childId = id);

  @override
  Widget build(BuildContext context) => _SignedIn(
    child: ParentChildInterestsCard(familyId: 'fam-1', childId: childId),
  );
}

Future<void> _pumpParent(
  WidgetTester tester,
  Harness h, {
  String childId = 'child-1',
  Locale locale = const Locale('en'),
}) => pumpScreen(
  tester,
  _Host(childId: childId),
  overrides: h.overrides,
  locale: locale,
);

Future<void> _pumpChild(WidgetTester tester, Harness h) => pumpScreen(
  tester,
  const _SignedIn(child: ChildInterestsCard()),
  overrides: h.overrides,
);

bool _selected(WidgetTester tester, String key) =>
    tester.widget<FilterChip>(find.byKey(Key(key))).selected;

/// PrimaryButton / SecondaryButton are enabled when they have a callback.
bool _enabled(WidgetTester tester, String key) =>
    (tester.widget(find.byKey(Key(key))) as dynamic).onPressed != null;

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  group('parent account / parent mode', () {
    testWidgets('loads the linked child with approved and pending separate', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.reply(
        'GET',
        _parentPath('fam-1', 'child-1'),
        _body(interests: ['science'], pending: ['stories']),
      );
      await _pumpParent(tester, h);

      final get = h.backend
          .requestsTo('GET', _parentPath('fam-1', 'child-1'))
          .single;
      expect(get.headers['Authorization'], 'Bearer parent.jwt.token');
      expect(
        find.byKey(const Key('parent.interests.active.science')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('parent.interests.pendingItem.stories')),
        findsOneWidget,
      );
      expect(_selected(tester, 'parent.interest.science'), isTrue);
      expect(_selected(tester, 'parent.interest.stories'), isFalse);
      // Nothing changed yet: nothing to save.
      expect(_enabled(tester, 'parent.interests.save'), isFalse);
    });

    testWidgets('save sends the selection and shows success after the server', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.parentSession());
      final path = _parentPath('fam-1', 'child-1');
      h.backend
        ..reply('GET', path, _body(interests: ['science'], pending: ['music']))
        ..on('PUT', path, (r) => _echoPut(r, pending: ['music']));
      await _pumpParent(tester, h);

      await _tap(tester, 'parent.interest.stories');
      expect(_enabled(tester, 'parent.interests.save'), isTrue);
      await _tap(tester, 'parent.interests.save');

      final put = h.backend.requestsTo('PUT', path).single;
      expect(put.headers['Authorization'], 'Bearer parent.jwt.token');
      final data = put.data as Map;
      expect(
        List<String>.from(data['interests'] as List),
        unorderedEquals(['science', 'stories']),
      );
      // The parent's own save leaves the child's request waiting.
      expect(data['clear_pending'], isFalse);
      expect(find.text('Interests updated'), findsOneWidget);
      expect(
        find.byKey(const Key('parent.interests.active.stories')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('parent.interests.pending')), findsOneWidget);
      expect(_enabled(tester, 'parent.interests.save'), isFalse);
    });

    for (final (label, reply) in [
      ('500', FakeReply.error(500, 'internal_error', 'boom')),
      ('403', FakeReply.error(403, 'forbidden', 'Parent access required')),
      ('422', FakeReply.error(422, 'validation_error', 'bad')),
      ('network', const FakeReply.fail(DioExceptionType.connectionError)),
    ]) {
      testWidgets('failed save ($label) keeps the selection, no success', (
        tester,
      ) async {
        final h = await Harness.create(session: Fx.parentSession());
        final path = _parentPath('fam-1', 'child-1');
        h.backend
          ..reply('GET', path, _body(interests: ['science']))
          ..on('PUT', path, (_) => reply);
        await _pumpParent(tester, h);

        await _tap(tester, 'parent.interest.music');
        await _tap(tester, 'parent.interests.save');

        expect(h.backend.requestsTo('PUT', path), hasLength(1));
        expect(find.text('Interests updated'), findsNothing);
        expect(_selected(tester, 'parent.interest.music'), isTrue);
        expect(_selected(tester, 'parent.interest.science'), isTrue);
        // Still unsaved, so the parent can retry.
        expect(_enabled(tester, 'parent.interests.save'), isTrue);
        expect(
          find.byKey(const Key('parent.interests.active.music')),
          findsNothing,
        );
      });
    }

    testWidgets('a double tap on save sends one request', (tester) async {
      final h = await Harness.create(session: Fx.parentSession());
      final path = _parentPath('fam-1', 'child-1');
      h.backend
        ..reply('GET', path, _body(interests: ['science']))
        ..on('PUT', path, _echoPut);
      await _pumpParent(tester, h);

      await _tap(tester, 'parent.interest.music');
      final save = find.byKey(const Key('parent.interests.save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.tap(save, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(h.backend.requestsTo('PUT', path), hasLength(1));
    });

    testWidgets('approve applies exactly the requested set and clears it', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.parentSession());
      final path = _parentPath('fam-1', 'child-1');
      h.backend
        ..reply(
          'GET',
          path,
          _body(
            interests: ['science', 'music'],
            pending: ['science', 'stories'],
          ),
        )
        ..on('PUT', path, _echoPut);
      await _pumpParent(tester, h);

      await _tap(tester, 'parent.interests.approve');

      final data = h.backend.requestsTo('PUT', path).single.data as Map;
      expect(data['interests'], ['science', 'stories']);
      expect(data['clear_pending'], isTrue);
      expect(find.byKey(const Key('parent.interests.pending')), findsNothing);
      expect(
        find.byKey(const Key('parent.interests.active.music')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('parent.interests.active.stories')),
        findsOneWidget,
      );
    });

    testWidgets('dismiss keeps the approved topics and drops unsaved edits', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.parentSession());
      final path = _parentPath('fam-1', 'child-1');
      h.backend
        ..reply(
          'GET',
          path,
          _body(interests: ['science'], pending: ['stories']),
        )
        ..on('PUT', path, _echoPut);
      await _pumpParent(tester, h);

      await _tap(tester, 'parent.interest.music'); // not saved
      await _tap(tester, 'parent.interests.reject');

      final data = h.backend.requestsTo('PUT', path).single.data as Map;
      expect(data['interests'], ['science']);
      expect(data['clear_pending'], isTrue);
      expect(find.byKey(const Key('parent.interests.pending')), findsNothing);
    });

    testWidgets('switching children loads the new child, never stale state', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend
        ..reply(
          'GET',
          _parentPath('fam-1', 'child-1'),
          _body(interests: ['science']),
        )
        ..reply(
          'GET',
          _parentPath('fam-1', 'child-2'),
          _body(interests: ['music']),
        )
        ..on('PUT', _parentPath('fam-1', 'child-2'), _echoPut);
      await _pumpParent(tester, h);
      await _tap(tester, 'parent.interest.stories'); // unsaved, child-1 only

      tester.state<_HostState>(find.byType(_Host)).show('child-2');
      await tester.pumpAndSettle();

      expect(
        h.backend.requestsTo('GET', _parentPath('fam-1', 'child-2')),
        hasLength(1),
      );
      expect(_selected(tester, 'parent.interest.music'), isTrue);
      expect(_selected(tester, 'parent.interest.science'), isFalse);
      expect(_selected(tester, 'parent.interest.stories'), isFalse);

      await _tap(tester, 'parent.interest.science');
      await _tap(tester, 'parent.interests.save');
      expect(
        h.backend.requestsTo('PUT', _parentPath('fam-1', 'child-1')),
        isEmpty,
      );
      expect(
        h.backend.requestsTo('PUT', _parentPath('fam-1', 'child-2')),
        hasLength(1),
      );
    });

    testWidgets('a child outside the family shows a not-linked message', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.on(
        'GET',
        _parentPath('fam-1', 'child-1'),
        (_) => FakeReply.error(404, 'http_error', 'Child profile not found'),
      );
      await _pumpParent(tester, h);
      expect(
        find.textContaining("isn't linked to your account"),
        findsOneWidget,
      );
      expect(find.byKey(const Key('parent.interests.save')), findsNothing);
    });

    testWidgets('missing schema (503) says interests are not ready', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.on(
        'GET',
        _parentPath('fam-1', 'child-1'),
        (_) => FakeReply.error(503, 'http_error', 'not available'),
      );
      await _pumpParent(tester, h);
      expect(find.textContaining("aren't ready yet"), findsOneWidget);
    });

    testWidgets('empty catalogue shows an explicit empty state', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.reply(
        'GET',
        _parentPath('fam-1', 'child-1'),
        _body(interests: [], categories: []),
      );
      await _pumpParent(tester, h);
      expect(find.byKey(const Key('parent.interests.empty')), findsOneWidget);
    });

    for (final locale in const [Locale('hi'), Locale('gu')]) {
      testWidgets('parent card renders in ${locale.languageCode}', (
        tester,
      ) async {
        final h = await Harness.create(session: Fx.parentSession());
        h.backend.reply(
          'GET',
          _parentPath('fam-1', 'child-1'),
          _body(interests: ['science'], pending: ['stories']),
        );
        await _pumpParent(tester, h, locale: locale);
        expect(find.text('Approved topics'), findsNothing);
        expect(find.text('Choose topics'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('child account', () {
    testWidgets('submits the selected topics with the child token', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend
        ..reply('GET', _childPath, _body(interests: ['science']))
        ..on(
          'POST',
          _requestPath,
          (r) => FakeReply(
            200,
            _body(
              interests: ['science'],
              pending: List<String>.from((r.data as Map)['interests'] as List),
            ),
          ),
        );
      await _pumpChild(tester, h);

      await _tap(tester, 'child.interest.stories');
      await _tap(tester, 'child.interests.request');

      final post = h.backend.requestsTo('POST', _requestPath).single;
      expect(post.headers['Authorization'], 'Bearer child.jwt.token');
      expect(
        List<String>.from((post.data as Map)['interests'] as List),
        unorderedEquals(['science', 'stories']),
      );
      expect(find.text('Interest request sent to parent'), findsOneWidget);
      expect(find.byKey(const Key('child.interests.pending')), findsOneWidget);
      // Never calls a parent-only route.
      expect(
        h.backend.requests.where((r) => r.uri.path.contains('/families/')),
        isEmpty,
      );
    });

    testWidgets('an empty selection cannot be sent', (tester) async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply('GET', _childPath, _body(interests: ['science']));
      await _pumpChild(tester, h);

      await _tap(tester, 'child.interest.science'); // deselect the only topic
      expect(find.byKey(const Key('child.interests.pickOne')), findsOneWidget);
      expect(_enabled(tester, 'child.interests.request'), isFalse);
      await tester.tap(
        find.byKey(const Key('child.interests.request')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(h.backend.requestsTo('POST', _requestPath), isEmpty);
    });

    testWidgets('server 422 for an empty request is explained, not faked', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend
        ..reply('GET', _childPath, _body(interests: ['science']))
        ..on(
          'POST',
          _requestPath,
          (_) => FakeReply.error(
            422,
            'interest_request_empty',
            'Choose at least one available topic.',
          ),
        );
      await _pumpChild(tester, h);

      await _tap(tester, 'child.interest.music');
      await _tap(tester, 'child.interests.request');

      expect(find.text('Interest request sent to parent'), findsNothing);
      expect(
        find.text('Pick at least one topic to ask for.'),
        findsAtLeastNWidgets(1),
      );
      expect(_selected(tester, 'child.interest.music'), isTrue);
    });

    testWidgets('a double tap sends one request', (tester) async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend
        ..reply('GET', _childPath, _body(interests: ['science']))
        ..reply(
          'POST',
          _requestPath,
          _body(interests: ['science'], pending: ['science', 'music']),
        );
      await _pumpChild(tester, h);

      await _tap(tester, 'child.interest.music');
      final button = find.byKey(const Key('child.interests.request'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(h.backend.requestsTo('POST', _requestPath), hasLength(1));
    });
  });
}
