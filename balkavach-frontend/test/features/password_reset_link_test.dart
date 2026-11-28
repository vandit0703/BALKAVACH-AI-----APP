import 'package:balkavach_app/app.dart';
import 'package:balkavach_app/core/routing/app_router.dart';
import 'package:balkavach_app/features/authentication/presentation/forgot_password_screen.dart';
import 'package:balkavach_app/features/authentication/presentation/reset_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _token = 'tok_0123456789012345678901234567890123456789';

/// The password-reset email link (`balkavach://app/reset-password?token=…`)
/// must reach the reset screen with its token whether the app was closed
/// (cold start: the link is the first route) or already open.
Future<(ProviderContainer, Harness)> _start(
  WidgetTester tester, {
  String? coldLink,
  Map<String, Object> prefs = onboardedPrefs,
  bool signedIn = false,
}) async {
  final h = await Harness.create(
    prefs: prefs,
    session: signedIn ? Fx.parentSession() : null,
  );
  setWindow(tester, const Size(393, 852));
  if (coldLink != null) {
    tester.platformDispatcher.defaultRouteNameTestValue = coldLink;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  }
  final container = ProviderContainer(
    overrides: h.overrides,
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const BalKavachApp(),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return (container, h);
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

void _expectResetScreenWithToken(WidgetTester tester, ProviderContainer c) {
  final router = c.read(appRouterProvider);
  expect(
    router.routerDelegate.currentConfiguration.uri.path,
    startsWith('/reset-password'),
  );
  final screen = find.byType(ResetPasswordScreen);
  expect(screen, findsOneWidget);
  expect(tester.widget<ResetPasswordScreen>(screen).token, _token);
}

void main() {
  testWidgets('a refused reset request shows an error, never "link sent"', (
    tester,
  ) async {
    final h = await Harness.create(prefs: onboardedPrefs);
    h.backend.reply('POST', '/api/v1/auth/password/forgot', {
      'error': {
        'code': 'password_reset_unavailable',
        'message': 'Password reset by email is not available right now.',
      },
    }, status: 503);
    await pumpScreen(
      tester,
      const ForgotPasswordScreen(initialEmail: 'parent@example.com'),
      overrides: h.overrides,
    );
    await tester.tap(find.byKey(const Key('forgot.submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('forgot.done')), findsNothing);
    expect(find.byKey(const Key('forgot.error')), findsOneWidget);
  });

  for (final link in [
    'balkavach://app/reset-password?token=$_token',
    'balkavach://app/reset-password/?token=$_token',
  ]) {
    testWidgets('cold start keeps the token: $link', (tester) async {
      final (c, _) = await _start(tester, coldLink: link);
      _expectResetScreenWithToken(tester, c);
      await _finish(tester);
    });

    testWidgets('app already open keeps the token: $link', (tester) async {
      final (c, _) = await _start(tester);
      c.read(appRouterProvider).go(link);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      _expectResetScreenWithToken(tester, c);
      await _finish(tester);
    });
  }

  testWidgets('cold start before onboarding still opens the reset screen', (
    tester,
  ) async {
    final (c, _) = await _start(
      tester,
      coldLink: 'balkavach://app/reset-password?token=$_token',
      prefs: const {},
    );
    _expectResetScreenWithToken(tester, c);
    await _finish(tester);
  });

  testWidgets('cold start while a parent is signed in opens the reset screen', (
    tester,
  ) async {
    final (c, _) = await _start(
      tester,
      coldLink: 'balkavach://app/reset-password?token=$_token',
      signedIn: true,
    );
    _expectResetScreenWithToken(tester, c);
    await _finish(tester);
  });
}
