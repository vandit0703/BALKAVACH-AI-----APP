import 'package:balkavach_app/features/approvals/presentation/approvals_screen.dart';
import 'package:balkavach_app/features/authentication/domain/session.dart';
import 'package:balkavach_app/features/authentication/presentation/parent_auth_screen.dart';
import 'package:balkavach_app/features/child_profile/presentation/child_profile_screen.dart';
import 'package:balkavach_app/features/child_profile/presentation/create_child_screen.dart';
import 'package:balkavach_app/features/garden/presentation/garden_screen.dart';
import 'package:balkavach_app/features/learning/data/learning_repository.dart';
import 'package:balkavach_app/features/learning/presentation/learning_screen.dart';
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
import 'package:balkavach_app/features/progress/presentation/weekly_report_screen.dart';
import 'package:balkavach_app/features/rewards/presentation/parent_rewards_screen.dart';
import 'package:balkavach_app/features/rewards/presentation/reward_form_screen.dart';
import 'package:balkavach_app/features/rewards/presentation/rewards_screen.dart';
import 'package:balkavach_app/features/settings/presentation/parent_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

/// Representative logical widths from the brief: small phone, standard
/// phones, foldable/tablet portrait, tablet landscape.
const _widths = [320.0, 360.0, 393.0, 600.0, 840.0];
const _textScales = [1.0, 2.0];

/// Landscape phone and a very short window.
const _shortWindows = [Size(740, 360), Size(568, 320)];

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
  _Case('approvals', () => const ApprovalsScreen(), session: Fx.parentSession),
  _Case(
    'weekly report',
    () => const WeeklyReportScreen(),
    session: Fx.parentSession,
  ),
  _Case(
    'child profile',
    () => const ChildProfileScreen(childId: Fx.childId),
    session: Fx.parentSession,
  ),
  _Case(
    'parent settings',
    () => const ParentSettingsScreen(),
    session: Fx.parentSession,
  ),
  _Case(
    'rewards',
    () => const ChildShell(location: '/child/rewards', child: RewardsScreen()),
    session: Fx.childSession,
  ),
  _Case(
    'garden',
    () => const ChildShell(location: '/child/garden', child: GardenScreen()),
    session: Fx.childSession,
  ),
  _Case(
    'learning',
    () => const ChildShell(location: '/child/learn', child: LearningScreen()),
    session: Fx.childSession,
  ),
  _Case(
    'learning detail',
    () => LearningDetailScreen(item: LearningItem.fromJson(_longLearningItem)),
    session: Fx.childSession,
  ),
  _Case(
    'parent rewards',
    () => const ParentRewardsScreen(),
    session: Fx.parentSession,
  ),
  _Case(
    'reward form',
    () => const RewardFormScreen(rewardId: Fx.rewardId),
    session: Fx.parentSession,
  ),
];

const _longLearningItem = <String, Object?>{
  'id': 'learn-1',
  'title': 'A Very Long Title About Counting Colourful Mangoes in the Garden',
  'description':
      'Sing along with numbers from one to a hundred and learn how to '
      'count every colourful mango in the big garden together with friends.',
  'content_type': 'video',
  'category_id': null,
  'language_code': 'en',
  'content_url': 'https://example.com/a-very-long-link-that-must-not-overflow',
  'thumbnail_url': null,
  'video_id': null,
  'collection_id': null,
  'requires_entitlement': false,
  'is_active': true,
};

