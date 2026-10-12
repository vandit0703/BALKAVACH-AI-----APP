import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/parent_auth_screen.dart';
import '../../features/authentication/presentation/session_controller.dart';
import '../../features/child_profile/presentation/create_child_screen.dart';
import '../../features/missions/presentation/child_home_screen.dart';
import '../../features/missions/presentation/child_shell.dart';
import '../../features/missions/presentation/mission_detail_screen.dart';
import '../../features/missions/presentation/mission_submit_screen.dart';
import '../../features/missions/presentation/mission_waiting_screen.dart';
import '../../features/missions/presentation/missions_screen.dart';
import '../../features/onboarding/presentation/consent_screen.dart';
import '../../features/onboarding/presentation/onboarding_controller.dart';
import '../../features/onboarding/presentation/role_selection_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/parent_dashboard/presentation/create_mission_screen.dart';
import '../../features/parent_dashboard/presentation/parent_home_screen.dart';
import 'app_routes.dart';
import 'route_guard.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Re-runs redirects whenever the session or onboarding state changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref
      ..listen(sessionControllerProvider, (_, _) => notifyListeners())
      ..listen(onboardingControllerProvider, (_, _) => notifyListeners());
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      return resolveRedirect(
        location: state.matchedLocation,
        sessionResolved: !session.isLoading || session.hasValue,
        onboarding: ref.read(onboardingControllerProvider),
        session: session.value,
      );
    },
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, _) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.consent,
        builder: (_, _) => const ConsentScreen(),
      ),
      GoRoute(
        path: AppRoutes.role,
        builder: (_, _) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: AppRoutes.childStart,
        builder: (_, _) => const ChildStartScreen(),
      ),
      GoRoute(
        path: AppRoutes.parentAuth,
        builder: (_, _) => const ParentAuthScreen(),
      ),
      GoRoute(
        path: AppRoutes.parentHome,
        builder: (_, _) => const ParentHomeScreen(),
        routes: [
          GoRoute(
            path: 'children/new',
            builder: (_, _) => const CreateChildScreen(),
          ),
          GoRoute(
            path: 'missions/new',
            builder: (_, _) => const CreateMissionScreen(),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) =>
            ChildShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.childHome,
            pageBuilder: (_, _) =>
                const NoTransitionPage(child: ChildHomeScreen()),
            routes: [
              GoRoute(
                path: 'missions',
                pageBuilder: (_, _) =>
                    const NoTransitionPage(child: MissionsScreen()),
                routes: [
                  // Mission screens cover the shell (no bottom bar).
                  GoRoute(
                    path: ':taskId',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) => MissionDetailScreen(
                      taskId: state.pathParameters['taskId']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'submit',
                        parentNavigatorKey: _rootKey,
                        builder: (_, state) => MissionSubmitScreen(
                          taskId: state.pathParameters['taskId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'waiting',
                        parentNavigatorKey: _rootKey,
                        builder: (_, state) => MissionWaitingScreen(
                          taskId: state.pathParameters['taskId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
