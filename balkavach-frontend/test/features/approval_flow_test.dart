// Parent approval: what the screen shows, what it sends, and how it reacts to each answer the server can give.
//
// These are fake-server widget tests: the app runs against `FakeBackend` with the JSON shapes the real routes
// return (see balkavach-backend/tests/test_parent_mission_approval.py, which runs the real approval code). They
// do not prove the production server or database behave this way.
import 'package:balkavach_app/features/approvals/presentation/approvals_screen.dart';
import 'package:balkavach_app/l10n/app_localizations_en.dart';
import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _queue = '/api/v1/reviews/submissions';
const _review = '/api/v1/reviews/submissions/${Fx.submissionId}';

/// A review-queue row as `GET /reviews/submissions` returns it: what an approval pays comes from the server.
Map<String, Object?> _row({String status = 'pending'}) => {
  ...Fx.submission(status: status, taskTitle: 'Saturday Rhythm Rockstar'),
  'family_id': Fx.familyId,
  'task_title': 'Saturday Rhythm Rockstar',
  'category_name': 'Creativity',
  'child_name': 'hshs',
  'star_reward': 10,
  'xp_reward': 15,
  'video_minutes_reward': 15,
  'required_video_seconds': 900,
  'verified_video_seconds': 900,
};

/// The server's queue, which moves the row between statuses as reviews succeed.
class _Server {
  String status = 'pending';

  FakeReply queue(RequestOptions options) {
    final wanted = (options.queryParameters['status'] as List).first;
    final inBucket = switch (status) {
      'pending' => wanted == 'pending',
      'approved' => wanted == 'approved',
      _ => wanted == 'rejected' || wanted == 'resubmission_requested',
    };
    return FakeReply(200, [if (inBucket) _row(status: status)]);
  }
}

Future<({Harness h, _Server server})> _screen(WidgetTester tester) async {
  final h = await Harness.create(
    session: Fx.parentSession(),
    prefs: onboardedPrefs,
  );
  final server = _Server();
  h.backend
    ..on('GET', _queue, server.queue)
    ..reply('GET', '/api/v1/notifications', <Object?>[]);
  await pumpScreen(tester, const ApprovalsScreen(), overrides: h.overrides);
  return (h: h, server: server);
}

