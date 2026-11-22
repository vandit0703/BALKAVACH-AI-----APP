import 'package:balkavach_app/features/approvals/presentation/approvals_screen.dart';
import 'package:balkavach_app/features/authentication/domain/session.dart';
import 'package:balkavach_app/features/authentication/presentation/child_login_screen.dart';
import 'package:balkavach_app/features/authentication/presentation/parent_auth_screen.dart';
import 'package:balkavach_app/features/authentication/presentation/parent_mode_screen.dart';
import 'package:balkavach_app/features/authentication/presentation/reset_password_screen.dart';
import 'package:balkavach_app/features/child_profile/presentation/child_home_profile_screen.dart';
import 'package:balkavach_app/features/child_profile/presentation/child_profile_screen.dart';
import 'package:balkavach_app/features/child_profile/presentation/create_child_screen.dart';
import 'package:balkavach_app/features/garden/presentation/garden_screen.dart';
import 'package:balkavach_app/features/learning/data/learning_repository.dart';
import 'package:balkavach_app/features/learning/data/video_feed_repository.dart';
import 'package:balkavach_app/features/learning/presentation/learning_screen.dart';
import 'package:balkavach_app/features/learning/presentation/video_feed_screen.dart';
import 'package:balkavach_app/features/learning/presentation/watch_home_screen.dart';
import 'package:balkavach_app/features/learning/presentation/youtube_player_screen.dart';
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

class _DeviceConfig {
  const _DeviceConfig({
    required this.name,
    required this.manufacturer,
    required this.size,
    this.topInset = 24.0,
    this.bottomInset = 24.0,
    this.leftInset = 0.0,
    this.rightInset = 0.0,
    this.pixelRatio = 2.625,
    this.fontScale = 1.0,
  });

  final String name;
  final String manufacturer;
  final Size size;
  final double topInset;
  final double bottomInset;
  final double leftInset;
  final double rightInset;
  final double pixelRatio;
  final double fontScale;
}

