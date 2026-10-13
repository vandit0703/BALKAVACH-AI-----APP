import 'package:balkavach_app/features/approvals/data/approvals_repository.dart';
import 'package:balkavach_app/features/approvals/domain/review_models.dart';
import 'package:balkavach_app/features/approvals/presentation/approval_providers.dart';
import 'package:balkavach_app/features/approvals/presentation/approvals_screen.dart';
import 'package:balkavach_app/features/authentication/presentation/session_controller.dart';
import 'package:balkavach_app/features/missions/domain/mission_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_photo_picker.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _queue = '/api/v1/reviews/submissions';

Map<String, Object?> _queued({
  String id = Fx.submissionId,
  String status = 'pending',
  String taskId = Fx.taskId,
  String title = 'Read a Storybook',
  String childName = 'Aarav',
  String? proofUrl,
  String proofType = 'note',
  int stars = 10,
}) => {
  ...Fx.submission(
    id: id,
    status: status,
    taskId: taskId,
    proofType: proofType,
    proofUrl: proofUrl,
  ),
  'family_id': Fx.familyId,
  'task_title': title,
  'category_name': 'Learn',
  'child_name': childName,
  'star_reward': stars,
  'xp_reward': 20,
};

void main() {
  group('repository', () {
    test('asks for a family\'s submissions by status', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.reply('GET', _queue, [_queued()]);
      final repo = h.container().read(approvalsRepositoryProvider);

      final list = await repo.listFamilySubmissions(
        Fx.familyId,
        statuses: ['rejected', 'resubmission_requested'],
        limit: 50,
      );
      expect(list.single.childName, 'Aarav');
      expect(list.single.starReward, 10);
      final query = h.backend.requestsTo('GET', _queue).single.queryParameters;
      expect(query['family_id'], Fx.familyId);
      expect(query['status'], ['rejected', 'resubmission_requested']);
      expect(query['limit'], 50);
    });
  });

  group('inbox', () {
    test('three bounded requests, however many missions exist', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.on('GET', _queue, (options) {
        final status = (options.queryParameters['status'] as List).first;
        return FakeReply(200, [
          if (status == 'pending') _queued(),
          if (status == 'approved')
            _queued(id: 'a1', status: 'approved', title: 'Done thing'),
          if (status == 'rejected')
            _queued(id: 'r1', status: 'rejected', title: 'Try again thing'),
        ]);
      });
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      final inbox = await container.read(
        approvalInboxProvider(Fx.familyId).future,
      );

      expect(inbox.pending.single.submission.id, Fx.submissionId);
      expect(inbox.approved.single.submission.id, 'a1');
      expect(inbox.retry.single.submission.id, 'r1');
      expect(h.backend.requestsTo('GET', _queue), hasLength(3));
      expect(
        h.backend.requests.where((r) => r.uri.path.contains('/tasks/')),
        isEmpty,
        reason: 'no per-task fan-out any more',
      );
    });

    test('a removed task keeps its real title and stars', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend
        ..reply('GET', '/api/v1/tasks', <Object?>[])
        ..on(
          'GET',
          _queue,
          (options) => FakeReply(200, [
            if ((options.queryParameters['status'] as List).first == 'pending')
              _queued(title: 'Deleted but real', stars: 7),
          ]),
        );
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      final inbox = await container.read(
        approvalInboxProvider(Fx.familyId).future,
      );
      final item = inbox.pending.single;
      expect(item.mission?.title, 'Deleted but real');
      expect(item.mission?.starReward, 7);
      expect(item.childName, 'Aarav');
    });

    test(
      'falls back to per-task loading on a server without the endpoint',
      () async {
        final h = await Harness.create(session: Fx.parentSession());
        h.backend
          ..reply('GET', '/api/v1/notifications', [
            Fx.notification(type: 'task_submitted'),
          ])
          ..reply('GET', '/api/v1/tasks/${Fx.taskId}/submissions', [
            Fx.submission(),
          ]);
        final container = h.container();
        await container.read(sessionControllerProvider.future);
        final inbox = await container.read(
          approvalInboxProvider(Fx.familyId).future,
        );
        expect(inbox.pending, hasLength(1));
        expect(
          h.backend.requestsTo('GET', '/api/v1/tasks/${Fx.taskId}/submissions'),
          hasLength(1),
        );
      },
    );

    test('flags a full page as possibly truncated', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.on(
        'GET',
        _queue,
        (options) => FakeReply(200, [
          if ((options.queryParameters['status'] as List).first == 'pending')
            for (var i = 0; i < 100; i++) _queued(id: 'p$i'),
        ]),
      );
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      final inbox = await container.read(
        approvalInboxProvider(Fx.familyId).future,
      );
      expect(inbox.pending, hasLength(100));
      expect(inbox.truncated, isTrue);
    });
  });

  group('review item', () {
    test('reports the child name from the queue when the profile is gone', () {
      final item = ReviewItem(
        submission: TaskSubmission.fromJson(_queued(childName: 'Mira')),
      );
      expect(item.child, isNull);
      expect(item.childName, 'Mira');
    });
  });

  group('screen: proof photos', () {
    Future<Harness> pump(
      WidgetTester tester, {
      bool photoFails = false,
      String proofUrl = '/api/v1/uploads/task-proofs/up-1',
    }) async {
      final h = await Harness.create(
        session: Fx.parentSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..on(
          'GET',
          _queue,
          (options) => FakeReply(200, [
            if ((options.queryParameters['status'] as List).first == 'pending')
              _queued(proofType: 'image', proofUrl: proofUrl),
          ]),
        )
        ..on(
          'GET',
          '/api/v1/uploads/task-proofs/up-1',
          (_) => photoFails
              ? FakeReply.error(404, 'upload_not_found', 'gone')
              : FakeReply(200, kTinyPng.toList()),
        );
      await pumpScreen(tester, const ApprovalsScreen(), overrides: h.overrides);
      return h;
    }

    testWidgets(
      'a stored photo is fetched with the parent\'s token and shown',
      (tester) async {
        final h = await pump(tester);
        expect(find.byKey(const Key('review.proof')), findsOneWidget);
        final fetch = h.backend.requestsTo(
          'GET',
          '/api/v1/uploads/task-proofs/up-1',
        );
        expect(fetch, hasLength(1));
        expect(
          fetch.single.headers['Authorization'],
          'Bearer parent.jwt.token',
        );
      },
    );

    testWidgets('tapping the photo opens a zoomable full-screen view', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('review.proof')));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('a photo that cannot be loaded says so instead of failing', (
      tester,
    ) async {
      await pump(tester, photoFails: true);
      expect(find.byKey(const Key('review.proof')), findsNothing);
      expect(find.text("The photo couldn't be loaded."), findsOneWidget);
    });
  });
}
