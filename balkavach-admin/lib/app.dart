import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/session.dart';
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

/// Where each section lives and the permission it needs.
const kSections = <Section>[
  Section('Dashboard', Icons.dashboard_outlined, '/', 'dashboard:read'),
  Section('Users', Icons.people_outline_rounded, '/users', 'users:read'),
  Section(
    'Families',
    Icons.family_restroom_rounded,
    '/families',
    'families:read',
  ),
  Section('Missions', Icons.task_alt_rounded, '/missions', 'tasks:read'),
  Section('Categories', Icons.category_outlined, '/categories', 'content:read'),
  Section(
    'Preset missions',
    Icons.lightbulb_outline_rounded,
    '/presets',
    'content:read',
  ),
  Section('Rewards', Icons.redeem_rounded, '/rewards', 'rewards:read'),
  Section(
    'Reward requests',
    Icons.inbox_rounded,
    '/redemptions',
    'redemptions:read',
  ),
  Section(
    'Learning content',
    Icons.play_circle_outline_rounded,
    '/content',
    'content:read',
  ),
  Section('Badges', Icons.military_tech_outlined, '/badges', 'badges:read'),
  Section('Settings', Icons.tune_rounded, '/settings', 'settings:read'),
  Section('Audit log', Icons.history_rounded, '/audit', 'audit:read'),
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
      title: 'Bal Kavach Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0051B6),
          secondary: const Color(0xFF006A60),
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
