import 'package:balkavach_app/core/theme/app_theme.dart';
import 'package:balkavach_app/features/missions/presentation/mission_approval_celebrator.dart';
import 'package:balkavach_app/features/missions/presentation/mission_providers.dart';
import 'package:balkavach_app/features/progress/data/milestone_store.dart';
import 'package:balkavach_app/features/progress/data/progress_repository.dart';
import 'package:balkavach_app/features/progress/presentation/achievements_widgets.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _progressPath = '/api/v1/progress/children/${Fx.childId}';
const _achievementsPath = '$_progressPath/achievements';
const _mine = '/api/v1/tasks/submissions/mine';

Map<String, Object?> _badge(String id, String name, String at) => {
  ...Fx.badge(id: id, name: name),
  'unlocked_at': at,
};

Map<String, Object?> _progress(
  int level, {
  String name = 'Explorer',
  List<Map<String, Object?>> badges = const [],
}) => {
  ...Fx.progress(badges: badges),
  'level_number': level,
  'level_name': name,
};

Map<String, Object?> _ach({
  int total = 420,
  int min = 300,
  int? next = 700,
  int level = 3,
  List<Map<String, Object?>> badges = const [],
}) => {
  'level': {
    'level_number': level,
    'name': 'Explorer',
    'minimum_xp': min,
    'next_level_number': next == null ? null : level + 1,
    'next_level_name': next == null ? null : 'Hero',
    'next_minimum_xp': next,
    'total_xp': total,
  },
  'badges': badges,
};

Map<String, Object?> _lockedBadge(
  String id,
  String name, {
  int? threshold = 10,
  int? current = 3,
  String? description = 'Do it',
}) => {
  'badge_id': id,
  'name': name,
  'description': description,
  'icon_url': null,
  'unlocked': false,
  'unlocked_at': null,
  'criteria_type': 'total_xp',
  'threshold': threshold,
  'current': current,
};

