import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _placeholders(String message) => {
  for (final m in RegExp(r'\{(\w+)[,}]').allMatches(message)) m.group(1)!,
};

/// Strings that are legitimately the same in every language (units, brand).
const _sameInAllLanguages = {'missionXpCount'};

void main() {
  final en = _arb('en');
  final keys = [
    for (final key in en.keys)
      if (!key.startsWith('@')) key,
  ];

  for (final lang in ['gu', 'hi']) {
    group('$lang translations', () {
      final data = _arb(lang);

      test('define every key the English file defines', () {
        expect([
          for (final k in keys)
            if (!data.containsKey(k)) k,
        ], isEmpty);
      });

      test('define no keys the English file lacks', () {
        expect([
          for (final k in data.keys)
            if (!k.startsWith('@') && !en.containsKey(k)) k,
        ], isEmpty);
      });

      test('are not empty', () {
        expect([
          for (final k in keys)
            if ((data[k] as String).trim().isEmpty) k,
        ], isEmpty);
      });

      test('use the same placeholders as English', () {
        expect([
          for (final k in keys)
            if (!_placeholders(
                  en[k] as String,
                ).containsAll(_placeholders(data[k] as String)) ||
                !_placeholders(
                  data[k] as String,
                ).containsAll(_placeholders(en[k] as String)))
              k,
        ], isEmpty);
      });

      test('are not silent copies of the English text', () {
        final copies = [
          for (final k in keys)
            if (data[k] == en[k] &&
                RegExp('[A-Za-z]{3}').hasMatch(en[k] as String) &&
                !_sameInAllLanguages.contains(k))
              k,
        ];
        expect(copies, isEmpty, reason: 'untranslated: $copies');
      });
    });
  }

  test('there are no hard-coded user-facing strings in widgets', () {
    // Visible text must come from AppLocalizations. Interpolated semantic
    // labels and internal exception messages are not user-facing copy.
    final literal = RegExp(
      r'''(?:Text\(|tooltip:|semanticLabel:|label:|labelText:|hintText:|helperText:|message:)\s*(?:const\s+)?['"][^'"$]*[A-Za-z]{3}''',
    );
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      if (path.contains('/l10n/')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final insideException =
            line.contains('Exception(') ||
            (i > 0 && lines[i - 1].contains('Exception('));
        if (literal.hasMatch(line) && !insideException) {
          offenders.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
