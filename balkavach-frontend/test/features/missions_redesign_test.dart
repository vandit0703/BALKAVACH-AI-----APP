// The redesigned Missions and Mission detail screens: every status, the real
// reward and today's totals, no silent failures, no misleading repeat action.
//
// Mock/fake tests: the Flutter app runs against `FakeBackend` (no real server,
// no PostgreSQL, no device). Backend reward rules are tested in
// `balkavach-backend/tests/test_api_mission_rewards.py` (PostgreSQL) and
// `test_mission_reward_standard.py` (SQLite).
import 'package:balkavach_app/app.dart';
import 'package:balkavach_app/features/missions/presentation/child_shell.dart';
import 'package:balkavach_app/features/missions/presentation/mission_detail_screen.dart';
import 'package:balkavach_app/features/missions/presentation/mission_submit_screen.dart';
import 'package:balkavach_app/features/missions/presentation/missions_screen.dart';
import 'package:balkavach_app/features/missions/presentation/widgets/mission_card.dart';
import 'package:balkavach_app/features/missions/presentation/widgets/mission_motion.dart';
import 'package:balkavach_app/features/missions/presentation/widgets/mission_steps.dart';
import 'package:balkavach_app/l10n/app_localizations_en.dart';
import 'package:balkavach_app/shared/widgets/buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

final _en = AppLocalizationsEn();
const _today = '/api/v1/daily-missions/today';
const _unfinished = '/api/v1/daily-missions/unfinished';
const _day = '2026-10-12'; // Fx.now's date
const _a1 = '99999999-9999-4999-8999-0000000000c1';
const _a2 = '99999999-9999-4999-8999-0000000000c2';
const _a3 = '99999999-9999-4999-8999-0000000000c3';
const _choiceTask = '55555555-5555-4555-8555-5555555555c1';
const _approvedTask = '55555555-5555-4555-8555-5555555555c2';

Map<String, Object?> _content(String title, {int stars = 10, int xp = 15}) => {
  'title': title,
  'description': 'Description of $title.',
  'instructions': '1. Look.\n2. Listen.',
  'required_materials': ['paper'],
  'duration_minutes': 12,
  'safety_instructions': 'Stay safe.',
  'completion_criteria': 'Done.',
  'mission_type': 'interactive',
  'theme': 'monday_sound_detective',
  'star_reward': stars,
  'xp_reward': xp,
  'is_surprise': false,
  'locale': 'en',
};

Map<String, Object?> _choice(
  String id,
  String title, {
  String status = 'available',
  String? taskId,
  int slot = 1,
  String date = _day,
}) => {
  'id': id,
  'local_date': date,
  'choice_slot': slot,
  'age_band': '7_10',
  'status': status,
  'task_id': taskId,
  'content': _content(title),
};

Map<String, Object?> _todayBody(
  List<Map<String, Object?>> choices, {
  String? selected,
}) => {
  'local_date': _day,
  'timezone': 'Asia/Kolkata',
  'age_band': '7_10',
  'selected_assignment_id': selected,
  'choices': choices,
};

/// A task as the backend serves it now: the standard 10 stars / 15 XP.
Map<String, Object?> _task(String id, String title, {String? description}) => {
  ...Fx.task(
    id: id,
    title: title,
    description: description ?? 'Do $title well.',
  ),
  'star_reward': 10,
  'xp_reward': 15,
};

Future<Harness> _child({
  List<Map<String, Object?>> choices = const [],
  String? selected,
  List<Map<String, Object?>> unfinished = const [],
  List<Map<String, Object?>> tasks = const [],
  List<Map<String, Object?>> submissions = const [],
  List<Map<String, Object?>> activityDays = const [],
}) async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  h.backend
    ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
    ..reply('GET', _today, _todayBody(choices, selected: selected))
    ..reply('GET', _unfinished, unfinished)
    ..reply('GET', '/api/v1/tasks', tasks)
    ..reply('GET', '/api/v1/tasks/submissions/mine', submissions)
    ..reply(
      'GET',
      '/api/v1/progress/children/${Fx.childId}',
      Fx.progress(activityDays: activityDays),
    );
  return h;
}

Future<void> _missions(
  WidgetTester tester,
  Harness h, {
  Size size = const Size(393, 3000),
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool reduceMotion = false,
}) async {
  await pumpScreen(
    tester,
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: const ChildShell(
          location: '/child/missions',
          child: MissionsScreen(),
        ),
      ),
    ),
    overrides: h.overrides,
    size: size,
    locale: locale,
    textScale: textScale,
  );
  // A screen with nothing animating settles before the last fake request's
  // zero-length timer fires: let it run, then settle again.
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

