import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/api_exception.dart';
import 'api_client.dart';
import 'interceptors.dart';

/// Result of the unauthenticated health checks.
///
/// `reachable` means the API process answered `/health`. `databaseReady`
/// means `/ready` could query the database. Neither proves that every feature
/// works.
class ServerHealth {
  const ServerHealth({required this.reachable, required this.databaseReady});

  final bool reachable;
  final bool databaseReady;
}

class HealthApi {
  HealthApi(this._dio);

  final Dio _dio;

  Future<ServerHealth> check() async {
    await guardApi(
      () => _dio.get<Map<String, dynamic>>(
        '/health',
        options: Options(extra: {kAuthenticatedExtra: false}),
      ),
    );
    try {
      await guardApi(
        () => _dio.get<Map<String, dynamic>>(
          '/ready',
          options: Options(extra: {kAuthenticatedExtra: false}),
        ),
      );
      return const ServerHealth(reachable: true, databaseReady: true);
    } on ServerException {
      return const ServerHealth(reachable: true, databaseReady: false);
    }
  }
}

final healthApiProvider = Provider<HealthApi>(
  (ref) => HealthApi(ref.watch(apiDioProvider)),
);

final serverHealthProvider = FutureProvider.autoDispose<ServerHealth>(
  (ref) => ref.watch(healthApiProvider).check(),
);
