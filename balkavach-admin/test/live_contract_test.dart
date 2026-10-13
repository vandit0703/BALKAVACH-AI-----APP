// Opt-in: drives the panel's real API layer against a LIVE server.
//
//   flutter test test/live_contract_test.dart \
//     --dart-define=LIVE_API_BASE_URL=http://127.0.0.1:8765 \
//     --dart-define=LIVE_ADMIN_EMAIL=you@example.com \
//     --dart-define=LIVE_ADMIN_PASSWORD=...
//
// Skipped unless all three are set. Use a disposable local backend.
import 'package:balkavach_admin/core/api.dart';
import 'package:balkavach_admin/core/session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = String.fromEnvironment('LIVE_API_BASE_URL');
const _email = String.fromEnvironment('LIVE_ADMIN_EMAIL');
const _password = String.fromEnvironment('LIVE_ADMIN_PASSWORD');

void main() {
  final skip = (_base.isEmpty || _email.isEmpty || _password.isEmpty)
      ? 'set LIVE_API_BASE_URL, LIVE_ADMIN_EMAIL and LIVE_ADMIN_PASSWORD'
      : null;

  test(
    'the panel signs in and reads every section from a real server',
    () async {
      final tokens = TokenStore();
      final container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          dioProvider.overrideWithValue(createDio(tokens, baseUrl: _base)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionProvider.notifier).signIn(_email, _password);
      final session = container.read(sessionProvider)!;
      expect(session.can('users:write'), isTrue);

      final api = container.read(adminApiProvider);
      expect(await api.getMap('/api/v1/admin/dashboard'), contains('users'));
      expect(
        await api.getMap(
          '/api/v1/admin/analytics/overview',
          query: {'days': 7},
        ),
        contains('daily'),
      );
      for (final path in [
        '/api/v1/admin/users',
        '/api/v1/admin/families',
        '/api/v1/admin/tasks',
        '/api/v1/admin/rewards',
        '/api/v1/admin/redemptions',
        '/api/v1/admin/task-categories',
        '/api/v1/admin/preset-tasks',
        '/api/v1/admin/badges',
        '/api/v1/admin/educational-content',
        '/api/v1/admin/settings',
        '/api/v1/admin/audit-logs',
        '/api/v1/admin/roles',
      ]) {
        expect(
          await api.getList(path),
          isA<List<Map<String, dynamic>>>(),
          reason: path,
        );
      }

      // A change round-trips and is audited.
      final created = await api.post('/api/v1/admin/preset-tasks', {
        'title': 'Live preset ${DateTime.now().microsecondsSinceEpoch}',
      });
      final updated = await api.patch(
        '/api/v1/admin/preset-tasks/${created['id']}',
        {'is_active': false},
      );
      expect(updated['is_active'], isFalse);
      final audit = await api.getList(
        '/api/v1/admin/audit-logs',
        query: {'limit': 20},
      );
      expect(
        audit.map((row) => row['action']),
        contains('preset_task.updated'),
      );

      // Wrong credentials are refused.
      await expectLater(
        container
            .read(sessionProvider.notifier)
            .signIn(_email, 'definitely-wrong'),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
      );

      await container.read(sessionProvider.notifier).signOut();
      expect(container.read(sessionProvider), isNull);
      await expectLater(
        api.getMap('/api/v1/admin/dashboard'),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
      );
    },
    skip: skip,
  );
}