Future<void> _app(WidgetTester tester, Harness h) async {
  setWindow(tester, const Size(393, 3000));
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      retry: (_, _) => null,
      child: const BalKavachApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Missions').last);
  await tester.pumpAndSettle();
}

Map<String, Object?> _approvedSubmission(String taskId) => {
  ...Fx.submission(
    id: '77777777-7777-4777-8777-7777777777c1',
    taskId: taskId,
    status: 'approved',
  ),
  'stars_awarded': 10,
  'xp_awarded': 15,
};

void main() {
  group('header', () {
    testWidgets('shows today\'s real totals from the server day row', (
      tester,
    ) async {
      final h = await _child(
        tasks: [_task(Fx.taskId, 'Read a Storybook')],
        activityDays: [
          Fx.activityDay(_day, tasks: 2, stars: 20, xp: 30),
          Fx.activityDay('2026-10-11', tasks: 5, stars: 50, xp: 75),
        ],
      );
      await _missions(tester, h);

      expect(find.text(_en.missionsHeroTitle), findsOneWidget);
      expect(find.text('My Missions'), findsOneWidget, reason: 'screen title');
      Finder tile(String key, String value) =>
          find.descendant(of: find.byKey(Key(key)), matching: find.text(value));
      expect(tile('missions.today.done', '2'), findsOneWidget);
      expect(tile('missions.today.stars', '20'), findsOneWidget);
      expect(tile('missions.today.xp', '30'), findsOneWidget);
      // 2 approved today, 1 mission still open.
      expect(find.text(_en.missionsDone(2, 3)), findsOneWidget);
      expect(find.text(_en.missionsProgressKeepGoing), findsOneWidget);
    });

    testWidgets('nothing approved today shows zeros, not invented values', (
      tester,
    ) async {
      final h = await _child(tasks: [_task(Fx.taskId, 'Read a Storybook')]);
      await _missions(tester, h);
      for (final key in [
        'missions.today.done',
        'missions.today.stars',
        'missions.today.xp',
      ]) {
        expect(
          find.descendant(of: find.byKey(Key(key)), matching: find.text('0')),
          findsOneWidget,
          reason: key,
        );
      }
      expect(find.text(_en.missionsProgressStart), findsOneWidget);
    });
  });

  group('today\'s choices follow their real status', () {
    testWidgets('nothing chosen yet: every choice can be started', (
      tester,
    ) async {
      final h = await _child(
        choices: [
          _choice(_a1, 'Sound Map'),
          _choice(_a2, 'Paper Lab', slot: 2),
        ],
      );
      await _missions(tester, h);
      expect(find.byKey(const Key('missions.choice.start.$_a1')), findsOne);
      expect(find.byKey(const Key('missions.choice.start.$_a2')), findsOne);
      expect(find.text(_en.missionsChoosePrompt), findsOneWidget);
      expect(find.text(_en.missionStarsCount(10)), findsWidgets);
      expect(find.text(_en.missionXpCount(15)), findsWidgets);
    });

    testWidgets(
      'one chosen: it continues, and the other choices can still be started',
      (tester) async {
        final h = await _child(
          selected: _a1,
          choices: [
            _choice(_a1, 'Sound Map', status: 'selected', taskId: _choiceTask),
            _choice(_a2, 'Paper Lab', slot: 2),
          ],
          tasks: [_task(_choiceTask, 'Sound Map')],
        );
        await _missions(tester, h);
        expect(find.byKey(const Key('missions.choice.open.$_a1')), findsOne);
        // All three daily choices can be completed: choosing one never locks
        // the others.
        expect(find.byKey(const Key('missions.choice.start.$_a2')), findsOne);
        expect(find.text(_en.missionsChoiceTaken), findsNothing);
        // The chosen task is not repeated in the general list.
        expect(find.text('Sound Map'), findsOneWidget);
        expect(find.byKey(const Key('mission.$_choiceTask')), findsNothing);
      },
    );

    testWidgets('sent: waiting for a parent', (tester) async {
      final h = await _child(
        selected: _a1,
        choices: [
          _choice(
            _a1,
            'Sound Map',
            status: 'pending_parent_approval',
            taskId: _choiceTask,
          ),
          _choice(_a2, 'Paper Lab', slot: 2),
        ],
      );
      await _missions(tester, h);
      expect(
        find.descendant(
          of: find.byKey(const Key('missions.choice.open.$_a1')),
          matching: find.text(_en.missionWaitingButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('approved: done, no start and no continue', (tester) async {
      final done = await _child(
        selected: _a1,
        choices: [
          _choice(_a1, 'Sound Map', status: 'approved', taskId: _choiceTask),
        ],
      );
      await _missions(tester, done);
      expect(find.text(_en.statusApproved), findsOneWidget);
      expect(find.byKey(const Key('missions.choice.start.$_a1')), findsNothing);
      expect(find.byKey(const Key('missions.choice.open.$_a1')), findsNothing);
    });

    testWidgets('a refused choice says why instead of doing nothing', (
      tester,
    ) async {
      final h = await _child(choices: [_choice(_a1, 'Sound Map')]);
      h.backend.on(
        'POST',
        '/api/v1/daily-missions/$_a1/select',
        (_) => FakeReply.error(
          409,
          'daily_mission_already_selected',
          'Only one daily mission can be selected',
        ),
      );
      await _missions(tester, h);
      final todayRequests = h.backend.requestsTo('GET', _today).length;

      await tester.tap(find.byKey(const Key('missions.choice.start.$_a1')));
      await tester.pumpAndSettle();

      expect(find.text(_en.errorDailyAlreadySelected), findsOneWidget);
      expect(find.byType(MissionDetailScreen), findsNothing);
      expect(
        h.backend.requestsTo('GET', _today).length,
        greaterThan(todayRequests),
        reason: 'the choices are refreshed after a refusal',
      );
    });

    testWidgets('a server error shows a notice with retry', (tester) async {
      final h = await _child(tasks: [_task(Fx.taskId, 'Read a Storybook')]);
      h.backend.on(
        'GET',
        _today,
        (_) => FakeReply.error(503, 'daily_missions_unavailable', 'Not enough'),
      );
      await _missions(tester, h);
      expect(find.byKey(const Key('missions.today.retry')), findsOneWidget);
      expect(find.text('Read a Storybook'), findsOneWidget);

      h.backend.reply('GET', _today, _todayBody([_choice(_a1, 'Sound Map')]));
      await tester.tap(find.byKey(const Key('missions.today.retry')));
      await tester.pumpAndSettle();
      expect(find.text('Sound Map'), findsOneWidget);
    });
  });

  group('missions for you and completed', () {
    testWidgets('an approved mission is completed: what it earned, no repeat', (
      tester,
    ) async {
      final h = await _child(
        tasks: [
          _task(Fx.taskId, 'Read a Storybook'),
          _task(_approvedTask, 'Water the Plants'),
        ],
        submissions: [_approvedSubmission(_approvedTask)],
      );
      await _missions(tester, h);

      final completed = find.byKey(const Key('mission.$_approvedTask'));
      expect(
        find.descendant(
          of: completed,
          matching: find.text(_en.missionsStarsEarned(10)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: completed, matching: find.byType(PrimaryButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: completed, matching: find.text(_en.missionDoAgain)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('mission.${Fx.taskId}')),
          matching: find.text(_en.missionStartMission),
        ),
        findsOneWidget,
      );
      // Order: missions to do, then completed.
      expect(
        tester.getTopLeft(find.byKey(const Key('missions.forYou'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('missions.completed'))).dy,
        ),
      );
    });

    testWidgets('empty: a friendly empty state, no invented missions', (
      tester,
    ) async {
      final h = await _child();
      await _missions(tester, h);
      expect(find.text(_en.missionsEmpty), findsOneWidget);
      expect(find.byType(MissionCard), findsNothing);
    });

    testWidgets('a failed mission list shows an error with retry', (
      tester,
    ) async {
      final h = await _child();
      h.backend.on(
        'GET',
        '/api/v1/tasks',
        (_) => FakeReply.error(500, 'internal_error', 'boom'),
      );
      await _missions(tester, h);
      expect(find.text(_en.retry), findsWidgets);
      expect(find.text(_en.errorServer), findsOneWidget);
    });
  });

  group('unfinished missions carry forward', () {
    testWidgets('shown with real progress and Continue opens the same task', (
      tester,
    ) async {
      final h = await _child(
        unfinished: [
          _choice(
            _a3,
            'Sound Map',
            status: 'in_progress',
            taskId: _choiceTask,
            date: '2026-10-10',
          ),
        ],
        tasks: [_task(_choiceTask, 'Sound Map')],
      );
      await _app(tester, h);
      expect(find.byKey(const Key('missions.unfinished')), findsOneWidget);
      expect(find.text(_en.missionsUnfinishedTitle), findsOneWidget);

      await tester.tap(find.byKey(const Key('missions.unfinished.open.$_a3')));
      await tester.pumpAndSettle();
      expect(find.byType(MissionDetailScreen), findsOneWidget);
      // Started earlier: the detail offers Continue, not a fresh start.
      expect(
        find.descendant(
          of: find.byKey(const Key('mission.start')),
          matching: find.text(_en.missionContinue),
        ),
        findsOneWidget,
      );
      expect(
        h.backend.requests.where((r) => r.method == 'POST'),
        isEmpty,
        reason: 'opening never selects, starts or creates anything',
      );
    });
  });

  group('mission detail', () {
    testWidgets('a chosen daily mission is marked started, then submitted', (
      tester,
    ) async {
      final h = await _child(
        selected: _a1,
        choices: [
          _choice(_a1, 'Sound Map', status: 'selected', taskId: _choiceTask),
        ],
        tasks: [_task(_choiceTask, 'Sound Map')],
      );
      h.backend.reply(
        'POST',
        '/api/v1/daily-missions/$_a1/start',
        _choice(_a1, 'Sound Map', status: 'in_progress', taskId: _choiceTask),
      );
      await _app(tester, h);
      await tester.tap(find.byKey(const Key('missions.choice.open.$_a1')));
      await tester.pumpAndSettle();

      expect(find.text(_en.missionEarnBoth(10, 15)), findsOneWidget);
      await tester.tap(find.byKey(const Key('mission.start')));
      await tester.pumpAndSettle();

      expect(find.byType(MissionSubmitScreen), findsOneWidget);
      expect(
        h.backend.requestsTo('POST', '/api/v1/daily-missions/$_a1/start'),
        hasLength(1),
      );
      expect(
        h.backend.requests.where(
          (r) => r.method == 'POST' && !r.uri.path.endsWith('/start'),
        ),
        isEmpty,
        reason: 'starting submits nothing and pays nothing',
      );
    });

    testWidgets('a failed start never blocks the child', (tester) async {
      final h = await _child(
        selected: _a1,
        choices: [
          _choice(_a1, 'Sound Map', status: 'selected', taskId: _choiceTask),
        ],
        tasks: [_task(_choiceTask, 'Sound Map')],
      );
      h.backend.on(
        'POST',
        '/api/v1/daily-missions/$_a1/start',
        (_) => FakeReply.error(500, 'internal_error', 'boom'),
      );
      await _app(tester, h);
      await tester.tap(find.byKey(const Key('missions.choice.open.$_a1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mission.start')));
      await tester.pumpAndSettle();
      expect(find.byType(MissionSubmitScreen), findsOneWidget);
    });

    testWidgets('approved: completion state with what was earned, no submit', (
      tester,
    ) async {
      final h = await _child(
        tasks: [_task(_approvedTask, 'Water the Plants')],
        submissions: [_approvedSubmission(_approvedTask)],
      );
      await pumpScreen(
        tester,
        const MissionDetailScreen(taskId: _approvedTask),
        overrides: h.overrides,
      );
      expect(find.byKey(const Key('mission.completed')), findsOneWidget);
      expect(find.text(_en.missionCompleteTitle), findsOneWidget);
      expect(find.text(_en.missionEarnedBoth(10, 15)), findsOneWidget);
      expect(find.byKey(const Key('mission.start')), findsNothing);
      expect(find.byKey(const Key('mission.back')), findsOneWidget);
    });

    testWidgets('pending: waits for a parent', (tester) async {
      final pending = await _child(
        tasks: [_task(Fx.taskId, 'Read a Storybook')],
        submissions: [Fx.submission()],
      );
      await pumpScreen(
        tester,
        const MissionDetailScreen(taskId: Fx.taskId),
        overrides: pending.overrides,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('mission.start')),
          matching: find.text(_en.missionWaitingButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('rejected: try again', (tester) async {
      final rejected = await _child(
        tasks: [_task(Fx.taskId, 'Read a Storybook')],
        submissions: [Fx.submission(status: 'rejected')],
      );
      await pumpScreen(
        tester,
        const MissionDetailScreen(taskId: Fx.taskId),
        overrides: rejected.overrides,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('mission.start')),
          matching: find.text(_en.missionDoAgain),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a mission that is gone offers a way back', (tester) async {
      final h = await _child();
      await pumpScreen(
        tester,
        const MissionDetailScreen(taskId: Fx.taskId),
        overrides: h.overrides,
      );
      expect(find.text(_en.missionNotFound), findsOneWidget);
      expect(find.byKey(const Key('mission.notFound.back')), findsOneWidget);
    });

    testWidgets('numbered instructions become steps, every line kept', (
      tester,
    ) async {
      const text =
          'Listen in two places.\n\n'
          '1. Sit quietly for 1 minute.\n2. Move to another room.\n'
          'Another way: draw it.\n\n'
          'A sound map with 5 sounds.\nParent check: ask which was loudest.';
      final h = await _child(
        tasks: [_task(Fx.taskId, 'Sound Map', description: text)],
      );
      await pumpScreen(
        tester,
        const MissionDetailScreen(taskId: Fx.taskId),
        overrides: h.overrides,
        size: const Size(320, 1400),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Sit quietly for 1 minute.'), findsOneWidget);
      expect(find.text('Move to another room.'), findsOneWidget);
      expect(find.text('Another way: draw it.'), findsOneWidget);
      expect(
        find.textContaining('Parent check: ask which was loudest.'),
        findsOneWidget,
      );
    });
  });

  group('instruction parsing', () {
    test('two or more numbered lines become steps; prose stays prose', () {
      final blocks = parseInstructions('Intro.\n\n1. One.\n2. Two.\nTail.');
      expect(blocks, hasLength(3));
      expect((blocks[0] as ParagraphBlock).text, 'Intro.');
      expect((blocks[1] as StepsBlock).steps, ['One.', 'Two.']);
      expect((blocks[2] as ParagraphBlock).text, 'Tail.');
    });

    test('a single numbered line is not a step list', () {
      final blocks = parseInstructions('Use 1. good idea only.\n1. One.');
      expect(blocks, hasLength(1));
      expect(blocks.single, isA<ParagraphBlock>());
    });
  });

  group('languages and sizes', () {
    for (final locale in const ['en', 'gu', 'hi']) {
      for (final (size, scale) in const [
        (Size(320, 4000), 2.0),
        (Size(393, 3000), 1.0),
        (Size(840, 2400), 1.0),
      ]) {
        testWidgets('$locale ${size.width.toInt()}px x$scale: no overflow', (
          tester,
        ) async {
          final h = await _child(
            selected: _a1,
            choices: [
              _choice(
                _a1,
                'A Very Long Mission Title That Has To Wrap Nicely',
                status: 'pending_parent_approval',
                taskId: _choiceTask,
              ),
              _choice(_a2, 'Paper Lab', slot: 2),
            ],
            unfinished: [
              _choice(
                _a3,
                'Older One',
                status: 'rejected',
                taskId: '55555555-5555-4555-8555-5555555555c9',
                date: '2026-10-10',
              ),
            ],
            tasks: [
              _task(Fx.taskId, 'Help Clean Your Study Table and All the Books'),
              _task(_approvedTask, 'Water the Plants'),
            ],
            submissions: [_approvedSubmission(_approvedTask)],
            activityDays: [Fx.activityDay(_day, tasks: 1, stars: 10, xp: 15)],
          );
          await _missions(
            tester,
            h,
            size: size,
            textScale: scale,
            locale: Locale(locale),
          );
          expect(tester.takeException(), isNull);
          for (final card in find.byType(MissionCard).evaluate()) {
            expect(
              tester.getRect(find.byWidget(card.widget)).right,
              lessThanOrEqualTo(size.width),
            );
          }
        });
      }
    }
  });

  testWidgets('reduced motion: nothing animates in', (tester) async {
    final h = await _child(
      choices: [_choice(_a1, 'Sound Map')],
      tasks: [_task(Fx.taskId, 'Read a Storybook')],
      activityDays: [Fx.activityDay(_day, tasks: 1, stars: 10, xp: 15)],
    );
    await _missions(tester, h, reduceMotion: true);
    expect(find.byType(EntranceFade), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(EntranceFade),
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('missions.header')),
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
      findsNothing,
    );
  });

  testWidgets('393 px meets contrast and tap-target guidelines', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = await _child(
      selected: _a1,
      choices: [
        _choice(_a1, 'Sound Map', status: 'selected', taskId: _choiceTask),
        _choice(_a2, 'Paper Lab', slot: 2),
      ],
      unfinished: [
        _choice(
          _a3,
          'Older One',
          status: 'rejected',
          taskId: '55555555-5555-4555-8555-5555555555c9',
          date: '2026-10-10',
        ),
      ],
      tasks: [
        _task(Fx.taskId, 'Read a Storybook'),
        _task(_approvedTask, 'Water the Plants'),
      ],
      submissions: [_approvedSubmission(_approvedTask)],
      activityDays: [Fx.activityDay(_day, tasks: 1, stars: 10, xp: 15)],
    );
    await _missions(tester, h, size: const Size(393, 3000));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
