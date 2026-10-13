import 'package:balkavach_admin/core/api.dart';
import 'package:balkavach_admin/core/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Map<String, Object?> _user({
  String id = 'u1',
  String name = 'Priya Parent',
  bool active = true,
  String role = 'parent',
}) => {
  'id': id,
  'full_name': name,
  'email': 'priya@example.com',
  'role': role,
  'preferred_language': 'en',
  'is_active': active,
  'created_at': '2026-10-01T10:00:00Z',
  'last_login_at': null,
};

void main() {
  group('sign-in', () {
    testWidgets('an administrator reaches the dashboard', (tester) async {
      final server = baseServer();
      await pumpAdmin(tester, server);
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.byKey(const Key('tile.users')), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      final login = server.to('POST', '/api/v1/auth/login').single;
      expect(login.headers.containsKey('Authorization'), isFalse);
      expect(
        server.to('GET', '/api/v1/admin/me').single.headers['Authorization'],
        'Bearer access-1',
      );
    });

    testWidgets('a wrong password is explained', (tester) async {
      final server = baseServer()
        ..on(
          'POST',
          '/api/v1/auth/login',
          (_) => Reply.error(401, 'invalid_credentials', 'bad'),
        );
      await pumpAdmin(tester, server);
      expect(find.byKey(const Key('login.error')), findsOneWidget);
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      expect(find.byKey(const Key('tile.users')), findsNothing);
    });

    testWidgets('a parent account never gets a panel session', (tester) async {
      final server = baseServer()
        ..reply('POST', '/api/v1/auth/login', loginBody(role: 'parent'));
      await pumpAdmin(tester, server);
      expect(
        find.text('This account is not an administrator.'),
        findsOneWidget,
      );
      expect(
        server.to('GET', '/api/v1/admin/me'),
        isEmpty,
        reason: 'no admin call is made with a parent token',
      );
    });

    testWidgets('empty fields are caught before any request', (tester) async {
      final server = baseServer();
      await pumpAdmin(tester, server, signedIn: false);
      await tester.tap(find.byKey(const Key('login.submit')));
      await tester.pumpAndSettle();
      expect(find.text('Enter your email'), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('signing out ends the server session and returns to sign-in', (
      tester,
    ) async {
      final server = baseServer();
      await pumpAdmin(tester, server);
      await tester.tap(find.byKey(const Key('account.menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(server.to('POST', '/api/v1/auth/logout').single.data, {
        'refresh_token': 'refresh-1',
      });
      expect(find.byKey(const Key('login.submit')), findsOneWidget);
    });
  });

  group('permissions', () {
    testWidgets('a content manager only sees content sections', (tester) async {
      final server = baseServer(
        permissions: [
          'content:read',
          'content:write',
          'video:read',
          'video:write',
        ],
        roles: ['content_manager'],
      );
      await pumpAdmin(tester, server);
      expect(find.text('Learning content'), findsWidgets);
      expect(find.text('Preset missions'), findsWidgets);
      expect(find.text('Users'), findsNothing);
      expect(find.text('Audit log'), findsNothing);
    });

    testWidgets('the account menu shows who is signed in and their roles', (
      tester,
    ) async {
      await pumpAdmin(tester, baseServer());
      await tester.tap(find.byKey(const Key('account.menu')));
      await tester.pumpAndSettle();
      expect(find.textContaining('asha@example.com'), findsOneWidget);
      expect(find.text('Roles: super_admin'), findsOneWidget);
    });

    test('AdminSession.can honours the wildcard and exact permissions', () {
      final everything = AdminSession.fromMe(me());
      expect(everything.can('anything:at-all'), isTrue);
      final limited = AdminSession.fromMe(
        me(permissions: ['content:read'], roles: ['x']),
      );
      expect(limited.can('content:read'), isTrue);
      expect(limited.can('content:write'), isFalse);
    });
  });

  group('users', () {
    testWidgets('lists, searches and pages', (tester) async {
      final server = baseServer()
        ..on(
          'GET',
          '/api/v1/admin/users',
          (o) => Reply(200, [
            for (var i = 0; i < 25; i++) _user(id: 'u$i', name: 'User $i'),
          ]),
        );
      await pumpAdmin(tester, server);
      await openSection(tester, 'Users');
      expect(find.text('User 0'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('users.search')), 'priya');
      await tapKey(tester, 'users.apply');
      expect(
        server.to('GET', '/api/v1/admin/users').last.queryParameters['q'],
        'priya',
      );

      await tapKey(tester, 'table.next');
      expect(
        server.to('GET', '/api/v1/admin/users').last.queryParameters['offset'],
        25,
      );
    });

    testWidgets('deactivating asks first, then patches', (tester) async {
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/users', [_user()])
        ..reply('PATCH', '/api/v1/admin/users/u1/status', _user(active: false));
      await pumpAdmin(tester, server);
      await openSection(tester, 'Users');
      await tapKey(tester, 'user.toggle.u1');
      expect(find.text('Deactivate account?'), findsOneWidget);
      expect(server.to('PATCH', '/api/v1/admin/users/u1/status'), isEmpty);
      await tapKey(tester, 'confirm.yes');
      expect(server.to('PATCH', '/api/v1/admin/users/u1/status').single.data, {
        'is_active': false,
      });
      expect(find.text('Account deactivated'), findsOneWidget);
    });

    testWidgets('a refusal from the server is shown, not swallowed', (
      tester,
    ) async {
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/users', [_user()])
        ..on(
          'PATCH',
          '/api/v1/admin/users/u1/status',
          (_) => Reply.error(403, 'http_error', 'nope'),
        );
      await pumpAdmin(tester, server);
      await openSection(tester, 'Users');
      await tapKey(tester, 'user.toggle.u1');
      await tapKey(tester, 'confirm.yes');
      expect(
        find.text('You do not have permission to do this.'),
        findsOneWidget,
      );
    });

    testWidgets('a load failure offers retry', (tester) async {
      final server = baseServer()
        ..on(
          'GET',
          '/api/v1/admin/users',
          (_) => Reply.error(500, 'internal_error', 'boom'),
        );
      await pumpAdmin(tester, server);
      await openSection(tester, 'Users');
      expect(find.byKey(const Key('error.retry')), findsOneWidget);
      server.reply('GET', '/api/v1/admin/users', [_user()]);
      await tapKey(tester, 'error.retry');
      expect(find.text('Priya Parent'), findsOneWidget);
    });

    testWidgets('role assignment is offered only for administrator accounts', (
      tester,
    ) async {
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/users', [
          _user(),
          _user(id: 'a1', name: 'Ops Admin', role: 'admin'),
        ])
        ..reply('GET', '/api/v1/admin/roles', [
          {
            'id': 'r1',
            'name': 'super_admin',
            'description': null,
            'permissions': ['*'],
          },
          {
            'id': 'r2',
            'name': 'content_manager',
            'description': null,
            'permissions': <String>[],
          },
        ])
        ..reply('POST', '/api/v1/admin/users/a1/roles', null, status: 204);
      await pumpAdmin(tester, server);
      await openSection(tester, 'Users');
      expect(find.byKey(const Key('user.roles.u1')), findsNothing);
      await tapKey(tester, 'user.roles.a1');
      await tester.tap(find.byKey(const Key('field.role_id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('content_manager').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'form.submit');
      expect(server.to('POST', '/api/v1/admin/users/a1/roles').single.data, {
        'role_id': 'r2',
      });
    });
  });

  group('families', () {
    testWidgets('opens details and deactivates a child after confirming', (
      tester,
    ) async {
      final family = {
        'id': 'f1',
        'family_name': 'Sharma Family',
        'created_at': '2026-10-01T10:00:00Z',
        'member_count': 3,
        'parent_count': 1,
        'child_count': 1,
        'active_task_count': 2,
      };
      final detail = {
        ...family,
        'timezone': 'Asia/Kolkata',
        'parents': [
          {
            'user_id': 'p1',
            'full_name': 'Priya',
            'email': 'priya@example.com',
            'is_active': true,
          },
        ],
        'children': [
          {
            'id': 'c1',
            'user_id': 'cu1',
            'display_name': 'Aarav',
            'is_active': true,
            'created_at': '2026-10-02T10:00:00Z',
          },
        ],
      };
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/families', [family])
        ..reply('GET', '/api/v1/admin/families/f1', detail)
        ..reply('PATCH', '/api/v1/admin/children/c1/status', {
          'id': 'c1',
          'family_id': 'f1',
          'display_name': 'Aarav',
          'is_active': false,
        });
      await pumpAdmin(tester, server);
      await openSection(tester, 'Families');
      await tapKey(tester, 'family.open.f1');
      expect(find.text('Time zone: Asia/Kolkata'), findsOneWidget);
      expect(find.text('Aarav'), findsOneWidget);
      expect(find.text('priya@example.com'), findsOneWidget);

      await tapKey(tester, 'child.toggle.c1');
      expect(server.to('PATCH', '/api/v1/admin/children/c1/status'), isEmpty);
      await tapKey(tester, 'confirm.yes');
      expect(
        server.to('PATCH', '/api/v1/admin/children/c1/status').single.data,
        {'is_active': false},
      );
    });
  });

  group('missions and rewards', () {
    testWidgets('deactivating a mission asks first', (tester) async {
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/tasks', [
          {
            'id': 't1',
            'family_id': 'f1',
            'family_name': 'Sharma Family',
            'title': 'Read a story',
            'category_name': 'Learning',
            'assigned_child_name': null,
            'star_reward': 5,
            'xp_reward': 20,
            'due_at': null,
            'is_active': true,
            'created_at': '2026-10-01T10:00:00Z',
          },
        ])
        ..reply('PATCH', '/api/v1/admin/tasks/t1/active', {});
      await pumpAdmin(tester, server);
      await openSection(tester, 'Missions');
      expect(find.text('Any child'), findsOneWidget);
      await tapKey(tester, 'mission.toggle.t1');
      await tapKey(tester, 'confirm.yes');
      expect(server.to('PATCH', '/api/v1/admin/tasks/t1/active').single.data, {
        'is_active': false,
      });
    });

    testWidgets('reward requests are read-only and filterable', (tester) async {
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/redemptions', [
          {
            'id': 'x1',
            'family_id': 'f1',
            'family_name': 'Sharma Family',
            'reward_name': 'Ice cream',
            'child_name': 'Aarav',
            'status': 'pending',
            'star_cost_at_request': 5,
            'requested_at': '2026-10-01T10:00:00Z',
            'reviewed_at': null,
          },
        ]);
      await pumpAdmin(tester, server);
      await openSection(tester, 'Reward requests');
      expect(find.text('Ice cream'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      await tester.tap(find.byKey(const Key('redemptions.status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pending').last);
      await tester.pumpAndSettle();
      expect(
        server
            .to('GET', '/api/v1/admin/redemptions')
            .last
            .queryParameters['status'],
        'pending',
      );
    });
  });

  group('content management', () {
    testWidgets('a new preset sends typed values', (tester) async {
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/preset-tasks', <Object?>[])
        ..reply('GET', '/api/v1/admin/task-categories', [
          {
            'id': 'cat1',
            'name': 'Learning',
            'description': null,
            'icon_name': null,
            'is_default': true,
            'is_active': true,
          },
        ])
        ..reply('POST', '/api/v1/admin/preset-tasks', {}, status: 201);
      await pumpAdmin(tester, server);
      await openSection(tester, 'Preset missions');
      await tapKey(tester, 'presets.add');
      await tester.enterText(
        find.byKey(const Key('field.title')),
        'Brush your teeth',
      );
      await tester.enterText(
        find.byKey(const Key('field.suggested_star_reward')),
        '2',
      );
      await tapKey(tester, 'form.submit');
      final body =
          server.to('POST', '/api/v1/admin/preset-tasks').single.data as Map;
      expect(body['title'], 'Brush your teeth');
      expect(body['suggested_star_reward'], 2);
      expect(body['language_code'], 'en');
      expect(body['suggested_star_reward'], isA<int>());
    });

    testWidgets('the form refuses an empty title and a bad number', (
      tester,
    ) async {
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/preset-tasks', <Object?>[])
        ..reply('GET', '/api/v1/admin/task-categories', <Object?>[]);
      await pumpAdmin(tester, server);
      await openSection(tester, 'Preset missions');
      await tapKey(tester, 'presets.add');
      await tester.enterText(
        find.byKey(const Key('field.suggested_star_reward')),
        '99999',
      );
      await tapKey(tester, 'form.submit');
      expect(find.text('Required'), findsWidgets);
      expect(find.text('At most 10000'), findsOneWidget);
      expect(server.to('POST', '/api/v1/admin/preset-tasks'), isEmpty);
    });

    testWidgets('learning links must be https', (tester) async {
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/educational-content', <Object?>[])
        ..reply('POST', '/api/v1/admin/educational-content', {}, status: 201);
      await pumpAdmin(tester, server);
      await openSection(tester, 'Learning content');
      await tapKey(tester, 'content.add');
      await tester.enterText(
        find.byKey(const Key('field.title')),
        'Counting song',
      );
      await tester.enterText(
        find.byKey(const Key('field.content_url')),
        'http://example.com/a',
      );
      await tapKey(tester, 'form.submit');
      expect(find.text('Enter a full https:// link'), findsOneWidget);
      expect(server.to('POST', '/api/v1/admin/educational-content'), isEmpty);

      await tester.enterText(
        find.byKey(const Key('field.content_url')),
        'https://example.com/a',
      );
      await tapKey(tester, 'form.submit');
      final body =
          server.to('POST', '/api/v1/admin/educational-content').single.data
              as Map;
      expect(body['content_url'], 'https://example.com/a');
      expect(body['content_type'], 'link');
    });

    testWidgets('a server conflict on a category name is shown', (
      tester,
    ) async {
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/task-categories', <Object?>[])
        ..on(
          'POST',
          '/api/v1/tasks/categories',
          (_) => Reply.error(
            409,
            'http_error',
            'A task category with that name already exists',
          ),
        );
      await pumpAdmin(tester, server);
      await openSection(tester, 'Categories');
      await tapKey(tester, 'categories.add');
      await tester.enterText(find.byKey(const Key('field.name')), 'Learning');
      await tapKey(tester, 'form.submit');
      expect(
        find.text('A task category with that name already exists'),
        findsOneWidget,
      );
    });

    testWidgets('badges are created with a threshold', (tester) async {
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/badges', <Object?>[])
        ..reply('POST', '/api/v1/admin/badges', {}, status: 201);
      await pumpAdmin(tester, server);
      await openSection(tester, 'Badges');
      await tapKey(tester, 'badges.add');
      await tester.enterText(find.byKey(const Key('field.name')), 'Helper');
      await tester.tap(find.byKey(const Key('field.criteria_type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approved missions').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('field.threshold')), '3');
      await tapKey(tester, 'form.submit');
      expect(server.to('POST', '/api/v1/admin/badges').single.data, {
        'name': 'Helper',
        'criteria_type': 'approved_tasks',
        'threshold': 3,
      });
    });
  });

  group('settings', () {
    final settings = [
      {
        'key': 'consent_versions',
        'value': {'parent_guardian_terms': '2026-10-draft'},
        'overridden': false,
      },
      {
        'key': 'maintenance',
        'value': {'enabled': false, 'message': ''},
        'overridden': false,
      },
    ];

    testWidgets('publishing a consent version needs an explicit confirmation', (
      tester,
    ) async {
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/settings', settings)
        ..reply('PUT', '/api/v1/admin/settings/consent_versions', {});
      await pumpAdmin(tester, server);
      await openSection(tester, 'Settings');
      expect(find.textContaining('built-in draft'), findsOneWidget);
      await tapKey(tester, 'settings.consent.edit');
      final field = find.byKey(const Key('field.parent_guardian_terms'));
      await tester.enterText(field, '2027-01');
      await tapKey(tester, 'form.submit');
      expect(find.text('Ask all parents to accept again?'), findsOneWidget);
      expect(
        server.to('PUT', '/api/v1/admin/settings/consent_versions'),
        isEmpty,
      );
      await tapKey(tester, 'confirm.yes');
      expect(
        server.to('PUT', '/api/v1/admin/settings/consent_versions').single.data,
        {
          'value': {'parent_guardian_terms': '2027-01'},
        },
      );
    });

    testWidgets('maintenance can be switched on with a message', (
      tester,
    ) async {
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/settings', settings)
        ..reply('PUT', '/api/v1/admin/settings/maintenance', {});
      await pumpAdmin(tester, server);
      await openSection(tester, 'Settings');
      await tapKey(tester, 'settings.maintenance.edit');
      await tester.tap(find.byKey(const Key('field.enabled')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('field.message')),
        'Back at 6 pm',
      );
      await tapKey(tester, 'form.submit');
      expect(
        server.to('PUT', '/api/v1/admin/settings/maintenance').single.data,
        {
          'value': {'enabled': true, 'message': 'Back at 6 pm'},
        },
      );
    });
  });

  group('session handling', () {
    testWidgets('an expired access token is renewed transparently', (
      tester,
    ) async {
      var calls = 0;
      final server = baseServer()
        ..on('GET', '/api/v1/admin/audit-logs', (o) {
          calls++;
          return o.headers['Authorization'] == 'Bearer access-2'
              ? const Reply(200, <Object?>[])
              : Reply.error(401, 'http_error', 'expired');
        })
        ..reply(
          'POST',
          '/api/v1/auth/refresh',
          loginBody(access: 'access-2', refresh: 'refresh-2'),
        );
      await pumpAdmin(tester, server);
      await openSection(tester, 'Audit log');
      expect(calls, 2);
      expect(server.to('POST', '/api/v1/auth/refresh').single.data, {
        'refresh_token': 'refresh-1',
      });
      expect(find.byKey(const Key('table.empty')), findsOneWidget);
    });

    testWidgets('a refused refresh returns to sign-in', (tester) async {
      final server = baseServer()
        ..on(
          'GET',
          '/api/v1/admin/audit-logs',
          (_) => Reply.error(401, 'http_error', 'expired'),
        )
        ..on(
          'POST',
          '/api/v1/auth/refresh',
          (_) => Reply.error(401, 'refresh_token_reused', 'ended'),
        );
      await pumpAdmin(tester, server);
      await openSection(tester, 'Audit log');
      expect(find.byKey(const Key('login.submit')), findsOneWidget);
    });
  });

  test(
    'a reply with no JSON object (204) is an empty map, not a crash',
    () async {
      final server = FakeServer()
        // jsonEncode('') is the string "" — what some HTTP adapters deliver for 204.
        ..reply('POST', '/api/v1/auth/logout', '', status: 204)
        ..reply('PUT', '/api/v1/admin/settings/maintenance', '')
        ..reply('PATCH', '/api/v1/admin/tasks/t1/active', null);
      final tokens = TokenStore();
      final api = AdminApi(testDio(server, tokens));
      expect(await api.anonymousPost('/api/v1/auth/logout', {}), isEmpty);
      expect(await api.put('/api/v1/admin/settings/maintenance', {}), isEmpty);
      expect(await api.patch('/api/v1/admin/tasks/t1/active', {}), isEmpty);
    },
  );

  test('ApiError helpers', () {
    expect(const ApiError(403, null, 'x').isForbidden, isTrue);
    expect(const ApiError(0, null, 'x').isNetwork, isTrue);
  });

  group('dashboard', () {
    testWidgets('shows activity for the chosen range', (tester) async {
      final server = baseServer();
      await pumpAdmin(tester, server);
      expect(find.byKey(const Key('analytics.totals')), findsOneWidget);
      expect(find.text('Submissions: 8'), findsOneWidget);
      expect(find.text('Learning: 4'), findsOneWidget);
      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();
      expect(
        server
            .to('GET', '/api/v1/admin/analytics/overview')
            .last
            .queryParameters['days'],
        7,
      );
    });

    testWidgets('without the reports permission the activity block is absent', (
      tester,
    ) async {
      final server = baseServer(
        permissions: ['dashboard:read'],
        roles: ['viewer'],
      );
      await pumpAdmin(tester, server);
      expect(find.byKey(const Key('tile.users')), findsOneWidget);
      expect(find.byKey(const Key('analytics.totals')), findsNothing);
      expect(server.to('GET', '/api/v1/admin/analytics/overview'), isEmpty);
    });
  });

  group('layout', () {
    testWidgets('a narrow window uses a navigation drawer', (tester) async {
      await pumpAdmin(tester, baseServer(), size: const Size(420, 800));
      expect(find.byType(NavigationRail), findsNothing);
      await tester.tap(find.byType(DrawerButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nav./users')), findsOneWidget);
    });
  });
}
