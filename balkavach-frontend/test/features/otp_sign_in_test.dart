// Phase 3: email codes that start real sessions.
//
// Registration verification and passwordless sign-in must store the session
// the server returned (through the session controller) before leaving the
// screen, and must store nothing when the server refuses the code.

import 'package:balkavach_app/core/routing/app_routes.dart';
import 'package:balkavach_app/core/theme/app_theme.dart';
import 'package:balkavach_app/features/authentication/presentation/email_verification_screen.dart';
import 'package:balkavach_app/features/authentication/presentation/login_code_screen.dart';
import 'package:balkavach_app/features/authentication/presentation/parent_auth_screen.dart';
import 'package:balkavach_app/features/authentication/presentation/session_controller.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _email = 'parent@example.com';
const _code = '482913';

Map<String, Object?> _error(String code) => {
  'error': {'code': code, 'message': code},
};

Map<String, Object?> _tokens() =>
    Fx.token(accessToken: 'otp.access.token', refreshToken: 'otp-refresh-1');

Future<ProviderContainer> _pumpRoutes(
  WidgetTester tester,
  Harness harness, {
  required String initial,
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
        path: AppRoutes.loginCode,
        builder: (_, state) => LoginCodeScreen(
          initialEmail: state.uri.queryParameters['email'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.parentHome,
        builder: (_, _) => const Scaffold(body: Text('PARENT HOME')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final container = harness.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildAppTheme(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _expectNothingPersistedButTheSession() async {
  final prefs = await SharedPreferences.getInstance();
  for (final key in prefs.getKeys()) {
    expect('${prefs.get(key)}', isNot(contains(_code)), reason: key);
  }
}

void main() {
  group('registration verification', () {
    testWidgets('a verified code stores the server session, then goes home', (
      tester,
    ) async {
      final harness = await Harness.create(prefs: onboardedPrefs);
      harness.backend.reply('POST', '/api/v1/auth/verify-email', _tokens());
      final container = await _pumpRoutes(
        tester,
        harness,
        initial: '${AppRoutes.verifyEmail}?email=parent%40example.com',
      );

      await tester.enterText(find.byKey(const Key('verify.otp')), _code);
      await _tap(tester, find.byKey(const Key('verify.submit')));

      final request = harness.backend
          .requestsTo('POST', '/api/v1/auth/verify-email')
          .single;
      expect(request.data, {'email': _email, 'otp': _code});
      expect(request.headers.containsKey('Authorization'), isFalse);
      final stored = await harness.storage.read();
      expect(stored?.accessToken, 'otp.access.token');
      expect(stored?.refreshToken, 'otp-refresh-1');
      expect(stored?.isParent, isTrue);
      expect(
        container.read(sessionControllerProvider).value?.accessToken,
        'otp.access.token',
      );
      expect(find.text('PARENT HOME'), findsOneWidget);
      await _expectNothingPersistedButTheSession();
    });

    testWidgets('a refused code stores nothing and stays on the screen', (
      tester,
    ) async {
      final harness = await Harness.create(prefs: onboardedPrefs);
      harness.backend.reply(
        'POST',
        '/api/v1/auth/verify-email',
        _error('invalid_verification_code'),
        status: 400,
      );
      await _pumpRoutes(
        tester,
        harness,
        initial: '${AppRoutes.verifyEmail}?email=parent%40example.com',
      );
      await tester.enterText(find.byKey(const Key('verify.otp')), _code);
      await _tap(tester, find.byKey(const Key('verify.submit')));

      expect(await harness.storage.read(), isNull);
      expect(find.byType(EmailVerificationScreen), findsOneWidget);
      expect(
        find.text('Enter the 6-digit code from your email.'),
        findsOneWidget,
      );
    });

    testWidgets('a double tap sends one verification request', (tester) async {
      final harness = await Harness.create(prefs: onboardedPrefs);
      harness.backend.reply('POST', '/api/v1/auth/verify-email', _tokens());
      await _pumpRoutes(
        tester,
        harness,
        initial: '${AppRoutes.verifyEmail}?email=parent%40example.com',
      );
      await tester.enterText(find.byKey(const Key('verify.otp')), _code);
      final submit = find.byKey(const Key('verify.submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.tap(submit, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        harness.backend.requestsTo('POST', '/api/v1/auth/verify-email'),
        hasLength(1),
      );
    });
  });

  group('passwordless sign-in', () {
    Future<(Harness, ProviderContainer)> openFromSignIn(
      WidgetTester tester,
    ) async {
      final harness = await Harness.create(prefs: onboardedPrefs);
      harness.backend.reply(
        'POST',
        '/api/v1/auth/login-code/request',
        null,
        status: 202,
      );
      final container = await _pumpRoutes(
        tester,
        harness,
        initial: AppRoutes.parentAuth,
      );
      await tester.enterText(find.byKey(const Key('auth.email')), _email);
      await _tap(tester, find.byKey(const Key('auth.useEmailCode')));
      expect(find.byType(LoginCodeScreen), findsOneWidget);
      return (harness, container);
    }

    testWidgets('password sign-in stays available next to the code option', (
      tester,
    ) async {
      final harness = await Harness.create(prefs: onboardedPrefs);
      await _pumpRoutes(tester, harness, initial: AppRoutes.parentAuth);
      expect(find.byKey(const Key('auth.password')), findsOneWidget);
      expect(find.byKey(const Key('auth.useEmailCode')), findsOneWidget);
      await _tap(tester, find.text('Create account').first);
      // Registering is unchanged: no code sign-in option there.
      expect(find.byKey(const Key('auth.useEmailCode')), findsNothing);
    });

    testWidgets('email, then code: the server session is stored, then home', (
      tester,
    ) async {
      final (harness, container) = await openFromSignIn(tester);
      // The email carried over and is readable (not masked).
      final emailField = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('loginCode.email')),
          matching: find.byType(EditableText),
        ),
      );
      expect(emailField.controller.text, _email);
      expect(emailField.obscureText, isFalse);

      await _tap(tester, find.byKey(const Key('loginCode.send')));
      final sent = harness.backend
          .requestsTo('POST', '/api/v1/auth/login-code/request')
          .single;
      expect(sent.data, {'email': _email});
      expect(sent.headers.containsKey('Authorization'), isFalse);
      expect(find.byKey(const Key('loginCode.otp')), findsOneWidget);
      expect(find.byKey(const Key('loginCode.timer')), findsOneWidget);
      expect(find.textContaining(_email), findsOneWidget);

      harness.backend.reply(
        'POST',
        '/api/v1/auth/login-code/verify',
        _tokens(),
      );
      await tester.enterText(find.byKey(const Key('loginCode.otp')), _code);
      await _tap(tester, find.byKey(const Key('loginCode.verify')));

      expect(
        harness.backend
            .requestsTo('POST', '/api/v1/auth/login-code/verify')
            .single
            .data,
        {'email': _email, 'otp': _code},
      );
      final stored = await harness.storage.read();
      expect(stored?.refreshToken, 'otp-refresh-1');
      expect(
        container.read(sessionControllerProvider).value?.refreshToken,
        'otp-refresh-1',
      );
      expect(find.text('PARENT HOME'), findsOneWidget);
      await _expectNothingPersistedButTheSession();
    });

    testWidgets('a wrong code stores nothing and asks for the code again', (
      tester,
    ) async {
      final (harness, _) = await openFromSignIn(tester);
      await _tap(tester, find.byKey(const Key('loginCode.send')));
      harness.backend.reply(
        'POST',
        '/api/v1/auth/login-code/verify',
        _error('invalid_login_code'),
        status: 400,
      );
      await tester.enterText(find.byKey(const Key('loginCode.otp')), '000000');
      await _tap(tester, find.byKey(const Key('loginCode.verify')));

      expect(await harness.storage.read(), isNull);
      expect(
        find.text('This code is incorrect or has expired. Request a new code.'),
        findsOneWidget,
      );
      final otp = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('loginCode.otp')),
          matching: find.byType(EditableText),
        ),
      );
      expect(otp.controller.text, isEmpty); // the refused code is not kept
      expect(find.text('PARENT HOME'), findsNothing);
    });

    testWidgets('six digits are required before anything is sent', (
      tester,
    ) async {
      final (harness, _) = await openFromSignIn(tester);
      await _tap(tester, find.byKey(const Key('loginCode.send')));
      await tester.enterText(find.byKey(const Key('loginCode.otp')), '123');
      await _tap(tester, find.byKey(const Key('loginCode.verify')));
      expect(
        harness.backend.requestsTo('POST', '/api/v1/auth/login-code/verify'),
        isEmpty,
      );
    });

    testWidgets('resend waits for the countdown; email can be changed', (
      tester,
    ) async {
      final (harness, _) = await openFromSignIn(tester);
      await _tap(tester, find.byKey(const Key('loginCode.send')));
      expect(find.byKey(const Key('loginCode.resend')), findsNothing);

      await tester.pump(const Duration(seconds: 60));
      await _tap(tester, find.byKey(const Key('loginCode.resend')));
      expect(
        harness.backend.requestsTo('POST', '/api/v1/auth/login-code/request'),
        hasLength(2),
      );
      expect(find.byKey(const Key('loginCode.timer')), findsOneWidget);

      await _tap(tester, find.byKey(const Key('loginCode.changeEmail')));
      expect(find.byKey(const Key('loginCode.email')), findsOneWidget);
      expect(find.byKey(const Key('loginCode.otp')), findsNothing);
      // Let the cancelled countdown's last frame pass.
      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('no email delivery on the server is explained, not hidden', (
      tester,
    ) async {
      final (harness, _) = await openFromSignIn(tester);
      harness.backend.reply(
        'POST',
        '/api/v1/auth/login-code/request',
        _error('email_unavailable'),
        status: 503,
      );
      await _tap(tester, find.byKey(const Key('loginCode.send')));
      expect(
        find.text(
          'Email codes are not available right now. Please try again later '
          'or use your password.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('loginCode.otp')), findsNothing);
    });

    testWidgets('a double tap sends one sign-in request', (tester) async {
      final (harness, _) = await openFromSignIn(tester);
      await _tap(tester, find.byKey(const Key('loginCode.send')));
      harness.backend.reply(
        'POST',
        '/api/v1/auth/login-code/verify',
        _tokens(),
      );
      await tester.enterText(find.byKey(const Key('loginCode.otp')), _code);
      final verify = find.byKey(const Key('loginCode.verify'));
      await tester.ensureVisible(verify);
      await tester.tap(verify);
      await tester.tap(verify, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        harness.backend.requestsTo('POST', '/api/v1/auth/login-code/verify'),
        hasLength(1),
      );
    });
  });

  group('session controller', () {
    test('a code session survives an app restart', () async {
      final harness = await Harness.create(prefs: onboardedPrefs);
      harness.backend.reply(
        'POST',
        '/api/v1/auth/login-code/verify',
        _tokens(),
      );
      final first = harness.container();
      await first.read(sessionControllerProvider.future);
      await first
          .read(sessionControllerProvider.notifier)
          .signInWithCode(email: _email, otp: _code);
      first.dispose();

      // A new process: only the stored session is left.
      final restarted = harness.container();
      final restored = await restarted.read(sessionControllerProvider.future);
      expect(restored?.accessToken, 'otp.access.token');
      expect(restored?.refreshToken, 'otp-refresh-1');
      expect(restored?.isParent, isTrue);
      final me = harness.backend.requestsTo('GET', '/api/v1/auth/me').last;
      expect(me.headers['Authorization'], 'Bearer otp.access.token');
    });

    test(
      'an older server that only verifies leaves the user signed out',
      () async {
        final harness = await Harness.create(prefs: onboardedPrefs);
        harness.backend.reply(
          'POST',
          '/api/v1/auth/verify-email',
          null,
          status: 204,
        );
        final container = harness.container();
        await container.read(sessionControllerProvider.future);
        final signedIn = await container
            .read(sessionControllerProvider.notifier)
            .verifyRegistrationEmail(email: _email, otp: _code);
        expect(signedIn, isFalse);
        expect(await harness.storage.read(), isNull);
        expect(container.read(sessionControllerProvider).value, isNull);
      },
    );
  });

  group('layout', () {
    for (final (size, scale, locale) in [
      (const Size(320, 568), 2.0, const Locale('en')),
      (const Size(360, 640), 1.3, const Locale('hi')),
      (const Size(360, 640), 1.3, const Locale('gu')),
      (const Size(834, 1194), 1.0, const Locale('gu')),
      (const Size(1440, 900), 1.0, const Locale('hi')),
    ]) {
      testWidgets(
        'sign-in code screen fits at $size x$scale ${locale.languageCode}',
        (tester) async {
          final harness = await Harness.create(prefs: onboardedPrefs);
          harness.backend.reply(
            'POST',
            '/api/v1/auth/login-code/request',
            null,
            status: 202,
          );
          await pumpScreen(
            tester,
            const LoginCodeScreen(initialEmail: _email),
            overrides: harness.overrides,
            size: size,
            textScale: scale,
            locale: locale,
          );
          await tester.ensureVisible(find.byKey(const Key('loginCode.send')));
          await tester.tap(find.byKey(const Key('loginCode.send')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('loginCode.otp')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(seconds: 61));
        },
      );
    }
  });
}
