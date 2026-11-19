import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../domain/notification_preferences.dart';

/// Verified contract: `app/api/v1/settings.py`
/// (`/settings/families/{id}/notification-preferences`, parent only; a family
/// the parent does not belong to is a 404, a child account a 403).
class NotificationPreferencesRepository {
  NotificationPreferencesRepository(this._dio);

  final Dio _dio;

  String _path(String familyId) =>
      '/api/v1/settings/families/$familyId/notification-preferences';

  Future<NotificationPreferences> load(String familyId) => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(_path(familyId));
    return NotificationPreferences.fromJson(response.data!);
  });

  /// Partial update: only what is passed is changed on the server.
  Future<NotificationPreferences> save(
    String familyId, {
    Map<String, bool>? categories,
    QuietHours? quietHours,
  }) => guardApi(() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      _path(familyId),
      data: {'categories': ?categories, 'quiet_hours': ?quietHours?.toJson()},
    );
    return NotificationPreferences.fromJson(response.data!);
  });
}

final notificationPreferencesRepositoryProvider =
    Provider<NotificationPreferencesRepository>(
      (ref) => NotificationPreferencesRepository(ref.watch(apiDioProvider)),
    );
