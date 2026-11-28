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

  /// `POST /api/v1/auth/register` (parents only). 202 means the OTP was sent.
  Future<String> register({
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
    return response.data!['email'] as String;
  });

  /// `POST /api/v1/auth/verify-email` with the registration code. Returns the
  /// new parent's session (200 + tokens), issued by the server only after it
  /// checked and consumed the code. `null` from an older server that answers
  /// 204 without tokens: the parent then signs in as before.
  Future<Session?> verifyEmail({required String email, required String otp}) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/v1/auth/verify-email',
          data: {'email': email.trim(), 'otp': otp},
          options: Options(extra: _unauthenticated),
        );
        final body = response.data;
        return body != null && body['access_token'] is String
            ? Session.fromTokenResponse(body)
            : null;
      });

  /// `POST /api/v1/auth/login-code/request`: emails a sign-in code to an
  /// existing, verified parent account. Always 202 for a valid address
  /// (whether or not an account exists); 503 `email_unavailable` when the
  /// server cannot send email.
  Future<void> requestLoginCode(String email) => guardApi(() async {
    await _dio.post<void>(
      '/api/v1/auth/login-code/request',
      data: {'email': email.trim()},
      options: Options(extra: _unauthenticated),
    );
  });

  /// `POST /api/v1/auth/login-code/verify`: exchanges the emailed code for a
  /// normal parent session. 400 `invalid_login_code` for any wrong, expired
  /// or used code.
  Future<Session> verifyLoginCode({
    required String email,
    required String otp,
  }) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/login-code/verify',
      data: {'email': email.trim(), 'otp': otp},
      options: Options(extra: _unauthenticated),
    );
    return Session.fromTokenResponse(response.data!);
  });

  Future<void> resendVerification(String email) => guardApi(() async {
    await _dio.post<void>(
      '/api/v1/auth/resend-verification',
      data: {'email': email.trim()},
      options: Options(extra: _unauthenticated),
    );
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

  Future<void> requestPasswordReset(String email) => guardApi(() async {
    await _dio.post<void>(
      '/api/v1/auth/password/forgot',
      data: {'email': email.trim()},
      options: Options(extra: _unauthenticated),
    );
  });

  Future<void> resetPassword({
    required String token,
    required String password,
  }) => guardApi(() async {
    await _dio.post<void>(
      '/api/v1/auth/password/reset',
      data: {'token': token, 'password': password},
      options: Options(extra: _unauthenticated),
    );
  });

  /// `DELETE /api/v1/auth/account` (parent): soft-deletes and anonymizes PII
  /// while preserving anonymized reward ledgers and audit logs (DEC-09).
  Future<void> deleteAccount(String password) => guardApi(() async {
    await _dio.delete<void>(
      '/api/v1/auth/account',
      data: {'password': password},
    );
  });

  /// `POST /api/v1/auth/child-link/redeem`: redeems a single-use linking code
  /// or QR payload (`balkavach://link?code=...`) for a child session (DEC-05).
  Future<Session> redeemChildLinkCode(String code) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/child-link/redeem',
      data: {'code': code.trim()},
      options: Options(extra: _unauthenticated),
    );
    return Session.fromTokenResponse(response.data!);
  });

  /// `POST /api/v1/auth/parent-mode/enter`: leave child mode. Sent **with the
  /// child session's bearer token** (the server binds the attempt to that
  /// device and to the child's family); the credentials are the same email and
  /// password as the normal parent sign-in.
  ///
  /// 403 `parent_authentication_failed` is one generic answer for every kind of
  /// failure; 423 `parent_mode_locked` carries the retry delay.
  Future<Session> enterParentMode({
    required String email,
    required String password,
  }) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/parent-mode/enter',
      data: {'email': email.trim(), 'password': password},
    );
    return Session.fromTokenResponse(response.data!);
  });
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiDioProvider)),
);
