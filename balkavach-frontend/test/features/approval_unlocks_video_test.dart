// A parent approval must unlock video time in the child's app without a
// sign-out, a push or an app restart (docs/VIDEO_ENTITLEMENT_APPROVAL_FIX_REPORT.md).
//
// The server is authoritative: the app only re-reads
// `GET /api/v1/video-access/allowance` when it learns of a new approval, and
// never infers time from the approval itself.
import 'package:balkavach_app/core/theme/app_theme.dart';
import 'package:balkavach_app/features/learning/presentation/widgets/video_allowance_card.dart';
import 'package:balkavach_app/features/missions/presentation/mission_approval_celebrator.dart';
import 'package:balkavach_app/features/missions/presentation/mission_providers.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _mine = '/api/v1/tasks/submissions/mine';
const _allowance = '/api/v1/video-access/allowance';
const _notifications = '/api/v1/notifications';
const _submissionId = '00000000-0000-4000-8000-000000000001';

Map<String, Object?> _submission({required String status, int? stars}) => {
  ...Fx.submission(
    id: _submissionId,
    status: status,
    taskTitle: 'Water the plants',
    number: 1,
    submittedAt: '2026-10-12T09:01:00Z',
  ),
  'stars_awarded': ?stars,
  'xp_awarded': ?(stars == null ? null : 15),
};

Future<Harness> _harness() async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  h.backend
    ..reply('GET', _mine, [_submission(status: 'pending')])
    ..reply('GET', _notifications, <Object?>[])
    // Free daily allowance is zero and nothing is earned yet.
    ..reply(
      'GET',
      _allowance,
      Fx.allowance(remaining: 0, earned: 0, active: 0),
    );
  return h;
}

Future<void> _open(WidgetTester tester, Harness h) async {
  setWindow(tester, const Size(393, 852));
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      retry: (_, _) => null,
      child: MaterialApp(
        theme: buildAppTheme(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const MissionApprovalCelebrator(
          child: Scaffold(body: VideoAllowanceCard()),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

/// What the app does when it next looks at the child's submissions (opening a
/// screen, pull-to-refresh, returning to the app).
Future<void> _reloadSubmissions(WidgetTester tester) async {
  ProviderScope.containerOf(
    tester.element(find.byType(VideoAllowanceCard)),
  ).invalidate(mySubmissionsProvider);
  await _settle(tester);
}

void main() {
  testWidgets('zero earned seconds shows the locked state', (tester) async {
    final h = await _harness();
    await _open(tester, h);
    expect(find.text('Video time locked'), findsOneWidget);
    expect(find.textContaining('video time left today'), findsNothing);
  });

  testWidgets('a detected approval re-reads the allowance and replaces the '
      'stale zero balance with the server\'s 900 seconds', (tester) async {
    final h = await _harness();
    await _open(tester, h);
    expect(find.text('Video time locked'), findsOneWidget);
    final readsBefore = h.backend.requestsTo('GET', _allowance).length;

    // The parent approves: the server now reports the submission approved
    // and 900 earned seconds. No push arrives and the app is not restarted.
    h.backend
      ..reply('GET', _mine, [_submission(status: 'approved', stars: 10)])
      ..reply('GET', _allowance, Fx.allowance());
    await _reloadSubmissions(tester);

    expect(
      h.backend.requestsTo('GET', _allowance).length,
      greaterThan(readsBefore),
      reason: 'the approval must trigger a fresh allowance request',
    );
    // The celebration is on top; the card underneath is already unlocked.
    await tester.tap(find.byKey(const Key('celebration.continue')));
    await _settle(tester);
    expect(find.text('15m video time left today'), findsOneWidget);
    expect(find.text('Video time locked'), findsNothing);
  });

  testWidgets('an approval does not unlock anything the server did not grant', (
    tester,
  ) async {
    final h = await _harness();
    await _open(tester, h);
    // Approved, but the server reports no time (e.g. the daily cap was full).
    h.backend.reply('GET', _mine, [_submission(status: 'approved', stars: 10)]);
    await _reloadSubmissions(tester);
    await tester.tap(find.byKey(const Key('celebration.continue')));
    await _settle(tester);
    expect(find.text('Video time locked'), findsOneWidget);
    expect(find.textContaining('video time left today'), findsNothing);
  });

  testWidgets('an allowance error never shows time as granted', (tester) async {
    final h = await _harness();
    h.backend.on(
      'GET',
      _allowance,
      (_) => FakeReply.error(500, 'internal_error', 'boom'),
    );
    await _open(tester, h);
    h.backend.reply('GET', _mine, [_submission(status: 'approved', stars: 10)]);
    await _reloadSubmissions(tester);
    await tester.tap(find.byKey(const Key('celebration.continue')));
    await _settle(tester);
    expect(find.textContaining('video time left today'), findsNothing);
    expect(find.byKey(const Key('watch.allowance.card')), findsNothing);
  });
}