Future<void> _tap(WidgetTester tester, Key key) async {
  if (key == const Key('review.approve') &&
      find.byType(SnackBar).evaluate().isNotEmpty) {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<String> _tabCount(WidgetTester tester, String tab) async {
  if (find.byType(SnackBar).evaluate().isNotEmpty) {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
  await tester.pumpAndSettle();
  final tabButton = find.byKey(Key('approvals.tab.$tab'));
  final finder = find.descendant(of: tabButton, matching: find.byType(Text));
  final texts = tester.widgetList<Text>(finder).map((t) => t.data).toList();
  return texts.last ?? '';
}

void main() {
  final l10n = AppLocalizationsEn();

  testWidgets(
    'the card shows the three rewards the server states, separately',
    (tester) async {
      await _screen(tester);

      expect(find.textContaining('Mission:'), findsOneWidget);
      final rewards = find.byKey(const Key('review.rewards'));
      expect(
        find.descendant(of: rewards, matching: find.text('+10')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rewards, matching: find.text('+15 XP')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rewards, matching: find.text('15 min video')),
        findsOneWidget,
      );
      expect(find.text(l10n.approvalsApprove(10)), findsOneWidget);
      expect(find.text(l10n.approvalVideoProgress(15, 15)), findsOneWidget);
    },
  );

  testWidgets('a server that does not state XP or minutes shows only stars', (
    tester,
  ) async {
    final h = await Harness.create(
      session: Fx.parentSession(),
      prefs: onboardedPrefs,
    );
    h.backend
      ..on('GET', _queue, (options) {
        final row = {..._row()}
          ..remove('xp_reward')
          ..remove('video_minutes_reward');
        return FakeReply(
          200,
          (options.queryParameters['status'] as List).first == 'pending'
              ? [row]
              : <Object?>[],
        );
      })
      ..reply('GET', '/api/v1/notifications', <Object?>[]);
    await pumpScreen(tester, const ApprovalsScreen(), overrides: h.overrides);

    expect(find.byKey(const Key('review.reward.xp')), findsNothing);
    expect(find.byKey(const Key('review.reward.video')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('review.rewards')),
        matching: find.text('+10'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'approving: nothing is shown as earned until the server confirms, then counts refresh',
    (tester) async {
      final s = await _screen(tester);
      expect(await _tabCount(tester, 'pending'), '1');
      expect(await _tabCount(tester, 'approved'), '0');

      s.h.backend.on('POST', _review, (options) {
        expect(options.data, {'decision': 'approved'});
        s.server.status = 'approved';
        return FakeReply(200, Fx.submission(status: 'approved'));
      });
      await _tap(tester, const Key('review.approve'));

      expect(
        find.text(l10n.approvalsApprovedToastFull('Aarav', 10, 15, 15)),
        findsOneWidget,
      );
      expect(await _tabCount(tester, 'pending'), '0');
      expect(await _tabCount(tester, 'approved'), '1');
      expect(await _tabCount(tester, 'retry'), '0');
      expect(s.h.backend.requestsTo('POST', _review), hasLength(1));
    },
  );

  testWidgets(
    'a failed approval shows the real reason, awards nothing on screen, and can be retried',
    (tester) async {
      final s = await _screen(tester);
      var calls = 0;
      s.h.backend.on('POST', _review, (_) {
        calls++;
        if (calls == 1) {
          return FakeReply.error(
            500,
            'approval_failed',
            'The approval could not be saved. Nothing was awarded. Please try again.',
          );
        }
        s.server.status = 'approved';
        return FakeReply(200, Fx.submission(status: 'approved'));
      });

      await _tap(tester, const Key('review.approve'));

      expect(find.text(l10n.errorApprovalFailed), findsOneWidget);
      expect(
        find.text(l10n.errorServer),
        findsNothing,
        reason: 'not the generic message',
      );
      expect(
        find.text(l10n.approvalsApprovedToastFull('Aarav', 10, 15, 15)),
        findsNothing,
      );
      expect(await _tabCount(tester, 'pending'), '1');
      expect(await _tabCount(tester, 'approved'), '0');

      // The button works again; the retry succeeds.
      await _tap(tester, const Key('review.approve'));
      expect(calls, 2);
      expect(
        find.text(l10n.approvalsApprovedToastFull('Aarav', 10, 15, 15)),
        findsOneWidget,
      );
      expect(await _tabCount(tester, 'approved'), '1');
    },
  );

  testWidgets(
    'a missing video-time schema is explained, not shown as a generic server problem',
    (tester) async {
      final s = await _screen(tester);
      s.h.backend.on(
        'POST',
        _review,
        (_) => FakeReply.error(
          503,
          'video_allowance_unavailable',
          'Video time cannot be granted right now.',
        ),
      );
      await _tap(tester, const Key('review.approve'));
      expect(find.text(l10n.errorVideoAllowanceUnavailable), findsOneWidget);
      expect(find.text(l10n.errorServer), findsNothing);
      expect(await _tabCount(tester, 'pending'), '1');
    },
  );

  testWidgets(
    'an unexplained server error still gets the generic message and a working button',
    (tester) async {
      final s = await _screen(tester);
      s.h.backend.on(
        'POST',
        _review,
        (_) => FakeReply.error(
          500,
          'internal_error',
          'An internal error occurred',
        ),
      );
      await _tap(tester, const Key('review.approve'));
      expect(find.text(l10n.errorServer), findsOneWidget);
      await _tap(tester, const Key('review.approve'));
      expect(s.h.backend.requestsTo('POST', _review), hasLength(2));
    },
  );

  testWidgets(
    'a repeated approval that the server answers with the existing result counts as success',
    (tester) async {
      final s = await _screen(tester);
      s.server.status =
          'approved'; // the first response was lost: the server already approved it
      s.h.backend.on(
        'POST',
        _review,
        (_) => FakeReply(200, Fx.submission(status: 'approved')),
      );
      await _tap(tester, const Key('review.approve'));
      expect(
        find.text(l10n.approvalsApprovedToastFull('Aarav', 10, 15, 15)),
        findsOneWidget,
      );
      expect(find.text(l10n.errorServer), findsNothing);
    },
  );

  testWidgets(
    'already reviewed elsewhere (409) says so and refreshes the lists',
    (tester) async {
      final s = await _screen(tester);
      s.h.backend.on('POST', _review, (_) {
        s.server.status = 'rejected';
        return FakeReply.error(
          409,
          'submission_already_reviewed',
          'This submission has already been reviewed',
        );
      });
      await _tap(tester, const Key('review.approve'));
      expect(find.text(l10n.approvalsAlreadyReviewed), findsOneWidget);
      expect(await _tabCount(tester, 'pending'), '0');
      expect(await _tabCount(tester, 'retry'), '1');
    },
  );

  testWidgets('tapping approve twice sends one request', (tester) async {
    final s = await _screen(tester);
    s.h.backend.on('POST', _review, (_) {
      s.server.status = 'approved';
      return FakeReply(200, Fx.submission(status: 'approved'));
    });
    await tester.tap(find.byKey(const Key('review.approve')));
    await tester.tap(
      find.byKey(const Key('review.approve')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(s.h.backend.requestsTo('POST', _review), hasLength(1));
  });

  testWidgets(
    'declining and asking for a retry send their own decision and move the counts',
    (tester) async {
      final s = await _screen(tester);
      s.h.backend.on('POST', _review, (options) {
        final decision = (options.data as Map)['decision'];
        s.server.status = decision as String;
        return FakeReply(200, Fx.submission(status: decision));
      });
      await _tap(tester, const Key('review.retry'));
      await tester.tap(find.byKey(const Key('review.note.confirm')));
      await tester.pumpAndSettle();

      expect(s.h.backend.requestsTo('POST', _review).single.data, {
        'decision': 'resubmission_requested',
      });
      expect(await _tabCount(tester, 'pending'), '0');
      expect(await _tabCount(tester, 'retry'), '1');
      expect(await _tabCount(tester, 'approved'), '0');
      expect(
        find.text(l10n.approvalsApprovedToastFull('Aarav', 10, 15, 15)),
        findsNothing,
      );
    },
  );
}
