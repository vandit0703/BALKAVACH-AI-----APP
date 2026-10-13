import 'dart:async';

import 'package:balkavach_app/core/push/push_token_source.dart';
import 'package:balkavach_app/features/approvals/presentation/approval_providers.dart';
import 'package:balkavach_app/features/authentication/presentation/session_controller.dart';
import 'package:balkavach_app/features/notifications/presentation/push_registration.dart';
import 'package:balkavach_app/features/settings/presentation/settings_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

class _FakeSource implements PushTokenSource {
  _FakeSource({this.grants = true});

  final bool grants;
  String? current = 'token-aaaaaaaaaaaaaaaaaaaa';
  final refreshes = StreamController<String>.broadcast();
  final messages = StreamController<void>.broadcast();
  var permissionAsked = 0;
  var deleted = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<bool> requestPermission() async {
    permissionAsked++;
    return grants;
  }

  @override
  Future<String?> token() async => current;

  @override
  Stream<String> get onTokenRefresh => refreshes.stream;

  @override
  Stream<void> get onMessage => messages.stream;

  @override
  Future<void> deleteToken() async => deleted++;
}

const _devices = '/api/v1/notifications/devices';

Future<(Harness, ProviderContainer)> _signedIn(
  PushTokenSource source, {
  bool pushEnabled = true,
}) async {
  final h = await Harness.create(session: Fx.parentSession());
  h.backend
    ..reply('PUT', _devices, null, status: 204)
    ..reply('POST', '$_devices/unregister', null, status: 204)
    ..reply('POST', '/api/v1/auth/logout', null, status: 204)
    ..reply('GET', '/api/v1/settings/me', Fx.userSettings(push: pushEnabled));
  final container = ProviderContainer(
    overrides: [
      ...h.overrides,
      pushTokenSourceProvider.overrideWithValue(source),
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await container.read(sessionControllerProvider.future);
  await container.read(userSettingsProvider.future);
  container.listen(pushRegistrationProvider, (_, _) {});
  return (h, container);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test(
    'no Firebase configuration means push is simply not configured',
    () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.reply('GET', '/api/v1/settings/me', Fx.userSettings());
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      expect(
        container.read(pushRegistrationProvider),
        PushStatus.notConfigured,
      );
      await _settle();
      expect(h.backend.requestsTo('PUT', _devices), isEmpty);
    },
  );

  test('signed out: nothing is registered', () async {
    final h = await Harness.create();
    final container = ProviderContainer(
      overrides: [
        ...h.overrides,
        pushTokenSourceProvider.overrideWithValue(_FakeSource()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await container.read(sessionControllerProvider.future);
    expect(container.read(pushRegistrationProvider), PushStatus.signedOut);
    expect(h.backend.requestsTo('PUT', _devices), isEmpty);
  });

  test(
    'a signed-in user registers this phone after granting permission',
    () async {
      final source = _FakeSource();
      final (h, container) = await _signedIn(source);
      await _settle();
      expect(container.read(pushRegistrationProvider), PushStatus.registered);
      expect(source.permissionAsked, 1);
      final put = h.backend.requestsTo('PUT', _devices).single;
      expect(put.data, {
        'token': 'token-aaaaaaaaaaaaaaaaaaaa',
        'platform': 'android',
      });
      expect(put.headers['Authorization'], 'Bearer parent.jwt.token');
    },
  );

  test('a denied permission registers nothing and says so', () async {
    final (h, container) = await _signedIn(_FakeSource(grants: false));
    await _settle();
    expect(
      container.read(pushRegistrationProvider),
      PushStatus.permissionDenied,
    );
    expect(h.backend.requestsTo('PUT', _devices), isEmpty);
  });

  test('a token refresh is sent to the server', () async {
    final source = _FakeSource();
    final (h, _) = await _signedIn(source);
    await _settle();
    source.refreshes.add('token-bbbbbbbbbbbbbbbbbbbb');
    await _settle();
    final tokens = h.backend
        .requestsTo('PUT', _devices)
        .map((r) => (r.data as Map)['token'])
        .toList();
    expect(tokens, [
      'token-aaaaaaaaaaaaaaaaaaaa',
      'token-bbbbbbbbbbbbbbbbbbbb',
    ]);
  });

  test('push turned off in settings removes the device', () async {
    final source = _FakeSource();
    final (h, container) = await _signedIn(source);
    await _settle();
    h.backend.reply(
      'PATCH',
      '/api/v1/settings/me',
      Fx.userSettings(push: false),
    );
    await container
        .read(userSettingsProvider.notifier)
        .save(pushEnabled: false);
    await _settle();
    expect(container.read(pushRegistrationProvider), PushStatus.off);
    expect(h.backend.requestsTo('POST', '$_devices/unregister'), hasLength(1));
    expect(source.deleted, 1);
  });

  test('signing out unregisters while still authenticated', () async {
    final source = _FakeSource();
    final (h, container) = await _signedIn(source);
    await _settle();
    await container.read(sessionControllerProvider.notifier).signOut();
    await _settle();
    final unregister = h.backend
        .requestsTo('POST', '$_devices/unregister')
        .single;
    expect(unregister.data, {'token': 'token-aaaaaaaaaaaaaaaaaaaa'});
    expect(unregister.headers['Authorization'], 'Bearer parent.jwt.token');
    expect(source.deleted, 1);
    expect(container.read(pushRegistrationProvider), PushStatus.signedOut);
  });

  test('a push while the app is open refreshes what is on screen', () async {
    final source = _FakeSource();
    final (h, container) = await _signedIn(source);
    h.backend.reply('GET', '/api/v1/notifications', <Object?>[]);
    await container.read(parentNotificationsProvider.future);
    final before = h.backend.requestsTo('GET', '/api/v1/notifications').length;
    container.listen(parentNotificationsProvider, (_, _) {});
    await _settle();

    source.messages.add(null);
    await _settle();
    await container.read(parentNotificationsProvider.future);
    expect(
      h.backend.requestsTo('GET', '/api/v1/notifications').length,
      greaterThan(before),
    );
  });

  test('a server failure is reported, not thrown', () async {
    final (h, container) = await _signedIn(_FakeSource());
    h.backend.on(
      'PUT',
      _devices,
      (_) => FakeReply.error(500, 'internal_error', 'x'),
    );
    container.invalidate(pushRegistrationProvider);
    await _settle();
    expect(container.read(pushRegistrationProvider), PushStatus.failed);
  });

  test('being offline is reported, not thrown', () async {
    final (h, container) = await _signedIn(_FakeSource());
    h.backend.on(
      'PUT',
      _devices,
      (_) => const FakeReply.fail(DioExceptionType.connectionError),
    );
    container.invalidate(pushRegistrationProvider);
    await _settle();
    expect(container.read(pushRegistrationProvider), PushStatus.failed);
  });
}