final _oemConfigs = <_DeviceConfig>[
  // 1. Samsung Galaxy Z Fold 5/6 Cover Screen (Narrow 23.1:9 aspect ratio)
  const _DeviceConfig(
    name: 'Samsung Galaxy Z Fold 5/6 (Cover Screen)',
    manufacturer: 'Samsung (One UI)',
    size: Size(344, 882),
    topInset: 38.0,
    bottomInset: 24.0,
    pixelRatio: 3.0,
  ),
  // 2. Samsung Galaxy Z Fold 5/6 Unfolded Inner Screen (Large 4:5 squarish)
  const _DeviceConfig(
    name: 'Samsung Galaxy Z Fold 5/6 (Inner Screen Unfolded)',
    manufacturer: 'Samsung (One UI)',
    size: Size(884, 1104),
    topInset: 24.0,
    bottomInset: 24.0,
    pixelRatio: 3.0,
  ),
  // 3. Samsung Galaxy Z Fold 5/6 Compact Foldable Inner Screen
  const _DeviceConfig(
    name: 'Samsung Galaxy Z Fold (Compact Inner)',
    manufacturer: 'Samsung (One UI)',
    size: Size(673, 841),
    topInset: 24.0,
    bottomInset: 24.0,
    pixelRatio: 2.5,
  ),
  // 4. Samsung Galaxy Z Flip 5/6 Unfolded (Tall 21.2:9 aspect ratio)
  const _DeviceConfig(
    name: 'Samsung Galaxy Z Flip 5/6 (Unfolded Tall)',
    manufacturer: 'Samsung (One UI)',
    size: Size(360, 848),
    topInset: 40.0,
    bottomInset: 24.0,
    pixelRatio: 3.0,
  ),
  // 5. Xiaomi Redmi / POCO physical device (22041219I HyperOS / MIUI)
  const _DeviceConfig(
    name: 'Xiaomi Redmi / POCO 22041219I',
    manufacturer: 'Xiaomi (HyperOS)',
    size: Size(393, 852),
    topInset: 36.0,
    bottomInset: 24.0,
    pixelRatio: 2.75,
  ),
  // 6. Xiaomi Redmi A2 / Vivo Y02 Budget (3-Button Navigation, high font scale)
  const _DeviceConfig(
    name: 'Budget Phone (Redmi A2 / Vivo Y02 / 3-Button Nav)',
    manufacturer: 'Xiaomi / Vivo (Funtouch / Go)',
    size: Size(360, 640),
    topInset: 24.0,
    bottomInset: 48.0, // 3-button navigation
    pixelRatio: 2.0,
    fontScale: 1.3,
  ),
  // 7. Google Pixel Fold / OnePlus Open Unfolded (Landscape-first 6:5 foldable)
  const _DeviceConfig(
    name: 'Google Pixel Fold / OnePlus Open (Unfolded Wide)',
    manufacturer: 'Google / OnePlus (OxygenOS / Pixel UI)',
    size: Size(840, 700),
    topInset: 24.0,
    bottomInset: 24.0,
    pixelRatio: 2.625,
  ),
  // 8. Samsung Galaxy S24 Ultra / OnePlus 12 (Flagship QHD+, Center Punch Hole)
  const _DeviceConfig(
    name: 'Samsung Galaxy S24 Ultra / OnePlus 12',
    manufacturer: 'Samsung / OnePlus (One UI / OxygenOS)',
    size: Size(412, 915),
    topInset: 44.0,
    bottomInset: 20.0,
    pixelRatio: 3.5,
  ),
  // 9. Motorola Edge / Vivo V-Series (Curved Edge Display with Side Insets)
  const _DeviceConfig(
    name: 'Motorola Edge / Vivo Curved Screen (Side Insets)',
    manufacturer: 'Motorola / Vivo (My UX / Funtouch)',
    size: Size(393, 852),
    topInset: 36.0,
    bottomInset: 24.0,
    leftInset: 16.0,
    rightInset: 16.0,
    pixelRatio: 2.75,
  ),
  // 10. Android Multi-Window Split Screen (Top / Bottom half)
  const _DeviceConfig(
    name: 'Android Multi-Window Split-Screen',
    manufacturer: 'Android Split Screen (Any OEM)',
    size: Size(393, 390),
    topInset: 0.0,
    bottomInset: 16.0,
    pixelRatio: 2.75,
  ),
  // 11. Samsung Pop-up View / Xiaomi Floating Window (Freeform window)
  const _DeviceConfig(
    name: 'Samsung Pop-up View / Xiaomi Floating Window',
    manufacturer: 'Samsung / Xiaomi (One UI / HyperOS)',
    size: Size(340, 500),
    topInset: 0.0,
    bottomInset: 0.0,
    pixelRatio: 2.75,
  ),
];

class _Case {
  const _Case(this.name, this.build, {this.session, this.settle = true});

  final String name;
  final Widget Function() build;
  final Session? Function()? session;
  final bool settle;
}

const _longFeedVideo = <String, Object?>{
  'id': 'feed-1',
  'title': 'Volcanoes and Earthquakes: Science for Curious Kids',
  'description': null,
  'thumbnail_url': null,
  'duration_seconds': 3725,
  'category_id': null,
  'language_code': 'en',
  'content_rating': 'educational',
  'video_source': 'youtube',
  'youtube_video_id': 'dQw4w9WgXcQ',
};

