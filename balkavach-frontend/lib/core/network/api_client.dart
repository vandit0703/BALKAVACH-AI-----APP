import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'access_token_store.dart';
import 'interceptors.dart';

/// Timeouts sized for a cold Render instance: DB-backed calls were observed
/// taking ~12 s on first request.
const kConnectTimeout = Duration(seconds: 20);
const kSendTimeout = Duration(seconds: 30);
const kReceiveTimeout = Duration(seconds: 45);

Dio createApiDio({
  required AppConfig config,
  required AccessTokenStore tokens,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: kConnectTimeout,
      sendTimeout: kSendTimeout,
      receiveTimeout: kReceiveTimeout,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      headers: const {'Accept': 'application/json'},
    ),
  );
  dio.interceptors.addAll([
    AuthInterceptor(tokens, retryClient: dio),
    RedactingLogInterceptor(),
  ]);
  return dio;
}

/// Shared Dio for the backend. Paths are relative to the server origin,
/// e.g. `/api/v1/auth/login`.
final apiDioProvider = Provider<Dio>((ref) {
  final dio = createApiDio(
    config: ref.watch(appConfigProvider),
    tokens: ref.watch(accessTokenStoreProvider),
  );
  ref.onDispose(dio.close);
  return dio;
});
