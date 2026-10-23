import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/approvals/presentation/approvals_screen.dart';
import '../../features/authentication/presentation/child_login_screen.dart';
import '../../features/authentication/presentation/parent_auth_screen.dart';
import '../../features/authentication/presentation/session_controller.dart';
import '../../features/child_profile/presentation/child_home_profile_screen.dart';
import '../../features/child_profile/presentation/child_profile_screen.dart';
import '../../features/child_profile/presentation/create_child_screen.dart';
import '../../features/garden/presentation/garden_screen.dart';
import '../../features/learning/data/learning_repository.dart';
import '../../features/learning/data/video_feed_repository.dart';
import '../../features/learning/presentation/learning_screen.dart';
import '../../features/learning/presentation/video_feed_screen.dart';
import '../../features/learning/presentation/video_player_screen.dart';
import '../../features/learning/presentation/watch_home_screen.dart';
import '../../features/learning/presentation/youtube_player_screen.dart';
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
import '../../features/progress/presentation/weekly_report_screen.dart';
import '../../features/rewards/presentation/parent_rewards_screen.dart';
import '../../features/rewards/presentation/reward_form_screen.dart';
import '../../features/rewards/presentation/rewards_screen.dart';
import '../../features/settings/presentation/parent_settings_screen.dart';
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
        redirect: (_, _) => AppRoutes.childLogin,
      ),
      GoRoute(
        path: AppRoutes.childLogin,
        builder: (_, _) => const ChildLoginScreen(),
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
          // After `children/new` so "new" is not read as an id.
          GoRoute(
            path: 'children/:childId',
            builder: (_, state) =>
                ChildProfileScreen(childId: state.pathParameters['childId']!),
          ),
          GoRoute(
            path: 'missions/new',
            builder: (_, _) => const CreateMissionScreen(),
          ),
          GoRoute(
            path: 'missions/:taskId/edit',
            builder: (_, state) =>
                EditMissionScreen(taskId: state.pathParameters['taskId']!),
          ),
          GoRoute(
            path: 'approvals',
            builder: (_, _) => const ApprovalsScreen(),
          ),
          GoRoute(
            path: 'reports',
            builder: (_, state) => WeeklyReportScreen(
              initialChildId: state.uri.queryParameters['child'],
            ),
          ),
          GoRoute(
            path: 'settings',
            builder: (_, _) => const ParentSettingsScreen(),
          ),
          GoRoute(
            path: 'rewards',
            builder: (_, _) => const ParentRewardsScreen(),
            routes: [
              GoRoute(path: 'new', builder: (_, _) => const RewardFormScreen()),
              GoRoute(
                path: ':rewardId/edit',
                builder: (_, state) => RewardFormScreen(
                  rewardId: state.pathParameters['rewardId'],
                ),
              ),
            ],
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
                const NoTransitionPage(child: WatchHomeScreen()),
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
              GoRoute(
                path: 'rewards',
                pageBuilder: (_, _) =>
                    const NoTransitionPage(child: RewardsScreen()),
              ),
              GoRoute(
                path: 'garden',
                pageBuilder: (_, _) =>
                    const NoTransitionPage(child: GardenScreen()),
              ),
              GoRoute(
                path: 'profile',
                pageBuilder: (_, _) =>
                    const NoTransitionPage(child: ChildHomeProfileScreen()),
              ),
              GoRoute(
                path: 'videos',
                parentNavigatorKey: _rootKey,
                builder: (_, _) => const VideoFeedScreen(),
                routes: [
                  GoRoute(
                    path: 'play',
                    parentNavigatorKey: _rootKey,
                    // Only an approved YouTube item from the feed can play; a
                    // bare deep link has nothing to play.
                    redirect: (_, state) =>
                        state.extra is FeedVideo &&
                            (state.extra! as FeedVideo).isYouTube
                        ? null
                        : AppRoutes.childVideos,
                    builder: (_, state) =>
                        YouTubePlayerScreen(video: state.extra! as FeedVideo),
                  ),
                ],
              ),
              GoRoute(
                path: 'learn',
                pageBuilder: (_, _) =>
                    const NoTransitionPage(child: LearningScreen()),
                routes: [
                  GoRoute(
                    path: ':itemId',
                    parentNavigatorKey: _rootKey,
                    // The list passes the item along; a deep link without it
                    // returns to the list.
                    redirect: (_, state) => state.extra is LearningItem
                        ? null
                        : AppRoutes.childLearn,
                    builder: (_, state) => LearningDetailScreen(
                      item: state.extra! as LearningItem,
                    ),
                    routes: [
                      GoRoute(
                        path: 'play',
                        parentNavigatorKey: _rootKey,
                        // Like the detail route, the item travels with the
                        // navigation; a bare deep link has nothing to play.
                        redirect: (_, state) => state.extra is LearningItem
                            ? null
                            : AppRoutes.childLearn,
                        builder: (_, state) => VideoPlayerScreen(
                          item: state.extra! as LearningItem,
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
