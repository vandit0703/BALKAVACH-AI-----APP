import 'dart:convert';

import 'package:balkavach_app/app.dart';
import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/core/routing/app_routes.dart';
import 'package:balkavach_app/core/routing/route_guard.dart';
import 'package:balkavach_app/features/authentication/domain/session.dart';
import 'package:balkavach_app/features/authentication/presentation/reset_password_screen.dart';
import 'package:balkavach_app/features/authentication/presentation/session_controller.dart';
import 'package:balkavach_app/features/onboarding/presentation/onboarding_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _enter = '/api/v1/auth/parent-mode/enter';

Future<void> _pumpApp(WidgetTester tester, Harness h) async {
  setWindow(tester, const Size(393, 852));
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      retry: (_, _) => null,
      child: const BalKavachApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<Harness> _childDevice() async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  h.backend.reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson());
  return h;
}

Future<void> _openGate(WidgetTester tester) async {
  await _tap(tester, find.byKey(const Key('parentGate')));
}

Future<void> _fill(
  WidgetTester tester, {
  String email = 'p@example.com',
}) async {
  await tester.enterText(find.byKey(const Key('parentGate.email')), email);
  await tester.enterText(
    find.byKey(const Key('parentGate.password')),
    'a-long-parent-password',
  );
}

