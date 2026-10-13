import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/core/network/access_token_store.dart';
import 'package:balkavach_app/features/approvals/domain/review_models.dart';
import 'package:balkavach_app/features/missions/data/missions_repository.dart';
import 'package:balkavach_app/features/missions/domain/mission_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';

void main() {
  late FakeBackend backend;
  late MissionsRepository repo;

  setUp(() {
    backend = FakeBackend();
    repo = MissionsRepository(createTestDio(backend, AccessTokenStore()));
  });

  List<Map<String, Object?>> page(int from, int count) => [
    for (var i = from; i < from + count; i++)
      Fx.task(id: '55555555-5555-4555-8555-${i.toString().padLeft(12, '0')}'),
  ];

  group('listMissions paging', () {
    test('one short page needs one request and no offset', () async {
      backend.reply('GET', '/api/v1/tasks', page(0, 3));
      final missions = await repo.listMissions();
      expect(missions, hasLength(3));
      expect(backend.requests, hasLength(1));
      expect(backend.requests.single.uri.queryParameters, {'limit': '100'});
    });

    test('keeps asking while pages come back full', () async {
      backend.on('GET', '/api/v1/tasks', (options) {
        final offset = int.parse(options.uri.queryParameters['offset'] ?? '0');
        return FakeReply(200, page(offset, offset == 200 ? 7 : 100));
      });
      final missions = await repo.listMissions();
      expect(missions, hasLength(207));
      expect(backend.requests.map((r) => r.uri.queryParameters['offset']), [
        null,
        '100',
        '200',
      ]);
      expect(missions.map((m) => m.id).toSet(), hasLength(207));
    });

    test('stops at the page cap instead of looping forever', () async {
      backend.on('GET', '/api/v1/tasks', (options) {
        final offset = int.parse(options.uri.queryParameters['offset'] ?? '0');
        return FakeReply(200, page(offset, 100));
      });
      final missions = await repo.listMissions(maxPages: 3);
      expect(missions, hasLength(300));
      expect(backend.requests, hasLength(3));
    });

    test(
      'a failing later page fails the whole load (no silent gaps)',
      () async {
        backend.on('GET', '/api/v1/tasks', (options) {
          final offset = int.parse(
            options.uri.queryParameters['offset'] ?? '0',
          );
          return offset == 0
              ? FakeReply(200, page(0, 100))
              : FakeReply.error(500, 'internal_error', 'boom');
        });
        await expectLater(repo.listMissions(), throwsA(isA<ServerException>()));
      },
    );

    test('family id is sent on every page', () async {
      backend.on('GET', '/api/v1/tasks', (options) {
        final offset = int.parse(options.uri.queryParameters['offset'] ?? '0');
        return FakeReply(200, page(offset, offset == 0 ? 100 : 1));
      });
      await repo.listMissions(familyId: Fx.familyId);
      expect(
        backend.requests.map((r) => r.uri.queryParameters['family_id']),
        everyElement(Fx.familyId),
      );
    });
  });

  group('NewMission bodies', () {
    test('create leaves out blank optional fields', () {
      const mission = NewMission(
        familyId: Fx.familyId,
        title: ' Read ',
        description: '   ',
      );
      expect(mission.toJson(), {
        'family_id': Fx.familyId,
        'title': 'Read',
        'star_reward': 0,
        'xp_reward': 0,
      });
    });

    test('create sends the due date as UTC with an offset', () {
      final mission = NewMission(
        familyId: Fx.familyId,
        title: 'Read',
        dueAt: DateTime.utc(2026, 11, 3, 18, 29),
      );
      expect(mission.toJson()['due_at'], '2026-11-03T18:29:00.000Z');
    });

    test('a local due date is converted to UTC, never sent naive', () {
      final due =
          NewMission(
                familyId: Fx.familyId,
                title: 'Read',
                dueAt: DateTime(2026, 11, 3, 23, 59),
              ).toJson()['due_at']!
              as String;
      expect(due, endsWith('Z'));
      expect(DateTime.parse(due).isUtc, isTrue);
    });

    test('patch sends explicit nulls so fields can be cleared', () {
      const mission = NewMission(
        familyId: Fx.familyId,
        title: 'Read',
        starReward: 5,
        xpReward: 9,
      );
      expect(mission.toPatchJson(), {
        'title': 'Read',
        'description': null,
        'category_id': null,
        'assigned_child_id': null,
        'star_reward': 5,
        'xp_reward': 9,
        'due_at': null,
      });
    });
  });

  group('mission mutations', () {
    const path = '/api/v1/tasks/${Fx.taskId}';

    test('updateMission issues PATCH and parses the task', () async {
      backend.reply('PATCH', path, Fx.task(title: 'New title'));
      final updated = await repo.updateMission(
        Fx.taskId,
        const NewMission(familyId: Fx.familyId, title: 'New title'),
      );
      expect(backend.requests.single.method, 'PATCH');
      expect(backend.requests.single.data, containsPair('title', 'New title'));
      expect(updated.title, 'New title');
    });

    test('updating a removed mission maps to NotFoundException', () async {
      backend.on(
        'PATCH',
        path,
        (_) => FakeReply.error(404, 'http_error', 'Task not found'),
      );
      await expectLater(
        repo.updateMission(
          Fx.taskId,
          const NewMission(familyId: Fx.familyId, title: 'x'),
        ),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('deactivateMission issues DELETE and accepts 204', () async {
      backend.on('DELETE', path, (_) => const FakeReply(204));
      await repo.deactivateMission(Fx.taskId);
      expect(backend.requests.single.method, 'DELETE');
    });

    test('markNotificationRead posts to the notification', () async {
      const id = '88888888-8888-4888-8888-888888888888';
      backend.reply(
        'POST',
        '/api/v1/notifications/$id/read',
        Fx.notification(type: 'task_submitted'),
      );
      await repo.markNotificationRead(id);
      expect(backend.requests.single.method, 'POST');
    });
  });

  test('unreviewedSubmissionCount counts unread task_submitted only', () {
    AppNotification n(String type, {bool read = false}) =>
        AppNotification.fromJson({
          ...Fx.notification(type: type),
          'is_read': read,
        });
    expect(
      unreviewedSubmissionCount([
        n('task_submitted'),
        n('task_submitted'),
        n('task_submitted', read: true),
        n('task_approved'),
        n('badge_unlocked'),
      ]),
      2,
    );
    expect(unreviewedSubmissionCount(const []), 0);
  });
}
