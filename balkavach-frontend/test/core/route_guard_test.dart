import 'package:balkavach_app/core/routing/app_routes.dart';
import 'package:balkavach_app/core/routing/route_guard.dart';
import 'package:balkavach_app/features/onboarding/presentation/onboarding_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';

void main() {
  const fresh = OnboardingState();
  const languageOnly = OnboardingState(languageCode: 'gu');
  const onboarded = OnboardingState(
    languageCode: 'en',
    consentAcknowledged: true,
  );

  String? go(
    String location, {
    bool resolved = true,
    OnboardingState onboarding = onboarded,
    bool parent = false,
    bool child = false,
  }) => resolveRedirect(
    location: location,
    sessionResolved: resolved,
    onboarding: onboarding,
    session: parent ? Fx.parentSession() : (child ? Fx.childSession() : null),
  );

  test('holds on splash while the session restores', () {
    expect(go(AppRoutes.splash, resolved: false), isNull);
    expect(go(AppRoutes.parentHome, resolved: false), AppRoutes.splash);
  });

  test('fresh install goes to welcome, then consent', () {
    expect(go(AppRoutes.splash, onboarding: fresh), AppRoutes.welcome);
    expect(go(AppRoutes.role, onboarding: fresh), AppRoutes.welcome);
    expect(go(AppRoutes.splash, onboarding: languageOnly), AppRoutes.consent);
    expect(
      go(AppRoutes.welcome, onboarding: languageOnly),
      isNull,
      reason: 'can go back to change language',
    );
  });

  test(
    'signed out after onboarding can reach role, child start and auth only',
    () {
      expect(go(AppRoutes.splash), AppRoutes.role);
      expect(go(AppRoutes.parentAuth), isNull);
      expect(go(AppRoutes.childStart), isNull);
      expect(go(AppRoutes.parentHome), AppRoutes.role);
      expect(go(AppRoutes.childMissions), AppRoutes.role);
    },
  );

  test('parent session stays in the parent area', () {
    expect(go(AppRoutes.parentAuth, parent: true), AppRoutes.parentHome);
    expect(go(AppRoutes.parentNewChild, parent: true), isNull);
    expect(go(AppRoutes.childHome, parent: true), AppRoutes.parentHome);
  });

  test('child session cannot reach parent screens', () {
    expect(go(AppRoutes.parentHome, child: true), AppRoutes.childHome);
    expect(go(AppRoutes.parentNewMission, child: true), AppRoutes.childHome);
    expect(
      go(AppRoutes.childStart, child: true),
      AppRoutes.childHome,
      reason: 'prefix sibling',
    );
    expect(go(AppRoutes.childMissionSubmit(Fx.taskId), child: true), isNull);
  });
}
