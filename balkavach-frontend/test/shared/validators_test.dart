import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:balkavach_app/shared/validation/validators.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final v = Validators(l10n);

  test('email', () {
    expect(v.email('priya@example.com'), isNull);
    expect(v.email('  priya@example.com '), isNull);
    expect(v.email('priya'), l10n.validationEmailInvalid);
    expect(v.email(''), l10n.validationEmailInvalid);
  });

  test('new password mirrors backend 12–128', () {
    expect(v.newPassword(''), l10n.validationPasswordRequired);
    expect(v.newPassword('a' * 11), l10n.validationPasswordTooShort);
    expect(v.newPassword('a' * 12), isNull);
    expect(v.newPassword('a' * 129), l10n.validationTooLong(128));
  });

  test('login password only requires a value', () {
    expect(v.loginPassword('x'), isNull);
    expect(v.loginPassword(''), l10n.validationPasswordRequired);
  });

  test('names respect each schema minimum', () {
    expect(v.fullName('A'), l10n.validationNameTooShort);
    expect(v.fullName('Al'), isNull);
    expect(v.childName('A'), isNull, reason: 'display_name min is 1');
    expect(v.childName('   '), l10n.validationNameRequired);
    expect(v.childName('a' * 101), l10n.validationTooLong(100));
    expect(v.missionTitle('A'), l10n.validationNameTooShort);
  });

  test('integer ranges', () {
    expect(v.intRange('', min: 0, max: 10), isNull);
    expect(v.intRange('5', min: 0, max: 10), isNull);
    expect(
      v.intRange('11', min: 0, max: 10),
      l10n.validationNumberRange(0, 10),
    );
    expect(v.intRange('x', min: 0, max: 10), l10n.validationNumberRange(0, 10));
  });
}
