import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'access_token_store.dart';

/// Request option key: set to `false` to send a request without the session
/// token (login, register).
const kAuthenticatedExtra = 'authenticated';

/// Adds `Authorization: Bearer` from [AccessTokenStore] and reports 401s on
/// authenticated requests so the session can be cleared.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._tokens);

  final AccessTokenStore _tokens;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final wantsAuth = options.extra[kAuthenticatedExtra] != false;
    final token = _tokens.token;
    if (wantsAuth &&
        token != null &&
        !options.headers.containsKey('Authorization')) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final sentToken = err.requestOptions.headers.containsKey('Authorization');
    if (err.response?.statusCode == 401 && sentToken) {
      _tokens.reportUnauthorized();
    }
    handler.next(err);
  }
}

/// Debug-only request log. Prints method, path, status and duration.
///
/// Never prints headers, bodies or query strings, so tokens, passwords and
/// child data stay out of logs.
class RedactingLogInterceptor extends Interceptor {
  RedactingLogInterceptor({void Function(String)? sink})
    : _sink = sink ?? debugPrint;

  final void Function(String) _sink;
  static const _startedAt = '_logStartedAt';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAt] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _log(response.requestOptions, response.statusCode?.toString() ?? '-');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log(
      err.requestOptions,
      err.response?.statusCode?.toString() ?? err.type.name,
    );
    handler.next(err);
  }

  void _log(RequestOptions options, String outcome) {
    if (!kDebugMode) return;
    final started = options.extra[_startedAt];
    final elapsed = started is int
        ? '${DateTime.now().millisecondsSinceEpoch - started} ms'
        : '?';
    _sink(
      '[api] ${options.method} ${redactPath(options.uri.path)} → $outcome ($elapsed)',
    );
  }

  /// Replaces UUID path segments so ids of children are not logged.
  static String redactPath(String path) => path.replaceAll(
    RegExp(
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    ),
    ':id',
  );
}
