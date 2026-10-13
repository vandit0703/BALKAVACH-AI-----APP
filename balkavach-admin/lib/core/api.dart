import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time configuration: `--dart-define=API_BASE_URL=https://host`.
const kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://balkavach-ai-app.onrender.com',
);

/// A failed API call, reduced to what the panel shows.
class ApiError implements Exception {
  const ApiError(this.status, this.code, this.message);

  /// HTTP status, or 0 when the server could not be reached.
  final int status;
  final String? code;
  final String message;

  bool get isForbidden => status == 403;
  bool get isUnauthorized => status == 401;
  bool get isConflict => status == 409;
  bool get isNetwork => status == 0;

  @override
  String toString() => 'ApiError($status, $code, $message)';
}

ApiError mapError(DioException error) {
  final response = error.response;
  if (response == null) {
    return const ApiError(
      0,
      null,
      'Cannot reach the server. Check the connection.',
    );
  }
  final data = response.data;
  String? code;
  String? message;
  if (data is Map<String, dynamic>) {
    final envelope = data['error'];
    if (envelope is Map<String, dynamic>) {
      code = envelope['code'] as String?;
      message = envelope['message'] as String?;
      final details = envelope['details'];
      if (details is List && details.isNotEmpty) {
        final first = details.first;
        if (first is Map<String, dynamic> && first['message'] is String) {
          message = '${message ?? 'Invalid input'}: ${first['message']}';
        }
      }
    }
  }
  return ApiError(response.statusCode ?? 0, code, message ?? 'Request failed');
}

/// Access/refresh tokens, held in memory only: reloading the page signs the
/// administrator out, and nothing sensitive is left in browser storage.
class TokenStore {
  String? accessToken;
  String? refreshToken;

  /// Renews the session; installed by the session controller.
  Future<bool> Function()? refresher;
  Future<bool>? _inFlight;

  final _expired = StreamController<void>.broadcast();
  Stream<void> get onExpired => _expired.stream;

  void expire() {
    accessToken = null;
    refreshToken = null;
    if (!_expired.isClosed) _expired.add(null);
  }

  Future<bool> refreshOnce() {
    final refresh = refresher;
    if (refresh == null) return Future.value(false);
    return _inFlight ??= refresh().whenComplete(() => _inFlight = null);
  }
}

const _retried = 'retried';
const _anonymous = 'anonymous';

Dio createDio(TokenStore tokens, {String baseUrl = kApiBaseUrl}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 45),
      contentType: Headers.jsonContentType,
      headers: const {'Accept': 'application/json'},
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = tokens.accessToken;
        if (token != null && options.extra[_anonymous] != true) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final options = error.requestOptions;
        final sent = options.headers.containsKey('Authorization');
        if (error.response?.statusCode != 401 ||
            !sent ||
            options.extra[_retried] == true) {
          handler.next(error);
          return;
        }
        if (await tokens.refreshOnce()) {
          final replay = options.copyWith(
            headers: {...options.headers}..remove('Authorization'),
            extra: {...options.extra, _retried: true},
          );
          try {
            handler.resolve(await dio.fetch<dynamic>(replay));
          } on DioException catch (retryError) {
            handler.next(retryError);
          }
          return;
        }
        tokens.expire();
        handler.next(error);
      },
    ),
  );
  return dio;
}

/// A JSON object, or an empty map for replies without a body (204): an empty
/// body arrives as a string or null depending on the HTTP adapter.
Map<String, dynamic> _mapOrEmpty(dynamic data) =>
    data is Map<String, dynamic> ? data : const <String, dynamic>{};

/// The panel's view of the admin API. Responses are kept as plain JSON: the
/// panel renders what the server sends and sends back only what it is given.
class AdminApi {
  AdminApi(this._dio);

  final Dio _dio;

  Future<T> _run<T>(
    Future<Response<dynamic>> Function() call,
    T Function(dynamic data) parse,
  ) async {
    try {
      final response = await call();
      return parse(response.data);
    } on DioException catch (error) {
      throw mapError(error);
    }
  }

  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) => _run(
    () => _dio.get<dynamic>(path, queryParameters: query),
    (d) => d as Map<String, dynamic>,
  );

  Future<List<Map<String, dynamic>>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) => _run(
    () => _dio.get<dynamic>(path, queryParameters: query),
    (d) => (d as List<dynamic>).cast<Map<String, dynamic>>(),
  );

  Future<Map<String, dynamic>> post(String path, Object? body) =>
      _run(() => _dio.post<dynamic>(path, data: body), (d) => _mapOrEmpty(d));

  Future<Map<String, dynamic>> patch(
    String path,
    Object? body, {
    Map<String, dynamic>? query,
  }) => _run(
    () => _dio.patch<dynamic>(path, data: body, queryParameters: query),
    (d) => _mapOrEmpty(d),
  );

  Future<Map<String, dynamic>> put(String path, Object? body) =>
      _run(() => _dio.put<dynamic>(path, data: body), (d) => _mapOrEmpty(d));

  Future<void> delete(String path) =>
      _run(() => _dio.delete<dynamic>(path), (_) {});

  /// Sign-in endpoints carry no bearer token.
  Future<Map<String, dynamic>> anonymousPost(String path, Object? body) => _run(
    () => _dio.post<dynamic>(
      path,
      data: body,
      options: Options(extra: const {_anonymous: true}),
    ),
    (d) => _mapOrEmpty(d),
  );
}

final tokenStoreProvider = Provider<TokenStore>((ref) {
  final store = TokenStore();
  ref.onDispose(() => store._expired.close());
  return store;
});

final dioProvider = Provider<Dio>((ref) {
  final dio = createDio(ref.watch(tokenStoreProvider));
  ref.onDispose(dio.close);
  return dio;
});

final adminApiProvider = Provider<AdminApi>(
  (ref) => AdminApi(ref.watch(dioProvider)),
);
