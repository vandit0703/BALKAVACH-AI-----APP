import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/push/push_token_source.dart';
import '../../approvals/presentation/approval_providers.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../learning/data/learning_repository.dart';
import '../../missions/presentation/mission_providers.dart';
import '../../rewards/data/rewards_repository.dart';
import '../../settings/presentation/settings_providers.dart';
import '../data/device_repository.dart';

/// What push looks like for the signed-in user on this phone.
enum PushStatus {
  /// Nobody is signed in.
  signedOut,

  /// This build has no Firebase configuration, so no push can arrive.
  notConfigured,

  /// The user turned notifications off in settings.
  off,

  /// The user (or Android) denied the notification permission.
  permissionDenied,

  /// Registering with the server.
  working,

  /// This phone is registered and will receive notifications.
  registered,

  /// Registration failed (offline, server error); retried next launch.
  failed,
}

/// Keeps this phone's push token registered with the server for whoever is
/// signed in, and removes it on sign-out so a shared phone never delivers one
/// person's notifications to another.
///
/// A push never carries content; when one arrives the app refreshes what it
/// shows from the server.
class PushRegistration extends Notifier<PushStatus> {
  StreamSubscription<String>? _refresh;
  StreamSubscription<void>? _messages;
  void Function()? _removeHook;
  String? _registeredToken;

  @override
  PushStatus build() {
    ref.onDispose(_stop);
    final source = ref.watch(pushTokenSourceProvider);
    final session = ref.watch(sessionControllerProvider).value;

    _stop();
    if (session == null) return PushStatus.signedOut;
    if (!source.isAvailable) return PushStatus.notConfigured;
    // Only a signed-in user on a push-capable build reads (and so requests)
    // the notification preference.
    final wantsPush = ref.watch(
      userSettingsProvider.select((s) => s.value?.pushEnabled ?? true),
    );
    if (!wantsPush) {
      unawaited(_unregister(source));
      return PushStatus.off;
    }
    _removeHook = ref.read(signOutHooksProvider).add(() => _unregister(source));
    unawaited(_register(source));
    return PushStatus.working;
  }

  void _stop() {
    unawaited(_refresh?.cancel());
    unawaited(_messages?.cancel());
    _refresh = null;
    _messages = null;
    _removeHook?.call();
    _removeHook = null;
  }

  Future<void> _register(PushTokenSource source) async {
    try {
      if (!await source.requestPermission()) {
        if (ref.mounted) state = PushStatus.permissionDenied;
        return;
      }
      final token = await source.token();
      if (token == null) {
        if (ref.mounted) state = PushStatus.failed;
        return;
      }
      await ref.read(deviceRepositoryProvider).register(token);
      _registeredToken = token;
      if (!ref.mounted) return;
      state = PushStatus.registered;
      _refresh = source.onTokenRefresh.listen((fresh) {
        unawaited(_replace(fresh));
      });
      _messages = source.onMessage.listen((_) => _refreshVisibleData());
    } on ApiException {
      if (ref.mounted) state = PushStatus.failed;
    } on Object {
      if (ref.mounted) state = PushStatus.failed;
    }
  }

  Future<void> _replace(String token) async {
    try {
      await ref.read(deviceRepositoryProvider).register(token);
      _registeredToken = token;
    } on ApiException {
      if (ref.mounted) state = PushStatus.failed;
    }
  }

  Future<void> _unregister(PushTokenSource source) async {
    final token = _registeredToken;
    if (token == null) return;
    _registeredToken = null;
    try {
      await ref.read(deviceRepositoryProvider).unregister(token);
    } on ApiException {
      // Best effort: the server also drops tokens the provider reports dead.
    }
    try {
      await source.deleteToken();
    } on Object {
      // Nothing more to do locally.
    }
  }

  /// A push means the server has something new; show it without waiting for a
  /// pull-to-refresh.
  void _refreshVisibleData() {
    if (!ref.mounted) return;
    ref
      ..invalidate(parentNotificationsProvider)
      ..invalidate(childMissionsProvider)
      ..invalidate(mySubmissionsProvider)
      ..invalidate(childNotificationsProvider)
      ..invalidate(myRedemptionsProvider)
      ..invalidate(childCatalogProvider)
      ..invalidate(learningItemsProvider)
      ..invalidate(familyRedemptionsProvider)
      ..invalidate(approvalInboxProvider)
      ..invalidate(familyMissionsProvider);
  }
}

final pushRegistrationProvider = NotifierProvider<PushRegistration, PushStatus>(
  PushRegistration.new,
);
