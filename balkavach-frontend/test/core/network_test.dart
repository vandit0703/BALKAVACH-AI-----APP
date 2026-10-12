import 'package:balkavach_app/core/config/app_config.dart';
import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/core/network/access_token_store.dart';
import 'package:balkavach_app/core/network/health_api.dart';
import 'package:balkavach_app/core/network/interceptors.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late AccessTokenStore tokens;
  late Dio dio;

  setUp(() {
    backend = FakeBackend();
    tokens = AccessTokenStore();
    dio = createTestDio(backend, tokens);
  });

  tearDown(() => tokens.dispose());

  group('mapDioException / guardApi', () {
    Future<ApiException> failWith(FakeReply reply) async {
      backend.on('GET', '/x', (_) => reply);
      try {
        await guardApi(() => dio.get<Object?>('/x'));
      } on ApiException catch (e) {
        return e;
      }
      fail('expected ApiException');
    }

    test('401 envelope keeps backend code and message', () async {
      final e = await failWith(
        FakeReply.error(
          401,
          'invalid_credentials',
          'Email or password is incorrect',
        ),
      );
      expect(e, isA<UnauthorizedException>());
      expect(e.code, 'invalid_credentials');
      expect(e.message, 'Email or password is incorrect');
    });

    test('422 exposes field errors by last location segment', () async {
      final e = await failWith(
        FakeReply.error(422, 'validation_error', 'Request validation failed', [
          {
            'location': ['body', 'email'],
            'message': 'bad email',
            'type': 'value_error',
          },
          {
            'location': ['body', 'password'],
            'message': 'too short',
            'type': 'string_too_short',
          },
        ]),
      );
      expect(e, isA<ValidationException>());
      final fields = (e as ValidationException).fieldErrors;
      expect(fields.map((f) => f.field), ['email', 'password']);
      expect(fields.first.message, 'bad email');
    });

    test('status codes map to typed exceptions', () async {
      expect(
        await failWith(FakeReply.error(403, 'http_error', 'x')),
        isA<ForbiddenException>(),
      );
      expect(
        await failWith(FakeReply.error(404, 'task_not_found', 'x')),
        isA<NotFoundException>(),
      );
      expect(
        await failWith(FakeReply.error(409, 'email_in_use', 'x')),
        isA<ConflictException>(),
      );
      final server = await failWith(
        FakeReply.error(503, 'http_error', 'Database is unavailable'),
      );
      expect(server, isA<ServerException>());
      expect(server.statusCode, 503);
    });

    test('FastAPI default {"detail"} shape still yields a message', () async {
      final e = await failWith(const FakeReply(400, {'detail': 'Bad thing'}));
      expect(e, isA<UnknownApiException>());
      expect(e.message, 'Bad thing');
    });

    test('transport failures become network/timeout exceptions', () async {
      expect(
        await failWith(const FakeReply.fail(DioExceptionType.connectionError)),
        isA<NetworkException>(),
      );
      expect(
        await failWith(const FakeReply.fail(DioExceptionType.receiveTimeout)),
        isA<RequestTimeoutException>(),
      );
    });

    test('unexpected response shape is reported, not crashed on', () async {
      backend.reply('GET', '/shape', {'unexpected': true});
      await expectLater(
        guardApi(() async {
          final r = await dio.get<Map<String, dynamic>>('/shape');
          return r.data!['id'] as String;
        }),
        throwsA(isA<UnknownApiException>()),
      );
    });
  });

  group('AuthInterceptor', () {
    test('adds bearer token when signed in', () async {
      tokens.token = 'abc';
      backend.reply('GET', '/me', {});
      await dio.get<Object?>('/me');
      expect(backend.requests.single.headers['Authorization'], 'Bearer abc');
    });

    test('skips token for unauthenticated requests', () async {
      tokens.token = 'abc';
      backend.reply('POST', '/login', {});
      await dio.post<Object?>(
        '/login',
        options: Options(extra: {kAuthenticatedExtra: false}),
      );
      expect(
        backend.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
    });

    test('reports 401 only for requests that carried a token', () async {
      var reports = 0;
      final sub = tokens.onUnauthorized.listen((_) => reports++);
      addTearDown(sub.cancel);
      backend.on(
        'GET',
        '/secure',
        (_) => FakeReply.error(401, 'http_error', 'expired'),
      );

      await expectLater(
        dio.get<Object?>('/secure'),
        throwsA(isA<DioException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(reports, 0, reason: 'no token was sent');

      tokens.token = 'abc';
      await expectLater(
        dio.get<Object?>('/secure'),
        throwsA(isA<DioException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(reports, 1);
    });
  });

  group('RedactingLogInterceptor', () {
    test('replaces UUIDs in paths', () {
      expect(
        RedactingLogInterceptor.redactPath(
          '/api/v1/progress/children/33333333-3333-4333-8333-333333333333',
        ),
        '/api/v1/progress/children/:id',
      );
    });

    test('never logs headers, query or body', () async {
      final lines = <String>[];
      final logging = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = backend
        ..interceptors.add(RedactingLogInterceptor(sink: lines.add));
      backend.reply('POST', '/api/v1/auth/login', {});
      await logging.post<Object?>(
        '/api/v1/auth/login',
        data: {'email': 'priya@example.com', 'password': 'super-secret-pass'},
        queryParameters: {'token': 'leak'},
        options: Options(headers: {'Authorization': 'Bearer secret-token'}),
      );
      final output = lines.join('\n');
      expect(output, contains('POST /api/v1/auth/login'));
      for (final secret in ['priya@', 'super-secret', 'leak', 'secret-token']) {
        expect(output, isNot(contains(secret)));
      }
    });
  });

  group('AppConfig', () {
    test('normalizes trailing slashes', () {
      expect(
        AppConfig.normalizeBaseUrl(' https://host.example/ '),
        'https://host.example',
      );
    });

    test('rejects non-http URLs', () {
      expect(() => AppConfig.normalizeBaseUrl('ftp://x'), throwsArgumentError);
      expect(
        () => AppConfig.normalizeBaseUrl('not a url'),
        throwsArgumentError,
      );
    });

    test('default points at the deployed API and v1 prefix', () {
      final config = AppConfig.fromEnvironment();
      expect(config.apiBaseUrl, AppConfig.defaultApiBaseUrl);
      expect(config.apiV1BaseUrl, '${AppConfig.defaultApiBaseUrl}/api/v1');
    });
  });

  group('HealthApi', () {
    test('reports reachable and ready', () async {
      backend
        ..reply('GET', '/health', {'status': 'ok'})
        ..reply('GET', '/ready', {'status': 'ready'});
      final health = await HealthApi(dio).check();
      expect(health.reachable, isTrue);
      expect(health.databaseReady, isTrue);
    });

    test('distinguishes server up from database down', () async {
      backend
        ..reply('GET', '/health', {'status': 'ok'})
        ..on(
          'GET',
          '/ready',
          (_) => FakeReply.error(503, 'http_error', 'Database is unavailable'),
        );
      final health = await HealthApi(dio).check();
      expect(health.reachable, isTrue);
      expect(health.databaseReady, isFalse);
    });

    test('throws when the server is unreachable', () async {
      backend.on(
        'GET',
        '/health',
        (_) => const FakeReply.fail(DioExceptionType.connectionError),
      );
      await expectLater(
        HealthApi(dio).check(),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
