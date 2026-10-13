import 'package:balkavach_app/features/progress/data/progress_repository.dart';
import 'package:balkavach_app/features/progress/presentation/weekly_report_screen.dart';
import 'package:balkavach_app/shared/platform/text_sharer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

Map<String, Object?> _report({
  int missions = 3,
  int stars = 7,
  int xp = 50,
  int pending = 0,
  int rejected = 0,
  String timezone = 'Asia/Kolkata',
  String start = '2026-10-05',
  String end = '2026-10-11',
  List<Map<String, Object?>>? categories,
}) => {
  'child_id': Fx.childId,
  'timezone': timezone,
  'period_start': start,
  'period_end': end,
  'totals': {
    'completed_tasks': missions,
    'stars_earned': stars,
    'xp_earned': xp,
  },
  'days': [
    for (var i = 0; i < 7; i++)
      {
        'date': '2026-10-${(5 + i).toString().padLeft(2, '0')}',
        'completed_tasks': i == 2 ? missions : 0,
        'stars_earned': i == 2 ? stars : 0,
        'xp_earned': i == 2 ? xp : 0,
      },
  ],
  'categories':
      categories ??
      [
        {
          'category_id': Fx.categoryId,
          'name': 'Learn',
          'completed_tasks': 2,
          'stars_earned': 5,
          'xp_earned': 30,
        },
        {
          'category_id': null,
          'name': 'Uncategorised',
          'completed_tasks': 1,
          'stars_earned': 2,
          'xp_earned': 20,
        },
      ],
  'pending_submissions': pending,
  'rejected_submissions': rejected,
  'current_streak': 5,
  'longest_streak': 9,
  'recent_approved': <Object?>[],
};

class _FakeSharer implements TextSharer {
  _FakeSharer({this.opens = true});

  final bool opens;
  String? text;
  String? subject;

  @override
  Future<bool> share(String text, {String? subject}) async {
    this.text = text;
    this.subject = subject;
    return opens;
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('WeeklyReport parses the server contract', () {
    final report = WeeklyReport.fromJson(_report());
    expect(report.timezone, 'Asia/Kolkata');
    expect(report.periodStart, DateTime.utc(2026, 10, 5));
    expect(report.days, hasLength(7));
    expect(report.completedTasks, 3);
    expect(report.activeDays, 1);
    expect(report.categories.map((c) => c.name), ['Learn', 'Uncategorised']);
  });

  group('repository', () {
    test('asks for the requested week', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.reply(
        'GET',
        '/api/v1/progress/children/${Fx.childId}/weekly',
        _report(),
      );
      final report = await h
          .container()
          .read(progressRepositoryProvider)
          .weeklyReport(Fx.childId, weeksBack: 2);
      expect(report, isNotNull);
      expect(
        h.backend
            .requestsTo('GET', '/api/v1/progress/children/${Fx.childId}/weekly')
            .single
            .queryParameters,
        {'weeks_back': 2},
      );
    });

    test('a server without the endpoint yields null, not an error', () async {
      final h = await Harness.create(session: Fx.parentSession());
      final report = await h
          .container()
          .read(progressRepositoryProvider)
          .weeklyReport(Fx.childId);
      expect(report, isNull);
    });

    test('a real "child not found" is still an error', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.on(
        'GET',
        '/api/v1/progress/children/${Fx.childId}/weekly',
        (_) => FakeReply.error(404, 'http_error', 'Child profile not found'),
      );
      await expectLater(
        h.container().read(progressRepositoryProvider).weeklyReport(Fx.childId),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('screen', () {
    Future<(Harness, _FakeSharer)> pump(
      WidgetTester tester, {
      Map<String, Object?>? report,
      bool sharerOpens = true,
    }) async {
      final sharer = _FakeSharer(opens: sharerOpens);
      final h = await Harness.create(
        session: Fx.parentSession(),
        prefs: onboardedPrefs,
      );
      if (report != null) {
        h.backend.on(
          'GET',
          '/api/v1/progress/children/${Fx.childId}/weekly',
          (_) => FakeReply(200, report),
        );
      }
      await pumpScreen(
        tester,
        const WeeklyReportScreen(),
        overrides: [
          ...h.overrides,
          textSharerProvider.overrideWithValue(sharer),
        ],
      );
      return (h, sharer);
    }

    testWidgets('shows the server week, categories and time zone', (
      tester,
    ) async {
      await pump(tester, report: _report(pending: 2, rejected: 1));
      expect(find.text('Oct 5 – Oct 11'), findsOneWidget);
      expect(find.byKey(const Key('reports.categories')), findsOneWidget);
      expect(find.text('Learn'), findsOneWidget);
      expect(find.text('2 missions'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('2 missions waiting for your review'), findsOneWidget);
      expect(find.text('1 mission needs another try'), findsOneWidget);
      expect(find.text('Days follow Asia/Kolkata time.'), findsOneWidget);
    });

    testWidgets('an empty week says so instead of drawing empty bars', (
      tester,
    ) async {
      await pump(
        tester,
        report: _report(missions: 0, stars: 0, xp: 0, categories: []),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('reports.categories')),
          matching: find.text('No approved missions this week yet.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('previous and next week ask the server for that week', (
      tester,
    ) async {
      final (h, _) = await pump(tester, report: _report());
      expect(find.byKey(const Key('reports.next')).evaluate(), isNotEmpty);
      final next = tester.widget<IconButton>(
        find.byKey(const Key('reports.next')),
      );
      expect(next.onPressed, isNull, reason: 'cannot go past the current week');

      await _tap(tester, find.byKey(const Key('reports.previous')));
      final weeks = h.backend
          .requestsTo('GET', '/api/v1/progress/children/${Fx.childId}/weekly')
          .map((r) => r.queryParameters['weeks_back'])
          .toList();
      expect(weeks, containsAllInOrder([0, 1]));

      await _tap(tester, find.byKey(const Key('reports.current')));
      // The current week is already cached: no new request is needed, and
      // "next" is disabled again because there is nothing newer.
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('reports.next')))
            .onPressed,
        isNull,
      );
      expect(find.text('Oct 5 – Oct 11'), findsOneWidget);
    });

    testWidgets('sharing hands the real summary to the system share sheet', (
      tester,
    ) async {
      final (_, sharer) = await pump(tester, report: _report());
      await _tap(tester, find.byKey(const Key('reports.share')));
      expect(sharer.text, contains('Aarav'));
      expect(sharer.text, contains('3 missions approved'));
      expect(sharer.text, contains('7 stars'));
      expect(sharer.text, contains('Oct 5 – Oct 11'));
      expect(sharer.subject, "Aarav's weekly progress");
    });

    testWidgets('a share sheet that cannot open falls back to a hint', (
      tester,
    ) async {
      await pump(tester, report: _report(), sharerOpens: false);
      await _tap(tester, find.byKey(const Key('reports.share')));
      expect(
        find.text("Couldn't open sharing. Try Copy instead."),
        findsOneWidget,
      );
    });

    testWidgets('an older server still gets a report (UTC fallback)', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byKey(const Key('reports.categories')), findsNothing);
      expect(find.byKey(const Key('reports.previous')), findsNothing);
      expect(find.byKey(const Key('reports.share')), findsOneWidget);
    });
  });
}