void main() {
  group('parent gate (leaving child mode)', () {
    testWidgets(
      'shows email, password with show/hide, forgot password, continue',
      (tester) async {
        final h = await _childDevice();
        await _pumpApp(tester, h);
        await _openGate(tester);

        expect(find.byKey(const Key('parentGate.email')), findsOneWidget);
        expect(find.byKey(const Key('parentGate.password')), findsOneWidget);
        expect(
          find.byKey(const Key('parentGate.forgotPassword')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('parentGate.submit')), findsOneWidget);
        expect(find.text('Parent sign-in'), findsWidgets);

        EditableText field() => tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(const Key('parentGate.password')),
            matching: find.byType(EditableText),
          ),
        );
        expect(field().obscureText, isTrue);
        await _tap(tester, find.byTooltip('Show password'));
        expect(field().obscureText, isFalse);
        await _tap(tester, find.byTooltip('Hide password'));
        expect(field().obscureText, isTrue);
      },
    );

    testWidgets('validates before any request is made', (tester) async {
      final h = await _childDevice();
      await _pumpApp(tester, h);
      await _openGate(tester);

      await _tap(tester, find.byKey(const Key('parentGate.submit')));
      expect(h.backend.requestsTo('POST', _enter), isEmpty);
      expect(find.text('Enter a valid email address.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('parentGate.email')),
        'not-an-email',
      );
      await _tap(tester, find.byKey(const Key('parentGate.submit')));
      expect(h.backend.requestsTo('POST', _enter), isEmpty);
    });

    testWidgets(
      'sends the child bearer token and the same credentials as login',
      (tester) async {
        final h = await _childDevice();
        h.backend.reply(
          'POST',
          _enter,
          Fx.token(user: Fx.user(role: 'parent')),
        );
        await _pumpApp(tester, h);
        await _openGate(tester);
        await _fill(tester, email: '  Parent@Example.com ');
        await _tap(tester, find.byKey(const Key('parentGate.submit')));

        final request = h.backend.requestsTo('POST', _enter).single;
        expect(request.headers['Authorization'], 'Bearer child.jwt.token');
        final body = request.data is String
            ? jsonDecode(request.data as String)
            : request.data;
        expect(body, {
          'email': 'Parent@Example.com',
          'password': 'a-long-parent-password',
        });
        expect((await h.storage.read())?.isParent, isTrue);
      },
    );

    testWidgets(
      'wrong credentials: one generic message, child session untouched',
      (tester) async {
        final h = await _childDevice();
        h.backend.on(
          'POST',
          _enter,
          (_) => const FakeReply(403, {
            'error': {
              'code': 'parent_authentication_failed',
              'message': 'Email or password is incorrect',
              'details': {'attempts_remaining': 3},
            },
          }),
        );
        await _pumpApp(tester, h);
        await _openGate(tester);
        await _fill(tester);
        await _tap(tester, find.byKey(const Key('parentGate.submit')));

        expect(find.byKey(const Key('parentGate.error')), findsOneWidget);
        expect(
          find.textContaining('Email or password is incorrect.'),
          findsOneWidget,
        );
        expect(find.textContaining('3 attempts left'), findsOneWidget);
        expect((await h.storage.read())?.isChild, isTrue);
        expect(find.byKey(const Key('parentGate.email')), findsOneWidget);
      },
    );

    testWidgets('a locked account explains how long to wait', (tester) async {
      final h = await _childDevice();
      h.backend.on(
        'POST',
        _enter,
        (_) => const FakeReply(423, {
          'error': {
            'code': 'parent_mode_locked',
            'message': 'Too many incorrect attempts. Please try again later.',
            'details': {'retry_after_seconds': 600},
          },
        }),
      );
      await _pumpApp(tester, h);
      await _openGate(tester);
      await _fill(tester);
      await _tap(tester, find.byKey(const Key('parentGate.submit')));

      expect(find.textContaining('10 minutes'), findsOneWidget);
      expect((await h.storage.read())?.isChild, isTrue);
    });

    testWidgets(
      'network failure shows a retryable message and keeps the child session',
      (tester) async {
        final h = await _childDevice();
        h.backend.on(
          'POST',
          _enter,
          (_) => const FakeReply.fail(DioExceptionType.connectionError),
        );
        await _pumpApp(tester, h);
        await _openGate(tester);
        await _fill(tester);
        await _tap(tester, find.byKey(const Key('parentGate.submit')));

        expect(find.byKey(const Key('parentGate.error')), findsOneWidget);
        expect((await h.storage.read())?.isChild, isTrue);
      },
    );

    testWidgets('back returns to child mode without calling the server', (
      tester,
    ) async {
      final h = await _childDevice();
      await _pumpApp(tester, h);
      await _openGate(tester);
      await _tap(tester, find.byKey(const Key('parentGate.stay')));

      expect(find.byKey(const Key('parentGate.email')), findsNothing);
      expect(h.backend.requestsTo('POST', _enter), isEmpty);
      expect((await h.storage.read())?.isChild, isTrue);
    });

    testWidgets('forgot password from the gate requests a reset link', (
      tester,
    ) async {
      final h = await _childDevice();
      h.backend.reply(
        'POST',
        '/api/v1/auth/password/forgot',
        null,
        status: 202,
      );
      await _pumpApp(tester, h);
      await _openGate(tester);
      await tester.enterText(
        find.byKey(const Key('parentGate.email')),
        'p@example.com',
      );
      await _tap(tester, find.byKey(const Key('parentGate.forgotPassword')));
      await tester.tap(find.byKey(const Key('forgot.submit')));
      await tester.pumpAndSettle();

      final request = h.backend
          .requestsTo('POST', '/api/v1/auth/password/forgot')
          .single;
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(
        find.text('If an account exists, a reset link has been sent.'),
        findsOneWidget,
      );
    });

    testWidgets('the retired PIN endpoint is never called', (tester) async {
      final h = await _childDevice();
      h.backend.reply('POST', _enter, Fx.token(user: Fx.user(role: 'parent')));
      await _pumpApp(tester, h);
      await _openGate(tester);
      await _fill(tester);
      await _tap(tester, find.byKey(const Key('parentGate.submit')));
      expect(
        h.backend.requests.where((r) => r.uri.path.contains('parent-pin')),
        isEmpty,
      );
    });
  });

  group('session controller', () {
    test('entering parent mode requires a child session', () async {
      final h = await Harness.create(session: Fx.parentSession());
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      await expectLater(
        container
            .read(sessionControllerProvider.notifier)
            .enterParentMode(email: 'p@example.com', password: 'x' * 12),
        throwsA(isA<ForbiddenException>()),
      );
      expect(h.backend.requestsTo('POST', _enter), isEmpty);
    });

    test('a failed attempt leaves the child session in place', () async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.on(
        'POST',
        _enter,
        (_) => FakeReply.error(403, 'parent_authentication_failed', 'nope'),
      );
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      await expectLater(
        container
            .read(sessionControllerProvider.notifier)
            .enterParentMode(email: 'p@example.com', password: 'x' * 12),
        throwsA(isA<ForbiddenException>()),
      );
      expect(container.read(sessionControllerProvider).value?.isChild, isTrue);
    });

    test('starting child mode ends the parent session on the server', () async {
      final parent = Fx.token(
        refreshToken: 'parent-refresh-token-value-0123456789',
        refreshExpiresAt: '2100-01-01T00:00:00Z',
      );
      final h = await Harness.create(
        session: Session.fromTokenResponse(parent),
      );
      h.backend
        ..reply(
          'POST',
          '/api/v1/auth/children/${Fx.childId}/session',
          Fx.childToken(),
        )
        ..reply('POST', '/api/v1/auth/logout', null, status: 204);
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      await container
          .read(sessionControllerProvider.notifier)
          .startChildMode(Fx.childId);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(sessionControllerProvider).value?.isChild, isTrue);
      final logout = h.backend.requestsTo('POST', '/api/v1/auth/logout').single;
      expect(logout.data, {
        'refresh_token': 'parent-refresh-token-value-0123456789',
      });
    });
  });

  group('route guard', () {
    const onboarded = OnboardingState(
      languageCode: 'en',
      consentAcknowledged: true,
    );

    String? go(String location, {bool child = false, bool signedOut = false}) =>
        resolveRedirect(
          location: location,
          sessionResolved: true,
          onboarding: signedOut ? const OnboardingState() : onboarded,
          session: signedOut
              ? null
              : (child ? Fx.childSession() : Fx.parentSession()),
        );

    test('a child session can reach the gate but no parent route', () {
      expect(go(AppRoutes.childParentGate, child: true), isNull);
      expect(go(AppRoutes.parentHome, child: true), AppRoutes.childHome);
      expect(go(AppRoutes.parentSettings, child: true), AppRoutes.childHome);
      expect(go(AppRoutes.parentApprovals, child: true), AppRoutes.childHome);
      expect(go(AppRoutes.parentAuth, child: true), AppRoutes.childHome);
    });

    test('the reset link is reachable in every state', () {
      const link = '${AppRoutes.resetPassword}?token=abc';
      expect(go(AppRoutes.resetPassword, signedOut: true), isNull);
      expect(go(AppRoutes.resetPassword, child: true), isNull);
      expect(go(AppRoutes.resetPassword), isNull);
      expect(link, contains('token='));
    });
  });

  group('reset password screen', () {
    Future<Harness> pump(WidgetTester tester, String? token) async {
      final h = await Harness.create(prefs: onboardedPrefs);
      await pumpScreen(
        tester,
        ResetPasswordScreen(token: token),
        overrides: h.overrides,
      );
      return h;
    }

    testWidgets('sets the new password and offers sign-in', (tester) async {
      final h = await Harness.create(prefs: onboardedPrefs);
      h.backend.reply('POST', '/api/v1/auth/password/reset', null, status: 204);
      await pumpScreen(
        tester,
        const ResetPasswordScreen(token: 'token-0123456789-0123456789'),
        overrides: h.overrides,
      );
      await tester.enterText(
        find.byKey(const Key('reset.password')),
        'a-brand-new-password',
      );
      await tester.enterText(
        find.byKey(const Key('reset.confirm')),
        'a-brand-new-password',
      );
      await _tap(tester, find.byKey(const Key('reset.submit')));

      final request = h.backend
          .requestsTo('POST', '/api/v1/auth/password/reset')
          .single;
      expect(request.data, {
        'token': 'token-0123456789-0123456789',
        'password': 'a-brand-new-password',
      });
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(find.byKey(const Key('reset.done')), findsOneWidget);
      expect(find.byKey(const Key('reset.toSignIn')), findsOneWidget);
    });

    testWidgets('mismatched or short passwords never reach the server', (
      tester,
    ) async {
      final h = await pump(tester, 'token-0123456789-0123456789');
      await tester.enterText(
        find.byKey(const Key('reset.password')),
        'a-brand-new-password',
      );
      await tester.enterText(
        find.byKey(const Key('reset.confirm')),
        'a-different-password',
      );
      await _tap(tester, find.byKey(const Key('reset.submit')));
      expect(find.text('The two passwords do not match.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('reset.password')), 'short');
      await tester.enterText(find.byKey(const Key('reset.confirm')), 'short');
      await _tap(tester, find.byKey(const Key('reset.submit')));
      expect(
        h.backend.requestsTo('POST', '/api/v1/auth/password/reset'),
        isEmpty,
      );
    });

    testWidgets('an expired or used link shows a clear message and stops', (
      tester,
    ) async {
      final h = await Harness.create(prefs: onboardedPrefs);
      h.backend.on(
        'POST',
        '/api/v1/auth/password/reset',
        (_) => FakeReply.error(400, 'invalid_reset_token', 'invalid'),
      );
      await pumpScreen(
        tester,
        const ResetPasswordScreen(token: 'token-0123456789-0123456789'),
        overrides: h.overrides,
      );
      await tester.enterText(
        find.byKey(const Key('reset.password')),
        'a-brand-new-password',
      );
      await tester.enterText(
        find.byKey(const Key('reset.confirm')),
        'a-brand-new-password',
      );
      await _tap(tester, find.byKey(const Key('reset.submit')));

      expect(
        find.text(
          'This reset link is invalid or has expired. Request a new one.',
        ),
        findsWidgets,
      );
      // The single-use token is forgotten: submitting again sends nothing.
      await tester.tap(
        find.byKey(const Key('reset.submit')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(
        h.backend.requestsTo('POST', '/api/v1/auth/password/reset'),
        hasLength(1),
      );
    });

    testWidgets('a link without a token cannot be submitted', (tester) async {
      final h = await pump(tester, null);
      expect(find.byKey(const Key('reset.error')), findsOneWidget);
      expect(
        h.backend.requestsTo('POST', '/api/v1/auth/password/reset'),
        isEmpty,
      );
    });

    testWidgets('renders in Gujarati and Hindi without overflow', (
      tester,
    ) async {
      for (final locale in const [Locale('gu'), Locale('hi')]) {
        final h = await Harness.create(prefs: onboardedPrefs);
        await pumpScreen(
          tester,
          const ResetPasswordScreen(token: 'token-0123456789-0123456789'),
          overrides: h.overrides,
          locale: locale,
          size: const Size(320, 640),
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull);
      }
    });
  });
}