const _longLearningItem = <String, Object?>{
  'id': 'learn-1',
  'title': 'A Very Long Title About Counting Colourful Mangoes in the Garden',
  'description': 'Sing along with numbers from one to a hundred together.',
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

final _cases = <_Case>[
  _Case('splash', () => const SplashScreen(), settle: false),
  _Case('welcome', () => const WelcomeScreen()),
  _Case('consent', () => const ConsentScreen()),
  _Case('role', () => const RoleSelectionScreen()),
  _Case('child login', () => const ChildLoginScreen()),
  _Case('parent auth', () => const ParentAuthScreen()),
  _Case(
    'parent gate',
    () => const ParentModeScreen(),
    session: Fx.childSession,
  ),
  _Case(
    'reset password',
    () => const ResetPasswordScreen(token: 'token-0123456789-0123456789'),
  ),
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
    () => const ChildShell(location: '/child', child: WatchHomeScreen()),
    session: Fx.childSession,
  ),
  _Case(
    'child profile tab',
    () => const ChildShell(
      location: '/child/profile',
      child: ChildHomeProfileScreen(),
    ),
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
  _Case('video feed', () => const VideoFeedScreen(), session: Fx.childSession),
  _Case(
    'youtube player',
    () => ProviderScope(
      overrides: [
        youtubeEmbedBuilderProvider.overrideWithValue(
          (_) => const ColoredBox(color: Colors.black),
        ),
      ],
      child: YouTubePlayerScreen(video: FeedVideo.fromJson(_longFeedVideo)),
    ),
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

Future<void> _renderDevice(
  WidgetTester tester,
  _Case c,
  _DeviceConfig config,
) async {
  final session = c.session?.call();
  final h = await Harness.create(session: session, prefs: onboardedPrefs);
  if (session != null) {
    h.backend.reply('GET', '/api/v1/auth/me', session.user.toJson());
  }

  h.backend
    ..reply('GET', '/api/v1/tasks', [
      Fx.task(
        title:
            'Help Clean Your Study Table and Arrange All the Colourful Books',
      ),
      Fx.task(
        id: Fx.task2Id,
        title: 'Draw Something Creative',
        stars: 1500,
        categoryId: null,
      ),
    ])
    ..reply('GET', '/api/v1/notifications', [
      Fx.notification(type: 'task_submitted'),
    ])
    ..reply('GET', '/api/v1/tasks/${Fx.taskId}/submissions', [
      Fx.submission(note: 'Finished tidying up table and arranging books!'),
    ])
    ..reply('GET', '/api/v1/progress/children/${Fx.childId}', Fx.progress())
    ..reply('GET', '/api/v1/redemptions/mine', [Fx.redemption()])
    ..reply('GET', '/api/v1/rewards', [
      Fx.reward(
        name: 'A Special Evening Out With The Whole Family',
        cost: 1500,
      ),
      Fx.reward(id: 'r2', name: 'Sticker', cost: 5, description: null),
    ])
    ..reply('GET', '/api/v1/redemptions', [
      Fx.redemption(
        rewardName: 'A Special Evening Out',
        childName: 'Aarav',
        cost: 1500,
      ),
    ])
    ..reply('GET', '/api/v1/tasks/submissions/mine', [
      Fx.submission(
        number: 2,
        status: 'rejected',
        taskTitle: 'Help Clean Your Study Table',
      ),
    ])
    ..reply('GET', '/api/v1/videos/feed', [_longFeedVideo])
    ..reply('GET', '/api/v1/videos/shorts', <Object?>[])
    ..reply('GET', '/api/v1/educational-content', [
      _longLearningItem,
      {..._longLearningItem, 'id': 'learn-2', 'title': 'Short one'},
    ])
    ..reply('GET', '/api/v1/videos/categories', <Object?>[])
    ..reply('GET', '/api/v1/settings/families/${Fx.familyId}', {
      'family_id': Fx.familyId,
      'default_language': 'en',
      'mission_settings': {'timezone': 'Asia/Kolkata'},
      'reward_settings': <String, Object?>{},
      'video_settings': <String, Object?>{},
      'updated_at': null,
    })
    ..reply('GET', '/api/v1/progress/children/${Fx.childId}/weekly', {
      'child_id': Fx.childId,
      'timezone': 'Asia/Kolkata',
      'period_start': '2026-11-16',
      'period_end': '2026-11-22',
      'totals': {'completed_tasks': 4, 'stars_earned': 200, 'xp_earned': 400},
      'days': [
        for (var i = 0; i < 7; i++)
          {
            'date': '2026-11-${(16 + i).toString().padLeft(2, '0')}',
            'completed_tasks': i,
            'stars_earned': 50 * i,
            'xp_earned': 100 * i,
          },
      ],
      'categories': [
        {
          'category_id': Fx.categoryId,
          'name': 'Creative Arts',
          'completed_tasks': 4,
          'stars_earned': 200,
          'xp_earned': 400,
        },
      ],
      'pending_submissions': 1,
      'rejected_submissions': 0,
      'current_streak': 3,
      'longest_streak': 7,
      'recent_approved': <Object?>[],
    })
    ..reply('GET', '/api/v1/settings/me', Fx.userSettings())
    ..reply('GET', '/api/v1/settings/families/${Fx.familyId}/consents', [
      Fx.consent(),
    ]);

  tester.view
    ..physicalSize = Size(
      config.size.width * config.pixelRatio,
      config.size.height * config.pixelRatio,
    )
    ..devicePixelRatio = config.pixelRatio
    ..padding = FakeViewPadding(
      top: config.topInset * config.pixelRatio,
      bottom: config.bottomInset * config.pixelRatio,
      left: config.leftInset * config.pixelRatio,
      right: config.rightInset * config.pixelRatio,
    );
  addTearDown(tester.view.reset);

  await pumpScreen(
    tester,
    c.build(),
    overrides: h.overrides,
    size: config.size,
    textScale: config.fontScale,
    settle: c.settle,
  );
}

void main() {
  group('OEM and Foldable Device Matrix Audit', () {
    for (final config in _oemConfigs) {
      group(
        '${config.manufacturer}: ${config.name} (${config.size.width.toInt()}x${config.size.height.toInt()})',
        () {
          for (final c in _cases) {
            testWidgets(
              '${c.name} fits with system insets (top: ${config.topInset}, btm: ${config.bottomInset})',
              (tester) async {
                await _renderDevice(tester, c, config);
              },
            );
          }
        },
      );
    }

    group('Dynamic Fold / Unfold Live Window Transition', () {
      testWidgets(
        'Samsung Galaxy Z Fold: Cover to Inner screen live transition preserves state',
        (tester) async {
          const coverConfig = _DeviceConfig(
            name: 'Samsung Z Fold Cover',
            manufacturer: 'Samsung',
            size: Size(344, 882),
            topInset: 38.0,
            bottomInset: 24.0,
          );
          const innerConfig = _DeviceConfig(
            name: 'Samsung Z Fold Inner',
            manufacturer: 'Samsung',
            size: Size(884, 1104),
            topInset: 24.0,
            bottomInset: 24.0,
          );

          final homeCase = _cases.firstWhere((c) => c.name == 'child home');
          // Start on Cover Screen
          await _renderDevice(tester, homeCase, coverConfig);
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(find.byType(NavigationRail), findsNothing);

          // Transition: Unfold device to Inner Screen
          tester.view
            ..physicalSize = Size(
              innerConfig.size.width * 3.0,
              innerConfig.size.height * 3.0,
            )
            ..devicePixelRatio = 3.0
            ..padding = const FakeViewPadding(top: 72, bottom: 72);
          await tester.pumpAndSettle();

          // Responsive layout adapts dynamically: NavigationRail appears on expanded screen
          expect(find.byType(NavigationRail), findsOneWidget);
          expect(find.byType(NavigationBar), findsNothing);

          // Transition: Fold back to Cover Screen
          tester.view
            ..physicalSize = Size(
              coverConfig.size.width * 3.0,
              coverConfig.size.height * 3.0,
            )
            ..devicePixelRatio = 3.0
            ..padding = const FakeViewPadding(top: 114, bottom: 72);
          await tester.pumpAndSettle();

          // Reverts cleanly to NavigationBar
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(find.byType(NavigationRail), findsNothing);
        },
      );

      testWidgets(
        'Parent Home: Cover to Inner screen live transition retains dashboard cards',
        (tester) async {
          const coverConfig = _DeviceConfig(
            name: 'Samsung Z Fold Cover',
            manufacturer: 'Samsung',
            size: Size(344, 882),
            topInset: 38.0,
            bottomInset: 24.0,
          );
          const innerConfig = _DeviceConfig(
            name: 'Samsung Z Fold Inner',
            manufacturer: 'Samsung',
            size: Size(884, 1104),
            topInset: 24.0,
            bottomInset: 24.0,
          );

          final parentCase = _cases.firstWhere((c) => c.name == 'parent home');
          await _renderDevice(tester, parentCase, coverConfig);

          // Unfold
          tester.view
            ..physicalSize = Size(
              innerConfig.size.width * 3.0,
              innerConfig.size.height * 3.0,
            )
            ..devicePixelRatio = 3.0
            ..padding = const FakeViewPadding(top: 72, bottom: 72);
          await tester.pumpAndSettle();

          // Fold
          tester.view
            ..physicalSize = Size(
              coverConfig.size.width * 3.0,
              coverConfig.size.height * 3.0,
            )
            ..devicePixelRatio = 3.0
            ..padding = const FakeViewPadding(top: 114, bottom: 72);
          await tester.pumpAndSettle();
        },
      );
    });
  });
}
