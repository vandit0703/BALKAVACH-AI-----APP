import '../../features/authentication/domain/session.dart';
import '../../features/onboarding/presentation/onboarding_controller.dart';
import 'app_routes.dart';

/// Pure redirect rules, kept separate from GoRouter for unit testing.
///
/// [sessionResolved] is false while the stored session is being restored.
String? resolveRedirect({
  required String location,
  required bool sessionResolved,
  required OnboardingState onboarding,
  required Session? session,
}) {
  if (!sessionResolved) {
    return location == AppRoutes.splash ? null : AppRoutes.splash;
  }

  // A signed-in session always goes to its own area; onboarding already
  // happened on this device or the user would not have signed in.
  if (session != null) {
    if (session.isChild) {
      return _isWithin(location, AppRoutes.childHome)
          ? null
          : AppRoutes.childHome;
    }
    if (session.isParent) {
      return _isWithin(location, AppRoutes.parentHome)
          ? null
          : AppRoutes.parentHome;
    }
  }

  if (!onboarding.languageChosen) {
    return location == AppRoutes.welcome ? null : AppRoutes.welcome;
  }
  if (!onboarding.consentAcknowledged) {
    // Allow stepping back to change language.
    return location == AppRoutes.consent || location == AppRoutes.welcome
        ? null
        : AppRoutes.consent;
  }
  if (AppRoutes.signedOut.contains(location)) return null;
  return AppRoutes.role;
}

/// True for [area] itself and its sub-paths (`/child`, `/child/missions`),
/// but not for siblings sharing a prefix (`/child-start`).
bool _isWithin(String location, String area) =>
    location == area || location.startsWith('$area/');
