// Wrong-age missions never reach the child, and age problems are explained.
//
// Mock/fake tests: the app runs against `FakeBackend`. The backend is the
// authority on eligibility (balkavach-backend/tests/test_child_age_eligibility.py
// on SQLite with the real catalogue, test_api_mission_age_eligibility.py on
// PostgreSQL); these tests prove the app shows only what it should and
// refreshes for the signed-in child.
import 'package:balkavach_app/features/missions/presentation/child_shell.dart';
import 'package:balkavach_app/features/missions/presentation/mission_providers.dart';
import 'package:balkavach_app/features/missions/presentation/mission_submit_screen.dart';
import 'package:balkavach_app/features/missions/presentation/missions_screen.dart';
import 'package:balkavach_app/l10n/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

final _en = AppLocalizationsEn();
const _today = '/api/v1/daily-missions/today';
const _unfinished = '/api/v1/daily-missions/unfinished';
const _day = '2026-10-12';

Map<String, Object?> _choice(
  String id,
  String title,
  String band, {
  String status = 'available',
  String? taskId,
  String date = _day,
  int slot = 1,
}) => {
  'id': id,
  'local_date': date,
  'choice_slot': slot,
  'age_band': band,
  'status': status,
  'task_id': taskId,
  'content': {
    'title': title,
    'description': 'About $title.',
    'instructions': '1. Do it.',
    'required_materials': ['paper'],
    'duration_minutes': 10,
    'safety_instructions': 'Stay safe.',
    'completion_criteria': 'Done.',
    'mission_type': 'offline',
    'theme': 'monday_sound_detective',
    'star_reward': 10,
    'xp_reward': 15,
    'is_surprise': false,
    'locale': 'en',
  },
};

Map<String, Object?> _todayBody(
  String band,
  List<Map<String, Object?>> choices,
) => {
  'local_date': _day,
  'timezone': 'Asia/Kolkata',
  'age_band': band,
  'selected_assignment_id': null,
  'choices': choices,
};

Future<Harness> _child() async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  h.backend
    ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
    ..reply('GET', '/api/v1/tasks', <Object?>[])
    ..reply('GET', '/api/v1/tasks/submissions/mine', <Object?>[])
    ..reply('GET', _unfinished, <Object?>[]);
  return h;
}

Future<void> _missions(
  WidgetTester tester,
  Harness h, {
  Locale locale = const Locale('en'),
}) async {
  await pumpScreen(
    tester,
    const ChildShell(location: '/child/missions', child: MissionsScreen()),
    overrides: h.overrides,
    size: const Size(393, 3000),
    locale: locale,
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a choice labelled for another age group is never shown', (
    tester,
  ) async {
    final h = await _child();
    h.backend.reply(
      'GET',
      _today,
      _todayBody('7_10', [
        _choice('a1', 'Paper Plane Lab', '7_10'),
        _choice('a2', 'Three Sounds Hunt', '4_6', slot: 2),
      ]),
    );
    await _missions(tester, h);
    expect(find.text('Paper Plane Lab'), findsOneWidget);
    expect(find.text('Three Sounds Hunt'), findsNothing);
  });

  testWidgets('an older mission from another age group is not continued', (
    tester,
  ) async {
    final h = await _child();
    h.backend
      ..reply(
        'GET',
        _today,
        _todayBody('11_15', [_choice('a1', 'Beat Builder', '11_15')]),
      )
      ..reply('GET', _unfinished, [
        _choice(
          'a9',
          'Little Moon Walk',
          '4_6',
          status: 'selected',
          taskId: '55555555-5555-4555-8555-5555555555d9',
          date: '2026-10-10',
        ),
      ]);
    await _missions(tester, h);
    expect(find.byKey(const Key('missions.unfinished')), findsNothing);
    expect(find.text('Little Moon Walk'), findsNothing);
    expect(find.text('Beat Builder'), findsOneWidget);
  });

  for (final (code, message) in [
    ('birth_date_required', _en.errorBirthDateRequired),
    ('birth_date_invalid', _en.errorBirthDateInvalid),
    ('daily_missions_age_range', _en.errorAgeRange),
  ]) {
    testWidgets('$code: explained, no missions guessed', (tester) async {
      final h = await _child();
      h.backend.on(
        'GET',
        _today,
        (_) => FakeReply.error(422, code, 'server message'),
      );
      await _missions(tester, h);
      expect(find.byKey(const Key('missions.today.notice')), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(find.byKey(const Key('missions.today')), findsNothing);
    });
  }

  testWidgets('the age notices fit in Gujarati and Hindi', (tester) async {
    for (final locale in const [Locale('gu'), Locale('hi')]) {
      final h = await _child();
      h.backend.on(
        'GET',
        _today,
        (_) => FakeReply.error(422, 'birth_date_required', 'x'),
      );
      await _missions(tester, h, locale: locale);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('missions.today.notice')), findsOneWidget);
    }
  });

  testWidgets('submitting a mission the server says is for another age '
      'shows why and stays on the form', (tester) async {
    final h = await _child();
    h.backend
      ..reply('GET', '/api/v1/tasks', [Fx.task()])
      ..on(
        'POST',
        '/api/v1/tasks/${Fx.taskId}/submissions',
        (_) => FakeReply.error(409, 'mission_not_age_eligible', 'nope'),
      );
    await pumpScreen(
      tester,
      const MissionSubmitScreen(taskId: Fx.taskId),
      overrides: h.overrides,
      size: const Size(393, 1200),
    );
    await tester.tap(find.byKey(const Key('submit.button')));
    await tester.pumpAndSettle();
    expect(find.text(_en.errorMissionNotForAge), findsOneWidget);
    expect(find.byType(MissionSubmitScreen), findsOneWidget);
  });

  test('missions are fetched again for a different signed-in child', () async {
    final h = await _child();
    h.backend.reply(
      'GET',
      _today,
      _todayBody('4_6', [_choice('a1', 'Three Sounds Hunt', '4_6')]),
    );
    final who = NotifierProvider<_Who, String?>(_Who.new);
    final container = ProviderContainer(
      overrides: [
        ...h.overrides,
        activeChildIdProvider.overrideWith((ref) => ref.watch(who)),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    container.listen(dailyMissionChoicesProvider, (_, _) {});

    final first = await container.read(dailyMissionChoicesProvider.future);
    expect(first.ageBand, '4_6');

    // Another child (11) signs in on this device.
    h.backend.reply(
      'GET',
      _today,
      _todayBody('11_15', [_choice('b1', 'Beat Builder', '11_15')]),
    );
    container.read(who.notifier).set('another-child');
    final second = await container.read(dailyMissionChoicesProvider.future);
    expect(second.ageBand, '11_15');
    expect(second.choices.map((c) => c.content.title), ['Beat Builder']);
    expect(h.backend.requestsTo('GET', _today), hasLength(2));
  });
}

class _Who extends Notifier<String?> {
  @override
  String? build() => Fx.childId;

  void set(String id) => state = id;
}
