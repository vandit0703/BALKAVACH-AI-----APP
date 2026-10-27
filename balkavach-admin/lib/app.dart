import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/locale.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'l10n/app_localizations.dart';
import 'pages/audit_page.dart';
import 'pages/badges_page.dart';
import 'pages/categories_page.dart';
import 'pages/content_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/families_page.dart';
import 'pages/login_page.dart';
import 'pages/missions_page.dart';
import 'pages/presets_page.dart';
import 'pages/rewards_page.dart';
import 'pages/settings_page.dart';
import 'pages/shell.dart';
import 'pages/users_page.dart';
import 'pages/youtube_reviews_page.dart';

/// Where each section lives and the permission it needs.
const kSections = <Section>[
  Section(
    'dashboard',
    Icons.dashboard_outlined,
    '/',
    'dashboard:read',
    NavGroup.overview,
  ),
  Section(
    'users',
    Icons.people_outline_rounded,
    '/users',
    'users:read',
    NavGroup.people,
  ),
  Section(
    'families',
    Icons.family_restroom_rounded,
    '/families',
    'families:read',
    NavGroup.people,
  ),
  Section(
    'missions',
    Icons.task_alt_rounded,
    '/missions',
    'tasks:read',
    NavGroup.missions,
  ),
  Section(
    'categories',
    Icons.category_outlined,
    '/categories',
    'content:read',
    NavGroup.missions,
  ),
  Section(
    'presets',
    Icons.lightbulb_outline_rounded,
    '/presets',
    'content:read',
    NavGroup.missions,
  ),
  Section(
    'rewards',
    Icons.redeem_rounded,
    '/rewards',
    'rewards:read',
    NavGroup.missions,
  ),
  Section(
    'redemptions',
    Icons.inbox_rounded,
    '/redemptions',
    'redemptions:read',
    NavGroup.missions,
  ),
  Section(
    'content',
    Icons.play_circle_outline_rounded,
    '/content',
    'content:read',
    NavGroup.learning,
  ),
  Section(
    'youtubeReviews',
    Icons.ondemand_video_outlined,
    '/youtube-reviews',
    'video:read',
    NavGroup.learning,
  ),
  Section(
    'badges',
    Icons.military_tech_outlined,
    '/badges',
    'badges:read',
    NavGroup.learning,
  ),
  Section(
    'settings',
    Icons.tune_rounded,
    '/settings',
    'settings:read',
    NavGroup.system,
  ),
  Section(
    'audit',
    Icons.history_rounded,
    '/audit',
    'audit:read',
    NavGroup.system,
  ),
];

Widget _pageFor(String path) => switch (path) {
  '/users' => const UsersPage(),
  '/families' => const FamiliesPage(),
  '/missions' => const MissionsPage(),
  '/categories' => const CategoriesPage(),
  '/presets' => const PresetsPage(),
  '/rewards' => const RewardsPage(),
  '/redemptions' => const RedemptionsPage(),
  '/content' => const ContentPage(),
  '/youtube-reviews' => const YouTubeReviewsPage(),
  '/badges' => const BadgesPage(),
  '/settings' => const SettingsPage(),
  '/audit' => const AuditPage(),
  _ => const DashboardPage(),
};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  final router = GoRouter(
    refreshListenable: refresh,
    initialLocation: '/',
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final atLogin = state.matchedLocation == '/login';
      if (session == null) return atLogin ? null : '/login';
      return atLogin ? '/' : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      ShellRoute(
        builder: (context, state, child) =>
            AdminShell(location: state.matchedLocation, child: child),
        routes: [
          for (final section in kSections)
            GoRoute(
              path: section.path,
              pageBuilder: (context, state) => NoTransitionPage(
                child: Guarded(
                  permission: section.permission,
                  child: _pageFor(section.path),
                ),
              ),
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

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      theme: buildAdminTheme(),
      locale: ref.watch(localeProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
