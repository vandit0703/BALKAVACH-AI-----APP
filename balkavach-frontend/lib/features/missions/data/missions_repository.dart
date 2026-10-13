import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/json_utils.dart';
import '../../../shared/media/photo_picker.dart';
import '../domain/mission_models.dart';

/// `GET /tasks` page size limit (`le=100` on the server) and our page cap.
const kMissionPageSize = 100;

/// `GET /notifications` page size limit (`le=100`).
const kNotificationPageSize = 100;
const kMaxMissionPages = 5;

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
  ///
  /// The server caps a page at 100, so further pages are requested while a
  /// page comes back full, up to [maxPages] (500 missions) to bound the work.
  Future<List<Mission>> listMissions({
    String? familyId,
    int limit = kMissionPageSize,
    int maxPages = kMaxMissionPages,
  }) => guardApi(() async {
    final missions = <Mission>[];
    for (var page = 0; page < maxPages; page++) {
      final response = await _dio.get<List<dynamic>>(
        '/api/v1/tasks',
        queryParameters: {
          'limit': limit,
          if (page > 0) 'offset': page * limit,
          'family_id': ?familyId,
        },
      );
      final batch = parseJsonList(response.data, Mission.fromJson);
      missions.addAll(batch);
      if (batch.length < limit) break;
    }
    return missions;
  });

  /// `GET /api/v1/tasks/presets` (parent): the idea library, in the parent's
  /// language first. Empty on a server that predates it.
  Future<List<MissionPreset>> listPresets() => guardApi(() async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/api/v1/tasks/presets',
        queryParameters: {'limit': 100},
      );
      return parseJsonList(response.data, MissionPreset.fromJson);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return const <MissionPreset>[];
      rethrow;
    }
  });

  /// `POST /api/v1/tasks` (parent).
  Future<Mission> createMission(NewMission input) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/tasks',
      data: input.toJson(),
    );
    return Mission.fromJson(response.data!);
  });

  /// `PATCH /api/v1/tasks/{id}` (parent).
  Future<Mission> updateMission(String taskId, NewMission input) =>
      guardApi(() async {
        final response = await _dio.patch<Map<String, dynamic>>(
          '/api/v1/tasks/$taskId',
          data: input.toPatchJson(),
        );
        return Mission.fromJson(response.data!);
      });

  /// `DELETE /api/v1/tasks/{id}` (parent). The server marks the task
  /// inactive; its submissions and reviews stay on record.
  Future<void> deactivateMission(String taskId) => guardApi(() async {
    await _dio.delete<void>('/api/v1/tasks/$taskId');
  });

  /// `POST /api/v1/notifications/{id}/read`.
  Future<void> markNotificationRead(String notificationId) =>
      guardApi(() async {
        await _dio.post<void>('/api/v1/notifications/$notificationId/read');
      });

  /// `POST /api/v1/uploads/task-proofs` (child). Returns the upload id to send
  /// as `proof_upload_id`. 413 too large, 415 not an image, 429 too many
  /// unsent photos, 503 storage unavailable.
  Future<String> uploadProof(PickedPhoto photo) => guardApi(() async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        photo.bytes,
        filename: photo.fileName,
        contentType: DioMediaType.parse(photo.mimeType),
      ),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/uploads/task-proofs',
      data: form,
    );
    return response.data!['upload_id'] as String;
  });

  /// `POST /api/v1/tasks/{id}/submissions` (child). Sends a photo
  /// (`proof_upload_id`), a note, or neither. 409 `submission_pending` /
  /// `task_already_completed` when the mission cannot be sent again.
  Future<TaskSubmission> submitMission(
    String taskId, {
    String? note,
    String? uploadId,
  }) => guardApi(() async {
    final trimmed = note?.trim();
    final hasNote = trimmed != null && trimmed.isNotEmpty;
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/tasks/$taskId/submissions',
      data: {
        'proof_type': uploadId != null ? 'image' : (hasNote ? 'note' : 'none'),
        'proof_upload_id': ?uploadId,
        if (hasNote) 'proof_note': trimmed,
      },
    );
    return TaskSubmission.fromJson(response.data!);
  });

  /// `GET /api/v1/tasks/submissions/mine` (child): the child's own attempts,
  /// newest first, with the parent's notes. Pages of 100, up to 3 pages.
  Future<List<TaskSubmission>> listMySubmissions() => guardApi(() async {
    final submissions = <TaskSubmission>[];
    for (var page = 0; page < 3; page++) {
      final response = await _dio.get<List<dynamic>>(
        '/api/v1/tasks/submissions/mine',
        queryParameters: {'limit': 100, if (page > 0) 'offset': page * 100},
      );
      final batch = parseJsonList(response.data, TaskSubmission.fromJson);
      submissions.addAll(batch);
      if (batch.length < 100) break;
    }
    return submissions;
  });

  /// Fetches a stored proof photo (needs the signed-in user's token).
  Future<Uint8List> downloadProof(String proofUrl) => guardApi(() async {
    final response = await _dio.get<List<int>>(
      proofUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  });

  /// `GET /api/v1/notifications` for the signed-in user, newest first.
  Future<List<AppNotification>> listNotifications({
    int limit = kNotificationPageSize,
  }) => guardApi(() async {
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
