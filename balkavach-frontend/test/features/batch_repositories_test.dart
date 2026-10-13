import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/core/network/access_token_store.dart';
import 'package:balkavach_app/features/approvals/data/approvals_repository.dart';
import 'package:balkavach_app/features/approvals/domain/review_models.dart';
import 'package:balkavach_app/features/child_profile/data/family_repository.dart';
import 'package:balkavach_app/features/rewards/data/rewards_repository.dart';
import 'package:balkavach_app/features/settings/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';

void main() {
  late FakeBackend backend;
  late AccessTokenStore tokens;

  setUp(() {
    backend = FakeBackend();
    tokens = AccessTokenStore();
  });

  group('ApprovalsRepository', () {
    ApprovalsRepository repo() =>
        ApprovalsRepository(createTestDio(backend, tokens));
    const path = '/api/v1/reviews/submissions/${Fx.submissionId}';

    test('lists a task\'s submissions', () async {
      backend.reply('GET', '/api/v1/tasks/${Fx.taskId}/submissions', [
        Fx.submission(),
      ]);
      final list = await repo().listSubmissions(Fx.taskId);
      expect(list.single.status, 'pending');
      expect(backend.requests.single.queryParameters, {'limit': 50});
    });

    test('approve sends only the decision when there is no note', () async {
      backend.reply('POST', path, Fx.submission(status: 'approved'));
      final result = await repo().review(
        Fx.submissionId,
        ReviewDecision.approved,
      );
      expect(backend.requests.single.data, {'decision': 'approved'});
      expect(result.status, 'approved');
    });

    test('retry sends the snake_case decision and a trimmed note', () async {
      backend.reply(
        'POST',
        path,
        Fx.submission(status: 'resubmission_requested'),
      );
      await repo().review(
        Fx.submissionId,
        ReviewDecision.resubmissionRequested,
        note: '  draw the tree too  ',
      );
      expect(backend.requests.single.data, {
        'decision': 'resubmission_requested',
        'review_note': 'draw the tree too',
      });
    });

    test('blank notes are not sent', () async {
      backend.reply('POST', path, Fx.submission(status: 'rejected'));
      await repo().review(
        Fx.submissionId,
        ReviewDecision.rejected,
        note: '   ',
      );
      expect(backend.requests.single.data, {'decision': 'rejected'});
    });

    test('a second review maps to ConflictException', () async {
      backend.on(
        'POST',
        path,
        (_) => FakeReply.error(
          409,
          'submission_already_reviewed',
          'This submission has already been reviewed',
        ),
      );
      await expectLater(
        repo().review(Fx.submissionId, ReviewDecision.approved),
        throwsA(
          isA<ConflictException>().having(
            (e) => e.code,
            'code',
            'submission_already_reviewed',
          ),
        ),
      );
    });
  });

  group('FamilyRepository child management', () {
    FamilyRepository repo() => FamilyRepository(createTestDio(backend, tokens));
    const childPath = '/api/v1/families/${Fx.familyId}/children/${Fx.childId}';

    test('updateChild patches name and date of birth only', () async {
      backend.reply('PATCH', childPath, Fx.child(name: 'Aarav S'));
      final child = await repo().updateChild(
        Fx.familyId,
        Fx.childId,
        displayName: '  Aarav S ',
        dateOfBirth: DateTime(2019, 5, 4),
      );
      expect(backend.requests.single.data, {
        'display_name': 'Aarav S',
        'date_of_birth': '2019-05-04',
      });
      expect(child.displayName, 'Aarav S');
    });

    test('updateChild omits a missing date of birth', () async {
      backend.reply('PATCH', childPath, Fx.child());
      await repo().updateChild(Fx.familyId, Fx.childId, displayName: 'Aarav');
      expect(backend.requests.single.data, {'display_name': 'Aarav'});
    });

    test('an underage-violating date maps to ValidationException', () async {
      backend.on(
        'PATCH',
        childPath,
        (_) => FakeReply.error(422, 'validation_error', 'Invalid', [
          {
            'location': ['body', 'date_of_birth'],
            'message': 'date_of_birth must be in the past',
            'type': 'value_error',
          },
        ]),
      );
      await expectLater(
        repo().updateChild(Fx.familyId, Fx.childId, displayName: 'A'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('deactivateChild issues DELETE and accepts 204', () async {
      backend.on('DELETE', childPath, (_) => const FakeReply(204));
      await repo().deactivateChild(Fx.familyId, Fx.childId);
      expect(backend.requests.single.method, 'DELETE');
    });
  });

  group('SettingsRepository', () {
    SettingsRepository repo() =>
        SettingsRepository(createTestDio(backend, tokens));

    test('reads settings', () async {
      backend.reply('GET', '/api/v1/settings/me', Fx.userSettings(push: false));
      final settings = await repo().mySettings();
      expect(settings.pushEnabled, isFalse);
      expect(settings.emailNotificationsEnabled, isTrue);
    });

    test('sends only changed fields (null values are rejected)', () async {
      backend.reply('PATCH', '/api/v1/settings/me', Fx.userSettings());
      await repo().updateMySettings(pushEnabled: false);
      expect(backend.requests.single.data, {'push_enabled': false});
    });
  });

  group('RewardsRepository', () {
    test('parses the child\'s redemption requests', () async {
      backend.reply('GET', '/api/v1/redemptions/mine', [
        Fx.redemption(status: 'approved', cost: 75),
      ]);
      final list = await RewardsRepository(
        createTestDio(backend, tokens),
      ).myRedemptions();
      expect(list.single.status, 'approved');
      expect(list.single.starCost, 75);
    });
  });
}
