import 'package:balkavach_app/features/rewards/data/rewards_repository.dart';
import 'package:balkavach_app/features/rewards/presentation/parent_rewards_screen.dart';
import 'package:balkavach_app/features/rewards/presentation/reward_form_screen.dart';
import 'package:balkavach_app/features/rewards/presentation/rewards_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _otherReward = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('RewardsRepository', () {
    test('idempotency keys are long, random and different each time', () {
      final keys = {for (var i = 0; i < 50; i++) newIdempotencyKey()};
      expect(keys, hasLength(50));
      expect(keys.every((k) => k.length >= 8 && k.length <= 180), isTrue);
    });

    test('a child asks with an Idempotency-Key header', () async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply(
        'POST',
        '/api/v1/redemptions',
        Fx.redemption(),
        status: 201,
      );
      final repo = h.container().read(rewardsRepositoryProvider);
      final result = await repo.requestReward(Fx.rewardId, 'redeem-key-123456');
      expect(result.isPending, isTrue);
      final request = h.backend
          .requestsTo('POST', '/api/v1/redemptions')
          .single;
      expect(request.headers['Idempotency-Key'], 'redeem-key-123456');
      expect(request.data, {'reward_id': Fx.rewardId});
    });

    test('creating sends the family and only the filled fields', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.reply('POST', '/api/v1/rewards', Fx.reward(), status: 201);
      await h
          .container()
          .read(rewardsRepositoryProvider)
          .createReward(
            Fx.familyId,
            const RewardInput(
              name: '  Ice cream ',
              rewardType: 'gift',
              starCost: 12,
              description: '  ',
            ),
          );
      expect(h.backend.requestsTo('POST', '/api/v1/rewards').single.data, {
        'family_id': Fx.familyId,
        'name': 'Ice cream',
        'reward_type': 'gift',
        'star_cost': 12,
      });
    });

    test(
      'editing sends every field and clears a removed description',
      () async {
        final h = await Harness.create(session: Fx.parentSession());
        h.backend.reply('PATCH', '/api/v1/rewards/${Fx.rewardId}', Fx.reward());
        await h
            .container()
            .read(rewardsRepositoryProvider)
            .updateReward(
              Fx.rewardId,
              const RewardInput(name: 'Ice', rewardType: 'custom', starCost: 7),
            );
        expect(
          h.backend
              .requestsTo('PATCH', '/api/v1/rewards/${Fx.rewardId}')
              .single
              .data,
          {'name': 'Ice', 'star_cost': 7, 'description': null},
        );
      },
    );

    test('parent decisions use the documented endpoints', () async {
      final h = await Harness.create(session: Fx.parentSession());
      const id = Fx.redemptionId;
      for (final action in ['approve', 'reject', 'fulfill', 'cancel']) {
        h.backend.reply(
          'POST',
          '/api/v1/redemptions/$id/$action',
          Fx.redemption(),
        );
      }
      final repo = h.container().read(rewardsRepositoryProvider);
      await repo.approve(id);
      await repo.reject(id, note: '  later ');
      await repo.fulfill(id);
      await repo.cancelAsParent(id);
      expect(
        h.backend
            .requestsTo('POST', '/api/v1/redemptions/$id/approve')
            .single
            .data,
        <String, Object?>{},
      );
      expect(
        h.backend
            .requestsTo('POST', '/api/v1/redemptions/$id/reject')
            .single
            .data,
        {'review_note': 'later'},
      );
      expect(
        h.backend.requestsTo('POST', '/api/v1/redemptions/$id/fulfill'),
        hasLength(1),
      );
      expect(
        h.backend.requestsTo('POST', '/api/v1/redemptions/$id/cancel'),
        hasLength(1),
      );
    });

    test('family requests combine pending and approved', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.on('GET', '/api/v1/redemptions', (options) {
        final status = options.queryParameters['status'];
        return FakeReply(200, [
          if (status == 'pending')
            Fx.redemption(rewardName: 'Ice cream', childName: 'Aarav'),
          if (status == 'approved')
            Fx.redemption(
              id: 'done',
              status: 'approved',
              rewardName: 'Toy',
              childName: 'Aarav',
            ),
        ]);
      });
      final container = h.container();
      final list = await container.read(
        familyRedemptionsProvider(Fx.familyId).future,
      );
      expect(list.map((r) => r.status), ['pending', 'approved']);
      expect(list.first.rewardName, 'Ice cream');
      expect(container.read(pendingRedemptionCountProvider(Fx.familyId)), 1);
    });
  });

  test('a request listed as both pending and approved appears once', () async {
    final h = await Harness.create(session: Fx.parentSession());
    // Approved between the two calls: the server can return it in both.
    h.backend.on(
      'GET',
      '/api/v1/redemptions',
      (options) => FakeReply(200, [
        Fx.redemption(
          status: options.queryParameters['status'] as String,
          rewardName: 'Ice cream',
          childName: 'Aarav',
        ),
      ]),
    );
    final list = await h.container().read(
      familyRedemptionsProvider(Fx.familyId).future,
    );
    expect(list, hasLength(1));
    expect(list.single.status, 'approved', reason: 'the later state wins');
  });

  group('child shop', () {
    Future<Harness> pump(
      WidgetTester tester, {
      List<Map<String, Object?>>? requests,
      List<Map<String, Object?>>? catalog,
    }) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
        ..reply(
          'GET',
          '/api/v1/rewards',
          catalog ??
              [
                Fx.reward(),
                Fx.reward(id: _otherReward, name: 'Big toy', cost: 300),
              ],
        )
        ..reply('GET', '/api/v1/redemptions/mine', requests ?? <Object?>[]);
      await pumpScreen(
        tester,
        const Scaffold(body: RewardsScreen()),
        overrides: h.overrides,
      );
      return h;
    }

    testWidgets('shows what can be asked for and what is still out of reach', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Ice cream'), findsOneWidget);
      expect(find.byKey(const Key('reward.ask')), findsOneWidget);
      // 240 stars: the 300-star toy is 60 away
      expect(find.text('60 more stars to go'), findsOneWidget);
    });

    testWidgets('an empty catalog explains what to do', (tester) async {
      await pump(tester, catalog: <Map<String, Object?>>[]);
      expect(
        find.text('No rewards yet. Ask your parent to add some!'),
        findsOneWidget,
      );
    });

    testWidgets('asking confirms first, then sends one request with a key', (
      tester,
    ) async {
      final h = await pump(tester);
      h.backend.reply(
        'POST',
        '/api/v1/redemptions',
        Fx.redemption(),
        status: 201,
      );
      await _tap(tester, find.byKey(const Key('reward.ask')));
      expect(find.text('Ask for Ice cream?'), findsOneWidget);
      expect(h.backend.requestsTo('POST', '/api/v1/redemptions'), isEmpty);

      await _tap(tester, find.byKey(const Key('reward.confirm')));
      final posts = h.backend.requestsTo('POST', '/api/v1/redemptions');
      expect(posts, hasLength(1));
      expect(posts.single.headers['Idempotency-Key'], startsWith('redeem-'));
      expect(find.text('Request sent to your parent!'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      final h = await pump(tester);
      await _tap(tester, find.byKey(const Key('reward.ask')));
      await _tap(tester, find.text('Cancel'));
      expect(h.backend.requestsTo('POST', '/api/v1/redemptions'), isEmpty);
    });

    testWidgets('a retry after a lost connection re-uses the same key', (
      tester,
    ) async {
      final h = await pump(tester);
      var calls = 0;
      h.backend.on('POST', '/api/v1/redemptions', (_) {
        calls++;
        return calls == 1
            ? const FakeReply.fail(DioExceptionType.connectionError)
            : FakeReply(201, Fx.redemption());
      });
      await _tap(tester, find.byKey(const Key('reward.ask')));
      await _tap(tester, find.byKey(const Key('reward.confirm')));
      expect(
        find.text('Can\'t reach Bal Kavach. Check your internet connection.'),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 5));
      await _tap(tester, find.byKey(const Key('reward.ask')));
      await _tap(tester, find.byKey(const Key('reward.confirm')));
      final keys = h.backend
          .requestsTo('POST', '/api/v1/redemptions')
          .map((r) => r.headers['Idempotency-Key'])
          .toList();
      expect(keys, hasLength(2));
      expect(keys.first, keys.last);
    });

    testWidgets(
      'a definite refusal is explained and the next ask uses a new key',
      (tester) async {
        final h = await pump(tester);
        var calls = 0;
        h.backend.on('POST', '/api/v1/redemptions', (_) {
          calls++;
          return calls == 1
              ? FakeReply.error(409, 'insufficient_stars', 'not enough')
              : FakeReply(201, Fx.redemption());
        });
        await _tap(tester, find.byKey(const Key('reward.ask')));
        await _tap(tester, find.byKey(const Key('reward.confirm')));
        expect(
          find.text('There aren\'t enough stars for this.'),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 5));
        await _tap(tester, find.byKey(const Key('reward.ask')));
        await _tap(tester, find.byKey(const Key('reward.confirm')));
        final keys = h.backend
            .requestsTo('POST', '/api/v1/redemptions')
            .map((r) => r.headers['Idempotency-Key'])
            .toList();
        expect(keys, hasLength(2));
        expect(
          keys.first,
          isNot(keys.last),
          reason: 'a refused request must not be replayed under its old key',
        );
      },
    );

    testWidgets('stars promised to a pending request are not offered twice', (
      tester,
    ) async {
      await pump(
        tester,
        requests: [Fx.redemption(rewardId: _otherReward, cost: 200)],
      );
      // 240 - 200 reserved = 40 available < 50
      expect(find.byKey(const Key('reward.ask')), findsNothing);
      expect(find.text('10 more stars to go'), findsOneWidget);
    });

    testWidgets(
      'a reward that is already asked for shows waiting, not a button',
      (tester) async {
        await pump(tester, requests: [Fx.redemption()]);
        expect(find.text('Waiting for your parent'), findsOneWidget);
        expect(find.byKey(const Key('reward.ask')), findsNothing);
      },
    );

    testWidgets('a pending request can be cancelled', (tester) async {
      final h = await pump(tester, requests: [Fx.redemption()]);
      h.backend.reply(
        'POST',
        '/api/v1/redemptions/${Fx.redemptionId}/cancel/mine',
        Fx.redemption(status: 'cancelled'),
      );
      await _tap(
        tester,
        find.byKey(const Key('reward.cancel.${Fx.redemptionId}')),
      );
      expect(
        h.backend.requestsTo(
          'POST',
          '/api/v1/redemptions/${Fx.redemptionId}/cancel/mine',
        ),
        hasLength(1),
      );
    });

    testWidgets('the parent\'s note on a declined request is shown', (
      tester,
    ) async {
      await pump(
        tester,
        requests: [
          Fx.redemption(status: 'rejected', reviewNote: 'after dinner'),
        ],
      );
      expect(find.text('Parent\'s note: after dinner'), findsOneWidget);
    });
  });

  group('parent rewards', () {
    Future<Harness> pump(
      WidgetTester tester, {
      List<Map<String, Object?>> pending = const [],
      List<Map<String, Object?>> approved = const [],
    }) async {
      final h = await Harness.create(
        session: Fx.parentSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..on('GET', '/api/v1/redemptions', (options) {
          final status = options.queryParameters['status'];
          return FakeReply(200, status == 'pending' ? pending : approved);
        })
        ..reply('GET', '/api/v1/rewards', [Fx.reward()]);
      await pumpScreen(
        tester,
        const ParentRewardsScreen(),
        overrides: h.overrides,
      );
      return h;
    }

    Map<String, Object?> request({String status = 'pending'}) => Fx.redemption(
      status: status,
      rewardName: 'Ice cream',
      childName: 'Aarav',
    );

    testWidgets('lists a request in words a parent understands', (
      tester,
    ) async {
      await pump(tester, pending: [request()]);
      expect(find.text('Aarav asked for Ice cream'), findsOneWidget);
      expect(find.text('Requests (1)'), findsOneWidget);
    });

    testWidgets('an empty inbox says so', (tester) async {
      await pump(tester);
      expect(find.text('No requests waiting.'), findsOneWidget);
    });

    testWidgets('approving calls the server once and states the stars taken', (
      tester,
    ) async {
      final h = await pump(tester, pending: [request()]);
      h.backend.reply(
        'POST',
        '/api/v1/redemptions/${Fx.redemptionId}/approve',
        Fx.redemption(status: 'approved'),
      );
      await _tap(tester, find.byKey(const Key('request.approve')));
      expect(
        h.backend.requestsTo(
          'POST',
          '/api/v1/redemptions/${Fx.redemptionId}/approve',
        ),
        hasLength(1),
      );
      expect(find.text('Approved. 50 stars were taken.'), findsOneWidget);
    });

    testWidgets('declining asks for an optional note and sends it', (
      tester,
    ) async {
      final h = await pump(tester, pending: [request()]);
      h.backend.reply(
        'POST',
        '/api/v1/redemptions/${Fx.redemptionId}/reject',
        Fx.redemption(status: 'rejected'),
      );
      await _tap(tester, find.byKey(const Key('request.decline')));
      await tester.enterText(
        find.byKey(const Key('request.note')),
        'not today',
      );
      await _tap(tester, find.byKey(const Key('request.decline.confirm')));
      expect(
        h.backend
            .requestsTo('POST', '/api/v1/redemptions/${Fx.redemptionId}/reject')
            .single
            .data,
        {'review_note': 'not today'},
      );
    });

    testWidgets(
      'someone else handled it first: friendly message, list refreshed',
      (tester) async {
        final h = await pump(tester, pending: [request()]);
        h.backend.on(
          'POST',
          '/api/v1/redemptions/${Fx.redemptionId}/approve',
          (_) => FakeReply.error(409, 'redemption_already_reviewed', 'done'),
        );
        await _tap(tester, find.byKey(const Key('request.approve')));
        expect(find.text('This request was already handled.'), findsOneWidget);
        expect(
          h.backend.requestsTo('GET', '/api/v1/redemptions').length,
          greaterThan(2),
        );
      },
    );

    testWidgets('not enough stars at approval time is explained', (
      tester,
    ) async {
      final h = await pump(tester, pending: [request()]);
      h.backend.on(
        'POST',
        '/api/v1/redemptions/${Fx.redemptionId}/approve',
        (_) => FakeReply.error(409, 'insufficient_stars', 'low'),
      );
      await _tap(tester, find.byKey(const Key('request.approve')));
      expect(find.text('There aren\'t enough stars for this.'), findsOneWidget);
    });

    testWidgets(
      'an approved request can be handed over or cancelled with a refund',
      (tester) async {
        final h = await pump(tester, approved: [request(status: 'approved')]);
        h.backend
          ..reply(
            'POST',
            '/api/v1/redemptions/${Fx.redemptionId}/fulfill',
            Fx.redemption(status: 'fulfilled'),
          )
          ..reply(
            'POST',
            '/api/v1/redemptions/${Fx.redemptionId}/cancel',
            Fx.redemption(status: 'cancelled'),
          );
        await _tap(tester, find.byKey(const Key('request.fulfill')));
        expect(find.text('Marked as given'), findsOneWidget);
        await _tap(tester, find.byKey(const Key('request.refund')));
        expect(
          h.backend.requestsTo(
            'POST',
            '/api/v1/redemptions/${Fx.redemptionId}/cancel',
          ),
          hasLength(1),
        );
      },
    );

    testWidgets('removing a reward asks first, then deletes it', (
      tester,
    ) async {
      final h = await pump(tester);
      h.backend.reply(
        'DELETE',
        '/api/v1/rewards/${Fx.rewardId}',
        null,
        status: 204,
      );
      await _tap(tester, find.byKey(const Key('rewards.tab.catalog')));
      expect(find.text('Ice cream'), findsOneWidget);
      await _tap(
        tester,
        find.byKey(const Key('catalog.remove.${Fx.rewardId}')),
      );
      expect(
        find.text('Remove Ice cream? Children will no longer see it.'),
        findsOneWidget,
      );
      expect(
        h.backend.requestsTo('DELETE', '/api/v1/rewards/${Fx.rewardId}'),
        isEmpty,
      );
      await _tap(tester, find.byKey(const Key('catalog.remove.confirm')));
      expect(
        h.backend.requestsTo('DELETE', '/api/v1/rewards/${Fx.rewardId}'),
        hasLength(1),
      );
    });
  });

  group('reward form', () {
    Future<Harness> pump(WidgetTester tester, {String? rewardId}) async {
      final h = await Harness.create(
        session: Fx.parentSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..reply('GET', '/api/v1/rewards', [Fx.reward(description: 'One scoop')])
        ..reply('POST', '/api/v1/rewards', Fx.reward(), status: 201)
        ..reply('PATCH', '/api/v1/rewards/${Fx.rewardId}', Fx.reward());
      await pumpScreen(
        tester,
        RewardFormScreen(rewardId: rewardId),
        overrides: h.overrides,
      );
      return h;
    }

    testWidgets('validates before calling the server', (tester) async {
      final h = await pump(tester);
      await tester.enterText(find.byKey(const Key('reward.name')), 'x');
      await tester.enterText(find.byKey(const Key('reward.cost')), '0');
      await _tap(tester, find.byKey(const Key('reward.save')));
      expect(find.text('Enter a number from 1 to 100000.'), findsOneWidget);
      expect(h.backend.requestsTo('POST', '/api/v1/rewards'), isEmpty);
    });

    testWidgets('creates a reward', (tester) async {
      final h = await pump(tester);
      await tester.enterText(
        find.byKey(const Key('reward.name')),
        'Movie night',
      );
      await tester.enterText(find.byKey(const Key('reward.cost')), '30');
      await _tap(tester, find.byKey(const Key('reward.save')));
      expect(h.backend.requestsTo('POST', '/api/v1/rewards').single.data, {
        'family_id': Fx.familyId,
        'name': 'Movie night',
        'reward_type': 'custom',
        'star_cost': 30,
      });
    });

    testWidgets('editing pre-fills the form and patches', (tester) async {
      final h = await pump(tester, rewardId: Fx.rewardId);
      expect(find.widgetWithText(TextFormField, 'Ice cream'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'One scoop'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('reward.cost')), '75');
      await _tap(tester, find.byKey(const Key('reward.save')));
      final body =
          h.backend
                  .requestsTo('PATCH', '/api/v1/rewards/${Fx.rewardId}')
                  .single
                  .data
              as Map;
      expect(body['star_cost'], 75);
      expect(body['name'], 'Ice cream');
    });

    testWidgets('a server refusal stays on the form with a message', (
      tester,
    ) async {
      final h = await pump(tester);
      h.backend.on(
        'POST',
        '/api/v1/rewards',
        (_) => FakeReply.error(404, 'http_error', 'Family not found'),
      );
      await tester.enterText(
        find.byKey(const Key('reward.name')),
        'Movie night',
      );
      await _tap(tester, find.byKey(const Key('reward.save')));
      expect(find.byKey(const Key('reward.error')), findsOneWidget);
    });
  });
}