Future<void> _render(
  WidgetTester tester,
  _Case c, {
  required double width,
  double? height,
  double textScale = 1,
  Locale locale = const Locale('en'),
  FakeViewPadding keyboard = FakeViewPadding.zero,
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

  // Long notes, names and big numbers for the screens added after the first
  // slice: they must wrap, not overflow.
  h.backend
    ..reply('GET', '/api/v1/notifications', [
      Fx.notification(type: 'task_submitted'),
    ])
    ..reply('GET', '/api/v1/tasks/${Fx.taskId}/submissions', [
      Fx.submission(
        note:
            'I tidied my whole study table, arranged every colourful book by '
            'size and then drew a picture of Sheru the lion for everyone!',
      ),
    ])
    ..reply(
      'GET',
      '/api/v1/progress/children/${Fx.childId}',
      Fx.progress(
        garden: {
          'stage': 4,
          'stage_key': 'young-tree',
          'xp_to_next_stage': 800,
          'items': [
            {
              'key': 'first-mission',
              'badge': 'First Mission',
              'unlocked': true,
            },
            {
              'key': 'week-warrior',
              'badge': 'Super Helper of the Entire Neighbourhood',
              'unlocked': false,
            },
          ],
        },
        activityDays: [
          for (var d = 6; d >= 0; d--)
            Fx.activityDay(
              '2026-10-${(12 - d).toString().padLeft(2, '0')}',
              tasks: d + 1,
              stars: 1500,
              xp: 2500,
            ),
        ],
        badges: [
          Fx.badge(
            name: 'Super Helper of the Entire Neighbourhood',
            description: 'Finish ten chores promptly without being reminded',
          ),
          Fx.badge(id: 'b2', name: 'Bookworm'),
          Fx.badge(id: 'b3', name: 'Yoga Champ'),
        ],
      ),
    )
    ..reply('GET', '/api/v1/redemptions/mine', [Fx.redemption()])
    ..reply('GET', '/api/v1/rewards', [
      Fx.reward(
        name: 'A Special Evening Out With The Whole Family To The Big Park',
        description:
            'Pick any ride you like and share a very large ice cream with '
            'everyone who comes along for the fun afternoon.',
        cost: 1500,
      ),
      Fx.reward(id: 'r2', name: 'Sticker', cost: 5, description: null),
    ])
    ..reply('GET', '/api/v1/redemptions', [
      Fx.redemption(
        rewardName: 'A Special Evening Out With The Whole Family',
        childName: 'Aarav-with-a-Rather-Long-Name',
        cost: 1500,
      ),
    ])
    ..reply('GET', '/api/v1/tasks/submissions/mine', [
      Fx.submission(
        number: 2,
        status: 'rejected',
        taskTitle: 'Help Clean Your Study Table',
        reviewNote:
            'Lovely effort! Please also put the books back on the shelf '
            'in the right order and wipe the desk properly.',
      ),
    ])
    ..reply('GET', '/api/v1/educational-content', [
      _longLearningItem,
      {..._longLearningItem, 'id': 'learn-2', 'title': 'Short one'},
    ])
    ..reply('GET', '/api/v1/videos/categories', <Object?>[])
    ..reply('GET', '/api/v1/settings/families/${Fx.familyId}', {
      'family_id': Fx.familyId,
      'default_language': 'en',
      'mission_settings': {'timezone': 'America/Argentina/Buenos_Aires'},
      'reward_settings': <String, Object?>{},
      'video_settings': <String, Object?>{},
      'updated_at': null,
    })
    ..reply('GET', '/api/v1/progress/children/${Fx.childId}/weekly', {
      'child_id': Fx.childId,
      'timezone': 'America/Argentina/Buenos_Aires',
      'period_start': '2026-10-05',
      'period_end': '2026-10-11',
      'totals': {'completed_tasks': 9, 'stars_earned': 4500, 'xp_earned': 9000},
      'days': [
        for (var i = 0; i < 7; i++)
          {
            'date': '2026-10-${(5 + i).toString().padLeft(2, '0')}',
            'completed_tasks': i,
            'stars_earned': 100 * i,
            'xp_earned': 200 * i,
          },
      ],
      'categories': [
        {
          'category_id': Fx.categoryId,
          'name': 'Creative Arts, Crafts and Everything Colourful',
          'completed_tasks': 5,
          'stars_earned': 2500,
          'xp_earned': 5000,
        },
        {
          'category_id': null,
          'name': 'Uncategorised',
          'completed_tasks': 4,
          'stars_earned': 2000,
          'xp_earned': 4000,
        },
      ],
      'pending_submissions': 12,
      'rejected_submissions': 3,
      'current_streak': 5,
      'longest_streak': 9,
      'recent_approved': <Object?>[],
    })
    ..reply('GET', '/api/v1/settings/me', Fx.userSettings())
    ..reply('GET', '/api/v1/settings/families/${Fx.familyId}/consents', [
      Fx.consent(),
    ]);

  await pumpScreen(
    tester,
    c.build(),
    overrides: h.overrides,
    size: Size(width, height ?? (width >= 840 ? 700 : 800)),
    textScale: textScale,
    locale: locale,
    settle: c.settle,
  );
  if (keyboard != FakeViewPadding.zero) {
    tester.view.viewInsets = keyboard;
    await tester.pumpAndSettle();
  }
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
      // Landscape phone and a very short window: content must scroll, not
      // overflow, when there is little vertical room.
      for (final size in _shortWindows) {
        for (final scale in _textScales) {
          testWidgets('${size.width.toInt()}x${size.height.toInt()} landscape '
              '@ ${scale}x text', (tester) async {
            await _render(
              tester,
              c,
              width: size.width,
              height: size.height,
              textScale: scale,
            );
          });
        }
      }
      testWidgets('393 px text contrast meets the guideline', (tester) async {
        final handle = tester.ensureSemantics();
        await _render(tester, c, width: 393);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
      testWidgets('393 px meets tap-target and label guidelines', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _render(tester, c, width: 393);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    });
  }

  // Forms with the on-screen keyboard open on a short phone: the focused
  // field must stay visible above the keyboard.
  const keyboardHeight = 300.0;
  for (final name in const [
    'parent auth',
    'create child',
    'create mission',
    'mission submit',
  ]) {
    testWidgets('$name: focused field stays above the keyboard', (
      tester,
    ) async {
      final c = _cases.firstWhere((c) => c.name == name);
      await _render(
        tester,
        c,
        width: 393,
        height: 700,
        keyboard: const FakeViewPadding(bottom: keyboardHeight),
      );
      final field = find.byType(EditableText).last;
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(field).bottom,
        lessThanOrEqualTo(700 - keyboardHeight),
        reason: 'the field is hidden behind the keyboard',
      );
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
