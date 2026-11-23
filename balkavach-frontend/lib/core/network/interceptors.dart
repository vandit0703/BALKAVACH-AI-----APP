import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'access_token_store.dart';

/// Request option key: set to `false` to send a request without the session
/// token (login, register).
const kAuthenticatedExtra = 'authenticated';

/// Request option key: set on the retried copy of a request so a second 401
/// ends the session instead of refreshing again.
const kRetriedExtra = 'retried_after_refresh';
const _tokenPresentExtra = 'diagnostic_token_present';
const _authorizationAttachedExtra = 'diagnostic_authorization_attached';

bool _isVideoFeedPath(String path) =>
    path.endsWith('/api/v1/videos/feed') ||
    path.endsWith('/api/v1/videos/shorts');

/// Adds the current app language so localized, language-dependent content can be
/// resolved per request without relying on a best-effort server preference sync.
class LocaleInterceptor extends Interceptor {
  LocaleInterceptor(this._languageCode);

  final String Function() _languageCode;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final code = _languageCode().trim();
    if (code.isNotEmpty) {
      options.headers.putIfAbsent('Accept-Language', () => code);
      options.headers.putIfAbsent('X-App-Language', () => code);
    }
    handler.next(options);
  }
}

/// Adds `Authorization: Bearer` from [AccessTokenStore]. On a 401 for an
/// authenticated request it renews the session once and replays the request;
/// only if the session cannot be renewed is the user reported as signed out.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._tokens, {this.retryClient});

  final AccessTokenStore _tokens;

  /// Client used to replay a request after the session was renewed.
  final Dio? retryClient;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final wantsAuth = options.extra[kAuthenticatedExtra] != false;
    final token = _tokens.token;
    if (wantsAuth &&
        token != null &&
        !options.headers.containsKey('Authorization')) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    if (_isVideoFeedPath(options.uri.path)) {
      options.extra[_tokenPresentExtra] = token?.isNotEmpty ?? false;
      options.extra[_authorizationAttachedExtra] = options.headers.containsKey(
        'Authorization',
      );
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final sentToken = options.headers.containsKey('Authorization');
    if (err.response?.statusCode != 401 || !sentToken) {
      handler.next(err);
      return;
    }
    final client = retryClient;
    final canRetry =
        client != null &&
        options.extra[kRetriedExtra] != true &&
        options.extra[kAuthenticatedExtra] != false &&
        _tokens.refresher != null;
    if (canRetry) {
      final outcome = await _tokens.refreshOnce();
      if (outcome == RefreshOutcome.refreshed) {
        final replay = options.copyWith(
          headers: {...options.headers}..remove('Authorization'),
          extra: {...options.extra, kRetriedExtra: true},
        );
        try {
          handler.resolve(await client.fetch<dynamic>(replay));
        } on DioException catch (retryError) {
          handler.next(retryError);
        }
        return;
      }
      if (outcome == RefreshOutcome.unavailable) {
        // Offline while renewing: surface the failure, keep the session.
        handler.next(err);
        return;
      }
    }
    _tokens.reportUnauthorized();
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
      err.response?.data,
    );
    handler.next(err);
  }

  void _log(RequestOptions options, String outcome, [Object? errorBody]) {
    final isVideoFeed = _isVideoFeedPath(options.uri.path);
    if (!kDebugMode && !isVideoFeed) return;
    final started = options.extra[_startedAt];
    final elapsed = started is int
        ? '${DateTime.now().millisecondsSinceEpoch - started} ms'
        : '?';
    final authState = isVideoFeed
        ? ' token_present=${options.extra[_tokenPresentExtra] == true}'
              ' authorization_attached=${options.extra[_authorizationAttachedExtra] == true}'
        : '';
    final errorSummary = errorBody == null
        ? ''
        : ' ${_sanitizedError(errorBody)}';
    _sink(
      '[api] ${options.method} ${redactPath(options.uri.path)} status=$outcome'
      ' ($elapsed)$authState$errorSummary',
    );
  }

  static String _sanitizedError(Object? body) {
    if (body is! Map<String, dynamic>) return 'backend_error=unavailable';
    final error = body['error'];
    if (error is Map<String, dynamic>) {
      final code = error['code'];
      if (code is String && RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(code)) {
        return 'backend_error_code=$code';
      }
      return 'backend_error=unknown';
    }
    final detail = body['detail'];
    return 'backend_error=${switch (detail) {
      'Authentication required' => 'authentication_required',
      'Invalid access token' => 'invalid_access_token',
      'Invalid or expired access token' => 'invalid_or_expired_access_token',
      'Session has ended' => 'session_ended',
      'Invalid or inactive account' => 'invalid_or_inactive_account',
      'Child access required' => 'child_role_required',
      'Active child profile required' => 'active_child_profile_required',
      _ => 'other',
    }}';
  }

  /// Replaces UUID path segments so ids of children are not logged.
  static String redactPath(String path) => path.replaceAll(
    RegExp(
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    ),
    ':id',
  );
}
