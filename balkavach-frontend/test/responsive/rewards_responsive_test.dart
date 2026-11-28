// Phase 7: responsive UI & UX verification for Rewards across phone, tablet,
// and desktop viewports, text scaling, localization, and states.
import 'dart:async';

import 'package:balkavach_app/features/missions/presentation/child_shell.dart';
import 'package:balkavach_app/features/progress/data/progress_repository.dart';
import 'package:balkavach_app/features/rewards/presentation/rewards_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _matrix = <String, Size>{
  'small phone': Size(320, 640),
  'standard phone': Size(360, 800),
  'large phone': Size(412, 915),
  'small tablet': Size(600, 960),
  'large tablet': Size(800, 1280),
  'desktop': Size(1280, 800),
};

Future<Harness> _harness({
  int stars = 240,
  int streak = 4,
  List<Map<String, Object?>>? rewards,
  List<Map<String, Object?>>? redemptions,
}) async {
  final session = Fx.childSession();
  final h = await Harness.create(session: session, prefs: onboardedPrefs);
  h.backend
    ..reply('GET', '/api/v1/auth/me', session.user.toJson())
    ..reply('GET', '/api/v1/progress/children/${Fx.childId}', {
      ...Fx.progress(
        badges: [
          Fx.badge(
            name: 'Super Helper of the Entire Neighbourhood',
            description: 'Finish ten chores promptly without being reminded',
          ),
          Fx.badge(id: 'b2', name: 'Bookworm'),
          Fx.badge(id: 'b3', name: 'Yoga Champ'),
        ],
      ),
      'star_balance': stars,
      'current_streak': streak,
    })
    ..reply(
      'GET',
      '/api/v1/redemptions/mine',
      redemptions ?? [Fx.redemption(cost: 1500)],
    )
    ..reply(
      'GET',
      '/api/v1/rewards',
      rewards ??
          [
            Fx.reward(
              name:
                  'A Special Evening Out With The Whole Family To The Big Park',
              cost: 1500,
            ),
            Fx.reward(id: 'r2', name: 'Sticker', cost: 5, description: null),
          ],
    );
  return h;
}

void main() {
  for (final MapEntry(key: name, value: size) in _matrix.entries) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('responsive matrix: $name @ ${scale}x', (tester) async {
        final h = await _harness(stars: 1234567);
        await pumpScreen(
          tester,
          const ChildShell(location: '/child/rewards', child: RewardsScreen()),
          overrides: h.overrides,
          size: size,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('1,234,567'), findsOneWidget);

        final listRect = tester.getRect(find.byType(ListView).first);
        expect(listRect.width, lessThanOrEqualTo(size.width + 0.1));

        final card = find.byKey(const Key('reward.${Fx.rewardId}'));
        final cardRect = tester.getRect(card);
        expect(cardRect.right, lessThanOrEqualTo(size.width));
        if (size.width >= 1000) {
          // Desktop caps card width instead of stretching across the whole screen.
          expect(cardRect.width, lessThan(size.width * 0.8));
        }

        final badge = find.byType(BadgeTile).first;
        final share = find.descendant(
          of: badge,
          matching: find.byType(IconButton),
        );
        final avatar = find.descendant(
          of: badge,
          matching: find.byType(CircleAvatar),
        );
        expect(tester.getRect(share).overlaps(tester.getRect(avatar)), isFalse);
      });
    }
  }

  for (final locale in const [Locale('en'), Locale('hi'), Locale('gu')]) {
    testWidgets('localized text fits without overflow ($locale)', (
      tester,
    ) async {
      final h = await _harness(stars: 98765);
      await pumpScreen(
        tester,
        const ChildShell(location: '/child/rewards', child: RewardsScreen()),
        overrides: h.overrides,
        size: const Size(320, 640),
        textScale: 1.5,
        locale: locale,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('98,765'), findsOneWidget);
    });
  }

  testWidgets('empty catalog and empty requests show helpful empty states', (
    tester,
  ) async {
    final h = await _harness(rewards: const [], redemptions: const []);
    await pumpScreen(
      tester,
      const ChildShell(location: '/child/rewards', child: RewardsScreen()),
      overrides: h.overrides,
      size: const Size(360, 800),
    );
    expect(find.byKey(const Key('rewards.requests.empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading state does not crash or invent zero balances', (
    tester,
  ) async {
    final session = Fx.childSession();
    final h = await Harness.create(session: session, prefs: onboardedPrefs);
    final gate = Completer<ChildProgress>();
    h.backend.reply('GET', '/api/v1/auth/me', session.user.toJson());

    await pumpScreen(
      tester,
      const ChildShell(location: '/child/rewards', child: RewardsScreen()),
      overrides: [
        ...h.overrides,
        childProgressProvider.overrideWith((_, _) => gate.future),
      ],
      size: const Size(360, 800),
      settle: false,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('0'), findsNothing);
    gate.complete(ChildProgress.fromJson(Fx.progress()));
    await tester.pumpAndSettle();
  });

  testWidgets('API error shows retry and recovers on retry', (tester) async {
    final session = Fx.childSession();
    final h = await Harness.create(session: session, prefs: onboardedPrefs);
    var fail = true;
    h.backend
      ..reply('GET', '/api/v1/auth/me', session.user.toJson())
      ..on('GET', '/api/v1/progress/children/${Fx.childId}', (_) {
        if (fail) return FakeReply.error(500, 'server_error', 'Unavailable');
        return FakeReply(200, {...Fx.progress(), 'star_balance': 321});
      })
      ..reply('GET', '/api/v1/redemptions/mine', const <Object?>[])
      ..reply('GET', '/api/v1/rewards', const <Object?>[]);

    await pumpScreen(
      tester,
      const ChildShell(location: '/child/rewards', child: RewardsScreen()),
      overrides: h.overrides,
      size: const Size(360, 800),
    );
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    fail = false;
    await tester.pumpAndSettle();
    expect(find.text('321'), findsOneWidget);
  });

  testWidgets('scrolling and bottom navigation remain unobstructed', (
    tester,
  ) async {
    final h = await _harness();
    await pumpScreen(
      tester,
      const ChildShell(location: '/child/rewards', child: RewardsScreen()),
      overrides: h.overrides,
      size: const Size(360, 800),
    );
    final nav = tester.getRect(find.byType(NavigationBar));
    await tester.drag(find.byType(ListView).first, const Offset(0, -1500));
    await tester.pumpAndSettle();
    final list = tester.getRect(find.byType(ListView).first);
    expect(list.bottom, lessThanOrEqualTo(nav.top + 0.1));
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
