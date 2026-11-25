import 'package:balkavach_app/core/theme/app_theme.dart';
import 'package:balkavach_app/features/child_profile/presentation/child_profile_screen.dart';
import 'package:balkavach_app/features/progress/presentation/achievements_widgets.dart';
import 'package:balkavach_app/features/quizzes/presentation/parent_quiz_history_section.dart';
import 'package:balkavach_app/features/rewards/presentation/parent_rewards_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:balkavach_app/shared/widgets/gamification.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _achievementsPath =
    '/api/v1/progress/children/${Fx.childId}/achievements';
const _quizPath = '/api/v1/quizzes/children/${Fx.childId}/history';

Map<String, Object?> _ach({
  List<Map<String, Object?>> badges = const [],
  int? level = 3,
  int? next = 700,
}) => {
  'level': {
    'level_number': level,
    'name': level == null ? null : 'Explorer',
    'minimum_xp': 300,
    'next_level_number': next == null ? null : 4,
    'next_level_name': next == null ? null : 'Hero',
    'next_minimum_xp': next,
    'total_xp': 420,
  },
  'badges': badges,
};

Map<String, Object?> _earned(String id, String name, {String? description}) => {
  'badge_id': id,
  'name': name,
  'description': description,
  'icon_url': null,
  'unlocked': true,
  'unlocked_at': '2026-10-10T09:00:00Z',
  'criteria_type': 'approved_tasks',
  'threshold': 1,
  'current': 5,
};

Map<String, Object?> _locked(
  String id,
  String name, {
  int? threshold = 10,
  int? current = 3,
}) => {
  'badge_id': id,
  'name': name,
  'description': null,
  'icon_url': null,
  'unlocked': false,
  'unlocked_at': null,
  'criteria_type': 'total_xp',
  'threshold': threshold,
  'current': current,
};

Map<String, Object?> _attempt(
  int n, {
  bool passed = true,
  int percent = 100,
  int correct = 3,
  int stars = 0,
  int xp = 0,
  String title = 'Animals quiz',
}) => {
  'attempt_id': '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
  'quiz_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  'quiz_title': title,
  'score_percent': percent,
  'correct_count': correct,
  'total_questions': 3,
  'passed': passed,
  'stars_awarded': stars,
  'xp_awarded': xp,
  'submitted_at': '2026-10-1${n}T10:00:00Z',
};

Map<String, Object?> _redemption(
  String id,
  String status, {
  String? name = 'Ice cream',
  String? reviewedAt,
  String? fulfilledAt,
  String? note,
  String requestedAt = '2026-10-01T09:00:00Z',
}) => {
  ...Fx.redemption(
    id: id,
    status: status,
    rewardName: name,
    childName: 'Aarav',
    reviewNote: note,
  ),
  'requested_at': requestedAt,
  'reviewed_at': reviewedAt,
  'fulfilled_at': fulfilledAt,
};

