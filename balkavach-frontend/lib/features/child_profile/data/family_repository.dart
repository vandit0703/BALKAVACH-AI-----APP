import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/json_utils.dart';
import '../domain/family_models.dart';

/// Verified contracts: `app/api/v1/families.py`, `app/api/v1/settings.py`
/// (consents). All operations require a parent token.
class FamilyRepository {
  FamilyRepository(this._dio);

  final Dio _dio;

  /// `GET /api/v1/families`, newest first.
  Future<List<Family>> listFamilies() => guardApi(() async {
    final response = await _dio.get<List<dynamic>>('/api/v1/families');
    return parseJsonList(response.data, Family.fromJson);
  });

  /// `POST /api/v1/families`.
  Future<Family> createFamily(String familyName) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/families',
      data: {'family_name': familyName.trim()},
    );
    return Family.fromJson(response.data!);
  });

  /// `GET /api/v1/families/{id}/children` (active children only).
  Future<List<ChildProfile>> listChildren(String familyId) =>
      guardApi(() async {
        final response = await _dio.get<List<dynamic>>(
          '/api/v1/families/$familyId/children',
        );
        return parseJsonList(response.data, ChildProfile.fromJson);
      });

  /// `POST /api/v1/families/{id}/children`.
  Future<ChildProfile> createChild(String familyId, NewChildProfile input) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/v1/families/$familyId/children',
          data: input.toJson(),
        );
        return ChildProfile.fromJson(response.data!);
      });

  /// `PATCH /api/v1/families/{id}/children/{child_id}`. Only fields the
  /// backend stores are sent.
  Future<ChildProfile> updateChild(
    String familyId,
    String childId, {
    required String displayName,
    DateTime? dateOfBirth,
  }) => guardApi(() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/v1/families/$familyId/children/$childId',
      data: {
        'display_name': displayName.trim(),
        if (dateOfBirth != null) 'date_of_birth': formatIsoDate(dateOfBirth),
      },
    );
    return ChildProfile.fromJson(response.data!);
  });

  /// `DELETE /api/v1/families/{id}/children/{child_id}`. The backend
  /// deactivates the profile and its login; records are kept.
  Future<void> deactivateChild(String familyId, String childId) =>
      guardApi(() async {
        await _dio.delete<void>('/api/v1/families/$familyId/children/$childId');
      });

  /// `GET /api/v1/settings/families/{id}/consents`.
  Future<List<ConsentRecord>> listConsents(String familyId) =>
      guardApi(() async {
        final response = await _dio.get<List<dynamic>>(
          '/api/v1/settings/families/$familyId/consents',
        );
        return parseJsonList(response.data, ConsentRecord.fromJson);
      });

  /// `POST /api/v1/settings/families/{id}/consents`.
  Future<ConsentRecord> recordConsent({
    required String familyId,
    required String consentType,
    required String documentVersion,
  }) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/settings/families/$familyId/consents',
      data: {
        'consent_type': consentType,
        'document_version': documentVersion,
        'accepted': true,
      },
    );
    return ConsentRecord.fromJson(response.data!);
  });
}

final familyRepositoryProvider = Provider<FamilyRepository>(
  (ref) => FamilyRepository(ref.watch(apiDioProvider)),
);
