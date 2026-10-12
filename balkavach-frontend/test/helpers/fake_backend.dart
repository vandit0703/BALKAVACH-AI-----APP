import 'dart:convert';
import 'dart:typed_data';

import 'package:balkavach_app/core/network/access_token_store.dart';
import 'package:balkavach_app/core/network/interceptors.dart';
import 'package:dio/dio.dart';

/// Canned reply for one route.
class FakeReply {
  const FakeReply(this.status, [this.body]) : failure = null;

  const FakeReply.fail(DioExceptionType this.failure) : status = 0, body = null;

  final int status;
  final Object? body;
  final DioExceptionType? failure;

  /// Backend error envelope (`app/core/exceptions.py`).
  static FakeReply error(
    int status,
    String code,
    String message, [
    List<Map<String, Object?>>? details,
  ]) => FakeReply(status, {
    'error': {'code': code, 'message': message, 'details': ?details},
  });
}

/// In-memory HTTP layer for Dio. Routes are keyed by `METHOD /path`.
class FakeBackend implements HttpClientAdapter {
  final _routes = <String, FakeReply Function(RequestOptions)>{};
  final requests = <RequestOptions>[];

  void on(
    String method,
    String path,
    FakeReply Function(RequestOptions) reply,
  ) => _routes['$method $path'] = reply;

  void reply(String method, String path, Object? body, {int status = 200}) =>
      on(method, path, (_) => FakeReply(status, body));

  List<RequestOptions> requestsTo(String method, String path) =>
      requests.where((r) => r.method == method && r.uri.path == path).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final handler = _routes['${options.method} ${options.uri.path}'];
    final reply = handler == null
        ? FakeReply.error(404, 'http_error', 'Not Found')
        : handler(options);
    if (reply.failure != null) {
      throw DioException(requestOptions: options, type: reply.failure!);
    }
    return ResponseBody.fromString(
      reply.body == null ? '' : jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Dio wired like production (auth + logging interceptors) but without
/// timeouts, so tests leave no pending timers.
Dio createTestDio(FakeBackend backend, AccessTokenStore tokens) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.httpClientAdapter = backend;
  dio.interceptors.addAll([
    AuthInterceptor(tokens),
    RedactingLogInterceptor(sink: (_) {}),
  ]);
  return dio;
}
