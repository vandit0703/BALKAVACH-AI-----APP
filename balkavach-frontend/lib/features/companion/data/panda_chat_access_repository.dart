import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/json_utils.dart';

const _chatAccessPath = '/api/v1/companion/chat-access';

@immutable
class PandaChatAccessStatus {
  const PandaChatAccessStatus({
    required this.childId,
    required this.status,
    this.requestedAt,
    this.decidedAt,
    this.decidedBy,
  });

  factory PandaChatAccessStatus.fromJson(Map<String, dynamic> json) =>
      PandaChatAccessStatus(
        childId: json['child_id'] as String,
        status: json['status'] as String,
        requestedAt: json['requested_at'] == null
            ? null
            : DateTime.parse(json['requested_at'] as String),
        decidedAt: json['decided_at'] == null
            ? null
            : DateTime.parse(json['decided_at'] as String),
        decidedBy: json['decided_by'] as String?,
      );

  final String childId;
  final String status;
  final DateTime? requestedAt;
  final DateTime? decidedAt;
  final String? decidedBy;

  bool get approved => status == 'approved';
  bool get pending => status == 'pending';
}

class PandaChatAccessRepository {
  PandaChatAccessRepository(this._dio);

  final Dio _dio;

  Future<PandaChatAccessStatus> childStatus() => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(_chatAccessPath);
    return PandaChatAccessStatus.fromJson(response.data!);
  });

  Future<PandaChatAccessStatus> requestAccess() => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_chatAccessPath/request',
    );
    return PandaChatAccessStatus.fromJson(response.data!);
  });

  Future<List<PandaChatAccessStatus>> familyStatus(String familyId) =>
      guardApi(() async {
        final response = await _dio.get<List<dynamic>>(
          '/api/v1/settings/families/$familyId/panda-chat-access',
        );
        return parseJsonList(response.data, PandaChatAccessStatus.fromJson);
      });

  Future<PandaChatAccessStatus> decide({
    required String familyId,
    required String childId,
    required String action,
  }) => guardApi(() async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/v1/settings/families/$familyId/children/$childId/panda-chat-access',
      data: {'action': action},
    );
    return PandaChatAccessStatus.fromJson(response.data!);
  });
}

final pandaChatAccessRepositoryProvider = Provider<PandaChatAccessRepository>(
  (ref) => PandaChatAccessRepository(ref.watch(apiDioProvider)),
);

final childPandaChatAccessProvider = FutureProvider.autoDispose.family<
  PandaChatAccessStatus,
  String
>((ref, childId) => ref.watch(pandaChatAccessRepositoryProvider).childStatus());

final familyPandaChatAccessProvider = FutureProvider.autoDispose.family<
  List<PandaChatAccessStatus>,
  String
>(
  (ref, familyId) => ref
      .watch(pandaChatAccessRepositoryProvider)
      .familyStatus(familyId),
);
