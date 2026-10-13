import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';

/// What the signed-in administrator may do (from `GET /admin/me`).
@immutable
class AdminSession {
  const AdminSession({
    required this.name,
    required this.email,
    required this.roles,
    required this.permissions,
  });

  factory AdminSession.fromMe(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return AdminSession(
      name: user['full_name'] as String,
      email: (user['email'] as String?) ?? '',
      roles: (json['roles'] as List<dynamic>).cast<String>(),
      permissions: (json['permissions'] as List<dynamic>)
          .cast<String>()
          .toSet(),
    );
  }

  final String name;
  final String email;
  final List<String> roles;
  final Set<String> permissions;

  /// True when the administrator holds [permission] (`*` holds everything).
  bool can(String permission) =>
      permissions.contains('*') || permissions.contains(permission);
}

/// Sign-in, sign-out and token renewal for the panel.
class SessionController extends Notifier<AdminSession?> {
  StreamSubscription<void>? _expired;

  @override
  AdminSession? build() {
    final tokens = ref.watch(tokenStoreProvider);
    _expired = tokens.onExpired.listen((_) => state = null);
    tokens.refresher = _refresh;
    ref.onDispose(() {
      unawaited(_expired?.cancel());
      if (tokens.refresher == _refresh) tokens.refresher = null;
    });
    return null;
  }

  /// Signs in. Throws [ApiError]; accounts that are not administrators are
  /// refused here, before any admin screen is reachable.
  Future<void> signIn(String email, String password) async {
    final api = ref.read(adminApiProvider);
    final tokens = ref.read(tokenStoreProvider);
    final body = await api.anonymousPost('/api/v1/auth/login', {
      'email': email.trim(),
      'password': password,
    });
    final user = body['user'] as Map<String, dynamic>;
    final role = user['role'] as String?;
    if (role != 'admin' && role != 'staff') {
      // A parent or child credential never gets a working panel session.
      throw const ApiError(
        403,
        'not_admin',
        'This account is not an administrator.',
      );
    }
    tokens
      ..accessToken = body['access_token'] as String
      ..refreshToken = body['refresh_token'] as String?;
    try {
      state = AdminSession.fromMe(await api.getMap('/api/v1/admin/me'));
    } on ApiError {
      await _endSession(tokens);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _endSession(ref.read(tokenStoreProvider));
    state = null;
  }

  Future<void> _endSession(TokenStore tokens) async {
    final refresh = tokens.refreshToken;
    if (refresh != null) {
      try {
        await ref.read(adminApiProvider).anonymousPost('/api/v1/auth/logout', {
          'refresh_token': refresh,
        });
      } on ApiError {
        // Already gone or offline: the local tokens are dropped regardless.
      }
    }
    tokens
      ..accessToken = null
      ..refreshToken = null;
  }

  Future<bool> _refresh() async {
    final tokens = ref.read(tokenStoreProvider);
    final refresh = tokens.refreshToken;
    if (refresh == null) return false;
    try {
      final body = await ref.read(adminApiProvider).anonymousPost(
        '/api/v1/auth/refresh',
        {'refresh_token': refresh},
      );
      tokens
        ..accessToken = body['access_token'] as String
        ..refreshToken = (body['refresh_token'] as String?) ?? refresh;
      return true;
    } on ApiError {
      return false;
    }
  }
}

final sessionProvider = NotifierProvider<SessionController, AdminSession?>(
  SessionController.new,
);
