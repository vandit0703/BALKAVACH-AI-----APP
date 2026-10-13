import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/access_token_store.dart';
import '../data/auth_repository.dart';
import '../data/session_storage.dart';
import '../domain/session.dart';

/// Clock seam for expiry checks in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Work that must run while the user is still authenticated, just before the
/// session is dropped (for example unregistering this device from push).
class SignOutHooks {
  final _hooks = <Future<void> Function()>[];

  /// Registers [hook]; returns a function that removes it.
  void Function() add(Future<void> Function() hook) {
    _hooks.add(hook);
    return () => _hooks.remove(hook);
  }

  Future<void> runAll() async {
    for (final hook in List.of(_hooks)) {
      try {
        await hook();
      } on Object {
        // A failing cleanup must never keep someone signed in.
      }
    }
  }
}

final signOutHooksProvider = Provider<SignOutHooks>((ref) => SignOutHooks());

/// The device's current session, or `null` when signed out.
///
/// Sign-in methods leave the state untouched until they succeed and rethrow
/// [ApiException]s for the calling screen to display.
///
/// Access tokens are short-lived. When one is rejected (or already expired at
/// launch) the session is renewed with its refresh token; only a refusal by
/// the server ends the session, never being offline.
class SessionController extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() async {
    final tokens = ref.watch(accessTokenStoreProvider);
    final subscription = tokens.onUnauthorized.listen((_) => _expire());
    ref.onDispose(subscription.cancel);
    tokens.refresher = _refreshCurrent;
    ref.onDispose(() {
      if (tokens.refresher == _refreshCurrent) tokens.refresher = null;
    });

    final storage = ref.watch(sessionStorageProvider);
    var stored = await storage.read();
    if (stored == null) return null;
    final now = ref.read(clockProvider)();
    if (stored.isExpiredAt(now)) {
      if (!stored.canRefresh || stored.refreshExpiredAt(now)) {
        await storage.clear();
        return null;
      }
      switch (await _renew(stored)) {
        case _Renewed(:final session):
          stored = session;
        case _Refused():
          await storage.clear();
          return null;
        case _Unreachable():
          // Offline at launch: keep the session; the first request that
          // reaches the server will renew it.
          return stored;
      }
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
      if (stored.canRefresh) {
        switch (await _renew(stored)) {
          case _Renewed(:final session):
            await storage.write(session);
            tokens.token = session.accessToken;
            return session;
          case _Unreachable():
            tokens.token = stored.accessToken;
            return stored;
          case _Refused():
            break;
        }
      }
      await storage.clear();
      return null;
    } on ApiException {
      // Offline or server asleep: keep the unexpired session. Screens show
      // their own errors, and a later 401 still renews or signs the user out.
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

  /// Ends the session on this device and, best effort, on the server.
  Future<void> signOut() async {
    final current = state.value;
    await ref.read(signOutHooksProvider).runAll();
    final refreshToken = current?.refreshToken;
    if (refreshToken != null) {
      try {
        await ref.read(authRepositoryProvider).logout(refreshToken);
      } on ApiException {
        // Already gone, or offline: the local session is dropped regardless.
      }
    }
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
    ref.read(sessionEndedProvider.notifier).clear();
    state = AsyncData(session);
  }

  /// Called by the HTTP layer after a 401: renew tokens in place.
  Future<RefreshOutcome> _refreshCurrent() async {
    final current =
        state.value ?? await ref.read(sessionStorageProvider).read();
    if (current == null || !current.canRefresh) return RefreshOutcome.rejected;
    switch (await _renew(current)) {
      case _Renewed(:final session):
        await ref.read(sessionStorageProvider).write(session);
        ref.read(accessTokenStoreProvider).token = session.accessToken;
        if (ref.mounted) state = AsyncData(session);
        return RefreshOutcome.refreshed;
      case _Refused():
        return RefreshOutcome.rejected;
      case _Unreachable():
        return RefreshOutcome.unavailable;
    }
  }

  Future<_Renewal> _renew(Session current) async {
    try {
      final renewed = await ref
          .read(authRepositoryProvider)
          .refresh(current.refreshToken!);
      return _Renewed(current.renewedWith(renewed));
    } on UnauthorizedException {
      return const _Refused();
    } on ApiException catch (error) {
      // 5xx / network / timeout: say nothing about the session's validity.
      return error is ServerException ||
              error is NetworkException ||
              error is RequestTimeoutException
          ? const _Unreachable()
          : const _Refused();
    }
  }

  /// The server rejected the token and the session could not be renewed.
  /// Sign out and leave a notice for the role screen to explain why.
  void _expire() {
    if (state.value == null) return;
    ref.read(sessionEndedProvider.notifier).mark();
    unawaited(_dropLocalSession());
  }

  Future<void> _dropLocalSession() async {
    ref.read(accessTokenStoreProvider).token = null;
    await ref.read(sessionStorageProvider).clear();
    if (ref.mounted) state = const AsyncData(null);
  }
}

sealed class _Renewal {
  const _Renewal();
}

class _Renewed extends _Renewal {
  const _Renewed(this.session);
  final Session session;
}

class _Refused extends _Renewal {
  const _Refused();
}

class _Unreachable extends _Renewal {
  const _Unreachable();
}

/// True after the server ended the session (401), until the user acts on the
/// notice or signs in again. A deliberate sign-out does not set it.
class SessionEndedNotice extends Notifier<bool> {
  @override
  bool build() => false;

  void mark() => state = true;

  void clear() => state = false;
}

final sessionEndedProvider = NotifierProvider<SessionEndedNotice, bool>(
  SessionEndedNotice.new,
);

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, Session?>(SessionController.new);

/// Id of the signed-in user. Data providers watch this so their caches are
/// dropped whenever a different account (or child) uses the device.
final sessionUserIdProvider = Provider<String?>(
  (ref) => ref.watch(
    sessionControllerProvider.select((session) => session.value?.user.id),
  ),
);
