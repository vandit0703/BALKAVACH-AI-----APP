// Parent screen for Talk to Panda microphone consent. Verified against a FAKE
// BACKEND (test/helpers/fake_backend.dart); the endpoints themselves are
// tested in balkavach-backend/tests/test_panda_voice_consent.py (SQLite).

import 'dart:convert';

import 'package:balkavach_app/features/companion/data/panda_voice_consent_repository.dart';
import 'package:balkavach_app/features/companion/presentation/panda_voice_consent_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _path =
    '/api/v1/settings/families/${Fx.familyId}/children/${Fx.childId}/panda-voice-consent';

Map<String, Object?> _status(bool granted) => {
  'child_id': Fx.childId,
  'granted': granted,
  'granted_at': granted ? '2026-11-20T10:00:00Z' : null,
  'granted_by': granted ? Fx.parentUserId : null,
  'document_version': kPandaVoiceConsentVersion,
};

Map<String, dynamic> _body(RequestOptions r) => r.data is String
    ? jsonDecode(r.data as String) as Map<String, dynamic>
    : (r.data as Map).cast<String, dynamic>();

Future<Harness> _pump(
  WidgetTester tester, {
  bool granted = false,
  bool child = false,
  FakeReply Function(RequestOptions)? put,
  Locale locale = const Locale('en'),
}) async {
  final h = await Harness.create(
    session: child ? Fx.childSession() : Fx.parentSession(),
    prefs: onboardedPrefs,
  );
  var current = granted;
  h.backend
    ..on('GET', _path, (_) => FakeReply(200, _status(current)))
    ..on(
      'PUT',
      _path,
      put ??
          (r) {
            current = _body(r)['granted'] as bool;
            return FakeReply(200, _status(current));
          },
    );
  await pumpScreen(
    tester,
    const PandaVoiceConsentScreen(),
    overrides: h.overrides,
    locale: locale,
  );
  await tester.pumpAndSettle();
  return h;
}

Finder get _switch =>
    find.byKey(const Key('pandaConsent.switch.${Fx.childId}'));

void main() {
  testWidgets('explains the speech service honestly before anything is on', (
    tester,
  ) async {
    await _pump(tester);
    final disclosure = find.byKey(const Key('pandaConsent.disclosure'));
    expect(disclosure, findsOneWidget);
    expect(find.textContaining('Google'), findsOneWidget);
    expect(find.textContaining('keeps no recording'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(_switch).value, isFalse);
  });

  testWidgets('turning it on needs the parent to agree in a dialog, and sends '
      'the consent-text version shown', (tester) async {
    final h = await _pump(tester);

    await tester.tap(_switch);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pandaConsent.confirm')), findsOneWidget);

    // "Not now" changes nothing.
    await tester.tap(find.byKey(const Key('pandaConsent.cancel')));
    await tester.pumpAndSettle();
    expect(h.backend.requestsTo('PUT', _path), isEmpty);

    await tester.tap(_switch);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pandaConsent.agree')));
    await tester.pumpAndSettle();

    final put = h.backend.requestsTo('PUT', _path).single;
    expect(_body(put), {
      'granted': true,
      'document_version': kPandaVoiceConsentVersion,
    });
    expect(tester.widget<SwitchListTile>(_switch).value, isTrue);
  });

  testWidgets('turning it off withdraws at once, without a dialog', (
    tester,
  ) async {
    final h = await _pump(tester, granted: true);

    await tester.tap(_switch);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pandaConsent.confirm')), findsNothing);
    expect(_body(h.backend.requestsTo('PUT', _path).single), {
      'granted': false,
    });
    expect(tester.widget<SwitchListTile>(_switch).value, isFalse);
    expect(find.textContaining('Microphone turned off'), findsOneWidget);
  });

  testWidgets('an outdated consent text is explained, not silently saved', (
    tester,
  ) async {
    await _pump(
      tester,
      put: (_) => FakeReply.error(409, 'consent_version_outdated', 'changed'),
    );
    await tester.tap(_switch);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pandaConsent.agree')));
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.pandaConsentOutdated), findsOneWidget);
    expect(tester.widget<SwitchListTile>(_switch).value, isFalse);
  });

  testWidgets('a child never sees the switches', (tester) async {
    final h = await _pump(tester, child: true);
    expect(_switch, findsNothing);
    expect(h.backend.requestsTo('GET', _path), isEmpty);
  });

  for (final locale in const [Locale('hi'), Locale('gu')]) {
    testWidgets('localised (${locale.languageCode})', (tester) async {
      await _pump(tester, locale: locale);
      final l10n = lookupAppLocalizations(locale);
      expect(find.text(l10n.pandaConsentDisclosure), findsOneWidget);
      expect(find.text(l10n.pandaConsentOff), findsOneWidget);
    });
  }
}
