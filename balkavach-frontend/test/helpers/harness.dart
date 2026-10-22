import 'package:balkavach_app/core/network/access_token_store.dart';
import 'package:balkavach_app/core/network/api_client.dart';
import 'package:balkavach_app/core/storage/app_preferences.dart';
import 'package:balkavach_app/core/theme/app_theme.dart';
import 'package:balkavach_app/features/authentication/data/session_storage.dart';
import 'package:balkavach_app/features/authentication/domain/session.dart';
import 'package:balkavach_app/features/authentication/presentation/session_controller.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_backend.dart';
import 'fixtures.dart';

/// Everything a test needs to run real providers against a fake backend.
class Harness {
  Harness._(this.backend, this.prefs, this.storage);

  static Future<Harness> create({
    Session? session,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final shared = await SharedPreferences.getInstance();
    final harness = Harness._(
      FakeBackend(),
      AppPreferences(shared),
      InMemorySessionStorage(session),
    );
    harness.backend
      ..reply('GET', '/health', {'status': 'ok'})
      ..reply('GET', '/ready', {'status': 'ready'})
      ..reply(
        'GET',
        '/api/v1/auth/me',
        (session?.user ?? Fx.parentSession().user).toJson(),
      )
      ..reply('GET', '/api/v1/families', [Fx.family()])
      ..reply('GET', '/api/v1/families/${Fx.familyId}/children', [Fx.child()])
      ..reply(
        'GET',
        '/api/v1/settings/families/${Fx.familyId}/consents',
        <Object?>[],
      )
      ..reply('GET', '/api/v1/tasks/categories', [Fx.category()])
      ..reply('GET', '/api/v1/tasks', [
        Fx.task(),
        Fx.task(
          id: Fx.task2Id,
          title: 'Play Outdoors or Yoga',
          stars: 15,
          categoryId: null,
        ),
      ])
      ..reply('GET', '/api/v1/notifications', <Object?>[])
      ..reply('GET', '/api/v1/progress/children/${Fx.childId}', Fx.progress())
      ..reply('GET', '/api/v1/educational-content', <Object?>[])
      ..reply('GET', '/api/v1/videos/categories', <Object?>[])
      ..reply('GET', '/api/v1/learning-gate/today', Fx.learningGate());
    return harness;
  }

  final FakeBackend backend;
  final AppPreferences prefs;
  final InMemorySessionStorage storage;

  List<Override> get overrides => [
    clockProvider.overrideWithValue(() => Fx.now),
    appPreferencesProvider.overrideWithValue(prefs),
    sessionStorageProvider.overrideWithValue(storage),
    apiDioProvider.overrideWith(
      (ref) => createTestDio(backend, ref.watch(accessTokenStoreProvider)),
    ),
  ];

  ProviderContainer container() {
    final container = ProviderContainer(
      overrides: overrides,
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    return container;
  }
}

/// Prefs for a device that finished onboarding.
const onboardedPrefs = <String, Object>{
  'app.language_code': 'en',
  'onboarding.consent_version': '2026-10-draft',
};

/// Sets a logical window size (DPR 1) for the rest of the test.
void setWindow(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Pumps [child] inside the app theme and localizations.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  required List<Override> overrides,
  Size size = const Size(393, 852),
  double textScale = 1,
  Locale locale = const Locale('en'),
  bool settle = true,
}) async {
  setWindow(tester, size);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      retry: (_, _) => null,
      child: MaterialApp(
        theme: buildAppTheme(),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: child,
      ),
    ),
  );
  // Screens with endless animations (spinners) never settle.
  settle
      ? await tester.pumpAndSettle()
      : await tester.pump(const Duration(milliseconds: 100));
}
