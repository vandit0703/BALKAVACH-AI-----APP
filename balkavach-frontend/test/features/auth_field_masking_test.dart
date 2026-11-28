import 'package:balkavach_app/features/authentication/presentation/forgot_password_screen.dart';
import 'package:balkavach_app/features/authentication/presentation/parent_auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

/// Email inputs must always show what was typed; only passwords are masked.
/// Regression: switching to "Create account" inserts the name field above the
/// email field, and the email field used to inherit the password field's
/// hidden state.
bool _masked(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      ),
    )
    .obscureText;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _expectSignIn(WidgetTester tester) {
  expect(_masked(tester, 'auth.email'), isFalse, reason: 'email visible');
  expect(_masked(tester, 'auth.password'), isTrue, reason: 'password hidden');
}

void _expectRegister(WidgetTester tester) {
  expect(_masked(tester, 'auth.name'), isFalse, reason: 'name visible');
  expect(_masked(tester, 'auth.email'), isFalse, reason: 'email visible');
  expect(_masked(tester, 'auth.password'), isTrue, reason: 'password hidden');
}

void main() {
  testWidgets('email stays readable and password masked across tab switches', (
    tester,
  ) async {
    final h = await Harness.create(prefs: onboardedPrefs);
    await pumpScreen(tester, const ParentAuthScreen(), overrides: h.overrides);
    await tester.enterText(
      find.byKey(const Key('auth.email')),
      'parent@example.com',
    );

    _expectSignIn(tester);
    await _tap(tester, find.text('Create account').first);
    _expectRegister(tester);
    expect(find.text('parent@example.com'), findsOneWidget);
    await _tap(tester, find.text('Sign in').first);
    _expectSignIn(tester);
    await _tap(tester, find.text('Create account').first);
    _expectRegister(tester);
  });

  testWidgets('show/hide password still works after switching tabs', (
    tester,
  ) async {
    final h = await Harness.create(prefs: onboardedPrefs);
    await pumpScreen(tester, const ParentAuthScreen(), overrides: h.overrides);
    await _tap(tester, find.text('Create account').first);

    final toggle = find.descendant(
      of: find.byKey(const Key('auth.password')),
      matching: find.byType(IconButton),
    );
    // The toggle sits beside the field, inside the same AppTextField.
    final passwordToggle = toggle.evaluate().isNotEmpty
        ? toggle
        : find.byTooltip('Show password');
    await _tap(tester, passwordToggle.first);
    expect(_masked(tester, 'auth.password'), isFalse);
    expect(_masked(tester, 'auth.email'), isFalse);

    // Switching tabs keeps the parent's own show/hide choice on the password
    // and never moves it to the email field.
    await _tap(tester, find.text('Sign in').first);
    expect(_masked(tester, 'auth.email'), isFalse);
    expect(_masked(tester, 'auth.password'), isFalse);
    await _tap(tester, passwordToggle.first);
    expect(_masked(tester, 'auth.password'), isTrue);
    expect(_masked(tester, 'auth.email'), isFalse);
  });

  testWidgets('forgot-password email is readable', (tester) async {
    final h = await Harness.create(prefs: onboardedPrefs);
    await pumpScreen(
      tester,
      const ForgotPasswordScreen(initialEmail: 'parent@example.com'),
      overrides: h.overrides,
    );
    expect(_masked(tester, 'forgot.email'), isFalse);
    expect(find.text('parent@example.com'), findsOneWidget);
  });
}
