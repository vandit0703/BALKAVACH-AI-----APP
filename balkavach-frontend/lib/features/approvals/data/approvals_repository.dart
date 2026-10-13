import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/json_utils.dart';
import '../../missions/domain/mission_models.dart';
import '../domain/review_models.dart';

/// Verified contracts: `app/api/v1/tasks.py` (submissions list) and
/// `app/api/v1/reviews.py`. Both require a parent token.
class ApprovalsRepository {
  ApprovalsRepository(this._dio);

  final Dio _dio;

  /// `GET /api/v1/tasks/{id}/submissions`, newest first.
  Future<List<TaskSubmission>> listSubmissions(String taskId) =>
      guardApi(() async {
        final response = await _dio.get<List<dynamic>>(
          '/api/v1/tasks/$taskId/submissions',
          queryParameters: {'limit': 50},
        );
        return parseJsonList(response.data, TaskSubmission.fromJson);
      });

  /// `GET /api/v1/reviews/submissions?family_id=&status=…`: one family-wide
  /// request that replaces fetching every task (newest first, up to 100).
  Future<List<TaskSubmission>> listFamilySubmissions(
    String familyId, {
    List<String> statuses = const [],
    int limit = 100,
  }) => guardApi(() async {
    final response = await _dio.get<List<dynamic>>(
      '/api/v1/reviews/submissions',
      queryParameters: {
        'family_id': familyId,
        if (statuses.isNotEmpty) 'status': statuses,
        'limit': limit,
      },
    );
    return parseJsonList(response.data, TaskSubmission.fromJson);
  });

  /// `POST /api/v1/reviews/submissions/{id}`. Approving credits the task's
  /// stars and XP on the server. A second review of the same submission
  /// fails with 409 `submission_already_reviewed`.
  Future<TaskSubmission> review(
    String submissionId,
    ReviewDecision decision, {
    String? note,
  }) => guardApi(() async {
    final trimmed = note?.trim();
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/reviews/submissions/$submissionId',
      data: {
        'decision': decision.apiValue,
        if (trimmed != null && trimmed.isNotEmpty) 'review_note': trimmed,
      },
    );
    return TaskSubmission.fromJson(response.data!);
  });
}

final approvalsRepositoryProvider = Provider<ApprovalsRepository>(
  (ref) => ApprovalsRepository(ref.watch(apiDioProvider)),
);
