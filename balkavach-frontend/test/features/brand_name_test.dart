import 'dart:convert';
import 'dart:io';

import 'package:balkavach_app/features/onboarding/presentation/consent_screen.dart';
import 'package:balkavach_app/features/onboarding/presentation/welcome_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:balkavach_app/shared/widgets/brand_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

/// Old product-name spellings that must never be shown again.
final _oldNames = RegExp(
  r'bal\s*kavach|बाल\s*कवच|बालकवच|બાલ\s*કવચ|બાલકવચ|BALKAVACH\s*AI',
  caseSensitive: false,
);

void main() {
  const locales = ['en', 'gu', 'hi'];

  for (final code in locales) {
    test('$code: the app name is exactly BALKAVACH', () {
      final l10n = lookupAppLocalizations(Locale(code));
      expect(l10n.appTitle, 'BALKAVACH');
      expect(l10n.brandName, 'BALKAVACH');
    });

    test('$code: no translation uses an old product-name spelling', () {
      final arb =
          jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync())
              as Map<String, dynamic>;
      final offenders = <String>[
        for (final e in arb.entries)
          if (e.value is String &&
              !e.key.startsWith('@') &&
              (_oldNames.hasMatch(e.value as String) ||
                  // The exact all-caps name must not be lower-cased/mixed.
                  RegExp(r'balkavach', caseSensitive: false)
                      .allMatches(e.value as String)
                      .any((m) => m.group(0) != 'BALKAVACH')))
            e.key,
      ];
      expect(offenders, isEmpty);
    });
  }

  for (final code in locales) {
    testWidgets('$code: welcome wordmark shows BALKAVACH with no suffix', (
      tester,
    ) async {
      final h = await Harness.create();
      await pumpScreen(
        tester,
        const WelcomeScreen(),
        overrides: h.overrides,
        locale: Locale(code),
      );
      expect(find.text('BALKAVACH'), findsWidgets);
      expect(find.textContaining('BALKAVACH AI'), findsNothing);
    });

    testWidgets('$code: consent screen shows the approved BALKAVACH logo', (
      tester,
    ) async {
      final h = await Harness.create();
      await pumpScreen(
        tester,
        const ConsentScreen(),
        overrides: h.overrides,
        size: const Size(320, 640),
        locale: Locale(code),
      );
      expect(find.byType(BrandLogo), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Image && w.semanticLabel == brandLogoLabel,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