void main() {
  group('Achievements models', () {
    test('progress fractions come from the server numbers and are clamped', () {
      final a = Achievements.fromJson(
        _ach(
          badges: [
            _lockedBadge('b1', 'A', threshold: 10, current: 3),
            _lockedBadge('b2', 'B', threshold: 5, current: 9),
            _lockedBadge('b3', 'C', threshold: null, current: null),
          ],
        ),
      );
      expect(a.badges[0].fraction, closeTo(0.3, 1e-9));
      expect(a.badges[1].fraction, 1.0); // over target stays full
      expect(a.badges[2].hasProgress, isFalse); // nothing invented
      expect(a.badges[2].fraction, isNull);
      expect(a.locked, hasLength(3));
    });

    test('level progress: distance to the next level, and the top level', () {
      final mid = LevelProgress.fromJson(
        _ach(total: 420, min: 300, next: 700)['level']! as Map<String, dynamic>,
      );
      expect(mid.xpToNext, 280);
      expect(mid.fraction, closeTo(120 / 400, 1e-9));
      expect(mid.isTopLevel, isFalse);
      final top = LevelProgress.fromJson(
        _ach(total: 5000, min: 3000, next: null)['level']!
            as Map<String, dynamic>,
      );
      expect(top.isTopLevel, isTrue);
      expect(top.fraction, isNull);
      expect(top.xpToNext, isNull);
    });
  });

  group('MilestoneStore', () {
    Future<(MilestoneStore, Harness)> store() async {
      final h = await Harness.create(session: Fx.childSession());
      return (MilestoneStore(h.prefs), h);
    }

    ChildProgress progress(
      int level, {
      List<Map<String, Object?>> badges = const [],
    }) => ChildProgress.fromJson(_progress(level, badges: badges));

    test('the first look is a silent baseline', () async {
      final (s, _) = await store();
      final p = progress(
        4,
        badges: [_badge('b1', 'Old', '2026-10-01T09:00:00Z')],
      );
      expect(s.baselineDone(Fx.childId), isFalse);
      await s.recordBaseline(Fx.childId, p);
      expect(s.baselineDone(Fx.childId), isTrue);
      expect(s.pending(Fx.childId, p), isEmpty);
    });

    test('a higher level is one level-up; reaching Level 1 is not', () async {
      final (s, _) = await store();
      await s.recordBaseline(Fx.childId, ChildProgress.fromJson(Fx.progress()));
      // baseline stored level 4 (the fixture), so 4 is not news
      expect(s.pending(Fx.childId, progress(4)), isEmpty);
      // a jump of two levels is one celebration, for the level reached
      final jump = s.pending(Fx.childId, progress(6));
      expect(jump.single.kind, MilestoneKind.level);
      expect(jump.single.levelNumber, 6);
      await s.markLevelSeen(Fx.childId, 6);
      expect(s.pending(Fx.childId, progress(6)), isEmpty);
      // a lower number from the server never un-celebrates or re-celebrates
      expect(s.pending(Fx.childId, progress(5)), isEmpty);
    });

    test('a new child reaching Level 1 is not a level-up', () async {
      final (s, _) = await store();
      final fresh = ChildProgress.fromJson({
        ...Fx.progress(),
        'level_number': null,
        'level_name': null,
      });
      await s.recordBaseline(Fx.childId, fresh);
      expect(s.pending(Fx.childId, progress(1)), isEmpty);
      await s.acknowledgeStartingLevel(Fx.childId, progress(1));
      expect(s.pending(Fx.childId, progress(2)).single.levelNumber, 2);
    });

    test('new badges come oldest first, once, and survive a restart', () async {
      final (s, h) = await store();
      await s.recordBaseline(Fx.childId, progress(4));
      final p = progress(
        4,
        badges: [
          _badge('b2', 'Second', '2026-10-12T10:00:00Z'),
          _badge('b1', 'First', '2026-10-12T09:00:00Z'),
          _badge('b1', 'First', '2026-10-12T09:00:00Z'), // duplicate row
        ],
      );
      final pending = s.pending(Fx.childId, p);
      expect([for (final m in pending) m.id], ['b1', 'b2']);
      await s.markBadgeSeen(Fx.childId, 'b1');
      await s.markBadgeSeen(Fx.childId, 'b1');
      final restarted = MilestoneStore(h.prefs);
      expect([for (final m in restarted.pending(Fx.childId, p)) m.id], ['b2']);
      // Another child has no record on this device yet: their first look is a baseline.
      expect(restarted.baselineDone('someone-else'), isFalse);
    });
  });

  group('Achievement widgets', () {
    Future<void> show(
      WidgetTester tester,
      Harness h,
      Widget child, {
      Locale locale = const Locale('en'),
      Size size = const Size(393, 852),
      double scale = 1,
    }) async {
      setWindow(tester, size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          retry: (_, _) => null,
          child: MaterialApp(
            theme: buildAppTheme(),
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, app) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: app!,
            ),
            home: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('level card shows the real level and distance to the next', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply('GET', _achievementsPath, _ach());
      await show(tester, h, const LevelProgressCard(childId: Fx.childId));
      expect(find.text('Lv 3 · Explorer'), findsOneWidget);
      expect(find.text('280 XP to Level 4'), findsOneWidget);
    });

    testWidgets('level card at the top level says so', (tester) async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply(
        'GET',
        _achievementsPath,
        _ach(total: 9000, min: 3000, next: null, level: 6),
      );
      await show(tester, h, const LevelProgressCard(childId: Fx.childId));
      expect(find.text('You reached the top level!'), findsOneWidget);
    });

    testWidgets('a new child at zero XP shows an empty bar, not a fake one', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply(
        'GET',
        _achievementsPath,
        _ach(total: 0, min: 0, next: 100, level: 1),
      );
      await show(tester, h, const LevelProgressCard(childId: Fx.childId));
      expect(find.text('Lv 1 · Explorer'), findsOneWidget);
      expect(find.text('100 XP to Level 2'), findsOneWidget);
    });

    testWidgets('level card and locked list are hidden when data fails', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.on(
        'GET',
        _achievementsPath,
        (_) => const FakeReply.fail(DioExceptionType.connectionError),
      );
      await show(
        tester,
        h,
        const Column(
          children: [
            LevelProgressCard(childId: Fx.childId),
            LockedBadgesSection(childId: Fx.childId),
          ],
        ),
      );
      expect(find.byKey(const Key('level.card')), findsNothing);
      expect(find.byKey(const Key('badges.locked')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locked badges show real progress, and none when unmeasured', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply(
        'GET',
        _achievementsPath,
        _ach(
          badges: [
            _lockedBadge('b1', 'XP Climber', threshold: 10, current: 3),
            _lockedBadge('b2', 'Mystery', threshold: null, current: null),
            {
              ..._lockedBadge('b3', 'Earned'),
              'unlocked': true,
              'unlocked_at': '2026-10-01T09:00:00Z',
            },
          ],
        ),
      );
      await show(tester, h, const LockedBadgesSection(childId: Fx.childId));
      expect(find.text('XP Climber'), findsOneWidget);
      expect(find.text('3 of 10'), findsOneWidget);
      expect(find.text('Mystery'), findsOneWidget);
      expect(
        find.textContaining(' of '),
        findsOneWidget,
      ); // only the measured one
      expect(find.text('Earned'), findsNothing); // earned ones live elsewhere
    });

    testWidgets('nothing locked: the section is not shown', (tester) async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply('GET', _achievementsPath, _ach());
      await show(tester, h, const LockedBadgesSection(childId: Fx.childId));
      expect(find.byKey(const Key('badges.locked')), findsNothing);
    });

    for (final (locale, keep, xp) in [
      (const Locale('hi'), 'आगे बढ़ते रहो!', 'लेवल 4 तक 280 XP'),
      (const Locale('gu'), 'આગળ વધતા રહો!', 'લેવલ 4 સુધી 280 XP'),
    ]) {
      testWidgets('is localised for ${locale.languageCode}', (tester) async {
        final h = await Harness.create(session: Fx.childSession());
        h.backend.reply(
          'GET',
          _achievementsPath,
          _ach(badges: [_lockedBadge('b1', 'X')]),
        );
        await show(
          tester,
          h,
          const Column(
            children: [
              LevelProgressCard(childId: Fx.childId),
              LockedBadgesSection(childId: Fx.childId),
            ],
          ),
          locale: locale,
          size: const Size(320, 568),
          scale: 2,
        );
        expect(find.text(keep), findsOneWidget);
        expect(find.text(xp), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Level-up and badge celebrations', () {
    Future<Harness> harness(Map<String, Object?> progress) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..reply('GET', _progressPath, progress)
        ..reply('GET', _mine, <Object?>[]);
      return h;
    }

    Future<void> open(WidgetTester tester, Harness h) async {
      setWindow(tester, const Size(393, 852));
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: h.overrides,
          retry: (_, _) => null,
          child: MaterialApp(
            theme: buildAppTheme(),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const MissionApprovalCelebrator(
              child: Scaffold(body: Text('CHILD AREA')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The first look (the silent baseline) must finish before the test
      // changes what the server says.
      for (var i = 0; i < 40; i++) {
        if (h.prefs.levelSeen(Fx.childId) != null) break;
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Let a restart's first pass (and any celebration it starts) finish.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    }

    Future<void> reload(WidgetTester tester) async {
      ProviderScope.containerOf(tester.element(find.text('CHILD AREA')))
        ..invalidate(childProgressProvider(Fx.childId))
        ..invalidate(mySubmissionsProvider);
      await tester.pumpAndSettle();
    }

    Future<void> dismiss(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('celebration.continue')));
      await tester.pumpAndSettle();
    }

    testWidgets('a level-up celebrates once, with the server level', (
      tester,
    ) async {
      final h = await harness(_progress(4));
      await open(tester, h);
      expect(find.byKey(const Key('celebration.card')), findsNothing);

      h.backend.reply('GET', _progressPath, _progress(5, name: 'Hero'));
      await reload(tester);
      expect(find.text('Level up!'), findsOneWidget);
      expect(find.text('Lv 5 · Hero'), findsOneWidget);
      expect(find.byKey(const Key('celebration.rewards')), findsNothing);
      await dismiss(tester);
      await reload(tester);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
      // App restart: still not replayed.
      await tester.pumpWidget(const SizedBox());
      await open(tester, h);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
    });

    testWidgets('a new badge celebrates once by name', (tester) async {
      final h = await harness(_progress(4));
      await open(tester, h);
      h.backend.reply(
        'GET',
        _progressPath,
        _progress(
          4,
          badges: [_badge('b1', 'Bookworm', '2026-10-12T09:00:00Z')],
        ),
      );
      await reload(tester);
      expect(find.text('New badge!'), findsOneWidget);
      expect(find.text('Bookworm'), findsOneWidget);
      await dismiss(tester);
      await reload(tester);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
    });

    testWidgets('badges already held at first look are history', (
      tester,
    ) async {
      final h = await harness(
        _progress(4, badges: [_badge('b1', 'Old', '2026-10-01T09:00:00Z')]),
      );
      await open(tester, h);
      await reload(tester);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
    });

    testWidgets('level-up then badge play in order, one at a time', (
      tester,
    ) async {
      final h = await harness(_progress(4));
      await open(tester, h);
      h.backend.reply(
        'GET',
        _progressPath,
        _progress(
          5,
          badges: [_badge('b1', 'Bookworm', '2026-10-12T09:00:00Z')],
        ),
      );
      await reload(tester);
      expect(find.text('Level up!'), findsOneWidget);
      expect(find.byKey(const Key('celebration.card')), findsOneWidget);
      await dismiss(tester);
      expect(find.text('New badge!'), findsOneWidget);
      expect(find.byKey(const Key('celebration.card')), findsOneWidget);
      await dismiss(tester);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
    });

    testWidgets('an approval and a level-up never overlap', (tester) async {
      final h = await harness(_progress(4));
      await open(tester, h);
      h.backend
        ..reply('GET', _progressPath, _progress(5))
        ..reply('GET', _mine, [
          {
            ...Fx.submission(
              id: '00000000-0000-4000-8000-000000000001',
              status: 'approved',
              taskTitle: 'Water the plants',
            ),
            'stars_awarded': 10,
            'xp_awarded': 15,
            'reviewed_at': '2026-10-12T12:00:00Z',
          },
        ]);
      await reload(tester);
      final seen = <String>[];
      for (var i = 0; i < 4; i++) {
        final cards = find.byKey(const Key('celebration.card'));
        if (cards.evaluate().isEmpty) break;
        expect(cards, findsOneWidget, reason: 'never two at once');
        seen.add(
          (tester.widget<Text>(
            find.byKey(const Key('celebration.headline')),
          )).data!,
        );
        await dismiss(tester);
      }
      expect(seen, containsAll(['Mission approved!', 'Level up!']));
      expect(seen.length, 2);
    });

    testWidgets('an interrupted level-up celebration comes back', (
      tester,
    ) async {
      final h = await harness(_progress(4));
      await open(tester, h);
      h.backend.reply('GET', _progressPath, _progress(5));
      await reload(tester);
      expect(find.text('Level up!'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // killed before Continue
      await open(tester, h);
      expect(find.text('Level up!'), findsOneWidget);
      await dismiss(tester);
      await tester.pumpWidget(const SizedBox());
      await open(tester, h);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
    });

    testWidgets('failed progress celebrates nothing', (tester) async {
      final h = await harness(_progress(4));
      h.backend.on(
        'GET',
        _progressPath,
        (_) => const FakeReply.fail(DioExceptionType.connectionError),
      );
      await open(tester, h);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a level-up writes nothing to the server', (tester) async {
      final h = await harness(_progress(4));
      await open(tester, h);
      h.backend.reply('GET', _progressPath, _progress(5));
      await reload(tester);
      await dismiss(tester);
      expect(h.backend.requests.where((r) => r.method != 'GET'), isEmpty);
    });
  });
}
