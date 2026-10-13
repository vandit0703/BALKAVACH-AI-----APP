import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';

/// Verified contract: `app/api/v1/notifications.py` (`/notifications/devices`).
/// The server never returns a token; it only accepts or forgets one.
class DeviceRepository {
  DeviceRepository(this._dio);

  final Dio _dio;

  /// `PUT /api/v1/notifications/devices`: registers (or re-assigns to the
  /// signed-in user) this phone's push token.
  Future<void> register(String token, {String platform = 'android'}) =>
      guardApi(() async {
        await _dio.put<void>(
          '/api/v1/notifications/devices',
          data: {'token': token, 'platform': platform},
        );
      });

  /// `POST /api/v1/notifications/devices/unregister`.
  Future<void> unregister(String token) => guardApi(() async {
    await _dio.post<void>(
      '/api/v1/notifications/devices/unregister',
      data: {'token': token},
    );
  });
}

final deviceRepositoryProvider = Provider<DeviceRepository>(
  (ref) => DeviceRepository(ref.watch(apiDioProvider)),
);
