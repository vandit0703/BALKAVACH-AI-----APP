// Mission titles without age ranges, older unfinished missions, and the Start Mission hand-off.
//
// Mock/fake tests: the Flutter app runs against `FakeBackend` (no real server, no PostgreSQL, no device).
import 'package:balkavach_app/app.dart';
import 'package:balkavach_app/features/missions/domain/mission_titles.dart';
import 'package:balkavach_app/features/missions/presentation/mission_detail_screen.dart';
import 'package:balkavach_app/l10n/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _today = '/api/v1/daily-missions/today';
const _unfinished = '/api/v1/daily-missions/unfinished';
const _assignmentToday = '99999999-9999-4999-8999-000000000001';
const _assignmentOlder = '99999999-9999-4999-8999-000000000002';
const _olderTaskId = '55555555-5555-4555-8555-5555555555a1';
const _newTaskId = '55555555-5555-4555-8555-5555555555a2';

const _saturday = 'Saturday Rhythm Rockstar 2 (4 to 6)';
const _thursday = 'Thursday Paper Architect 3 (4 to 6)';

Map<String, Object?> _content(String title) => {
  'title': title,
  'description': 'Try the steps and tell a grown-up what you found.',
  'instructions': 'Do it with a trusted grown-up nearby.',
  'required_materials': ['safe household objects'],
  'duration_minutes': 10,
  'safety_instructions': 'Use only safe objects.',
  'completion_criteria': 'Share one thing you discovered.',
  'mission_type': 'interactive',
  'theme': 'saturday_rhythm_rockstar',
  'star_reward': 1,
  'xp_reward': 10,
  'is_surprise': false,
  'locale': 'en',
};

Map<String, Object?> _assignment({
  required String id,
  required String title,
  String status = 'available',
  String? taskId,
  String date = '2026-11-21',
  int slot = 1,
}) => {
  'id': id,
  'local_date': date,
  'choice_slot': slot,
  'age_band': '4_6',
  'status': status,
  'task_id': taskId,
  'content': _content(title),
};

Map<String, Object?> _choices(List<Map<String, Object?>> choices) => {
  'local_date': '2026-11-21',
  'timezone': 'Asia/Kolkata',
  'age_band': '4_6',
  'selected_assignment_id': null,
  'choices': choices,
};

Future<Harness> _child({
  List<Map<String, Object?>>? choices,
  List<Map<String, Object?>> unfinished = const [],
  List<Map<String, Object?>>? tasks,
  List<Map<String, Object?>> submissions = const [],
  Map<String, Object> prefs = onboardedPrefs,
}) async {
  final h = await Harness.create(session: Fx.childSession(), prefs: prefs);
  h.backend
    ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
    ..reply(
      'GET',
      _today,
      _choices(
        choices ??
            [
              _assignment(id: _assignmentToday, title: _saturday),
              _assignment(
                id: '99999999-9999-4999-8999-000000000003',
                title: _thursday,
                slot: 2,
              ),
            ],
      ),
    )
    ..reply('GET', _unfinished, unfinished)
    ..reply('GET', '/api/v1/tasks/submissions/mine', submissions);
  if (tasks != null) h.backend.reply('GET', '/api/v1/tasks', tasks);
  return h;
}

