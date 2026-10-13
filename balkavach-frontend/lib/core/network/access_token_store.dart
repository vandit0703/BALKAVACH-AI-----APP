import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Result of trying to renew the session after a 401.
enum RefreshOutcome {
  /// New tokens are in place; the failed request can be retried.
  refreshed,

  /// The server refused the refresh token: the session is over.
  rejected,

  /// Could not reach the server (offline, timeout). The session may still be
  /// valid, so the user must not be signed out for this.
  unavailable,
}

/// Holds the current bearer token for the HTTP layer.
///
/// The session controller writes here; the auth interceptor reads here. This
/// keeps Dio independent of the session provider (no provider cycle).
class AccessTokenStore {
  /// Current bearer token, or `null` when signed out.
  String? token;

  /// Renews the session; installed by the session controller.
  Future<RefreshOutcome> Function()? refresher;

  Future<RefreshOutcome>? _inFlight;
  final _unauthorized = StreamController<void>.broadcast();

  /// Emits when an authenticated request is rejected with 401 and the session
  /// could not be renewed.
  Stream<void> get onUnauthorized => _unauthorized.stream;

  void reportUnauthorized() {
    if (!_unauthorized.isClosed) _unauthorized.add(null);
  }

  /// Runs one refresh at a time; concurrent callers share its result, so a
  /// burst of 401s cannot spend (and rotate away) the refresh token twice.
  Future<RefreshOutcome> refreshOnce() {
    final refresh = refresher;
    if (refresh == null) return Future.value(RefreshOutcome.rejected);
    return _inFlight ??= refresh().whenComplete(() => _inFlight = null);
  }

  Future<void> dispose() => _unauthorized.close();
}

final accessTokenStoreProvider = Provider<AccessTokenStore>((ref) {
  final store = AccessTokenStore();
  ref.onDispose(store.dispose);
  return store;
});
