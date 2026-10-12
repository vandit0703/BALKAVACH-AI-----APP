import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/json_utils.dart';
import '../domain/mission_models.dart';

/// Verified contracts: `app/api/v1/tasks.py`, `app/schemas/task.py`,
/// `app/api/v1/notifications.py`.
class MissionsRepository {
  MissionsRepository(this._dio);

  final Dio _dio;

  /// `GET /api/v1/tasks/categories` (any signed-in user).
  Future<List<TaskCategory>> listCategories() => guardApi(() async {
    final response = await _dio.get<List<dynamic>>('/api/v1/tasks/categories');
    return parseJsonList(response.data, TaskCategory.fromJson);
  });

  /// `GET /api/v1/tasks`. For a child token the server returns the family's
  /// tasks that are unassigned or assigned to that child.
  Future<List<Mission>> listMissions({String? familyId, int limit = 100}) =>
      guardApi(() async {
        final response = await _dio.get<List<dynamic>>(
          '/api/v1/tasks',
          queryParameters: {'limit': limit, 'family_id': ?familyId},
        );
        return parseJsonList(response.data, Mission.fromJson);
      });

  /// `POST /api/v1/tasks` (parent).
  Future<Mission> createMission(NewMission input) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/tasks',
      data: input.toJson(),
    );
    return Mission.fromJson(response.data!);
  });

  /// `POST /api/v1/tasks/{id}/submissions` (child). Photo proof needs an
  /// upload endpoint the backend does not have (B2), so the app sends either
  /// `none` or a `note`.
  Future<TaskSubmission> submitMission(String taskId, {String? note}) =>
      guardApi(() async {
        final trimmed = note?.trim();
        final hasNote = trimmed != null && trimmed.isNotEmpty;
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/v1/tasks/$taskId/submissions',
          data: {
            'proof_type': hasNote ? 'note' : 'none',
            if (hasNote) 'proof_note': trimmed,
          },
        );
        return TaskSubmission.fromJson(response.data!);
      });

  /// `GET /api/v1/notifications` for the signed-in user, newest first.
  Future<List<AppNotification>> listNotifications({int limit = 100}) =>
      guardApi(() async {
        final response = await _dio.get<List<dynamic>>(
          '/api/v1/notifications',
          queryParameters: {'limit': limit},
        );
        return parseJsonList(response.data, AppNotification.fromJson);
      });
}

final missionsRepositoryProvider = Provider<MissionsRepository>(
  (ref) => MissionsRepository(ref.watch(apiDioProvider)),
);
