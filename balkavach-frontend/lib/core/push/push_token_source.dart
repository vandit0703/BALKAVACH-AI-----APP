import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the phone gets its push address from. Firebase Cloud Messaging in
/// production; a stand-in when Firebase is not set up for this build, so the
/// app works the same without it (in-app notifications still arrive).
abstract interface class PushTokenSource {
  /// False when push cannot work on this build (no Firebase configuration).
  bool get isAvailable;

  /// Asks the user for notification permission. `true` when granted.
  Future<bool> requestPermission();

  /// The current device token, or `null` if none could be obtained.
  Future<String?> token();

  /// Emits whenever the platform issues a new token.
  Stream<String> get onTokenRefresh;

  /// Emits when a push arrives while the app is open.
  Stream<void> get onMessage;

  /// Forgets this device's token (used on sign-out).
  Future<void> deleteToken();
}

class NoopPushTokenSource implements PushTokenSource {
  const NoopPushTokenSource();

  @override
  bool get isAvailable => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Stream<void> get onMessage => const Stream.empty();

  @override
  Future<void> deleteToken() async {}
}

class FirebasePushTokenSource implements PushTokenSource {
  FirebasePushTokenSource(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  bool get isAvailable => true;

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> token() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<void> get onMessage => FirebaseMessaging.onMessage.map((_) {});

  @override
  Future<void> deleteToken() => _messaging.deleteToken();
}

/// Initialises Firebase if this build has a configuration. Without
/// `google-services.json` initialisation throws; that is not an error, it
/// simply means push is not set up (see docs/push-notifications-setup.md).
Future<PushTokenSource> createPushTokenSource() async {
  try {
    await Firebase.initializeApp();
    return FirebasePushTokenSource(FirebaseMessaging.instance);
  } on Object {
    return const NoopPushTokenSource();
  }
}

/// Overridden in `bootstrap()` with the real source when available.
final pushTokenSourceProvider = Provider<PushTokenSource>(
  (ref) => const NoopPushTokenSource(),
);
