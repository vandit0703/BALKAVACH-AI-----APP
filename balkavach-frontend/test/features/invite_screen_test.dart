// Invite other parents: WhatsApp link, share sheet, the card picture and the
// privacy rule. System share sheet and WhatsApp are FAKES here; whether they
// open on a real phone is still to be checked on a device.

import 'dart:typed_data';

import 'package:balkavach_app/features/sharing/data/card_sharer.dart';
import 'package:balkavach_app/features/sharing/presentation/invite_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:balkavach_app/shared/platform/link_opener.dart';
import 'package:balkavach_app/shared/platform/text_sharer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

class _Opener implements LinkOpener {
  _Opener({this.opens = true});

  final bool opens;
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return opens;
  }
}

class _Text implements TextSharer {
  _Text({this.ok = true});

  final bool ok;
  final shared = <String>[];

  @override
  Future<bool> share(String text, {String? subject}) async {
    shared.add(text);
    return ok;
  }
}

class _Card implements CardSharer {
  final images = <Uint8List>[];
  final texts = <String>[];

  @override
  Future<bool> shareImage(Uint8List png, {required String text}) async {
    images.add(png);
    texts.add(text);
    return true;
  }
}

Future<(_Opener, _Text, _Card)> _pump(
  WidgetTester tester, {
  _Opener? opener,
  _Text? text,
  _Card? card,
  String url = '',
  Size size = const Size(393, 852),
  double scale = 1,
  Locale locale = const Locale('en'),
}) async {
  final o = opener ?? _Opener();
  final t = text ?? _Text();
  final c = card ?? _Card();
  await pumpScreen(
    tester,
    InviteScreen(url: url),
    overrides: [
      linkOpenerProvider.overrideWithValue(o),
      textSharerProvider.overrideWithValue(t),
      cardSharerProvider.overrideWithValue(c),
    ],
    size: size,
    textScale: scale,
    locale: locale,
  );
  return (o, t, c);
}

void main() {
  testWidgets('WhatsApp opens the share link with the localized message', (
    tester,
  ) async {
    final (opener, text, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('invite.whatsapp')));
    await tester.pumpAndSettle();
    expect(opener.opened, hasLength(1));
    final uri = opener.opened.single;
    expect(uri.host, 'wa.me');
    expect(uri.queryParameters['text'], contains('Bal Kavach'));
    expect(text.shared, isEmpty);
  });

  testWidgets('if WhatsApp cannot open, the system share sheet is used', (
    tester,
  ) async {
    final (_, text, _) = await _pump(tester, opener: _Opener(opens: false));
    await tester.tap(find.byKey(const Key('invite.whatsapp')));
    await tester.pumpAndSettle();
    expect(text.shared, hasLength(1));
  });

  testWidgets('a configured link is added to the message; none is invented', (
    tester,
  ) async {
    final (_, text, _) = await _pump(tester, url: 'https://example.org/get');
    await tester.tap(find.byKey(const Key('invite.share')));
    await tester.pumpAndSettle();
    expect(text.shared.single, endsWith('\nhttps://example.org/get'));

    final (_, noLink, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('invite.share')));
    await tester.pumpAndSettle();
    expect(noLink.shared.single, isNot(contains('http')));
  });

  testWidgets('sharing the card produces a real PNG', (tester) async {
    final (_, _, card) = await _pump(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('invite.shareImage')));
      // Real image encoding: wait for the result, not a fixed time.
      for (var i = 0; i < 100 && card.images.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();
    expect(card.images, hasLength(1));
    expect(card.images.single.take(4), [
      0x89,
      0x50,
      0x4E,
      0x47,
    ], reason: 'PNG signature');
  });

  testWidgets('a share that cannot open says so', (tester) async {
    await _pump(tester, text: _Text(ok: false));
    await tester.tap(find.byKey(const Key('invite.share')));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t open sharing.'), findsOneWidget);
  });

  testWidgets('the card and message contain nothing about a child', (
    tester,
  ) async {
    final (_, text, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('invite.share')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invite.privacy')), findsOneWidget);
    final lower = text.shared.single.toLowerCase();
    for (final word in ['age', 'years old', 'streak', 'stars']) {
      expect(lower, isNot(contains(word)), reason: word);
    }
  });

  for (final (size, scale, locale) in [
    (const Size(320, 568), 2.0, const Locale('en')),
    (const Size(360, 640), 1.0, const Locale('hi')),
    (const Size(390, 844), 2.0, const Locale('gu')),
    (const Size(740, 360), 1.0, const Locale('en')),
    (const Size(820, 1180), 1.0, const Locale('en')),
  ]) {
    testWidgets('fits $size @ ${scale}x in $locale', (tester) async {
      await _pump(tester, size: size, scale: scale, locale: locale);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const Key('invite.whatsapp')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('invite.whatsapp')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('supported locales include the three product languages', () {
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode),
      containsAll(['en', 'hi', 'gu']),
    );
  });
}
