import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/access_token_store.dart';
import '../data/auth_repository.dart';
import '../data/session_storage.dart';
import '../domain/session.dart';

/// Clock seam for expiry checks in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The device's current session, or `null` when signed out.
///
/// Sign-in methods leave the state untouched until they succeed and rethrow
/// [ApiException]s for the calling screen to display.
class SessionController extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() async {
    final tokens = ref.watch(accessTokenStoreProvider);
    final subscription = tokens.onUnauthorized.listen((_) => _expire());
    ref.onDispose(subscription.cancel);

    final storage = ref.watch(sessionStorageProvider);
    final stored = await storage.read();
    if (stored == null) return null;
    if (stored.isExpiredAt(ref.read(clockProvider)())) {
      await storage.clear();
      return null;
    }

    try {
      final user = await ref
          .read(authRepositoryProvider)
          .me(accessToken: stored.accessToken);
      if (user.id != stored.user.id) {
        await storage.clear();
        return null;
      }
      final refreshed = stored.copyWith(user: user);
      await storage.write(refreshed);
      tokens.token = refreshed.accessToken;
      return refreshed;
    } on UnauthorizedException {
      await storage.clear();
      return null;
    } on ApiException {
      // Offline or server asleep: keep the unexpired session. Screens show
      // their own errors, and a later 401 still signs the user out.
      tokens.token = stored.accessToken;
      return stored;
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    final session = await ref
        .read(authRepositoryProvider)
        .login(email: email, password: password);
    await _adopt(session);
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final session = await ref
        .read(authRepositoryProvider)
        .register(fullName: fullName, email: email, password: password);
    await _adopt(session);
  }

  /// Replaces the parent session with a child session for [childId]. The
  /// parent token is discarded so the child cannot reach parent screens.
  Future<void> startChildMode(String childId) async {
    final current = state.value;
    if (current == null || !current.isParent) {
      throw const ForbiddenException(message: 'Parent session required');
    }
    final session = await ref
        .read(authRepositoryProvider)
        .startChildSession(childId);
    await _adopt(session);
  }

  Future<void> signOut() async {
    ref.read(accessTokenStoreProvider).token = null;
    await ref.read(sessionStorageProvider).clear();
    state = const AsyncData(null);
  }

  Future<void> _adopt(Session session) async {
    if (session.user.role == UserRole.admin ||
        session.user.role == UserRole.staff) {
      // The mobile app has no admin screens; don't keep those credentials.
      throw const ForbiddenException(
        message: 'Administrator accounts are not supported in the app',
      );
    }
    await ref.read(sessionStorageProvider).write(session);
    ref.read(accessTokenStoreProvider).token = session.accessToken;
    state = AsyncData(session);
  }

  void _expire() {
    if (state.value == null) return;
    unawaited(signOut());
  }
}

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, Session?>(SessionController.new);

/// Id of the signed-in user. Data providers watch this so their caches are
/// dropped whenever a different account (or child) uses the device.
final sessionUserIdProvider = Provider<String?>(
  (ref) => ref.watch(
    sessionControllerProvider.select((session) => session.value?.user.id),
  ),
);
