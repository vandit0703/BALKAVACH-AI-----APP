import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/interceptors.dart';
import '../domain/session.dart';

/// Verified contracts: `app/api/v1/auth.py`, `app/schemas/auth.py`.
class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  static const _unauthenticated = {kAuthenticatedExtra: false};

  /// `POST /api/v1/auth/login`. 401 `invalid_credentials` on bad input.
  Future<Session> login({
    String? identifier,
    String? email,
    required String password,
  }) => guardApi(() async {
    final loginIdentifier = identifier ?? email ?? '';
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/login',
      data: {
        if (loginIdentifier.contains('@')) 'email': loginIdentifier.trim(),
        if (!loginIdentifier.contains('@')) 'username': loginIdentifier.trim(),
        'password': password,
      },
      options: Options(extra: _unauthenticated),
    );
    return Session.fromTokenResponse(response.data!);
  });

  /// `POST /api/v1/auth/register` (parents only). 409 `email_in_use`.
  Future<Session> register({
    required String fullName,
    required String email,
    required String password,
  }) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/register',
      data: {
        'full_name': fullName.trim(),
        'email': email.trim(),
        'password': password,
      },
      options: Options(extra: _unauthenticated),
    );
    return Session.fromTokenResponse(response.data!);
  });

  /// `GET /api/v1/auth/me` with an explicit token (used while restoring).
  Future<AppUser> me({required String accessToken}) => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/auth/me',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return AppUser.fromJson(response.data!);
  });

  /// `POST /api/v1/auth/refresh`. Rotates the refresh token; 401
  /// `invalid_refresh_token` / `refresh_token_reused` end the session.
  Future<Session> refresh(String refreshToken) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/refresh',
      data: {'refresh_token': refreshToken},
      options: Options(extra: _unauthenticated),
    );
    return Session.fromTokenResponse(response.data!);
  });

  /// `POST /api/v1/auth/logout`: ends the server-side session. Idempotent.
  Future<void> logout(String refreshToken) => guardApi(() async {
    await _dio.post<void>(
      '/api/v1/auth/logout',
      data: {'refresh_token': refreshToken},
      options: Options(extra: _unauthenticated),
    );
  });

  /// `DELETE /api/v1/auth/children/{child_id}/sessions` (parent): signs the
  /// child out on every device.
  Future<void> endChildSessions(String childId) => guardApi(() async {
    await _dio.delete<void>('/api/v1/auth/children/$childId/sessions');
  });

  /// `POST /api/v1/auth/children/{child_id}/session` (parent token).
  Future<Session> startChildSession(String childId) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/children/$childId/session',
    );
    return Session.fromTokenResponse(response.data!, childId: childId);
  });
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiDioProvider)),
);
