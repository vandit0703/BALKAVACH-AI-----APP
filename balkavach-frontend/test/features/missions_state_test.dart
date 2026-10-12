import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/features/authentication/presentation/session_controller.dart';
import 'package:balkavach_app/features/child_profile/presentation/family_providers.dart';
import 'package:balkavach_app/features/missions/domain/mission_models.dart';
import 'package:balkavach_app/features/missions/domain/mission_status.dart';
import 'package:balkavach_app/features/missions/presentation/mission_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

AppNotification _review(
  String type, {
  String? submissionId = Fx.submissionId,
  String at = '2026-10-12T10:00:00Z',
}) => AppNotification.fromJson(
  Fx.notification(type: type, submissionId: submissionId, createdAt: at),
);

LocalSubmissionRecord _local({
  String submissionId = Fx.submissionId,
  String at = '2026-10-12T09:00:00Z',
}) => LocalSubmissionRecord(
  taskId: Fx.taskId,
  submissionId: submissionId,
  submittedAt: DateTime.parse(at),
);

void main() {
  group('resolveMissionStatuses', () {
    test('local submission without review is pending', () {
      expect(
        resolveMissionStatuses(
          submissions: [_local()],
          notifications: const [],
        ),
        {Fx.taskId: MissionStatus.pending},
      );
    });

    test('review for the same submission resolves it', () {
      for (final (type, expected) in [
        ('task_approved', MissionStatus.approved),
        ('task_rejected', MissionStatus.rejected),
        ('task_resubmission_requested', MissionStatus.resubmissionRequested),
      ]) {
        expect(
          resolveMissionStatuses(
            submissions: [_local()],
            notifications: [_review(type)],
          ),
          {Fx.taskId: expected},
        );
      }
    });

    test('a newer local submission after a review is pending again', () {
      final statuses = resolveMissionStatuses(
        submissions: [
          _local(submissionId: 'second', at: '2026-10-12T11:00:00Z'),
        ],
        notifications: [_review('task_approved', at: '2026-10-12T10:00:00Z')],
      );
      expect(statuses[Fx.taskId], MissionStatus.pending);
    });

    test('reviews of submissions from another device apply by task', () {
      expect(
        resolveMissionStatuses(
          submissions: const [],
          notifications: [_review('task_approved', submissionId: 'elsewhere')],
        ),
        {Fx.taskId: MissionStatus.approved},
      );
    });

    test('unrelated notification types are ignored', () {
      expect(
        resolveMissionStatuses(
          submissions: const [],
          notifications: [_review('badge_unlocked')],
        ),
        isEmpty,
      );
    });
  });

  group('MissionSubmitController', () {
    Future<Harness> childHarness() async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply(
        'GET',
        '/api/v1/auth/me',
        Fx.childSession().user.toJson(),
      );
      return h;
    }

    test(
      'success records the submission locally and shows it as pending',
      () async {
        final h = await childHarness();
        h.backend.reply(
          'POST',
          '/api/v1/tasks/${Fx.taskId}/submissions',
          Fx.submission(),
          status: 201,
        );
        final container = h.container();
        await container.read(sessionControllerProvider.future);
        final sub = container.listen(
          missionSubmitControllerProvider,
          (_, _) {},
        );
        addTearDown(sub.close);

        final result = await container
            .read(missionSubmitControllerProvider.notifier)
            .submit(Fx.taskId, note: 'Done');

        expect(result?.status, 'pending');
        expect(
          container.read(missionSubmitControllerProvider).value?.id,
          Fx.submissionId,
        );
        expect(
          h.prefs.submissionRecords(Fx.childId).single['submission_id'],
          Fx.submissionId,
        );
        final snapshot = await container.read(missionStatusesProvider.future);
        expect(snapshot.statusOf(Fx.taskId), MissionStatus.pending);
        expect(snapshot.statusOf(Fx.task2Id), MissionStatus.notStarted);
      },
    );

    test('approval notification moves the mission to approved', () async {
      final h = await childHarness();
      h.backend.reply(
        'POST',
        '/api/v1/tasks/${Fx.taskId}/submissions',
        Fx.submission(),
        status: 201,
      );
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      final sub = container.listen(missionSubmitControllerProvider, (_, _) {});
      addTearDown(sub.close);
      await container
          .read(missionSubmitControllerProvider.notifier)
          .submit(Fx.taskId);

      h.backend.reply('GET', '/api/v1/notifications', [
        Fx.notification(type: 'task_approved'),
      ]);
      container.invalidate(childNotificationsProvider);
      final snapshot = await container.read(missionStatusesProvider.future);
      expect(snapshot.statusOf(Fx.taskId), MissionStatus.approved);
    });

    test('failure keeps the error and records nothing', () async {
      final h = await childHarness();
      h.backend.on(
        'POST',
        '/api/v1/tasks/${Fx.taskId}/submissions',
        (_) => FakeReply.error(404, 'task_not_found', 'Task not found'),
      );
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      final sub = container.listen(missionSubmitControllerProvider, (_, _) {});
      addTearDown(sub.close);

      final result = await container
          .read(missionSubmitControllerProvider.notifier)
          .submit(Fx.taskId);
      expect(result, isNull);
      expect(
        container.read(missionSubmitControllerProvider).error,
        isA<NotFoundException>(),
      );
      expect(h.prefs.submissionRecords(Fx.childId), isEmpty);
    });

    test(
      'notifications outage degrades to local statuses with a flag',
      () async {
        final h = await childHarness();
        h.backend.on(
          'GET',
          '/api/v1/notifications',
          (_) => const FakeReply.fail(DioExceptionType.connectionError),
        );
        final container = h.container();
        await container.read(sessionControllerProvider.future);
        final snapshot = await container.read(missionStatusesProvider.future);
        expect(snapshot.reviewsAvailable, isFalse);
      },
    );

    test('requires a child session', () async {
      final h = await Harness.create(session: Fx.parentSession());
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      final sub = container.listen(missionSubmitControllerProvider, (_, _) {});
      addTearDown(sub.close);
      expect(
        await container
            .read(missionSubmitControllerProvider.notifier)
            .submit(Fx.taskId),
        isNull,
      );
      expect(
        container.read(missionSubmitControllerProvider).error,
        isA<ForbiddenException>(),
      );
      expect(
        h.backend.requestsTo('POST', '/api/v1/tasks/${Fx.taskId}/submissions'),
        isEmpty,
      );
    });
  });

  group('consentSyncProvider', () {
    test('records consent once when none exists, then remembers it', () async {
      final h = await Harness.create(
        session: Fx.parentSession(),
        prefs: onboardedPrefs,
      );
      h.backend
          .reply('POST', '/api/v1/settings/families/${Fx.familyId}/consents', {
            'id': 'c1',
            'family_id': Fx.familyId,
            'child_id': null,
            'parent_user_id': Fx.parentUserId,
            'consent_type': 'parent_guardian_terms',
            'document_version': '2026-10-draft',
            'accepted': true,
            'accepted_at': '2026-10-12T09:00:00Z',
            'revoked_at': null,
            'created_at': '2026-10-12T09:00:00Z',
          }, status: 201);
      final container = h.container();
      expect(
        await container.read(consentSyncProvider(Fx.familyId).future),
        isTrue,
      );
      expect(
        h.backend.requestsTo(
          'POST',
          '/api/v1/settings/families/${Fx.familyId}/consents',
        ),
        hasLength(1),
      );

      container.invalidate(consentSyncProvider(Fx.familyId));
      expect(
        await container.read(consentSyncProvider(Fx.familyId).future),
        isTrue,
      );
      expect(
        h.backend.requestsTo(
          'POST',
          '/api/v1/settings/families/${Fx.familyId}/consents',
        ),
        hasLength(1),
      );
    });

    test(
      'does not record anything without on-device acknowledgement',
      () async {
        final h = await Harness.create(session: Fx.parentSession());
        final container = h.container();
        expect(
          await container.read(consentSyncProvider(Fx.familyId).future),
          isFalse,
        );
        expect(h.backend.requests, isEmpty);
      },
    );
  });
}
