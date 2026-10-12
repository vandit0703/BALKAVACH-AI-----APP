import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/core/network/access_token_store.dart';
import 'package:balkavach_app/features/authentication/data/auth_repository.dart';
import 'package:balkavach_app/features/authentication/domain/session.dart';
import 'package:balkavach_app/features/child_profile/data/family_repository.dart';
import 'package:balkavach_app/features/child_profile/domain/family_models.dart';
import 'package:balkavach_app/features/missions/data/missions_repository.dart';
import 'package:balkavach_app/features/missions/domain/mission_models.dart';
import 'package:balkavach_app/features/progress/data/progress_repository.dart';
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

  group('AuthRepository', () {
    AuthRepository repo() => AuthRepository(createTestDio(backend, tokens));

    test(
      'login posts credentials without a token and parses TokenResponse',
      () async {
        tokens.token = 'stale';
        backend.reply('POST', '/api/v1/auth/login', Fx.token());
        final session = await repo().login(
          email: ' priya@example.com ',
          password: 'pw',
        );

        final request = backend.requests.single;
        expect(request.data, {'email': 'priya@example.com', 'password': 'pw'});
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(session.accessToken, 'parent.jwt.token');
        expect(session.user.role, UserRole.parent);
        expect(session.expiresAt, DateTime.utc(2100));
        expect(session.childId, isNull);
      },
    );

    test('invalid credentials surface the backend code', () async {
      backend.on(
        'POST',
        '/api/v1/auth/login',
        (_) => FakeReply.error(
          401,
          'invalid_credentials',
          'Email or password is incorrect',
        ),
      );
      await expectLater(
        repo().login(email: 'a@b.co', password: 'x'),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.code,
            'code',
            'invalid_credentials',
          ),
        ),
      );
    });

    test('register sends full_name and maps 409 email_in_use', () async {
      backend.on(
        'POST',
        '/api/v1/auth/register',
        (_) => FakeReply.error(
          409,
          'email_in_use',
          'An account with this email already exists',
        ),
      );
      await expectLater(
        repo().register(
          fullName: ' Priya ',
          email: 'p@x.io',
          password: 'twelve-chars!',
        ),
        throwsA(isA<ConflictException>()),
      );
      expect(backend.requests.single.data, {
        'full_name': 'Priya',
        'email': 'p@x.io',
        'password': 'twelve-chars!',
      });
    });

    test('child session keeps the child profile id', () async {
      tokens.token = 'parent.jwt.token';
      backend.reply(
        'POST',
        '/api/v1/auth/children/${Fx.childId}/session',
        Fx.childToken(),
      );
      final session = await repo().startChildSession(Fx.childId);
      expect(session.isChild, isTrue);
      expect(session.childId, Fx.childId);
      expect(
        backend.requests.single.headers['Authorization'],
        'Bearer parent.jwt.token',
      );
    });

    test('me uses the explicit token', () async {
      backend.reply('GET', '/api/v1/auth/me', Fx.user());
      final user = await repo().me(accessToken: 'restored');
      expect(user.fullName, 'Priya Sharma');
      expect(
        backend.requests.single.headers['Authorization'],
        'Bearer restored',
      );
    });

    test('session JSON round-trips for secure storage', () {
      final session = Fx.childSession();
      expect(Session.fromJson(session.toJson()), session);
    });
  });

  group('FamilyRepository', () {
    FamilyRepository repo() => FamilyRepository(createTestDio(backend, tokens));

    test('createChild sends only stored fields with an ISO date', () async {
      backend.reply(
        'POST',
        '/api/v1/families/${Fx.familyId}/children',
        Fx.child(),
        status: 201,
      );
      final child = await repo().createChild(
        Fx.familyId,
        NewChildProfile(
          displayName: '  Aarav ',
          preferredLanguage: 'gu',
          dateOfBirth: DateTime(2019, 5, 4),
        ),
      );
      expect(backend.requests.single.data, {
        'display_name': 'Aarav',
        'preferred_language': 'gu',
        'date_of_birth': '2019-05-04',
      });
      expect(child.id, Fx.childId);
      expect(child.dateOfBirth, DateTime(2019, 5, 4));
    });

    test('omits date_of_birth when not provided', () {
      expect(
        const NewChildProfile(
          displayName: 'A',
          preferredLanguage: 'en',
        ).toJson(),
        {'display_name': 'A', 'preferred_language': 'en'},
      );
    });

    test('lists families and children', () async {
      backend
        ..reply('GET', '/api/v1/families', [Fx.family()])
        ..reply('GET', '/api/v1/families/${Fx.familyId}/children', [
          Fx.child(),
        ]);
      expect((await repo().listFamilies()).single.familyName, 'Sharma Family');
      expect(
        (await repo().listChildren(Fx.familyId)).single.displayName,
        'Aarav',
      );
    });

    test('recordConsent posts an accepted family-level consent', () async {
      backend
          .reply('POST', '/api/v1/settings/families/${Fx.familyId}/consents', {
            'id': '99999999-9999-4999-8999-999999999999',
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
      final record = await repo().recordConsent(
        familyId: Fx.familyId,
        consentType: 'parent_guardian_terms',
        documentVersion: '2026-10-draft',
      );
      expect(backend.requests.single.data, {
        'consent_type': 'parent_guardian_terms',
        'document_version': '2026-10-draft',
        'accepted': true,
      });
      expect(record.isActive, isTrue);
    });
  });

  group('MissionsRepository', () {
    MissionsRepository repo() =>
        MissionsRepository(createTestDio(backend, tokens));

    test('parses tasks and categories', () async {
      backend
        ..reply('GET', '/api/v1/tasks', [Fx.task()])
        ..reply('GET', '/api/v1/tasks/categories', [Fx.category()]);
      final missions = await repo().listMissions();
      expect(missions.single.title, 'Read a Storybook');
      expect(missions.single.starReward, 10);
      expect(backend.requests.first.uri.queryParameters, {'limit': '100'});
      expect((await repo().listCategories()).single.iconName, 'menu_book');
    });

    test('parent listing filters by family', () async {
      backend.reply('GET', '/api/v1/tasks', <Object?>[]);
      await repo().listMissions(familyId: Fx.familyId);
      expect(
        backend.requests.single.uri.queryParameters['family_id'],
        Fx.familyId,
      );
    });

    test('submission with a note sends proof_type note', () async {
      backend.reply(
        'POST',
        '/api/v1/tasks/${Fx.taskId}/submissions',
        Fx.submission(),
        status: 201,
      );
      final submission = await repo().submitMission(
        Fx.taskId,
        note: '  I read it! ',
      );
      expect(backend.requests.single.data, {
        'proof_type': 'note',
        'proof_note': 'I read it!',
      });
      expect(submission.status, 'pending');
    });

    test('submission without a note sends proof_type none', () async {
      backend.reply(
        'POST',
        '/api/v1/tasks/${Fx.taskId}/submissions',
        Fx.submission(proofType: 'none', note: null),
        status: 201,
      );
      await repo().submitMission(Fx.taskId, note: '   ');
      expect(backend.requests.single.data, {'proof_type': 'none'});
    });

    test(
      'submitting another child\'s task maps to ForbiddenException',
      () async {
        backend.on(
          'POST',
          '/api/v1/tasks/${Fx.taskId}/submissions',
          (_) => FakeReply.error(
            403,
            'task_not_assigned',
            'Task is assigned to another child',
          ),
        );
        await expectLater(
          repo().submitMission(Fx.taskId),
          throwsA(
            isA<ForbiddenException>().having(
              (e) => e.code,
              'code',
              'task_not_assigned',
            ),
          ),
        );
      },
    );

    test('createMission omits empty optional fields', () {
      expect(
        const NewMission(
          familyId: Fx.familyId,
          title: ' Tidy up ',
          description: '  ',
          starReward: 5,
        ).toJson(),
        {
          'family_id': Fx.familyId,
          'title': 'Tidy up',
          'star_reward': 5,
          'xp_reward': 0,
        },
      );
    });
  });

  group('ProgressRepository', () {
    test('parses ProgressPublic', () async {
      backend.reply(
        'GET',
        '/api/v1/progress/children/${Fx.childId}',
        Fx.progress(),
      );
      final progress = await ProgressRepository(
        createTestDio(backend, tokens),
      ).childProgress(Fx.childId);
      expect(progress.starBalance, 240);
      expect(progress.currentStreak, 5);
      expect(progress.levelNumber, 4);
      expect(progress.levelName, 'Explorer');
    });
  });
}
