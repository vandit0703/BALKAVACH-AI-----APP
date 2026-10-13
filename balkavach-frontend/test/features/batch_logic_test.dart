import 'package:balkavach_app/features/approvals/domain/review_models.dart';
import 'package:balkavach_app/features/child_profile/domain/family_models.dart';
import 'package:balkavach_app/features/garden/presentation/garden_screen.dart';
import 'package:balkavach_app/features/missions/domain/mission_models.dart';
import 'package:balkavach_app/features/progress/data/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';

TaskSubmission _submission(
  String id,
  String status, {
  String childId = Fx.childId,
  String submittedAt = '2026-10-12T09:00:00Z',
}) => TaskSubmission.fromJson({
  ...Fx.submission(id: id, status: status),
  'child_id': childId,
  'submitted_at': submittedAt,
});

void main() {
  group('ApprovalInbox.from', () {
    final missions = [Mission.fromJson(Fx.task())];
    final children = [ChildProfile.fromJson(Fx.child())];

    test('splits by status and keeps rejected under retry', () {
      final inbox = ApprovalInbox.from(
        submissions: [
          _submission('a', 'pending'),
          _submission('b', 'approved'),
          _submission('c', 'resubmission_requested'),
          _submission('d', 'rejected'),
        ],
        missions: missions,
        children: children,
      );
      expect(inbox.pending.map((i) => i.submission.id), ['a']);
      expect(inbox.approved.map((i) => i.submission.id), ['b']);
      expect(inbox.retry.map((i) => i.submission.id), ['c', 'd']);
    });

    test('ignores submissions from children outside the family', () {
      final inbox = ApprovalInbox.from(
        submissions: [
          _submission('a', 'pending'),
          _submission('x', 'pending', childId: 'someone-else'),
        ],
        missions: missions,
        children: children,
      );
      expect(inbox.pending.map((i) => i.submission.id), ['a']);
    });

    test('de-duplicates, sorts newest first and links task and child', () {
      final inbox = ApprovalInbox.from(
        submissions: [
          _submission('old', 'pending', submittedAt: '2026-10-10T09:00:00Z'),
          _submission('new', 'pending', submittedAt: '2026-10-12T09:00:00Z'),
          _submission('new', 'pending', submittedAt: '2026-10-12T09:00:00Z'),
        ],
        missions: missions,
        children: children,
      );
      expect(inbox.pending.map((i) => i.submission.id), ['new', 'old']);
      expect(inbox.pending.first.mission?.title, 'Read a Storybook');
      expect(inbox.pending.first.child?.displayName, 'Aarav');
    });

    test('a task that no longer exists still shows its submission', () {
      final inbox = ApprovalInbox.from(
        submissions: [_submission('a', 'pending')],
        missions: const [],
        children: children,
      );
      expect(inbox.pending.single.mission, isNull);
    });
  });

  test('submittedTaskIds keeps only task_submitted, de-duplicated', () {
    AppNotification n(String type, String? taskId) =>
        AppNotification.fromJson(Fx.notification(type: type, taskId: taskId));
    expect(
      submittedTaskIds([
        n('task_submitted', Fx.taskId),
        n('task_submitted', Fx.taskId),
        n('task_approved', Fx.task2Id),
        n('task_submitted', null),
        n('task_submitted', Fx.task2Id),
      ]),
      [Fx.taskId, Fx.task2Id],
    );
  });

  group('ChildProgress.week', () {
    test('fills seven days ending today with zeros for quiet days', () {
      final progress = ChildProgress.fromJson(
        Fx.progress(
          activityDays: [
            Fx.activityDay('2026-10-12', tasks: 2, stars: 20),
            Fx.activityDay('2026-10-10', tasks: 1),
            // Outside the 7-day window.
            Fx.activityDay('2026-10-01', tasks: 9),
          ],
        ),
      );
      final week = progress.week(Fx.now);
      expect(week, hasLength(7));
      expect(week.first.date, DateTime.utc(2026, 10, 6));
      expect(week.last.date, DateTime.utc(2026, 10, 12));
      expect(week.map((d) => d.completedTasks), [0, 0, 0, 0, 1, 0, 2]);
      expect(week.last.starsEarned, 20);
    });

    // The API contract (`ActivityDayPublic.activity_date`) is a UTC calendar
    // day: the backend sets it from `datetime.now(timezone.utc).date()` at
    // approval time. Asia/Kolkata is UTC+05:30, so IST 00:00-05:29 belongs to
    // the previous UTC day. Instants below are built in UTC so the tests do
    // not depend on the machine's time zone.
    group('Asia/Kolkata midnight', () {
      ChildProgress progressWith(List<String> days) => ChildProgress.fromJson(
        Fx.progress(
          activityDays: [for (final d in days) Fx.activityDay(d, tasks: 1)],
        ),
      );

      test(
        'activity_date parses to midnight UTC regardless of device zone',
        () {
          final day = ActivityDay.fromJson(Fx.activityDay('2026-10-13'));
          expect(day.date, DateTime.utc(2026, 10, 13));
          expect(day.date.isUtc, isTrue);
        },
      );

      test(
        'approval at 00:30 IST (19:00Z previous day) is on the current UTC bar',
        () {
          // 2026-10-14 00:30 IST == 2026-10-13T19:00Z -> server stores 10-13.
          final approvedAt = DateTime.utc(2026, 10, 13, 19);
          final week = progressWith(['2026-10-13']).week(approvedAt);
          expect(week.last.date, DateTime.utc(2026, 10, 13));
          expect(week.last.completedTasks, 1);
          expect(week.take(6).every((d) => d.completedTasks == 0), isTrue);
        },
      );

      test('same approval is still on its own bar at 06:00 IST next day', () {
        // 06:00 IST on Oct 14 == 00:30Z Oct 14: new UTC day has begun.
        final week = progressWith([
          '2026-10-13',
        ]).week(DateTime.utc(2026, 10, 14, 0, 30));
        expect(week.last.date, DateTime.utc(2026, 10, 14));
        expect(week.last.completedTasks, 0);
        expect(week[5].date, DateTime.utc(2026, 10, 13));
        expect(week[5].completedTasks, 1);
      });

      test('approval at 05:45 IST (00:15Z) lands on the new UTC day', () {
        final week = progressWith([
          '2026-10-14',
        ]).week(DateTime.utc(2026, 10, 14, 0, 15));
        expect(week.last.date, DateTime.utc(2026, 10, 14));
        expect(week.last.completedTasks, 1);
      });

      test(
        '23:45 IST approval is not pushed out of the week at IST midnight',
        () {
          // Approved 23:45 IST Oct 19 (18:15Z) -> stored 10-19. Viewed at
          // 00:10 IST Oct 20 (18:40Z Oct 19): bar must still be present.
          final week = progressWith([
            '2026-10-19',
          ]).week(DateTime.utc(2026, 10, 19, 18, 40));
          expect(week.last.date, DateTime.utc(2026, 10, 19));
          expect(week.last.completedTasks, 1);
        },
      );

      test('oldest day of the window is kept just after IST midnight', () {
        // View at 00:10 IST Oct 20 == 18:40Z Oct 19: window is Oct 13-19.
        // A device-local anchor (Oct 20) would drop Oct 13.
        final week = progressWith([
          '2026-10-13',
        ]).week(DateTime.utc(2026, 10, 19, 18, 40));
        expect(week.first.date, DateTime.utc(2026, 10, 13));
        expect(week.first.completedTasks, 1);
      });

      test('window ignores the representation of the same instant', () {
        final progress = progressWith(['2026-10-13']);
        final utc = DateTime.utc(2026, 10, 13, 19);
        // Local (device-zone) DateTime for the identical instant.
        final local = DateTime.fromMillisecondsSinceEpoch(
          utc.millisecondsSinceEpoch,
        );
        expect(
          progress.week(local).map((d) => d.date).toList(),
          progress.week(utc).map((d) => d.date).toList(),
        );
      });
    });

    test('parses badges', () {
      final progress = ChildProgress.fromJson(
        Fx.progress(badges: [Fx.badge(name: 'Bookworm')]),
      );
      expect(progress.badgeCount, 1);
      expect(progress.badges.single.name, 'Bookworm');
    });
  });

  group('GardenStage', () {
    test('maps approved missions this week to a stage', () {
      GardenStage s(int n) => GardenStage.forWeeklyMissions(n);
      expect(s(0), GardenStage.seed);
      expect(s(1), GardenStage.sprout);
      expect(s(2), GardenStage.sprout);
      expect(s(3), GardenStage.sapling);
      expect(s(5), GardenStage.sapling);
      expect(s(6), GardenStage.bloomingTree);
      expect(s(40), GardenStage.bloomingTree);
    });

    test('the top stage has no next stage', () {
      expect(GardenStage.bloomingTree.next, isNull);
      expect(GardenStage.seed.next, GardenStage.sprout);
    });
  });
}
