import 'package:balkavach_app/app.dart';
import 'package:balkavach_app/core/config/runtime_config.dart';
import 'package:balkavach_app/features/onboarding/presentation/onboarding_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

Map<String, Object?> _config({
  String version = '2027-01',
  String source = 'admin',
  bool maintenance = false,
  String message = '',
}) => {
  'consent_versions': {'parent_guardian_terms': version},
  'consent_source': source,
  'maintenance': {'enabled': maintenance, 'message': message},
};

void main() {
  test('parses the public configuration', () {
    final config = RuntimeConfig.fromJson(
      _config(maintenance: true, message: ' soon '),
    );
    expect(config.parentTermsVersion, '2027-01');
    expect(config.consentFromAdmin, isTrue);
    expect(config.maintenanceEnabled, isTrue);
    expect(config.maintenanceMessage, 'soon');
  });

  group('consent version', () {
    test('uses the built-in default until the server answers', () async {
      final h = await Harness.create();
      final container = h.container();
      expect(container.read(consentVersionProvider), kConsentDocumentVersion);
    });

    test(
      'adopts the server version and remembers it for offline use',
      () async {
        final h = await Harness.create();
        h.backend.reply('GET', '/api/v1/app-config', _config());
        final container = h.container();
        await container.read(runtimeConfigProvider.future);
        expect(container.read(consentVersionProvider), '2027-01');
        expect(h.prefs.currentConsentVersion, '2027-01');
      },
    );

    test('the request carries no credentials', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.reply('GET', '/api/v1/app-config', _config());
      await h.container().read(runtimeConfigProvider.future);
      expect(
        h.backend
            .requestsTo('GET', '/api/v1/app-config')
            .single
            .headers
            .containsKey('Authorization'),
        isFalse,
      );
    });

    test('offline keeps the last version this device saw', () async {
      final h = await Harness.create(
        prefs: {'config.consent_version': '2026-12'},
      );
      h.backend.on(
        'GET',
        '/api/v1/app-config',
        (_) => FakeReply.error(500, 'internal_error', 'x'),
      );
      final container = h.container();
      expect(await container.read(runtimeConfigProvider.future), isNull);
      expect(container.read(consentVersionProvider), '2026-12');
    });

    test('a newer version asks everyone to accept again', () async {
      final h = await Harness.create(
        prefs: {
          'app.language_code': 'en',
          'onboarding.consent_version': '2026-10-draft',
        },
      );
      h.backend.reply('GET', '/api/v1/app-config', _config(version: '2027-01'));
      final container = h.container();
      expect(
        container.read(onboardingControllerProvider).consentAcknowledged,
        isTrue,
      );

      await container.read(runtimeConfigProvider.future);
      expect(
        container.read(onboardingControllerProvider).consentAcknowledged,
        isFalse,
      );

      await container
          .read(onboardingControllerProvider.notifier)
          .acknowledgeConsent();
      expect(h.prefs.acknowledgedConsentVersion, '2027-01');
      expect(
        container.read(onboardingControllerProvider).consentAcknowledged,
        isTrue,
      );
    });
  });

  group('maintenance banner', () {
    Future<void> pump(WidgetTester tester, Harness h) async {
      setWindow(tester, const Size(393, 852));
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          retry: (_, _) => null,
          child: const BalKavachApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is shown with the administrator\'s message', (tester) async {
      final h = await Harness.create(prefs: onboardedPrefs);
      h.backend.reply(
        'GET',
        '/api/v1/app-config',
        _config(
          version: '2026-10-draft',
          maintenance: true,
          message: 'Back at 6 pm',
        ),
      );
      await pump(tester, h);
      expect(find.byKey(const Key('app.maintenance')), findsOneWidget);
      expect(find.text('Back at 6 pm'), findsOneWidget);
    });

    testWidgets('falls back to a default sentence', (tester) async {
      final h = await Harness.create(prefs: onboardedPrefs);
      h.backend.reply(
        'GET',
        '/api/v1/app-config',
        _config(version: '2026-10-draft', maintenance: true),
      );
      await pump(tester, h);
      expect(
        find.text(
          'Bal Kavach is being updated. Some things may not work for a while.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('is absent when maintenance is off', (tester) async {
      final h = await Harness.create(prefs: onboardedPrefs);
      h.backend.reply(
        'GET',
        '/api/v1/app-config',
        _config(version: '2026-10-draft'),
      );
      await pump(tester, h);
      expect(find.byKey(const Key('app.maintenance')), findsNothing);
    });
  });
}
