import 'package:balkavach_app/core/theme/app_theme.dart';
import 'package:balkavach_app/features/missions/data/approval_celebration_store.dart';
import 'package:balkavach_app/features/missions/domain/mission_models.dart';
import 'package:balkavach_app/features/missions/presentation/mission_approval_celebrator.dart';
import 'package:balkavach_app/features/missions/presentation/mission_providers.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _mine = '/api/v1/tasks/submissions/mine';

String _id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

Map<String, Object?> _sub(
  int n, {
  String status = 'approved',
  int? stars = 10,
  int? xp = 15,
  String title = 'Water the plants',
  String? reviewedAt,
}) => {
  ...Fx.submission(
    id: _id(n),
    status: status,
    taskTitle: title,
    number: n,
    submittedAt: '2026-10-12T09:0$n:00Z',
  ),
  'reviewed_at': ?reviewedAt,
  'stars_awarded': ?stars,
  'xp_awarded': ?xp,
};

TaskSubmission _model(Map<String, Object?> json) =>
    TaskSubmission.fromJson(json.cast<String, dynamic>());

void main() {
  group('ApprovalCelebrationStore', () {
    Future<ApprovalCelebrationStore> store() async {
      final h = await Harness.create(session: Fx.childSession());
      return ApprovalCelebrationStore(h.prefs);
    }

    test(
      'a newly approved mission carries the server amounts, untouched',
      () async {
        final s = await store();
        await s.recordBaseline(Fx.childId, const []);
        final pending = s.pending(Fx.childId, [
          _model(_sub(1, stars: 7, xp: 9, title: 'Read')),
        ]);
        expect(pending, hasLength(1));
        expect(pending.single.stars, 7); // not a Flutter-side 10
        expect(pending.single.xp, 9);
        expect(pending.single.title, 'Read');
      },
    );

    test('only approved submissions with a confirmed reward qualify', () async {
      final s = await store();
      final pending = s.pending(Fx.childId, [
        _model(_sub(1, status: 'pending', stars: 0, xp: 0)),
        _model(_sub(2, status: 'rejected', stars: 0, xp: 0)),
        _model(_sub(3, status: 'resubmission_requested', stars: 0, xp: 0)),
        _model(_sub(4, status: 'cancelled', stars: 0, xp: 0)),
        _model(_sub(5, stars: null, xp: null)), // approved, reward unknown
        _model(_sub(6, stars: 0, xp: 0)), // approved, nothing paid
        // A status that merely claims a reward is not enough: only approved.
        _model(_sub(7, status: 'pending', stars: 10, xp: 15)),
      ]);
      expect(pending, isEmpty);
    });

    test('a half-confirmed reward still celebrates what was paid', () async {
      final s = await store();
      final pending = s.pending(Fx.childId, [_model(_sub(1, stars: 0, xp: 5))]);
      expect(pending.single.stars, 0);
      expect(pending.single.xp, 5);
    });

    test(
      'unconfirmed approvals are not consumed and celebrate once confirmed',
      () async {
        final s = await store();
        expect(
          s.pending(Fx.childId, [_model(_sub(1, stars: null, xp: null))]),
          isEmpty,
        );
        expect(s.consumed(Fx.childId), isEmpty);
        expect(s.pending(Fx.childId, [_model(_sub(1))]), hasLength(1));
      },
    );

    test('duplicate rows for one submission count once', () async {
      final s = await store();
      final pending = s.pending(Fx.childId, [_model(_sub(1)), _model(_sub(1))]);
      expect(pending, hasLength(1));
    });

    test('several approvals come out oldest first, none dropped', () async {
      final s = await store();
      final pending = s.pending(Fx.childId, [
        _model(_sub(3, reviewedAt: '2026-10-12T12:03:00Z')),
        _model(_sub(1, reviewedAt: '2026-10-12T12:01:00Z')),
        _model(_sub(2, reviewedAt: '2026-10-12T12:02:00Z')),
      ]);
      expect(
        [for (final a in pending) a.submissionId],
        [_id(1), _id(2), _id(3)],
      );
    });

    test('the baseline marks history as seen without celebrating it', () async {
      final s = await store();
      expect(s.baselineDone(Fx.childId), isFalse);
      final history = [_model(_sub(1)), _model(_sub(2, status: 'pending'))];
      await s.recordBaseline(Fx.childId, history);
      expect(s.baselineDone(Fx.childId), isTrue);
      expect(s.pending(Fx.childId, history), isEmpty);
      // The one that was still pending is news when it is approved.
      final later = [_model(_sub(1)), _model(_sub(2))];
      expect(s.pending(Fx.childId, later).map((a) => a.submissionId), [_id(2)]);
    });

    test('consumption survives a restart and is per child', () async {
      final h = await Harness.create(session: Fx.childSession());
      final first = ApprovalCelebrationStore(h.prefs);
      await first.markCelebrated(Fx.childId, _id(1));
      final restarted = ApprovalCelebrationStore(h.prefs);
      expect(restarted.pending(Fx.childId, [_model(_sub(1))]), isEmpty);
      expect(
        restarted.pending('another-child', [_model(_sub(1))]),
        hasLength(1),
      );
    });

    test('marking twice records once, and memory is bounded', () async {
      final h = await Harness.create(session: Fx.childSession());
      final s = ApprovalCelebrationStore(h.prefs);
      await s.markCelebrated(Fx.childId, _id(1));
      await s.markCelebrated(Fx.childId, _id(1));
      expect(s.consumed(Fx.childId), {_id(1)});
      for (var i = 0; i < ApprovalCelebrationStore.maxRemembered + 20; i++) {
        await s.markCelebrated(Fx.childId, 'id-$i');
      }
      expect(
        s.consumed(Fx.childId),
        hasLength(ApprovalCelebrationStore.maxRemembered),
      );
      expect(
        s.consumed(Fx.childId),
        contains('id-${ApprovalCelebrationStore.maxRemembered + 19}'),
      );
    });
  });

  group('MissionApprovalCelebrator', () {
    Future<Harness> harness(List<Map<String, Object?>> subs) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend.reply('GET', _mine, subs);
      return h;
    }

    Future<void> open(
      WidgetTester tester,
      Harness h, {
      Locale locale = const Locale('en'),
    }) async {
      setWindow(tester, const Size(393, 852));
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: h.overrides,
          retry: (_, _) => null,
          child: MaterialApp(
            theme: buildAppTheme(),
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const MissionApprovalCelebrator(
              child: Scaffold(body: Text('CHILD AREA')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The child area also loads progress (for level-ups and badges); let
      // every request finish so none is still in flight when a test ends.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    }

    Future<void> reload(WidgetTester tester) async {
      ProviderScope.containerOf(
        tester.element(find.text('CHILD AREA')),
      ).invalidate(mySubmissionsProvider);
      await tester.pumpAndSettle();
    }

    Future<void> dismiss(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('celebration.continue')));
      await tester.pumpAndSettle();
    }

    int posts(Harness h) =>
        h.backend.requests.where((r) => r.method != 'GET').length;

    testWidgets('a newly approved mission celebrates with the server amounts', (
      tester,
    ) async {
      final h = await harness([_sub(1, status: 'pending', stars: 0, xp: 0)]);
      await open(tester, h);
      expect(find.byKey(const Key('celebration.card')), findsNothing);

      h.backend.reply('GET', _mine, [
        _sub(1, stars: 10, xp: 15, title: 'Water the plants'),
      ]);
      await reload(tester);
      expect(find.text('Mission approved!'), findsOneWidget);
      expect(find.text('Water the plants'), findsOneWidget);
      expect(find.text('+ 10 Stars + 15 XP'), findsOneWidget);
      expect(
        find.text('Your parent approved it. Here are your rewards!'),
        findsOneWidget,
      );
      await dismiss(tester);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
      expect(posts(h), 0, reason: 'celebrating never writes to the server');
    });

    testWidgets('shows whatever the server paid, not a fixed amount', (
      tester,
    ) async {
      final h = await harness([]);
      await open(tester, h);
      h.backend.reply('GET', _mine, [_sub(1, stars: 3, xp: 4)]);
      await reload(tester);
      expect(find.text('+ 3 Stars + 4 XP'), findsOneWidget);
    });

    testWidgets('already approved missions are history on first sight', (
      tester,
    ) async {
      final h = await harness([_sub(1), _sub(2)]);
      await open(tester, h);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
      await reload(tester);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
    });

    testWidgets(
      'reopening or refreshing never replays a consumed celebration',
      (tester) async {
        final h = await harness([]);
        await open(tester, h);
        h.backend.reply('GET', _mine, [_sub(1)]);
        await reload(tester);
        await dismiss(tester);
        for (var i = 0; i < 3; i++) {
          await reload(tester);
          expect(find.byKey(const Key('celebration.card')), findsNothing);
        }
        // App restart: a brand-new widget tree on the same device storage.
        await tester.pumpWidget(const SizedBox());
        await open(tester, h);
        expect(find.byKey(const Key('celebration.card')), findsNothing);
      },
    );

    testWidgets(
      'approved while the app was closed: celebrates on reopening, once',
      (tester) async {
        final h = await harness([_sub(1, status: 'pending', stars: 0, xp: 0)]);
        await open(tester, h); // first look: records the baseline
        await tester.pumpWidget(const SizedBox()); // the app is closed
        // The parent approves while it is closed.
        h.backend.reply('GET', _mine, [_sub(1, stars: 10, xp: 15)]);
        await open(tester, h);
        expect(find.text('Mission approved!'), findsOneWidget);
        expect(find.text('+ 10 Stars + 15 XP'), findsOneWidget);
        await dismiss(tester);
        await tester.pumpWidget(const SizedBox());
        await open(tester, h);
        expect(find.byKey(const Key('celebration.card')), findsNothing);
      },
    );

    testWidgets('an interrupted celebration is shown again, never lost', (
      tester,
    ) async {
      final h = await harness([]);
      await open(tester, h);
      h.backend.reply('GET', _mine, [_sub(1)]);
      await reload(tester);
      expect(find.byKey(const Key('celebration.card')), findsOneWidget);
      // The app is killed before the child tapped Continue.
      await tester.pumpWidget(const SizedBox());
      await open(tester, h);
      expect(find.byKey(const Key('celebration.card')), findsOneWidget);
      await dismiss(tester);
      await tester.pumpWidget(const SizedBox());
      await open(tester, h);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
    });

    testWidgets(
      'several approvals each get their own celebration, oldest first',
      (tester) async {
        final h = await harness([]);
        await open(tester, h);
        h.backend.reply('GET', _mine, [
          _sub(2, title: 'Second', reviewedAt: '2026-10-12T12:02:00Z'),
          _sub(1, title: 'First', reviewedAt: '2026-10-12T12:01:00Z'),
          _sub(3, title: 'Third', reviewedAt: '2026-10-12T12:03:00Z'),
        ]);
        await reload(tester);
        for (final title in ['First', 'Second', 'Third']) {
          expect(find.byKey(const Key('celebration.card')), findsOneWidget);
          expect(find.text(title), findsOneWidget);
          await dismiss(tester);
        }
        expect(find.byKey(const Key('celebration.card')), findsNothing);
        await reload(tester);
        expect(find.byKey(const Key('celebration.card')), findsNothing);
      },
    );

    testWidgets(
      'a list that reloads while one is open does not stack or repeat',
      (tester) async {
        final h = await harness([]);
        await open(tester, h);
        h.backend.reply('GET', _mine, [_sub(1)]);
        await reload(tester);
        await reload(tester); // the same list again, celebration still open
        await reload(tester);
        expect(find.byKey(const Key('celebration.card')), findsOneWidget);
        await dismiss(tester);
        expect(find.byKey(const Key('celebration.card')), findsNothing);
      },
    );

    testWidgets('pending, rejected and unconfirmed approvals never celebrate', (
      tester,
    ) async {
      final h = await harness([]);
      await open(tester, h);
      h.backend.reply('GET', _mine, [
        _sub(1, status: 'pending', stars: 0, xp: 0),
        _sub(2, status: 'rejected', stars: 0, xp: 0),
        _sub(3, stars: null, xp: null), // approved, no reward data
        _sub(4, stars: 0, xp: 0),
      ]);
      await reload(tester);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
      // Later the server confirms the reward for #3: now it celebrates.
      h.backend.reply('GET', _mine, [_sub(3)]);
      await reload(tester);
      expect(find.byKey(const Key('celebration.card')), findsOneWidget);
    });

    testWidgets('duplicate rows in one response celebrate once', (
      tester,
    ) async {
      final h = await harness([]);
      await open(tester, h);
      h.backend.reply('GET', _mine, [_sub(1), _sub(1)]);
      await reload(tester);
      await dismiss(tester);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
    });

    testWidgets('system Back counts as Continue and is remembered', (
      tester,
    ) async {
      final h = await harness([]);
      await open(tester, h);
      h.backend.reply('GET', _mine, [_sub(1)]);
      await reload(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('celebration.card')), findsNothing);
      await reload(tester);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
    });

    testWidgets('a failed or offline list celebrates nothing and recovers', (
      tester,
    ) async {
      final h = await harness([]);
      h.backend.on(
        'GET',
        _mine,
        (_) => const FakeReply.fail(DioExceptionType.connectionError),
      );
      await open(tester, h);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
      expect(tester.takeException(), isNull);
      h.backend.reply('GET', _mine, <Object?>[]);
      await reload(tester); // the first successful look is the baseline
      h.backend.reply('GET', _mine, [_sub(1)]);
      await reload(tester);
      expect(find.byKey(const Key('celebration.card')), findsOneWidget);
    });

    for (final (locale, headline) in [
      (const Locale('hi'), 'मिशन मंज़ूर!'),
      (const Locale('gu'), 'મિશન મંજૂર!'),
    ]) {
      testWidgets('is localised for ${locale.languageCode}', (tester) async {
        final h = await harness([]);
        await open(tester, h, locale: locale);
        h.backend.reply('GET', _mine, [_sub(1)]);
        await reload(tester);
        expect(find.text(headline), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
