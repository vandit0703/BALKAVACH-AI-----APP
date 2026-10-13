import 'package:balkavach_app/core/routing/app_routes.dart';
import 'package:balkavach_app/core/routing/route_guard.dart';
import 'package:balkavach_app/features/onboarding/presentation/onboarding_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';

void main() {
  const onboarded = OnboardingState(
    languageCode: 'en',
    consentAcknowledged: true,
  );

  String? go(String location, {bool parent = false, bool child = false}) =>
      resolveRedirect(
        location: location,
        sessionResolved: true,
        onboarding: onboarded,
        session: parent
            ? Fx.parentSession()
            : (child ? Fx.childSession() : null),
      );

  final parentOnly = [
    AppRoutes.parentApprovals,
    AppRoutes.parentReports,
    AppRoutes.parentReportsFor(Fx.childId),
    AppRoutes.parentSettings,
    AppRoutes.parentChild(Fx.childId),
  ];
  final childOnly = [AppRoutes.childRewards, AppRoutes.childGarden];

  test('signed-out users are sent to role selection', () {
    for (final route in [...parentOnly, ...childOnly]) {
      expect(go(route), AppRoutes.role, reason: route);
    }
  });

  test('children cannot reach any parent screen', () {
    for (final route in parentOnly) {
      expect(go(route, child: true), AppRoutes.childHome, reason: route);
    }
  });

  test('parents cannot reach child-mode screens', () {
    for (final route in childOnly) {
      expect(go(route, parent: true), AppRoutes.parentHome, reason: route);
    }
  });

  test('each role may open its own new screens', () {
    for (final route in parentOnly) {
      expect(go(route, parent: true), isNull, reason: route);
    }
    for (final route in childOnly) {
      expect(go(route, child: true), isNull, reason: route);
    }
  });

  test('the report route carries the child as a query parameter', () {
    final uri = Uri.parse(AppRoutes.parentReportsFor(Fx.childId));
    expect(uri.path, AppRoutes.parentReports);
    expect(uri.queryParameters['child'], Fx.childId);
  });

  group('consent re-acknowledgement', () {
    const outdated = OnboardingState(languageCode: 'en');

    String? goOutdated(
      String location, {
      bool parent = false,
      bool child = false,
    }) => resolveRedirect(
      location: location,
      sessionResolved: true,
      onboarding: outdated,
      session: parent ? Fx.parentSession() : (child ? Fx.childSession() : null),
    );

    test('a signed-in parent must accept a new consent version first', () {
      expect(goOutdated(AppRoutes.parentHome, parent: true), AppRoutes.consent);
      expect(
        goOutdated(AppRoutes.parentApprovals, parent: true),
        AppRoutes.consent,
      );
      expect(goOutdated(AppRoutes.consent, parent: true), isNull);
    });

    test('accepting it releases the parent to the parent area', () {
      expect(go(AppRoutes.consent, parent: true), AppRoutes.parentHome);
    });

    test('a child session is never sent to the parent consent', () {
      expect(goOutdated(AppRoutes.childHome, child: true), isNull);
      expect(goOutdated(AppRoutes.consent, child: true), AppRoutes.childHome);
    });
  });
}