Future<void> _pumpApp(WidgetTester tester, Harness h, {Size? size}) async {
  // Tall window: lists are lazy, so everything is built without scrolling.
  setWindow(tester, size ?? const Size(393, 2600));
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      retry: (_, _) => null,
      child: const BalKavachApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMissions(WidgetTester tester) async {
  await tester.tap(find.text('Missions').last);
  await tester.pumpAndSettle();
}

void main() {
  group('child-facing mission titles', () {
    const cases = {
      'Saturday Rhythm Rockstar 2 (4 to 6)': 'Saturday Rhythm Rockstar 2',
      'Thursday Paper Architect 3 (7 to 10)': 'Thursday Paper Architect 3',
      'Beat Builder (11 to 15)': 'Beat Builder',
      'Beat Builder (Ages 4-6)': 'Beat Builder',
      'Clap the Rhythm': 'Clap the Rhythm',
      'Draw a Cat (and a dog)': 'Draw a Cat (and a dog)',
      'Level (2)': 'Level (2)',
      '(4 to 6)': '(4 to 6)',
    };
    cases.forEach((raw, shown) {
      test('"$raw" is shown as "$shown"', () {
        expect(childFacingMissionTitle(raw), shown);
      });
    });
  });

  testWidgets('Missions: no card shows an age range, the metadata is kept', (
    tester,
  ) async {
    final h = await _child(
      tasks: [Fx.task(title: 'Beat Builder (7 to 10)')],
    );
    await _pumpApp(tester, h);
    await _openMissions(tester);

    expect(find.text('Saturday Rhythm Rockstar 2'), findsOneWidget);
    expect(find.text('Thursday Paper Architect 3'), findsOneWidget);
    expect(find.text('Beat Builder'), findsOneWidget); // task card
    expect(find.textContaining('(4 to 6)'), findsNothing);
    expect(find.textContaining('(7 to 10)'), findsNothing);
  });

  testWidgets('Mission detail: title has no age range', (tester) async {
    final h = await _child(
      tasks: [Fx.task(title: 'Beat Builder (7 to 10)')],
    );
    await _pumpApp(tester, h);
    await _openMissions(tester);
    await tester.tap(find.text('Beat Builder'));
    await tester.pumpAndSettle();

    expect(find.byType(MissionDetailScreen), findsOneWidget);
    expect(find.text('Beat Builder'), findsWidgets);
    expect(find.textContaining('(7 to 10)'), findsNothing);
  });

  group('Start Mission opens the mission that was just chosen', () {
    testWidgets('a task created by the server after the list was loaded', (
      tester,
    ) async {
      final h = await _child(tasks: const []);
      var selected = false;
      h.backend
        ..on('POST', '/api/v1/daily-missions/$_assignmentToday/select', (_) {
          selected = true;
          return FakeReply(
            200,
            _assignment(
              id: _assignmentToday,
              title: _saturday,
              status: 'selected',
              taskId: _newTaskId,
            ),
          );
        })
        ..on(
          'GET',
          '/api/v1/tasks',
          (_) => FakeReply(200, [
            if (selected)
              Fx.task(
                id: _newTaskId,
                title: 'Saturday Rhythm Rockstar 2',
                description: 'Try the steps and tell a grown-up what you found.',
              ),
          ]),
        );
      await _pumpApp(tester, h);
      await _openMissions(tester);

      await tester.tap(find.text('Start Mission').first);
      await tester.pumpAndSettle();

      expect(find.byType(MissionDetailScreen), findsOneWidget);
      expect(
        find.text(AppLocalizationsEn().missionNotFound),
        findsNothing,
        reason: 'the detail screen must load the mission that was just chosen',
      );
      expect(find.text('Saturday Rhythm Rockstar 2'), findsWidgets);
      expect(find.byKey(const Key('mission.start')), findsOneWidget);
      expect(
        h.backend.requestsTo(
          'POST',
          '/api/v1/daily-missions/$_assignmentToday/select',
        ),
        hasLength(1),
      );
    });
  });

  group('older unfinished missions', () {
    testWidgets('an unfinished mission from an earlier day is still listed', (
      tester,
    ) async {
      final h = await _child(
        unfinished: [
          _assignment(
            id: _assignmentOlder,
            title: _thursday,
            status: 'selected',
            taskId: _olderTaskId,
            date: '2026-11-19',
          ),
        ],
        tasks: [
          Fx.task(
            id: _olderTaskId,
            title: 'Thursday Paper Architect 3',
            description: 'Fold three paper shapes and test the strongest.',
          ),
        ],
      );
      await _pumpApp(tester, h);
      await _openMissions(tester);

      expect(find.byKey(const Key('missions.unfinished')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('missions.unfinished')),
          matching: find.text('Thursday Paper Architect 3'),
        ),
        findsOneWidget,
      );
      // Two cards carry this title: today's own choice and the older mission.
      // The same task is not repeated a third time in the general list below.
      expect(find.text('Thursday Paper Architect 3'), findsNWidgets(2));
    });

    testWidgets('it opens with its real content and keeps its progress', (
      tester,
    ) async {
      final h = await _child(
        choices: [
          _assignment(id: _assignmentToday, title: _saturday),
        ],
        unfinished: [
          _assignment(
            id: _assignmentOlder,
            title: 'Moon Walk (4 to 6)',
            status: 'rejected',
            taskId: _olderTaskId,
            date: '2026-11-19',
          ),
        ],
        tasks: [
          Fx.task(
            id: _olderTaskId,
            title: 'Moon Walk',
            description: 'Walk like the moon and tell us one thing you saw.',
          ),
        ],
        submissions: [
          Fx.submission(
            id: '77777777-7777-4777-8777-7777777777a1',
            taskId: _olderTaskId,
            status: 'rejected',
          ),
        ],
      );
      await _pumpApp(tester, h);
      await _openMissions(tester);

      await tester.tap(
        find.byKey(const Key('missions.unfinished.open.$_assignmentOlder')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MissionDetailScreen), findsOneWidget);
      expect(
        find.textContaining('Walk like the moon'),
        findsOneWidget,
        reason: 'the real mission content loads',
      );
      expect(find.text('Not approved'), findsWidgets, reason: 'progress kept');
      // Opening it never selects, starts or creates anything.
      expect(
        h.backend.requests.where((r) => r.method == 'POST'),
        isEmpty,
        reason: 'reopening must not create or reset an assignment',
      );
    });

    testWidgets('nothing older: the section is absent', (tester) async {
      final h = await _child(tasks: const []);
      await _pumpApp(tester, h);
      await _openMissions(tester);

      expect(find.byKey(const Key('missions.unfinished')), findsNothing);
    });

    testWidgets('a failed older-missions request does not break Missions', (
      tester,
    ) async {
      final h = await _child(tasks: const []);
      h.backend.on(
        'GET',
        _unfinished,
        (_) => FakeReply.error(500, 'internal_error', 'boom'),
      );
      await _pumpApp(tester, h);
      await _openMissions(tester);

      expect(find.byKey(const Key('missions.unfinished')), findsNothing);
      expect(find.text('Saturday Rhythm Rockstar 2'), findsOneWidget);
    });
  });
}
