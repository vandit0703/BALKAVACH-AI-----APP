import 'package:balkavach_app/features/authentication/presentation/parent_auth_screen.dart';
import 'package:balkavach_app/features/authentication/presentation/session_controller.dart';
import 'package:balkavach_app/features/child_profile/presentation/create_child_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

void main() {
  group('ParentAuthScreen', () {
    testWidgets('shows client-side validation without calling the API', (
      tester,
    ) async {
      final h = await Harness.create(prefs: onboardedPrefs);
      await pumpScreen(
        tester,
        const ParentAuthScreen(),
        overrides: h.overrides,
      );

      await tester.tap(find.byKey(const Key('auth.submit')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(find.text('Please enter your password.'), findsOneWidget);
      expect(h.backend.requestsTo('POST', '/api/v1/auth/login'), isEmpty);
    });

    testWidgets(
      'register mode enforces 12-character passwords and asks for a name',
      (tester) async {
        final h = await Harness.create(prefs: onboardedPrefs);
        await pumpScreen(
          tester,
          const ParentAuthScreen(),
          overrides: h.overrides,
        );

        await tester.tap(find.text('Create account').first);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('auth.email')),
          'priya@example.com',
        );
        await tester.enterText(find.byKey(const Key('auth.password')), 'short');
        await tester.ensureVisible(find.byKey(const Key('auth.submit')));
        await tester.tap(find.byKey(const Key('auth.submit')));
        await tester.pumpAndSettle();
        expect(find.text('Please enter a name.'), findsOneWidget);
        expect(find.text('Use at least 12 characters.'), findsOneWidget);
        expect(h.backend.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );

    testWidgets('wrong credentials show a friendly message', (tester) async {
      final h = await Harness.create(prefs: onboardedPrefs);
      h.backend.on(
        'POST',
        '/api/v1/auth/login',
        (_) => FakeReply.error(
          401,
          'invalid_credentials',
          'Email or password is incorrect',
        ),
      );
      await pumpScreen(
        tester,
        const ParentAuthScreen(),
        overrides: h.overrides,
      );

      await tester.enterText(
        find.byKey(const Key('auth.email')),
        'priya@example.com',
      );
      await tester.enterText(find.byKey(const Key('auth.password')), 'wrong');
      await tester.ensureVisible(find.byKey(const Key('auth.submit')));
      await tester.tap(find.byKey(const Key('auth.submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('auth.error')), findsOneWidget);
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
    });

    testWidgets('successful sign-in stores the session', (tester) async {
      final h = await Harness.create(prefs: onboardedPrefs);
      h.backend.reply('POST', '/api/v1/auth/login', Fx.token());
      await pumpScreen(
        tester,
        const ParentAuthScreen(),
        overrides: h.overrides,
      );

      await tester.enterText(
        find.byKey(const Key('auth.email')),
        'priya@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('auth.password')),
        'correct-horse',
      );
      await tester.ensureVisible(find.byKey(const Key('auth.submit')));
      await tester.tap(find.byKey(const Key('auth.submit')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ParentAuthScreen)),
      );
      expect(container.read(sessionControllerProvider).value?.isParent, isTrue);
      expect(await h.storage.read(), isNotNull);
    });

    testWidgets('server-side field errors appear under the field', (
      tester,
    ) async {
      final h = await Harness.create(prefs: onboardedPrefs);
      h.backend.on(
        'POST',
        '/api/v1/auth/login',
        (_) => FakeReply.error(
          422,
          'validation_error',
          'Request validation failed',
          [
            {
              'location': ['body', 'email'],
              'message': 'The domain name is not valid',
              'type': 'value_error',
            },
          ],
        ),
      );
      await pumpScreen(
        tester,
        const ParentAuthScreen(),
        overrides: h.overrides,
      );
      await tester.enterText(
        find.byKey(const Key('auth.email')),
        'priya@example.invalid',
      );
      await tester.enterText(find.byKey(const Key('auth.password')), 'pw');
      await tester.ensureVisible(find.byKey(const Key('auth.submit')));
      await tester.tap(find.byKey(const Key('auth.submit')));
      await tester.pumpAndSettle();
      expect(find.text('The domain name is not valid'), findsOneWidget);
    });
  });

  group('CreateChildScreen', () {
    testWidgets(
      'requires name and credentials, then creates the child with avatar stored locally',
      (tester) async {
        final h = await Harness.create(
          session: Fx.parentSession(),
          prefs: onboardedPrefs,
        );
        h.backend.reply(
          'POST',
          '/api/v1/families/${Fx.familyId}/children',
          Fx.child(),
          status: 201,
        );
        await pumpScreen(
          tester,
          const CreateChildScreen(),
          overrides: h.overrides,
        );

        await tester.ensureVisible(find.byKey(const Key('child.submit')));
        await tester.tap(find.byKey(const Key('child.submit')));
        await tester.pumpAndSettle();
        expect(find.text('Please enter a name.'), findsOneWidget);
        expect(find.textContaining('Use 3-32 characters'), findsOneWidget);
        expect(find.text('Please enter your password.'), findsOneWidget);

        await tester.enterText(find.byKey(const Key('child.name')), 'Aarav');
        await tester.enterText(
          find.byKey(const Key('child.username')),
          'aarav7',
        );
        await tester.enterText(
          find.byKey(const Key('child.password')),
          'a-secure-child-password',
        );
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(const Key('child.password')),
                  matching: find.byType(EditableText),
                ),
              )
              .obscureText,
          isTrue,
        );
        final passwordField = find.byKey(const Key('child.password'));
        await tester.ensureVisible(passwordField);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: passwordField, matching: find.byType(IconButton)),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(const Key('child.password')),
                  matching: find.byType(EditableText),
                ),
              )
              .obscureText,
          isFalse,
        );
        await tester.ensureVisible(find.byKey(const Key('avatar.astro')));
        await tester.tap(find.byKey(const Key('avatar.astro')));
        await tester.pumpAndSettle();
        expect(find.text("Create Aarav's Profile"), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('child.submit')));
        await tester.tap(find.byKey(const Key('child.submit')));
        await tester.pumpAndSettle();

        final request = h.backend
            .requestsTo('POST', '/api/v1/families/${Fx.familyId}/children')
            .single;
        expect(request.data, {
          'display_name': 'Aarav',
          'username': 'aarav7',
          'password': 'a-secure-child-password',
          'preferred_language': 'en',
        });
        expect(h.prefs.childAvatarKey(Fx.childId), 'astro');
      },
    );
  });

  group('ServerStatusBadge on ParentAuthScreen', () {
    Future<String> statusFor(
      WidgetTester tester,
      void Function(FakeBackend) setUp,
    ) async {
      final h = await Harness.create(prefs: onboardedPrefs);
      setUp(h.backend);
      await pumpScreen(
        tester,
        const ParentAuthScreen(),
        overrides: h.overrides,
      );
      return tester.widget<Text>(find.byKey(const Key('server.status'))).data!;
    }

    testWidgets('server and database up', (tester) async {
      expect(await statusFor(tester, (_) {}), 'Server online');
    });

    testWidgets('server up, database down', (tester) async {
      final status = await statusFor(
        tester,
        (b) => b.on(
          'GET',
          '/ready',
          (_) => FakeReply.error(503, 'http_error', 'Database is unavailable'),
        ),
      );
      expect(
        status,
        startsWith('Server is up, but its database is unavailable'),
      );
    });

    testWidgets('server unreachable offers a retry', (tester) async {
      final status = await statusFor(
        tester,
        (b) => b.on(
          'GET',
          '/health',
          (_) => const FakeReply.fail(DioExceptionType.connectionError),
        ),
      );
      expect(status, startsWith("Can't reach the server"));
      expect(find.byTooltip('Try again'), findsOneWidget);
    });
  });
}
