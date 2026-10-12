import 'package:balkavach_app/features/authentication/domain/session.dart';
import 'package:balkavach_app/features/authentication/presentation/parent_auth_screen.dart';
import 'package:balkavach_app/features/child_profile/presentation/create_child_screen.dart';
import 'package:balkavach_app/features/missions/presentation/child_home_screen.dart';
import 'package:balkavach_app/features/missions/presentation/child_shell.dart';
import 'package:balkavach_app/features/missions/presentation/mission_detail_screen.dart';
import 'package:balkavach_app/features/missions/presentation/mission_submit_screen.dart';
import 'package:balkavach_app/features/missions/presentation/mission_waiting_screen.dart';
import 'package:balkavach_app/features/missions/presentation/missions_screen.dart';
import 'package:balkavach_app/features/onboarding/presentation/consent_screen.dart';
import 'package:balkavach_app/features/onboarding/presentation/role_selection_screen.dart';
import 'package:balkavach_app/features/onboarding/presentation/splash_screen.dart';
import 'package:balkavach_app/features/onboarding/presentation/welcome_screen.dart';
import 'package:balkavach_app/features/parent_dashboard/presentation/create_mission_screen.dart';
import 'package:balkavach_app/features/parent_dashboard/presentation/parent_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

/// Representative logical widths from the brief: small phone, standard
/// phones, foldable/tablet portrait, tablet landscape.
const _widths = [320.0, 360.0, 393.0, 600.0, 840.0];
const _textScales = [1.0, 2.0];

class _Case {
  const _Case(this.name, this.build, {this.session, this.settle = true});

  final String name;
  final Widget Function() build;
  final Session? Function()? session;
  final bool settle;
}

final _cases = <_Case>[
  _Case('splash', () => const SplashScreen(), settle: false),
  _Case('welcome', () => const WelcomeScreen()),
  _Case('consent', () => const ConsentScreen()),
  _Case('role', () => const RoleSelectionScreen()),
  _Case('child start', () => const ChildStartScreen()),
  _Case('parent auth', () => const ParentAuthScreen()),
  _Case(
    'parent home',
    () => const ParentHomeScreen(),
    session: Fx.parentSession,
  ),
  _Case(
    'create child',
    () => const CreateChildScreen(),
    session: Fx.parentSession,
  ),
  _Case(
    'create mission',
    () => const CreateMissionScreen(),
    session: Fx.parentSession,
  ),
  _Case(
    'child home',
    () => const ChildShell(location: '/child', child: ChildHomeScreen()),
    session: Fx.childSession,
  ),
  _Case(
    'missions',
    () =>
        const ChildShell(location: '/child/missions', child: MissionsScreen()),
    session: Fx.childSession,
  ),
  _Case(
    'mission detail',
    () => const MissionDetailScreen(taskId: Fx.taskId),
    session: Fx.childSession,
  ),
  _Case(
    'mission submit',
    () => const MissionSubmitScreen(taskId: Fx.taskId),
    session: Fx.childSession,
  ),
  _Case(
    'mission waiting',
    () => const MissionWaitingScreen(taskId: Fx.taskId),
    session: Fx.childSession,
  ),
];

Future<void> _render(
  WidgetTester tester,
  _Case c, {
  required double width,
  double textScale = 1,
  Locale locale = const Locale('en'),
}) async {
  final session = c.session?.call();
  final h = await Harness.create(session: session, prefs: onboardedPrefs);
  if (session != null) {
    h.backend.reply('GET', '/api/v1/auth/me', session.user.toJson());
  }
  // Long titles and large numbers stress wrapping. The first task keeps
  // Fx.taskId so detail/submit screens resolve it.
  h.backend.reply('GET', '/api/v1/tasks', [
    Fx.task(
      title: 'Help Clean Your Study Table and Arrange All the Colourful Books',
    ),
    Fx.task(
      id: Fx.task2Id,
      title: 'Draw Something Creative',
      stars: 1500,
      categoryId: null,
    ),
  ]);

  await pumpScreen(
    tester,
    c.build(),
    overrides: h.overrides,
    size: Size(width, width >= 840 ? 700 : 800),
    textScale: textScale,
    locale: locale,
    settle: c.settle,
  );
}

void main() {
  for (final c in _cases) {
    group(c.name, () {
      for (final width in _widths) {
        for (final scale in _textScales) {
          testWidgets('${width.toInt()} px @ ${scale}x text', (tester) async {
            await _render(tester, c, width: width, textScale: scale);
          });
        }
      }
      for (final locale in const [Locale('gu'), Locale('hi')]) {
        testWidgets('320 px in ${locale.languageCode}', (tester) async {
          await _render(tester, c, width: 320, locale: locale);
        });
      }
    });
  }

  testWidgets('child shell switches to a navigation rail at 840 px', (
    tester,
  ) async {
    final c = _cases.firstWhere((c) => c.name == 'child home');
    await _render(tester, c, width: 840);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('child shell uses a bottom bar on phones', (tester) async {
    final c = _cases.firstWhere((c) => c.name == 'child home');
    await _render(tester, c, width: 393);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
