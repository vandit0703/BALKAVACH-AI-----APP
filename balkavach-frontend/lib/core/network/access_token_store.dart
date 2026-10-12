import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the current bearer token for the HTTP layer.
///
/// The session controller writes here; the auth interceptor reads here. This
/// keeps Dio independent of the session provider (no provider cycle).
class AccessTokenStore {
  /// Current bearer token, or `null` when signed out.
  String? token;
  final _unauthorized = StreamController<void>.broadcast();

  /// Emits when an authenticated request is rejected with 401.
  Stream<void> get onUnauthorized => _unauthorized.stream;

  void reportUnauthorized() {
    if (!_unauthorized.isClosed) _unauthorized.add(null);
  }

  Future<void> dispose() => _unauthorized.close();
}

final accessTokenStoreProvider = Provider<AccessTokenStore>((ref) {
  final store = AccessTokenStore();
  ref.onDispose(store.dispose);
  return store;
});
