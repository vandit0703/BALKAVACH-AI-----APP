import 'dart:convert';
import 'dart:io';

import 'package:balkavach_app/features/onboarding/presentation/consent_screen.dart';
import 'package:balkavach_app/features/onboarding/presentation/welcome_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:balkavach_app/shared/widgets/brand_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

/// The only allowed spelling of the product name, in every language.
const _brand = 'BALKAVACH';

/// Every way of writing the name (any case, with or without a space, Latin,
/// Devanagari or Gujarati). A match is allowed only if it is exactly [_brand].
final _anySpelling = RegExp(
  r'bal\s*kavach|बाल\s*कवच|बालकवच|બાલ\s*કવચ|બાલકવચ',
  caseSensitive: false,
);

/// The retired "BALKAVACH AI" form, never allowed even in the exact casing.
final _withAiSuffix = RegExp(r'bal\s*kavach\s*AI\b', caseSensitive: false);

/// True when [text] spells the product name any way other than exactly
/// [_brand].
bool usesOldName(String text) =>
    _withAiSuffix.hasMatch(text) ||
    _anySpelling.allMatches(text).any((m) => m.group(0) != _brand);

void main() {
  const locales = ['en', 'gu', 'hi'];

  test('the old-name check accepts only the exact brand spelling', () {
    expect(usesOldName('Who is using BALKAVACH?'), isFalse);
    expect(usesOldName('BALKAVACH aims to help'), isFalse);
    for (final old in [
      'Bal Kavach',
      'BalKavach',
      'Balkavach',
      'balkavach',
      'BAL KAVACH',
      'BALKAVACH AI',
      'BalKavach AI',
      'बाल कवच',
      'बालकवच',
      'બાલ કવચ',
      'બાલકવચ',
    ]) {
      expect(usesOldName('Try $old today'), isTrue, reason: old);
    }
  });

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
              usesOldName(e.value as String))
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
