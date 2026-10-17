import 'dart:convert';
import 'dart:io';

import 'package:balkavach_admin/app.dart';
import 'package:balkavach_admin/core/api.dart';
import 'package:balkavach_admin/core/locale.dart';
import 'package:balkavach_admin/l10n/app_localizations.dart';
import 'package:balkavach_admin/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

Map<String, dynamic> _arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _placeholders(String message) => {
  for (final m in RegExp(r'\{(\w+)\}').allMatches(message)) m.group(1)!,
};

/// One plausible row for every list the panel shows.
FakeServer _populated() {
  const id = '11111111-1111-4111-8111-111111111111';
  return baseServer()
    ..reply('GET', '/health', {'status': 'ok'})
    ..reply('GET', '/ready', {'status': 'ready'})
    ..reply('GET', '/api/v1/admin/users', [
      {
        'id': id,
        'full_name': 'Priya Parent',
        'email': 'priya@example.com',
        'role': 'parent',
        'is_active': true,
        'created_at': '2026-10-01T10:00:00Z',
        'last_login_at': '2026-10-02T10:00:00Z',
      },
    ])
    ..reply('GET', '/api/v1/admin/families', [
      {
        'id': id,
        'family_name': 'Patel family',
        'parent_count': 2,
        'child_count': 1,
        'active_task_count': 3,
        'created_at': '2026-10-01T10:00:00Z',
      },
    ])
    ..reply('GET', '/api/v1/admin/tasks', [
      {
        'id': id,
        'title': 'Read a book',
        'family_name': 'Patel family',
        'category_name': 'Learning',
        'assigned_child_name': null,
        'star_reward': 2,
        'xp_reward': 10,
        'is_active': true,
      },
    ])
    ..reply('GET', '/api/v1/admin/task-categories', [
      {
        'id': id,
        'name': 'Learning',
        'description': 'Books and puzzles',
        'icon_name': 'book-open',
        'is_active': true,
      },
    ])
    ..reply('GET', '/api/v1/admin/preset-tasks', [
      {
        'id': id,
        'title': 'Water the plants',
        'category_name': 'Home',
        'language_code': 'hi',
        'suggested_star_reward': 1,
        'suggested_xp_reward': 10,
        'age_min': 3,
        'age_max': 17,
        'is_active': true,
      },
    ])
    ..reply('GET', '/api/v1/admin/rewards', [
      {
        'id': id,
        'name': 'Ice cream',
        'family_name': 'Patel family',
        'reward_type': 'treat',
        'star_cost': 5,
        'is_active': true,
      },
    ])
    ..reply('GET', '/api/v1/admin/redemptions', [
      {
        'id': id,
        'reward_name': 'Ice cream',
        'child_name': 'Aarav',
        'family_name': 'Patel family',
        'star_cost_at_request': 5,
        'status': 'pending',
        'requested_at': '2026-10-01T10:00:00Z',
      },
    ])
    ..reply('GET', '/api/v1/admin/educational-content', [
      {
        'id': id,
        'title': 'Counting song',
        'content_type': 'video',
        'language_code': 'gu',
        'content_url': 'https://example.com/a/very/long/path/to/a/video',
        'is_active': true,
      },
    ])
    ..reply('GET', '/api/v1/admin/badges', [
      {
        'id': id,
        'name': 'First mission',
        'criteria_type': 'approved_tasks',
        'criteria_value': {'threshold': 1},
        'is_active': true,
      },
    ])
    ..reply('GET', '/api/v1/admin/audit-logs', [
      {
        'created_at': '2026-10-01T10:00:00Z',
        'action': 'user.deactivate',
        'entity_type': 'user',
        'actor_user_id': id,
      },
    ])
    ..reply('GET', '/api/v1/admin/settings', [
      {
        'key': 'maintenance',
        'value': {'enabled': true, 'message': 'Back soon'},
        'overridden': true,
      },
    ]);
}

Future<void> _go(
  WidgetTester tester,
  ProviderContainer container,
  String path,
) async {
  container.read(routerProvider).go(path);
  await tester.pumpAndSettle();
}

