import 'package:balkavach_app/app.dart';
import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/features/onboarding/presentation/onboarding_controller.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:balkavach_app/shared/widgets/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

Future<void> _pumpApp(WidgetTester tester, Harness h) async {
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

void main() {
  test('English is used when nothing is saved', () async {
    final h = await Harness.create();
    expect(h.container().read(appLocaleProvider), const Locale('en'));
  });

  test('invalid stored language falls back to English', () async {
    final h = await Harness.create(prefs: {'app.language_code': 'xx'});
    final c = h.container();
    expect(c.read(appLocaleProvider), const Locale('en'));
    expect(c.read(onboardingControllerProvider).languageChosen, isFalse);
  });

  for (final code in ['hi', 'gu']) {
    test('$code is applied and persisted', () async {
      final h = await Harness.create();
      final c = h.container();
      await c.read(onboardingControllerProvider.notifier).chooseLanguage(code);
      expect(c.read(appLocaleProvider), Locale(code));
      expect(h.prefs.languageCode, code);

      // A fresh container (app restart) restores it.
      expect(h.container().read(appLocaleProvider), Locale(code));
    });
  }

  test('unsupported language is rejected', () async {
    final h = await Harness.create();
    expect(
      () => h
          .container()
          .read(onboardingControllerProvider.notifier)
          .chooseLanguage('fr'),
      throwsArgumentError,
    );
  });

  testWidgets('switching language updates the app and survives navigation', (
    tester,
  ) async {
    final h = await Harness.create(prefs: {'app.language_code': 'en'});
    await _pumpApp(tester, h);
    final en = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
    expect(find.text(en.consentTitle), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    await container
        .read(onboardingControllerProvider.notifier)
        .chooseLanguage('hi');
    await tester.pumpAndSettle();
    final hi = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
    expect(hi.localeName, 'hi');
    expect(find.text(hi.consentTitle), findsOneWidget);
    expect(find.text(en.consentTitle), findsNothing);
  });

  test('error messages and server field errors are localized', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(describeError(l10n, const NetworkException()), l10n.errorNetwork);
      expect(
        describeError(
          l10n,
          const UnknownApiException(message: 'raw backend text'),
        ),
        isNot(contains('raw backend text')),
      );
    }
  });
}
