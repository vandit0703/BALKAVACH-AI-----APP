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
  // The password-reset link must survive start-up, onboarding and any session
  // state: the token in it is single-use and cannot be re-fetched. Checked
  // before the splash hold, which would otherwise replace the link when the
  // app is opened from it (cold start).
  if (_isWithin(location, AppRoutes.resetPassword)) return null;

  if (!sessionResolved) {
    return location == AppRoutes.splash ? null : AppRoutes.splash;
  }

  // Signed-out code and recovery screens. Once a session exists (for example
  // right after a code was verified) the session rules below take over, so a
  // signed-in parent always lands in their own area, behind consent.
  if (session == null &&
      (location == AppRoutes.verifyEmail ||
          location == AppRoutes.forgotPassword ||
          location == AppRoutes.loginCode)) {
    return null;
  }

  // A signed-in session always goes to its own area; onboarding already
  // happened on this device or the user would not have signed in.
  if (session != null) {
    if (session.isChild) {
      return _isWithin(location, AppRoutes.childHome) ||
              _isWithin(location, AppRoutes.streakScreen)
          ? null
          : AppRoutes.childHome;
    }
    if (session.isParent) {
      // A new consent document version must be accepted again before the
      // parent continues (the device only stores the last accepted version).
      if (!onboarding.consentAcknowledged) {
        return location == AppRoutes.consent ? null : AppRoutes.consent;
      }
      return _isWithin(location, AppRoutes.parentHome) ||
              _isWithin(location, AppRoutes.streakScreen)
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
