import 'package:balkavach_app/core/routing/app_routes.dart';
import 'package:balkavach_app/core/theme/app_theme.dart';
import 'package:balkavach_app/features/authentication/presentation/email_verification_screen.dart';
import 'package:balkavach_app/features/authentication/presentation/forgot_password_screen.dart';
import 'package:balkavach_app/features/authentication/presentation/parent_auth_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/harness.dart';

Future<void> _pumpRoutes(
  WidgetTester tester,
  Harness harness, {
  String initial = AppRoutes.parentAuth,
}) async {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: AppRoutes.parentAuth,
        builder: (_, _) => const ParentAuthScreen(),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (_, state) => EmailVerificationScreen(
          email: state.uri.queryParameters['email'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, state) => ForgotPasswordScreen(
          initialEmail: state.uri.queryParameters['email'] ?? '',
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildAppTheme(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('registration sends the parent to email verification', (
    tester,
  ) async {
    final harness = await Harness.create(prefs: onboardedPrefs);
    harness.backend.reply(
      'POST',
      '/api/v1/auth/register',
      {'email': 'parent@example.com'},
      status: 202,
    );
    await _pumpRoutes(tester, harness);
    await _tap(tester, find.text('Create account').first);
    await tester.enterText(find.byKey(const Key('auth.name')), 'Parent Name');
    await tester.enterText(
      find.byKey(const Key('auth.email')),
      'parent@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth.password')),
      'a-long-parent-password',
    );
    await _tap(tester, find.byKey(const Key('auth.submit')));
    expect(find.byType(EmailVerificationScreen), findsOneWidget);
    expect(find.textContaining('parent@example.com'), findsOneWidget);
    expect(
      harness.backend.requestsTo('POST', '/api/v1/auth/register'),
      hasLength(1),
    );
  });

  testWidgets('OTP requires six digits, verifies, then returns to sign in', (
    tester,
  ) async {
    final harness = await Harness.create(prefs: onboardedPrefs);
    harness.backend.reply(
      'POST',
      '/api/v1/auth/verify-email',
      null,
      status: 204,
    );
    await _pumpRoutes(
      tester,
      harness,
      initial: '${AppRoutes.verifyEmail}?email=parent%40example.com',
    );

    await _tap(tester, find.byKey(const Key('verify.submit')));
    expect(
      harness.backend.requestsTo('POST', '/api/v1/auth/verify-email'),
      isEmpty,
    );
    await tester.enterText(find.byKey(const Key('verify.otp')), '123456');
    await _tap(tester, find.byKey(const Key('verify.submit')));
    expect(find.byType(ParentAuthScreen), findsOneWidget);
    expect(
      harness.backend.requestsTo('POST', '/api/v1/auth/verify-email'),
      hasLength(1),
    );
  });

  testWidgets('resend waits for countdown and restarts it after request', (
    tester,
  ) async {
    final harness = await Harness.create(prefs: onboardedPrefs);
    harness.backend.reply(
      'POST',
      '/api/v1/auth/resend-verification',
      null,
      status: 202,
    );
    await _pumpRoutes(
      tester,
      harness,
      initial: '${AppRoutes.verifyEmail}?email=parent%40example.com',
    );
    expect(find.byKey(const Key('verify.timer')), findsOneWidget);
    expect(find.byKey(const Key('verify.resend')), findsNothing);

    await tester.pump(const Duration(seconds: 60));
    await _tap(tester, find.byKey(const Key('verify.resend')));
    expect(
      harness.backend.requestsTo('POST', '/api/v1/auth/resend-verification'),
      hasLength(1),
    );
    expect(find.byKey(const Key('verify.timer')), findsOneWidget);
  });

  testWidgets('parent login forgot link opens form and confirms generically', (
    tester,
  ) async {
    final harness = await Harness.create(prefs: onboardedPrefs);
    harness.backend.reply(
      'POST',
      '/api/v1/auth/password/forgot',
      null,
      status: 202,
    );
    await _pumpRoutes(tester, harness);
    await _tap(tester, find.byKey(const Key('auth.forgotPassword')));
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('forgot.email')),
      'parent@example.com',
    );
    await _tap(tester, find.byKey(const Key('forgot.submit')));
    expect(find.byKey(const Key('forgot.done')), findsOneWidget);
    expect(
      harness.backend.requestsTo('POST', '/api/v1/auth/password/forgot'),
      hasLength(1),
    );
    expect(
      harness.backend.requestsTo('POST', '/api/v1/auth/password/forgot').single
          .headers
          .containsKey('Authorization'),
      isFalse,
    );
  });
}