void main() {
  group('translation files', () {
    final en = _arb('en');
    final keys = [
      for (final k in en.keys)
        if (!k.startsWith('@')) k,
    ];
    for (final lang in ['hi', 'gu']) {
      final data = _arb(lang);
      test('$lang defines exactly the keys English defines', () {
        expect([
          for (final k in data.keys)
            if (!k.startsWith('@') && !en.containsKey(k)) k,
        ], isEmpty);
        expect([
          for (final k in keys)
            if (!data.containsKey(k)) k,
        ], isEmpty);
      });
      test('$lang values are filled in, use the same placeholders and are '
          'not copies of the English text', () {
        final problems = <String>[];
        for (final k in keys.where((k) => k != '@@locale')) {
          final text = data[k] as String;
          final english = en[k] as String;
          if (text.trim().isEmpty) problems.add('$k is empty');
          if (!_placeholders(text).containsAll(_placeholders(english)) ||
              !_placeholders(english).containsAll(_placeholders(text))) {
            problems.add('$k has different placeholders');
          }
          if (text == english && RegExp('[A-Za-z]{3}').hasMatch(english)) {
            problems.add('$k is untranslated');
          }
        }
        expect(problems, isEmpty);
      });
    }

    test('no widget builds user-facing text from a string literal', () {
      final literal = RegExp(
        r'''(?:Text\(|tooltip:|semanticLabel:|label:|labelText:|hintText:|helperText:|title:|subtitle:|message:|child: const Text\()\s*(?:const\s+)?['"][^'"$]*[A-Za-z]{3}''',
      );
      final offenders = <String>[];
      for (final dir in ['lib/pages', 'lib/ui']) {
        for (final file in Directory(dir).listSync(recursive: true)) {
          if (file is! File || !file.path.endsWith('.dart')) continue;
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (literal.hasMatch(lines[i])) {
              offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('language', () {
    testWidgets('English is used when nothing is saved', (tester) async {
      await pumpAdmin(tester, _populated(), signedIn: false);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('an invalid saved language falls back to English', (
      tester,
    ) async {
      await pumpAdmin(
        tester,
        _populated(),
        signedIn: false,
        storedPrefs: {'admin.language_code': 'xx'},
      );
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('a saved language is restored on start', (tester) async {
      await pumpAdmin(
        tester,
        _populated(),
        signedIn: false,
        storedPrefs: {'admin.language_code': 'gu'},
      );
      expect(find.text('સાઇન ઇન કરો'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
    });

    testWidgets('choosing a language updates every screen immediately and '
        'is remembered', (tester) async {
      final container = await pumpAdmin(tester, _populated());
      expect(find.text('Dashboard'), findsWidgets);

      await tapKey(tester, 'language.menu');
      await tapKey(tester, 'language.hi');
      expect(find.text('डैशबोर्ड'), findsWidgets);
      expect(find.text('उपयोगकर्ता'), findsWidgets);
      expect(find.text('Users'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('admin.language_code'), 'hi');

      // Navigating keeps the language, and a table is localized too.
      await _go(tester, container, '/users');
      expect(find.text('नाम या ईमेल खोजें'), findsOneWidget);
      expect(find.text('सक्रिय'), findsWidgets);

      // Still signed in: the language change does not touch the session.
      expect(find.byKey(const Key('account.menu')), findsOneWidget);

      // Signing out leaves the sign-in page in the chosen language.
      await tapKey(tester, 'account.menu');
      await tester.tap(find.text('साइन आउट करें'));
      await tester.pumpAndSettle();
      expect(find.text('साइन इन करें'), findsOneWidget);
    });

    testWidgets('the settings page switches language', (tester) async {
      final container = await pumpAdmin(tester, _populated());
      await _go(tester, container, '/settings');
      await tapKey(tester, 'settings.language.gu');
      expect(container.read(localeProvider), const Locale('gu'));
      expect(find.text('સેટિંગ'), findsWidgets);
    });

    testWidgets('errors and the permission message follow the language', (
      tester,
    ) async {
      final server = _populated()
        ..on(
          'GET',
          '/api/v1/admin/users',
          (_) => Reply.error(403, 'forbidden', 'no'),
        );
      final container = await pumpAdmin(
        tester,
        server,
        storedPrefs: {'admin.language_code': 'hi'},
      );
      await _go(tester, container, '/users');
      expect(find.text('आपको यह करने की अनुमति नहीं है।'), findsOneWidget);
      expect(
        find.byKey(const Key('error.retry')),
        findsNothing,
        reason: 'a permission problem is not fixed by retrying',
      );
    });

    testWidgets('form validation is localized', (tester) async {
      final container = await pumpAdmin(
        tester,
        _populated(),
        storedPrefs: {'admin.language_code': 'gu'},
      );
      await _go(tester, container, '/categories');
      await tapKey(tester, 'categories.add');
      await tapKey(tester, 'form.submit');
      expect(find.text('જરૂરી'), findsOneWidget);
    });
  });

  group('layouts in every language', () {
    const paths = [
      '/',
      '/users',
      '/families',
      '/missions',
      '/categories',
      '/presets',
      '/rewards',
      '/redemptions',
      '/content',
      '/badges',
      '/settings',
      '/audit',
    ];
    for (final lang in ['en', 'hi', 'gu']) {
      for (final size in const [
        Size(360, 740),
        Size(768, 1024),
        Size(1024, 768),
        Size(1440, 900),
      ]) {
        testWidgets('$lang at ${size.width.toInt()} px: every page lays out '
            'without overflow', (tester) async {
          final container = await pumpAdmin(
            tester,
            _populated(),
            size: size,
            storedPrefs: {'admin.language_code': lang},
          );
          for (final path in paths) {
            await _go(tester, container, path);
            expect(tester.takeException(), isNull, reason: '$path at $size');
          }
        });
      }
    }

    testWidgets('a table is a card list on a phone and a table on a desktop', (
      tester,
    ) async {
      final phone = await pumpAdmin(
        tester,
        _populated(),
        size: const Size(400, 800),
      );
      await _go(tester, phone, '/users');
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Priya Parent'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('a desktop shows a persistent sidebar and breadcrumb', (
      tester,
    ) async {
      final container = await pumpAdmin(tester, _populated());
      await _go(tester, container, '/users');
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.byKey(const Key('nav./users')), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);
    });
  });

  group('dashboard', () {
    testWidgets('shows live system status from the health endpoints', (
      tester,
    ) async {
      await pumpAdmin(tester, _populated());
      expect(find.byKey(const Key('system.status')), findsOneWidget);
      expect(find.text('Available'), findsNWidgets(2));
    });

    testWidgets('reports an unavailable service instead of hiding it', (
      tester,
    ) async {
      final server = _populated()
        ..on(
          'GET',
          '/ready',
          (_) => Reply.error(503, 'http_error', 'Database is unavailable'),
        );
      await pumpAdmin(tester, server);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
    });

    testWidgets('a card opens the page it counts', (tester) async {
      await pumpAdmin(tester, _populated());
      await tapKey(tester, 'tile.redemptions');
      expect(find.byKey(const Key('redemptions.status')), findsOneWidget);
    });

    testWidgets('cards are not links when the page is not permitted', (
      tester,
    ) async {
      await pumpAdmin(
        tester,
        baseServer(permissions: ['dashboard:read'], roles: ['viewer'])
          ..reply('GET', '/health', {'status': 'ok'}),
      );
      await tester.tap(find.byKey(const Key('tile.users')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tile.users')), findsOneWidget);
      expect(find.byKey(const Key('users.search')), findsNothing);
    });

    testWidgets('a failed load offers a retry that works', (tester) async {
      var calls = 0;
      final server = _populated()
        ..on('GET', '/api/v1/admin/dashboard', (_) {
          calls++;
          return calls == 1
              ? Reply.error(500, 'internal_error', 'boom')
              : const Reply(200, dashboardBody);
        });
      await pumpAdmin(tester, server);
      expect(find.byKey(const Key('error.message')), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
      await tapKey(tester, 'error.retry');
      expect(find.byKey(const Key('tile.users')), findsOneWidget);
    });
  });

  test('an unsupported language is refused', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(localeProvider.notifier).choose('fr'),
      throwsArgumentError,
    );
  });

  test(
    'every HTTP failure class has localized text in every language',
    () async {
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = await AppLocalizations.delegate.load(locale);
        final texts = <int, String>{
          for (final status in [0, 401, 403, 404, 409, 422, 429, 500, 503])
            status: describeError(
              l10n,
              ApiError(status, 'unmapped', 'raw English from the server'),
            ),
        };
        expect(texts[0], l10n.errorNetwork);
        expect(texts[401], l10n.errorSessionExpired);
        expect(texts[403], l10n.errorForbidden);
        expect(texts[404], l10n.errorNotFound);
        expect(texts[409], l10n.errorConflict);
        expect(texts[422], l10n.errorValidation);
        expect(texts[429], l10n.errorTooManyRequests);
        expect(texts[500], l10n.errorServer);
        expect(texts[503], l10n.errorServer);
        expect(
          texts.values.any((t) => t.contains('raw English')),
          isFalse,
          reason: 'raw server text must never reach the screen',
        );
      }
    },
  );
}