Future<void> _show(
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

Future<Harness> _parent() =>
    Harness.create(session: Fx.parentSession(), prefs: onboardedPrefs);

/// Opens the History tab. On a narrow screen the tab row scrolls, so the tab
/// is brought into view first, as a parent would.
Future<void> _openHistory(WidgetTester tester) async {
  final tab = find.byKey(const Key('rewards.tab.history'));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

int _writes(Harness h) =>
    h.backend.requests.where((r) => r.method != 'GET').length;

/// [count] attempts, newest first, each with its own id and title.
List<Map<String, Object?>> _manyAttempts(int count) => [
  for (var n = 1; n <= count; n++)
    {
      ..._attempt(1, title: 'Quiz $n'),
      'attempt_id': '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
    },
];

/// Serves [all] the way the server does, honouring limit and offset.
FakeReply _paged(RequestOptions options, List<Object?> all) {
  final offset = options.queryParameters['offset'] as int? ?? 0;
  final limit = options.queryParameters['limit'] as int? ?? 50;
  return FakeReply(200, all.skip(offset).take(limit).toList());
}

Future<void> _showMore(WidgetTester tester) async {
  final more = find.byKey(const Key('parent.quizHistory.more'));
  await tester.ensureVisible(more);
  await tester.tap(more);
  await tester.pumpAndSettle();
}

/// Shows [child] only while [open] is true, inside one long-lived provider
/// scope, the way leaving and reopening a screen does in the app.
Future<void> _reopenable(
  WidgetTester tester,
  Harness h,
  ValueNotifier<bool> open,
  Widget child,
) => _show(
  tester,
  h,
  ValueListenableBuilder<bool>(
    valueListenable: open,
    builder: (_, visible, _) => visible ? child : const SizedBox.shrink(),
  ),
);

Future<void> _reopen(WidgetTester tester, ValueNotifier<bool> open) async {
  open.value = false;
  await tester.pumpAndSettle();
  open.value = true;
  await tester.pumpAndSettle();
}

void main() {
  group('Parent achievements (child profile)', () {
    testWidgets('shows level progress, earned badges and locked progress', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.reply(
        'GET',
        _achievementsPath,
        _ach(
          badges: [
            _earned('b1', 'First Mission', description: 'Done one'),
            _locked('b2', 'XP Climber', threshold: 10, current: 3),
            _locked('b3', 'Mystery', threshold: null, current: null),
          ],
        ),
      );
      await _show(
        tester,
        h,
        const ParentAchievementsSection(childId: Fx.childId),
      );
      expect(find.text('Lv 3 · Explorer'), findsOneWidget);
      expect(find.text('280 XP to Level 4'), findsOneWidget);
      expect(find.text('First Mission'), findsOneWidget);
      expect(find.text('Earned Oct 10, 2026'), findsOneWidget);
      expect(find.byKey(const Key('badge.earned.b1')), findsOneWidget);
      expect(find.byKey(const Key('badge.locked.b2')), findsOneWidget);
      expect(find.text('3 of 10'), findsOneWidget);
      // The server gave no target for "Mystery": no number is invented.
      expect(find.byKey(const Key('badge.locked.b3')), findsOneWidget);
      expect(find.textContaining(' of '), findsOneWidget);
      expect(_writes(h), 0);
    });

    testWidgets('a child with no badges earned says so', (tester) async {
      final h = await _parent();
      h.backend.reply(
        'GET',
        _achievementsPath,
        _ach(badges: [_locked('b2', 'XP Climber')], level: 1),
      );
      await _show(
        tester,
        h,
        const ParentAchievementsSection(childId: Fx.childId),
      );
      expect(find.byKey(const Key('parent.badges.noneEarned')), findsOneWidget);
      expect(find.byKey(const Key('badge.locked.b2')), findsOneWidget);
    });

    testWidgets('no badges defined at all is an explicit empty state', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.reply('GET', _achievementsPath, _ach());
      await _show(
        tester,
        h,
        const ParentAchievementsSection(childId: Fx.childId),
      );
      expect(find.byKey(const Key('parent.badges.none')), findsOneWidget);
    });

    testWidgets('missing level values do not show a fake level', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.reply('GET', _achievementsPath, _ach(level: null, next: null));
      await _show(
        tester,
        h,
        const ParentAchievementsSection(childId: Fx.childId),
      );
      expect(find.byKey(const Key('level.card')), findsNothing);
      expect(find.byKey(const Key('parent.level.none')), findsOneWidget);
    });

    testWidgets('reopening the profile shows what the server says now', (
      tester,
    ) async {
      final h = await _parent();
      var badges = [_locked('b2', 'XP Climber', current: 3)];
      h.backend.on(
        'GET',
        _achievementsPath,
        (_) => FakeReply(200, _ach(badges: badges)),
      );
      final open = ValueNotifier(true);
      await _reopenable(
        tester,
        h,
        open,
        const ParentAchievementsSection(childId: Fx.childId),
      );
      expect(find.text('3 of 10'), findsOneWidget);
      badges = [_locked('b2', 'XP Climber', current: 8)];
      await _reopen(tester, open);
      expect(find.text('8 of 10'), findsOneWidget);
    });

    testWidgets('the top level says so', (tester) async {
      final h = await _parent();
      h.backend.reply('GET', _achievementsPath, _ach(level: 6, next: null));
      await _show(
        tester,
        h,
        const ParentAchievementsSection(childId: Fx.childId),
      );
      expect(find.text('You reached the top level!'), findsOneWidget);
    });

    testWidgets('another family\'s child is a safe error, not data', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.on(
        'GET',
        _achievementsPath,
        (_) => FakeReply.error(404, 'http_error', 'Child profile not found'),
      );
      await _show(
        tester,
        h,
        const ParentAchievementsSection(childId: Fx.childId),
      );
      expect(
        find.byKey(const Key('parent.achievements.error')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('level.card')), findsNothing);
    });

    testWidgets('a failed load can be retried', (tester) async {
      final h = await _parent();
      var fail = true;
      h.backend.on('GET', _achievementsPath, (_) {
        return fail
            ? const FakeReply.fail(DioExceptionType.connectionError)
            : FakeReply(200, _ach(badges: [_earned('b1', 'First Mission')]));
      });
      await _show(
        tester,
        h,
        const ParentAchievementsSection(childId: Fx.childId),
      );
      expect(
        find.byKey(const Key('parent.achievements.error')),
        findsOneWidget,
      );
      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('First Mission'), findsOneWidget);
    });

    for (final (locale, title, none) in [
      (const Locale('hi'), 'लेवल और बैज', 'अभी कोई बैज नहीं मिला।'),
      (const Locale('gu'), 'લેવલ અને બેજ', 'હજી કોઈ બેજ મળ્યો નથી.'),
    ]) {
      testWidgets('is localised for ${locale.languageCode} on a small screen', (
        tester,
      ) async {
        final h = await _parent();
        h.backend.reply(
          'GET',
          _achievementsPath,
          _ach(badges: [_locked('b2', 'XP Climber')]),
        );
        await _show(
          tester,
          h,
          const ParentAchievementsSection(childId: Fx.childId),
          locale: locale,
          size: const Size(320, 568),
          scale: 2,
        );
        expect(find.text(title), findsOneWidget);
        expect(find.text(none), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Parent quiz history (child profile)', () {
    testWidgets('lists passed, failed and retaken attempts with server rewards', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.reply('GET', _quizPath, [
        _attempt(3), // retake: passed, nothing paid
        _attempt(2, stars: 7, xp: 11), // first pass: paid
        _attempt(1, passed: false, percent: 33, correct: 1),
      ]);
      await _show(
        tester,
        h,
        const ParentQuizHistorySection(childId: Fx.childId),
      );
      expect(find.text('Animals quiz'), findsNWidgets(3));
      expect(find.text('Passed'), findsNWidgets(2));
      expect(find.text('Not passed'), findsOneWidget);
      // Written for the parent, who did not take the quiz.
      expect(find.text('1 of 3 right · 33%'), findsOneWidget);
      expect(find.textContaining('You got'), findsNothing);
      // Rewards come from the server's numbers; none shown when none were paid.
      expect(
        find.byKey(
          const Key(
            'parent.quiz.rewards.${'00000000-0000-4000-8000-000000000002'}',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('+ 7 Stars + 11 XP'), findsOneWidget);
      expect(find.textContaining('Stars'), findsOneWidget);
      expect(_writes(h), 0, reason: 'a parent view never writes');
    });

    testWidgets('no attempts yet is an explicit empty state', (tester) async {
      final h = await _parent();
      h.backend.reply('GET', _quizPath, <Object?>[]);
      await _show(
        tester,
        h,
        const ParentQuizHistorySection(childId: Fx.childId),
      );
      expect(find.byKey(const Key('parent.quizHistory.empty')), findsOneWidget);
    });

    testWidgets('unauthorised or failed loads show an error with retry', (
      tester,
    ) async {
      final h = await _parent();
      h.backend.on(
        'GET',
        _quizPath,
        (_) => FakeReply.error(404, 'http_error', 'Child profile not found'),
      );
      await _show(
        tester,
        h,
        const ParentQuizHistorySection(childId: Fx.childId),
      );
      expect(find.byKey(const Key('parent.quizHistory.error')), findsOneWidget);
      expect(find.text('Animals quiz'), findsNothing);
    });

    testWidgets('show more reaches every older attempt, ten at a time', (
      tester,
    ) async {
      final h = await _parent();
      final all = _manyAttempts(23);
      h.backend.on('GET', _quizPath, (o) => _paged(o, all));
      await _show(
        tester,
        h,
        const ParentQuizHistorySection(childId: Fx.childId),
      );
      expect(find.byType(StatusChip), findsNWidgets(10));
      expect(find.text('Quiz 11'), findsNothing);
      await _showMore(tester);
      expect(find.byType(StatusChip), findsNWidgets(20));
      await _showMore(tester);
      expect(find.byType(StatusChip), findsNWidgets(23));
      expect(find.text('Quiz 23'), findsOneWidget);
      expect(find.byKey(const Key('parent.quizHistory.more')), findsNothing);
      final offsets = [
        for (final r in h.backend.requestsTo('GET', _quizPath))
          r.queryParameters['offset'],
      ];
      // The first page can be asked for again while the session is restoring
      // in a test; each older page is fetched once, and only when asked for.
      expect(offsets.first, 0);
      expect(offsets.where((offset) => offset != 0), [10, 20]);
      expect(_writes(h), 0);
    });

    testWidgets('exactly one page offers nothing more', (tester) async {
      final h = await _parent();
      final all = _manyAttempts(10);
      h.backend.on('GET', _quizPath, (o) => _paged(o, all));
      await _show(
        tester,
        h,
        const ParentQuizHistorySection(childId: Fx.childId),
      );
      expect(find.byType(StatusChip), findsNWidgets(10));
      expect(find.byKey(const Key('parent.quizHistory.more')), findsNothing);
    });

    testWidgets('a failed older page keeps what is shown and can be retried', (
      tester,
    ) async {
      final h = await _parent();
      final all = _manyAttempts(12);
      var fail = true;
      h.backend.on('GET', _quizPath, (o) {
        if (fail && (o.queryParameters['offset'] ?? 0) != 0) {
          return const FakeReply.fail(DioExceptionType.connectionError);
        }
        return _paged(o, all);
      });
      await _show(
        tester,
        h,
        const ParentQuizHistorySection(childId: Fx.childId),
      );
      await _showMore(tester);
      expect(find.byType(StatusChip), findsNWidgets(10));
      expect(find.byKey(const Key('parent.quizHistory.error')), findsOneWidget);
      fail = false;
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byType(StatusChip), findsNWidgets(12));
      expect(find.byKey(const Key('parent.quizHistory.error')), findsNothing);
    });

    testWidgets('an attempt added between pages is not listed twice', (
      tester,
    ) async {
      final h = await _parent();
      var all = _manyAttempts(12);
      h.backend.on('GET', _quizPath, (o) => _paged(o, all));
      await _show(
        tester,
        h,
        const ParentQuizHistorySection(childId: Fx.childId),
      );
      // A new attempt pushes "Quiz 10" onto the second page.
      all = [
        {
          ..._attempt(1, title: 'Brand new'),
          'attempt_id': '00000000-0000-4000-8000-000000000099',
        },
        ...all,
      ];
      await _showMore(tester);
      expect(find.text('Quiz 10'), findsOneWidget);
      expect(find.byType(StatusChip), findsNWidgets(12));
    });

    testWidgets('reopening the profile shows newly taken quizzes', (
      tester,
    ) async {
      final h = await _parent();
      var all = <Map<String, Object?>>[];
      h.backend.on('GET', _quizPath, (o) => _paged(o, all));
      final open = ValueNotifier(true);
      await _reopenable(
        tester,
        h,
        open,
        const ParentQuizHistorySection(childId: Fx.childId),
      );
      expect(find.byKey(const Key('parent.quizHistory.empty')), findsOneWidget);
      all = _manyAttempts(1);
      await _reopen(tester, open);
      expect(find.text('Quiz 1'), findsOneWidget);
    });

    testWidgets("the date shown is the parent's local date, with the year", (
      tester,
    ) async {
      final h = await _parent();
      const sent = '2026-10-11T20:30:00Z';
      h.backend.reply('GET', _quizPath, [
        {..._attempt(1), 'submitted_at': sent},
      ]);
      await _show(
        tester,
        h,
        const ParentQuizHistorySection(childId: Fx.childId),
      );
      expect(
        find.text(
          DateFormat.yMMMd('en').format(DateTime.parse(sent).toLocal()),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('2026'), findsOneWidget);
    });

    for (final (locale, title, notPassed) in [
      (const Locale('hi'), 'क्विज़', 'पास नहीं हुए'),
      (const Locale('gu'), 'ક્વિઝ', 'પાસ થયા નથી'),
    ]) {
      testWidgets('is localised for ${locale.languageCode} on a small screen', (
        tester,
      ) async {
        final h = await _parent();
        h.backend.reply('GET', _quizPath, [
          _attempt(1, passed: false, percent: 33, correct: 1),
        ]);
        await _show(
          tester,
          h,
          const ParentQuizHistorySection(childId: Fx.childId),
          locale: locale,
          size: const Size(320, 568),
          scale: 2,
        );
        expect(find.text(title), findsOneWidget);
        expect(find.text(notPassed), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Child profile shows both sections', () {
    testWidgets('level, badges and quiz history appear for the parent', (
      tester,
    ) async {
      final h = await _parent();
      h.backend
        ..reply(
          'GET',
          _achievementsPath,
          _ach(badges: [_earned('b1', 'First Mission')]),
        )
        ..reply('GET', _quizPath, [_attempt(1, stars: 7, xp: 11)]);
      setWindow(tester, const Size(393, 2400));
      await pumpScreen(
        tester,
        const ChildProfileScreen(childId: Fx.childId),
        overrides: h.overrides,
        size: const Size(393, 2400),
      );
      expect(find.byKey(const Key('parent.achievements')), findsOneWidget);
      expect(find.text('First Mission'), findsOneWidget);
      expect(find.byKey(const Key('parent.quizHistory')), findsOneWidget);
      expect(find.text('+ 7 Stars + 11 XP'), findsOneWidget);
      expect(_writes(h), 0);
    });
  });

  group('Parent reward history', () {
    Future<Harness> open(
      WidgetTester tester, {
      List<Map<String, Object?>> fulfilled = const [],
      List<Map<String, Object?>> rejected = const [],
      List<Map<String, Object?>> cancelled = const [],
      Locale locale = const Locale('en'),
      Size size = const Size(393, 852),
      double scale = 1,
    }) async {
      final h = await _parent();
      h.backend
        ..on('GET', '/api/v1/redemptions', (options) {
          return FakeReply(200, switch (options.queryParameters['status']) {
            'fulfilled' => fulfilled,
            'rejected' => rejected,
            'cancelled' => cancelled,
            _ => <Object?>[],
          });
        })
        ..reply('GET', '/api/v1/rewards', [Fx.reward()]);
      await pumpScreen(
        tester,
        const ParentRewardsScreen(),
        overrides: h.overrides,
        locale: locale,
        size: size,
        textScale: scale,
      );
      await _openHistory(tester);
      return h;
    }

    testWidgets('shows every finished status with only the dates it has', (
      tester,
    ) async {
      final h = await open(
        tester,
        fulfilled: [
          _redemption(
            'f1',
            'fulfilled',
            name: 'Park visit',
            reviewedAt: '2026-10-02T09:00:00Z',
            fulfilledAt: '2026-10-03T09:00:00Z',
          ),
        ],
        rejected: [
          _redemption(
            'r1',
            'rejected',
            name: 'New book',
            reviewedAt: '2026-10-05T09:00:00Z',
            note: 'after dinner',
          ),
        ],
        cancelled: [_redemption('c1', 'cancelled', name: 'Movie night')],
      );
      expect(find.text('Handed over'), findsOneWidget);
      expect(find.text('Declined'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Park visit'), findsOneWidget);
      expect(find.text('New book'), findsOneWidget);
      expect(find.text('Movie night'), findsOneWidget);
      expect(find.text('Aarav · 50 Stars'), findsNWidgets(3));
      expect(find.byKey(const Key('history.note.r1')), findsOneWidget);
      expect(find.text('Note: after dinner'), findsOneWidget);
      // A cancelled request has no decision or hand-over date: none is invented.
      final cancelled = find.byKey(const Key('history.c1'));
      expect(
        find.descendant(
          of: cancelled,
          matching: find.textContaining('Decided'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: cancelled,
          matching: find.textContaining('Handed over'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: cancelled,
          matching: find.textContaining('Requested'),
        ),
        findsOneWidget,
      );
      // Read-only: nothing was approved, refunded or created.
      expect(_writes(h), 0);
      // One request per finished status, scoped to the family.
      final statuses = {
        for (final r in h.backend.requests.where(
          (r) => r.uri.path == '/api/v1/redemptions',
        ))
          r.queryParameters['status'],
      };
      expect(statuses, containsAll(['fulfilled', 'rejected', 'cancelled']));
    });

    testWidgets('most recent first, and a missing reward name is explicit', (
      tester,
    ) async {
      await open(
        tester,
        fulfilled: [
          _redemption(
            'old',
            'fulfilled',
            name: 'Old reward',
            fulfilledAt: '2026-10-02T09:00:00Z',
          ),
        ],
        cancelled: [
          _redemption(
            'new',
            'cancelled',
            name: null,
            requestedAt: '2026-10-20T09:00:00Z',
          ),
        ],
      );
      final newest = tester.getTopLeft(find.byKey(const Key('history.new'))).dy;
      final oldest = tester.getTopLeft(find.byKey(const Key('history.old'))).dy;
      expect(newest, lessThan(oldest));
      expect(find.text('Reward'), findsOneWidget);
    });

    testWidgets('dates carry the year', (tester) async {
      await open(tester, cancelled: [_redemption('c1', 'cancelled')]);
      expect(find.text('Requested Oct 1, 2026'), findsOneWidget);
    });

    for (final (language, scale) in [('en', 1.0), ('hi', 2.0), ('gu', 2.0)]) {
      testWidgets('tab labels are never clipped on a small phone '
          '($language x$scale)', (tester) async {
        final h = await _parent();
        h.backend
          ..on('GET', '/api/v1/redemptions', (options) {
            return FakeReply(
              200,
              options.queryParameters['status'] == 'pending'
                  ? [_redemption('p1', 'pending')]
                  : <Object?>[],
            );
          })
          ..reply('GET', '/api/v1/rewards', [Fx.reward()]);
        await pumpScreen(
          tester,
          const ParentRewardsScreen(),
          overrides: h.overrides,
          locale: Locale(language),
          size: const Size(320, 568),
          textScale: scale,
        );
        for (final tab in ['requests', 'catalog', 'history']) {
          final label = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.byKey(Key('rewards.tab.$tab')),
              matching: find.byType(RichText),
            ),
          );
          expect(
            label.size.width,
            greaterThanOrEqualTo(
              label.getMaxIntrinsicWidth(double.infinity) - 0.5,
            ),
            reason: '$tab label is cut off',
          );
        }
        // Every tab can still be reached.
        await _openHistory(tester);
        expect(find.byKey(const Key('history.empty')), findsOneWidget);
      });
    }

    testWidgets('requests beyond the server page size are not hidden', (
      tester,
    ) async {
      final h = await _parent();
      final many = [
        for (var n = 0; n < 130; n++)
          _redemption('f$n', 'fulfilled', name: 'Reward $n'),
      ];
      h.backend
        ..on('GET', '/api/v1/redemptions', (options) {
          return options.queryParameters['status'] == 'fulfilled'
              ? _paged(options, many)
              : const FakeReply(200, <Object?>[]);
        })
        ..reply('GET', '/api/v1/rewards', [Fx.reward()]);
      await pumpScreen(
        tester,
        const ParentRewardsScreen(),
        overrides: h.overrides,
      );
      await _openHistory(tester);
      expect(find.byKey(const Key('history.f0')), findsOneWidget);
      expect(find.byKey(const Key('history.f129')), findsOneWidget);
      expect(
        [
          for (final r in h.backend.requestsTo('GET', '/api/v1/redemptions'))
            if (r.queryParameters['status'] == 'fulfilled')
              r.queryParameters['offset'] ?? 0,
        ],
        [0, 100],
      );
    });

    testWidgets('shows the description while the reward is still offered', (
      tester,
    ) async {
      await open(
        tester,
        fulfilled: [_redemption('f1', 'fulfilled')],
        rejected: [
          {
            ..._redemption('r1', 'rejected', name: 'Removed reward'),
            'reward_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          },
        ],
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('history.f1')),
          matching: find.text('One scoop after dinner'),
        ),
        findsOneWidget,
      );
      // A removed reward has no description to show: none is invented.
      expect(find.byKey(const Key('history.description.r1')), findsNothing);
      expect(find.text('Removed reward'), findsOneWidget);
    });

    testWidgets('history is still shown if descriptions cannot be loaded', (
      tester,
    ) async {
      final h = await _parent();
      h.backend
        ..on('GET', '/api/v1/redemptions', (options) {
          return FakeReply(
            200,
            options.queryParameters['status'] == 'fulfilled'
                ? [_redemption('f1', 'fulfilled', name: 'Park visit')]
                : <Object?>[],
          );
        })
        ..on(
          'GET',
          '/api/v1/rewards',
          (_) => const FakeReply.fail(DioExceptionType.connectionError),
        );
      await pumpScreen(
        tester,
        const ParentRewardsScreen(),
        overrides: h.overrides,
      );
      await _openHistory(tester);
      expect(find.text('Park visit'), findsOneWidget);
      expect(find.byKey(const Key('history.error')), findsNothing);
    });

    testWidgets('returning to the tab shows requests finished meanwhile', (
      tester,
    ) async {
      final done = <Map<String, Object?>>[];
      await open(tester, fulfilled: done);
      expect(find.byKey(const Key('history.empty')), findsOneWidget);
      done.add(_redemption('f1', 'fulfilled', name: 'Park visit'));
      await tester.tap(find.byKey(const Key('rewards.tab.requests')));
      await tester.pumpAndSettle();
      await _openHistory(tester);
      expect(find.text('Park visit'), findsOneWidget);
    });

    testWidgets('an empty history is an explicit empty state', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('history.empty')), findsOneWidget);
    });

    testWidgets('a failed load shows an error and can be retried', (
      tester,
    ) async {
      final h = await _parent();
      var fail = true;
      h.backend
        ..on('GET', '/api/v1/redemptions', (options) {
          if (options.queryParameters['status'] == 'fulfilled' && fail) {
            return const FakeReply.fail(DioExceptionType.connectionError);
          }
          return FakeReply(
            200,
            options.queryParameters['status'] == 'fulfilled'
                ? [_redemption('f1', 'fulfilled', name: 'Park visit')]
                : <Object?>[],
          );
        })
        ..reply('GET', '/api/v1/rewards', [Fx.reward()]);
      await pumpScreen(
        tester,
        const ParentRewardsScreen(),
        overrides: h.overrides,
      );
      await _openHistory(tester);
      expect(find.byKey(const Key('history.error')), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Park visit'), findsOneWidget);
    });

    testWidgets('open requests stay in the Requests tab, not in history', (
      tester,
    ) async {
      final h = await _parent();
      h.backend
        ..on('GET', '/api/v1/redemptions', (options) {
          return FakeReply(
            200,
            options.queryParameters['status'] == 'pending'
                ? [_redemption('p1', 'pending', name: 'Pending reward')]
                : <Object?>[],
          );
        })
        ..reply('GET', '/api/v1/rewards', [Fx.reward()]);
      await pumpScreen(
        tester,
        const ParentRewardsScreen(),
        overrides: h.overrides,
      );
      expect(find.textContaining('Pending reward'), findsWidgets);
      await _openHistory(tester);
      expect(find.textContaining('Pending reward'), findsNothing);
      expect(find.byKey(const Key('history.empty')), findsOneWidget);
    });

    for (final (locale, done, empty) in [
      (const Locale('hi'), 'सौंप दिया गया', 'अभी कोई पूरा हुआ अनुरोध नहीं है।'),
      (const Locale('gu'), 'સોંપી દેવાયું', 'હજી કોઈ પૂર્ણ થયેલી વિનંતી નથી.'),
    ]) {
      testWidgets(
        'is localised for ${locale.languageCode} (small, large text)',
        (tester) async {
          await open(
            tester,
            fulfilled: [
              _redemption(
                'f1',
                'fulfilled',
                fulfilledAt: '2026-10-03T09:00:00Z',
              ),
            ],
            locale: locale,
            size: const Size(320, 568),
            scale: 2,
          );
          expect(find.text(done), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('empty state is localised for ${locale.languageCode}', (
        tester,
      ) async {
        await open(tester, locale: locale);
        expect(find.text(empty), findsOneWidget);
      });
    }
  });
}
