import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/core/network/access_token_store.dart';
import 'package:balkavach_app/core/network/api_client.dart';
import 'package:balkavach_app/features/authentication/data/auth_repository.dart';
import 'package:balkavach_app/features/authentication/domain/session.dart';
import 'package:balkavach_app/features/authentication/presentation/session_controller.dart';
import 'package:balkavach_app/features/learning/data/video_feed_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

Session _sessionWithRefresh({
  String access = 'old.access',
  String refresh = 'refresh-1',
  String expiresAt = '2100-01-01T00:00:00Z',
}) => Session.fromTokenResponse(
  Fx.token(accessToken: access, expiresAt: expiresAt, refreshToken: refresh),
);

Map<String, Object?> _renewed({
  String access = 'new.access',
  String refresh = 'refresh-2',
  Map<String, Object?>? user,
}) => Fx.token(accessToken: access, refreshToken: refresh, user: user);

void main() {
  group('Session model', () {
    test('keeps refresh fields through JSON and equality', () {
      final session = _sessionWithRefresh();
      final restored = Session.fromJson(session.toJson());
      expect(restored, session);
      expect(restored.refreshToken, 'refresh-1');
      expect(restored.canRefresh, isTrue);
    });

    test('a session stored before refresh support still loads', () {
      final legacy = Session.fromJson({
        'access_token': 'a',
        'expires_at': '2100-01-01T00:00:00Z',
        'user': Fx.user(),
      });
      expect(legacy.canRefresh, isFalse);
      expect(legacy.refreshExpiredAt(DateTime.utc(2200)), isFalse);
    });

    test('renewedWith keeps the child profile id', () {
      final child = Fx.childSession();
      final renewed = child.renewedWith(
        Session.fromTokenResponse(
          Fx.token(
            accessToken: 'c2',
            refreshToken: 'r2',
            user: Fx.user(id: Fx.childUserId, role: 'child', email: null),
          ),
        ),
      );
      expect(renewed.childId, Fx.childId);
      expect(renewed.accessToken, 'c2');
      expect(renewed.isChild, isTrue);
    });
  });

  group('launch', () {
    test('expired access token is renewed instead of signing out', () async {
      final expired = _sessionWithRefresh(expiresAt: '2020-01-01T00:00:00Z');
      final h = await Harness.create(session: expired);
      h.backend.reply('POST', '/api/v1/auth/refresh', _renewed());
      final container = h.container();

      final session = await container.read(sessionControllerProvider.future);
      expect(session?.accessToken, 'new.access');
      expect(session?.refreshToken, 'refresh-2');
      expect((await h.storage.read())?.refreshToken, 'refresh-2');
      expect(container.read(accessTokenStoreProvider).token, 'new.access');
      expect(h.backend.requestsTo('POST', '/api/v1/auth/refresh').single.data, {
        'refresh_token': 'refresh-1',
      });
      expect(
        h.backend
            .requestsTo('POST', '/api/v1/auth/refresh')
            .single
            .headers
            .containsKey('Authorization'),
        isFalse,
      );
    });

    test('refused renewal at launch clears the session', () async {
      final expired = _sessionWithRefresh(expiresAt: '2020-01-01T00:00:00Z');
      final h = await Harness.create(session: expired);
      h.backend.on(
        'POST',
        '/api/v1/auth/refresh',
        (_) => FakeReply.error(401, 'invalid_refresh_token', 'Sign in again'),
      );
      final container = h.container();
      expect(await container.read(sessionControllerProvider.future), isNull);
      expect(await h.storage.read(), isNull);
    });

    test('offline at launch keeps the session', () async {
      final expired = _sessionWithRefresh(expiresAt: '2020-01-01T00:00:00Z');
      final h = await Harness.create(session: expired);
      h.backend.on(
        'POST',
        '/api/v1/auth/refresh',
        (_) => const FakeReply.fail(DioExceptionType.connectionError),
      );
      final container = h.container();
      expect(await container.read(sessionControllerProvider.future), isNotNull);
      expect(await h.storage.read(), isNotNull);
    });

    test(
      'restored child session retries feed after startup refresh was offline',
      () async {
        final childUser = Fx.user(
          id: Fx.childUserId,
          role: 'child',
          name: 'Aarav',
          email: null,
        );
        final h = await Harness.create();
        h.backend.reply(
          'POST',
          '/api/v1/auth/login',
          Fx.token(
            accessToken: 'child.access.old',
            expiresAt: '2020-01-01T00:00:00Z',
            childId: Fx.childId,
            refreshToken: 'child.refresh.old',
            user: childUser,
          ),
        );
        final overrides = h.overrides;
        final loginContainer = ProviderContainer(
          overrides: overrides,
          retry: (_, _) => null,
        );
        addTearDown(loginContainer.dispose);
        await loginContainer.read(sessionControllerProvider.future);
        await loginContainer
            .read(sessionControllerProvider.notifier)
            .signIn(identifier: 'aarav', password: 'password');
        expect(
          loginContainer.read(sessionControllerProvider).value?.isChild,
          isTrue,
        );
        expect((await h.storage.read())?.accessToken, 'child.access.old');

        var refreshCalls = 0;
        h.backend.on('POST', '/api/v1/auth/refresh', (_) {
          refreshCalls++;
          return refreshCalls == 1
              ? const FakeReply.fail(DioExceptionType.connectionError)
              : FakeReply(
                  200,
                  Fx.token(
                    accessToken: 'child.access.new',
                    childId: Fx.childId,
                    refreshToken: 'child.refresh.new',
                    user: childUser,
                  ),
                );
        });
        h.backend.on('GET', '/api/v1/videos/feed', (request) {
          if (request.headers['Authorization'] == 'Bearer child.access.old') {
            return FakeReply.error(
              401,
              'http_error',
              'Invalid or expired access token',
            );
          }
          if (request.headers['Authorization'] == 'Bearer child.access.new') {
            return const FakeReply(200, [
              {
                'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                'title': 'Approved video',
                'duration_seconds': 120,
                'language_code': 'en',
                'content_rating': 'general',
                'video_source': 'youtube',
                'video_format': 'regular',
                'youtube_video_id': 'abcdefghijk',
                'last_position_seconds': 0,
                'playback_locked': false,
              },
            ]);
          }
          return FakeReply.error(401, 'http_error', 'Authentication required');
        });
        h.backend.on('GET', '/api/v1/videos/shorts', (request) {
          if (request.headers['Authorization'] == 'Bearer child.access.new') {
            return const FakeReply(200, [
              {
                'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                'title': 'Approved Short',
                'duration_seconds': 30,
                'language_code': 'en',
                'content_rating': 'general',
                'video_source': 'youtube',
                'video_format': 'short',
                'youtube_video_id': 'lmnopqrstuv',
                'last_position_seconds': 0,
                'playback_locked': false,
              },
            ]);
          }
          return FakeReply.error(401, 'http_error', 'Authentication required');
        });

        final appContainer = ProviderContainer(
          overrides: overrides,
          retry: (_, _) => null,
        );
        addTearDown(appContainer.dispose);
        final restored = await appContainer.read(
          sessionControllerProvider.future,
        );
        expect(restored?.isChild, isTrue);

        final videos = await appContainer
            .read(videoFeedRepositoryProvider)
            .page(VideoFeedKind.learn, limit: 20, offset: 0);

        expect(videos, hasLength(1));
        expect(videos.single.isYouTube, isTrue);
        expect(videos.single.youtubeVideoId, 'abcdefghijk');
        final shorts = await appContainer
            .read(videoFeedRepositoryProvider)
            .page(VideoFeedKind.shorts, limit: 10, offset: 0);
        expect(shorts, hasLength(1));
        expect(shorts.single.format, VideoFormat.short);
        expect(shorts.single.isYouTube, isTrue);
        expect(shorts.single.youtubeVideoId, 'lmnopqrstuv');
        expect(
          h.backend
              .requestsTo('GET', '/api/v1/videos/feed')
              .map((request) => request.headers['Authorization'])
              .toList(),
          ['Bearer child.access.old', 'Bearer child.access.new'],
        );
        expect(
          h.backend
              .requestsTo('GET', '/api/v1/videos/shorts')
              .single
              .headers['Authorization'],
          'Bearer child.access.new',
        );
        expect(
          appContainer.read(accessTokenStoreProvider).token,
          'child.access.new',
        );
        expect((await h.storage.read())?.accessToken, 'child.access.new');
      },
    );

    test('an expired refresh token needs no network call', () async {
      final dead = Session.fromTokenResponse(
        Fx.token(
          expiresAt: '2020-01-01T00:00:00Z',
          refreshToken: 'r',
          refreshExpiresAt: '2020-02-01T00:00:00Z',
        ),
      );
      final h = await Harness.create(session: dead);
      final container = h.container();
      expect(await container.read(sessionControllerProvider.future), isNull);
      expect(h.backend.requests, isEmpty);
    });

    test('server 401 on /auth/me renews and continues', () async {
      final h = await Harness.create(session: _sessionWithRefresh());
      var calls = 0;
      h.backend.on('GET', '/api/v1/auth/me', (_) {
        calls++;
        return calls == 1
            ? FakeReply.error(401, 'http_error', 'Invalid or expired')
            : FakeReply(200, Fx.user());
      });
      h.backend.reply('POST', '/api/v1/auth/refresh', _renewed());
      final container = h.container();
      final session = await container.read(sessionControllerProvider.future);
      expect(session?.accessToken, 'new.access');
      expect((await h.storage.read())?.accessToken, 'new.access');
    });
  });

  group('during use', () {
    Future<(Harness, ProviderContainer)> signedIn({Session? session}) async {
      final h = await Harness.create(session: session ?? _sessionWithRefresh());
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      return (h, container);
    }

    test(
      'a 401 renews once and replays the request with the new token',
      () async {
        final (h, container) = await signedIn();
        var attempts = 0;
        h.backend.on('GET', '/api/v1/families', (options) {
          attempts++;
          return options.headers['Authorization'] == 'Bearer new.access'
              ? FakeReply(200, [Fx.family()])
              : FakeReply.error(401, 'http_error', 'Expired');
        });
        h.backend.reply('POST', '/api/v1/auth/refresh', _renewed());

        final response = await container
            .read(apiDioProvider)
            .get<List<dynamic>>('/api/v1/families');
        expect(response.data, hasLength(1));
        expect(attempts, 2);
        expect(
          h.backend.requestsTo('POST', '/api/v1/auth/refresh'),
          hasLength(1),
        );
        expect(container.read(accessTokenStoreProvider).token, 'new.access');
        expect(container.read(sessionEndedProvider), isFalse);
        expect((await h.storage.read())?.refreshToken, 'refresh-2');
      },
    );

    test('simultaneous 401s share one refresh', () async {
      final (h, container) = await signedIn();
      h.backend.on('GET', '/api/v1/families', (options) {
        return options.headers['Authorization'] == 'Bearer new.access'
            ? FakeReply(200, [Fx.family()])
            : FakeReply.error(401, 'http_error', 'Expired');
      });
      h.backend.reply('POST', '/api/v1/auth/refresh', _renewed());
      final dio = container.read(apiDioProvider);

      final results = await Future.wait([
        dio.get<List<dynamic>>('/api/v1/families'),
        dio.get<List<dynamic>>('/api/v1/families'),
        dio.get<List<dynamic>>('/api/v1/families'),
      ]);
      expect(results.map((r) => r.statusCode), everyElement(200));
      expect(
        h.backend.requestsTo('POST', '/api/v1/auth/refresh'),
        hasLength(1),
      );
    });

    test('a refused refresh signs out with the session-ended notice', () async {
      final (h, container) = await signedIn();
      h.backend.on(
        'GET',
        '/api/v1/families',
        (_) => FakeReply.error(401, 'http_error', 'Expired'),
      );
      h.backend.on(
        'POST',
        '/api/v1/auth/refresh',
        (_) => FakeReply.error(401, 'refresh_token_reused', 'Ended'),
      );
      await expectLater(
        container.read(apiDioProvider).get<List<dynamic>>('/api/v1/families'),
        throwsA(isA<DioException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionControllerProvider).value, isNull);
      expect(container.read(sessionEndedProvider), isTrue);
      expect(await h.storage.read(), isNull);
    });

    test('offline while renewing keeps the user signed in', () async {
      final (h, container) = await signedIn();
      h.backend.on(
        'GET',
        '/api/v1/families',
        (_) => FakeReply.error(401, 'http_error', 'Expired'),
      );
      h.backend.on(
        'POST',
        '/api/v1/auth/refresh',
        (_) => const FakeReply.fail(DioExceptionType.connectionTimeout),
      );
      await expectLater(
        container.read(apiDioProvider).get<List<dynamic>>('/api/v1/families'),
        throwsA(isA<DioException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionControllerProvider).value, isNotNull);
      expect(container.read(sessionEndedProvider), isFalse);
    });

    test('a 401 right after a successful renewal does not loop', () async {
      final (h, container) = await signedIn();
      h.backend.on(
        'GET',
        '/api/v1/families',
        (_) => FakeReply.error(401, 'http_error', 'Account disabled'),
      );
      h.backend.reply('POST', '/api/v1/auth/refresh', _renewed());
      await expectLater(
        container.read(apiDioProvider).get<List<dynamic>>('/api/v1/families'),
        throwsA(isA<DioException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        h.backend.requestsTo('POST', '/api/v1/auth/refresh'),
        hasLength(1),
      );
      expect(h.backend.requestsTo('GET', '/api/v1/families'), hasLength(2));
      expect(container.read(sessionControllerProvider).value, isNull);
    });

    test('a child session renews as the same child', () async {
      final childSession = Session.fromTokenResponse(
        Fx.token(
          accessToken: 'child.old',
          refreshToken: 'child-refresh',
          user: Fx.user(id: Fx.childUserId, role: 'child', email: null),
        ),
        childId: Fx.childId,
      );
      final (h, container) = await signedIn(session: childSession);
      h.backend.on('GET', '/api/v1/tasks', (options) {
        return options.headers['Authorization'] == 'Bearer child.new'
            ? FakeReply(200, [Fx.task()])
            : FakeReply.error(401, 'http_error', 'Expired');
      });
      h.backend.reply(
        'POST',
        '/api/v1/auth/refresh',
        _renewed(
          access: 'child.new',
          refresh: 'child-refresh-2',
          user: Fx.user(id: Fx.childUserId, role: 'child', email: null),
        ),
      );
      await container.read(apiDioProvider).get<List<dynamic>>('/api/v1/tasks');
      final now = container.read(sessionControllerProvider).value!;
      expect(now.childId, Fx.childId);
      expect(now.isChild, isTrue);
      expect(now.refreshToken, 'child-refresh-2');
    });

    test('requests without a token never trigger a refresh', () async {
      final h = await Harness.create();
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      h.backend.on(
        'POST',
        '/api/v1/auth/login',
        (_) => FakeReply.error(401, 'invalid_credentials', 'Wrong'),
      );
      await expectLater(
        container
            .read(authRepositoryProvider)
            .login(email: 'a@b.c', password: 'x'),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(h.backend.requestsTo('POST', '/api/v1/auth/refresh'), isEmpty);
    });
  });

  group('sign out', () {
    test('ends the server session, runs hooks first, then clears', () async {
      final h = await Harness.create(session: _sessionWithRefresh());
      h.backend.reply('POST', '/api/v1/auth/logout', null, status: 204);
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      String? tokenSeenByHook;
      container.read(signOutHooksProvider).add(() async {
        tokenSeenByHook = container.read(accessTokenStoreProvider).token;
      });

      await container.read(sessionControllerProvider.notifier).signOut();
      expect(tokenSeenByHook, 'old.access');
      expect(h.backend.requestsTo('POST', '/api/v1/auth/logout').single.data, {
        'refresh_token': 'refresh-1',
      });
      expect(container.read(accessTokenStoreProvider).token, isNull);
      expect(await h.storage.read(), isNull);
      expect(container.read(sessionEndedProvider), isFalse);
    });

    test('still signs out when the server or a hook fails', () async {
      final h = await Harness.create(session: _sessionWithRefresh());
      h.backend.on(
        'POST',
        '/api/v1/auth/logout',
        (_) => const FakeReply.fail(DioExceptionType.connectionError),
      );
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      container
          .read(signOutHooksProvider)
          .add(() async => throw StateError('x'));
      await container.read(sessionControllerProvider.notifier).signOut();
      expect(container.read(sessionControllerProvider).value, isNull);
      expect(await h.storage.read(), isNull);
    });
  });
}
