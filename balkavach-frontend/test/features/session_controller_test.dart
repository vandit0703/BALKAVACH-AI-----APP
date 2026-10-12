import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/core/network/access_token_store.dart';
import 'package:balkavach_app/features/authentication/domain/session.dart';
import 'package:balkavach_app/features/authentication/presentation/session_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

void main() {
  test('no stored session resolves to signed out', () async {
    final h = await Harness.create();
    final container = h.container();
    expect(await container.read(sessionControllerProvider.future), isNull);
    expect(h.backend.requests, isEmpty);
  });

  test('expired stored session is cleared without a network call', () async {
    final expired = Session.fromTokenResponse(
      Fx.token(expiresAt: '2020-01-01T00:00:00Z'),
    );
    final h = await Harness.create(session: expired);
    final container = h.container();
    expect(await container.read(sessionControllerProvider.future), isNull);
    expect(await h.storage.read(), isNull);
    expect(h.backend.requests, isEmpty);
  });

  test(
    'valid stored session is confirmed with /auth/me and its token used',
    () async {
      final h = await Harness.create(session: Fx.parentSession());
      final container = h.container();
      final session = await container.read(sessionControllerProvider.future);
      expect(session?.isParent, isTrue);
      expect(
        h.backend
            .requestsTo('GET', '/api/v1/auth/me')
            .single
            .headers['Authorization'],
        'Bearer parent.jwt.token',
      );
      expect(
        container.read(accessTokenStoreProvider).token,
        'parent.jwt.token',
      );
    },
  );

  test('stored session rejected by the server (401) is cleared', () async {
    final h = await Harness.create(session: Fx.parentSession());
    h.backend.on(
      'GET',
      '/api/v1/auth/me',
      (_) =>
          FakeReply.error(401, 'http_error', 'Invalid or expired access token'),
    );
    final container = h.container();
    expect(await container.read(sessionControllerProvider.future), isNull);
    expect(await h.storage.read(), isNull);
  });

  test('offline restore keeps the unexpired session', () async {
    final h = await Harness.create(session: Fx.parentSession());
    h.backend.on(
      'GET',
      '/api/v1/auth/me',
      (_) => const FakeReply.fail(DioExceptionType.connectionError),
    );
    final container = h.container();
    expect(await container.read(sessionControllerProvider.future), isNotNull);
  });

  test('signIn persists the session; signOut clears it', () async {
    final h = await Harness.create();
    h.backend.reply('POST', '/api/v1/auth/login', Fx.token());
    final container = h.container();
    await container.read(sessionControllerProvider.future);

    await container
        .read(sessionControllerProvider.notifier)
        .signIn(email: 'p@x.io', password: 'pw');
    expect(
      container.read(sessionControllerProvider).value?.user.fullName,
      'Priya Sharma',
    );
    expect(await h.storage.read(), isNotNull);

    await container.read(sessionControllerProvider.notifier).signOut();
    expect(container.read(sessionControllerProvider).value, isNull);
    expect(await h.storage.read(), isNull);
    expect(container.read(accessTokenStoreProvider).token, isNull);
  });

  test('failed signIn leaves the state signed out and rethrows', () async {
    final h = await Harness.create();
    h.backend.on(
      'POST',
      '/api/v1/auth/login',
      (_) => FakeReply.error(401, 'invalid_credentials', 'no'),
    );
    final container = h.container();
    await container.read(sessionControllerProvider.future);
    await expectLater(
      container
          .read(sessionControllerProvider.notifier)
          .signIn(email: 'p@x.io', password: 'bad'),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(container.read(sessionControllerProvider).value, isNull);
  });

  test('admin accounts are refused by the mobile app', () async {
    final h = await Harness.create();
    h.backend.reply(
      'POST',
      '/api/v1/auth/login',
      Fx.token(user: Fx.user(role: 'admin')),
    );
    final container = h.container();
    await container.read(sessionControllerProvider.future);
    await expectLater(
      container
          .read(sessionControllerProvider.notifier)
          .signIn(email: 'a@x.io', password: 'pw'),
      throwsA(isA<ForbiddenException>()),
    );
    expect(await h.storage.read(), isNull);
  });

  test(
    'startChildMode replaces the parent session with the child session',
    () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.reply(
        'POST',
        '/api/v1/auth/children/${Fx.childId}/session',
        Fx.childToken(),
      );
      final container = h.container();
      await container.read(sessionControllerProvider.future);

      await container
          .read(sessionControllerProvider.notifier)
          .startChildMode(Fx.childId);
      final session = container.read(sessionControllerProvider).value!;
      expect(session.isChild, isTrue);
      expect(session.childId, Fx.childId);
      expect(container.read(accessTokenStoreProvider).token, 'child.jwt.token');
      expect((await h.storage.read())?.isChild, isTrue);
    },
  );

  test('startChildMode requires a parent session', () async {
    final h = await Harness.create(session: Fx.childSession());
    final container = h.container();
    await container.read(sessionControllerProvider.future);
    await expectLater(
      container
          .read(sessionControllerProvider.notifier)
          .startChildMode(Fx.childId),
      throwsA(isA<ForbiddenException>()),
    );
  });

  test('a 401 on any authenticated call signs the user out', () async {
    final h = await Harness.create(session: Fx.parentSession());
    final container = h.container();
    await container.read(sessionControllerProvider.future);

    container.read(accessTokenStoreProvider).reportUnauthorized();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(sessionControllerProvider).value, isNull);
  });
}
