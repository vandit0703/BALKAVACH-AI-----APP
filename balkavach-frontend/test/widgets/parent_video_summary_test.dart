// Parent view of today's video time, against a FAKE BACKEND. Every figure is
// whatever the server returned; the app does no arithmetic of its own beyond
// seconds to minutes.

import 'package:balkavach_app/features/child_profile/presentation/child_watch_history_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _childId = 'child-9';
const _summaryPath = '/api/v1/video-access/children/$_childId/summary';
const _historyPath = '/api/v1/videos/watch-history/children/$_childId';

Map<String, Object?> _summary({
  List<Map<String, Object?>> rewards = const [],
  int earned = 1800,
  int consumed = 600,
  int remaining = 1200,
  int cap = 4500,
}) => {
  ...Fx.allowance(
    earned: earned,
    consumed: consumed,
    remaining: remaining,
    cap: cap,
  ),
  'free_allowance_seconds': 900,
  'free_consumed_seconds': 300,
  'mission_rewards': rewards,
};

Future<Harness> _pump(
  WidgetTester tester, {
  required FakeReply Function(RequestOptions) summary,
  Size size = const Size(393, 852),
  double textScale = 1,
}) async {
  final h = await Harness.create(
    session: Fx.parentSession(),
    prefs: onboardedPrefs,
  );
  h.backend
    ..on('GET', _summaryPath, summary)
    ..reply('GET', _historyPath, <Object?>[]);
  await pumpScreen(
    tester,
    const ChildWatchHistoryScreen(childId: _childId),
    overrides: h.overrides,
    size: size,
    textScale: textScale,
  );
  return h;
}

void main() {
  testWidgets('shows the server figures and the missions that earned time', (
    tester,
  ) async {
    await _pump(
      tester,
      summary: (_) => FakeReply(
        200,
        _summary(
          rewards: [
            {
              'task_id': 't1',
              'task_title': 'Tidy your room',
              'granted_seconds': 900,
              'consumed_seconds': 300,
              'granted_at': '2026-11-19T08:00:00Z',
            },
            {
              'task_id': 't2',
              'task_title': 'Read a story',
              'granted_seconds': 900,
              'consumed_seconds': 0,
              'granted_at': '2026-11-19T09:00:00Z',
            },
          ],
        ),
      ),
    );

    expect(find.text('Today\'s video time'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('parent.videoSummary.earned')),
        matching: find.text('30'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('parent.videoSummary.watched')),
        matching: find.text('10'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('parent.videoSummary.left')),
        matching: find.text('20'),
      ),
      findsOneWidget,
    );
    expect(find.text('Daily cap: 75 min'), findsOneWidget);
    expect(find.text('Includes 15 free minutes'), findsOneWidget);
    expect(find.text('Tidy your room'), findsOneWidget);
    expect(find.text('5 of 15 min used'), findsOneWidget);
    expect(find.text('Read a story'), findsOneWidget);
    expect(find.text('0 of 15 min used'), findsOneWidget);
    // Watch history stays visible beneath the summary.
    expect(find.byKey(const Key('watchHistory.empty')), findsOneWidget);
  });

  testWidgets('no mission yet says so, with no invented rewards', (
    tester,
  ) async {
    await _pump(tester, summary: (_) => FakeReply(200, _summary()));
    expect(
      find.byKey(const Key('parent.videoSummary.noMissions')),
      findsOneWidget,
    );
  });

  testWidgets('a failed load says so and retry reloads it', (tester) async {
    var fail = true;
    await _pump(
      tester,
      summary: (_) => fail
          ? FakeReply.error(500, 'server_error', 'boom')
          : FakeReply(200, _summary()),
    );
    expect(find.byKey(const Key('parent.videoSummary.retry')), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('parent.videoSummary.retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('parent.videoSummary.earned')), findsOneWidget);
  });

  testWidgets('fits a 320 px phone at 2x text', (tester) async {
    await _pump(
      tester,
      size: const Size(320, 568),
      textScale: 2,
      summary: (_) => FakeReply(
        200,
        _summary(
          rewards: [
            {
              'task_id': 't1',
              'task_title': 'Water the plants in the garden carefully',
              'granted_seconds': 900,
              'consumed_seconds': 300,
              'granted_at': '2026-11-19T08:00:00Z',
            },
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('parent.videoSummary')), findsOneWidget);
  });
}
