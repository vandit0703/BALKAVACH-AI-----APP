import 'dart:convert';
import 'dart:typed_data';

import 'package:balkavach_admin/app.dart';
import 'package:balkavach_admin/core/api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class Reply {
  const Reply(this.status, [this.body]);

  final int status;
  final Object? body;

  static Reply error(int status, String code, String message) => Reply(status, {
    'error': {'code': code, 'message': message},
  });
}

/// In-memory server for Dio, keyed by `METHOD /path`.
class FakeServer implements HttpClientAdapter {
  final _routes = <String, Reply Function(RequestOptions)>{};
  final requests = <RequestOptions>[];

  void on(String method, String path, Reply Function(RequestOptions) reply) =>
      _routes['$method $path'] = reply;

  void reply(String method, String path, Object? body, {int status = 200}) =>
      on(method, path, (_) => Reply(status, body));

  List<RequestOptions> to(String method, String path) =>
      requests.where((r) => r.method == method && r.uri.path == path).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final handler = _routes['${options.method} ${options.uri.path}'];
    final reply = handler == null
        ? Reply.error(404, 'http_error', 'Not Found')
        : handler(options);
    return ResponseBody.fromString(
      reply.body == null ? '' : jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> adminUser({String role = 'admin'}) => {
  'id': 'aaaaaaaa-0000-4000-8000-000000000001',
  'full_name': 'Asha Admin',
  'email': 'asha@example.com',
  'role': role,
  'preferred_language': 'en',
  'is_active': true,
  'created_at': '2026-10-01T10:00:00Z',
  'last_login_at': null,
};

Map<String, Object?> loginBody({
  String role = 'admin',
  String access = 'access-1',
  String refresh = 'refresh-1',
}) => {
  'access_token': access,
  'token_type': 'bearer',
  'expires_at': '2100-01-01T00:00:00Z',
  'refresh_token': refresh,
  'refresh_expires_at': '2100-02-01T00:00:00Z',
  'user': adminUser(role: role),
};

Map<String, Object?> me({
  List<String> permissions = const ['*'],
  List<String> roles = const ['super_admin'],
}) => {'user': adminUser(), 'roles': roles, 'permissions': permissions};

const dashboardBody = {
  'users': 12,
  'families': 4,
  'children': 6,
  'active_tasks': 9,
  'published_videos': 0,
  'pending_redemptions': 2,
};

FakeServer baseServer({
  List<String> permissions = const ['*'],
  List<String> roles = const ['super_admin'],
}) {
  final server = FakeServer()
    ..reply('POST', '/api/v1/auth/login', loginBody())
    ..reply('POST', '/api/v1/auth/logout', null, status: 204)
    ..reply(
      'GET',
      '/api/v1/admin/me',
      me(permissions: permissions, roles: roles),
    )
    ..reply('GET', '/api/v1/admin/dashboard', dashboardBody)
    ..reply('GET', '/api/v1/admin/analytics/overview', {
      'period_days': 30,
      'totals': {
        'new_users': 3,
        'submissions': 8,
        'approvals': 5,
        'rejections': 1,
        'redemptions': 2,
      },
      'daily': [
        for (var i = 0; i < 30; i++)
          {
            'date': '2026-09-${(i % 28 + 1).toString().padLeft(2, '0')}',
            'new_users': 0,
            'submissions': i % 3,
            'approvals': 0,
          },
      ],
      'redemptions_by_status': {
        'pending': 2,
        'approved': 1,
        'rejected': 0,
        'fulfilled': 0,
        'cancelled': 0,
      },
      'top_categories': [
        {'name': 'Learning', 'approved_tasks': 4},
      ],
    });
  return server;
}

Dio testDio(FakeServer server, TokenStore tokens) {
  final dio = createDio(tokens, baseUrl: 'https://api.test');
  dio.httpClientAdapter = server;
  return dio;
}

Future<ProviderContainer> pumpAdmin(
  WidgetTester tester,
  FakeServer server, {
  Size size = const Size(1400, 900),
  bool signedIn = true,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final tokens = TokenStore();
  final container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(tokens),
      dioProvider.overrideWithValue(testDio(server, tokens)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const AdminApp()),
  );
  await tester.pumpAndSettle();
  if (signedIn) {
    await tester.enterText(
      find.byKey(const Key('login.email')),
      'asha@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login.password')),
      'a-long-password-123',
    );
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pumpAndSettle();
  }
  return container;
}

Future<void> openSection(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
