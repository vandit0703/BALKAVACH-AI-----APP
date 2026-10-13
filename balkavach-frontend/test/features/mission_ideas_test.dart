import 'package:balkavach_app/features/missions/data/missions_repository.dart';
import 'package:balkavach_app/features/missions/domain/mission_models.dart';
import 'package:balkavach_app/features/parent_dashboard/presentation/create_mission_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

Map<String, Object?> _preset({
  String id = 'p1',
  String title = 'Brush your teeth',
  int stars = 2,
  int xp = 15,
  String? categoryId = Fx.categoryId,
}) => {
  'id': id,
  'category_id': categoryId,
  'category_name': 'Learn',
  'title': title,
  'description': 'Two minutes, morning and night.',
  'language_code': 'en',
  'suggested_star_reward': stars,
  'suggested_xp_reward': xp,
  'age_min': 3,
  'age_max': 17,
  'is_active': true,
};

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('repository', () {
    test('parses the idea library', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.reply('GET', '/api/v1/tasks/presets', [_preset()]);
      final list = await h
          .container()
          .read(missionsRepositoryProvider)
          .listPresets();
      expect(list.single.title, 'Brush your teeth');
      expect(list.single.suggestedStars, 2);
      expect(list.single.categoryName, 'Learn');
    });

    test('a server without presets yields an empty library', () async {
      final h = await Harness.create(session: Fx.parentSession());
      expect(
        await h.container().read(missionsRepositoryProvider).listPresets(),
        isEmpty,
      );
    });
  });

  group('create mission', () {
    Future<Harness> pump(
      WidgetTester tester, {
      Mission? mission,
      List<Map<String, Object?>>? presets,
    }) async {
      final h = await Harness.create(
        session: Fx.parentSession(),
        prefs: onboardedPrefs,
      );
      h.backend.reply('GET', '/api/v1/tasks/presets', presets ?? [_preset()]);
      await pumpScreen(
        tester,
        CreateMissionScreen(mission: mission),
        overrides: h.overrides,
      );
      return h;
    }

    testWidgets('choosing an idea fills the form, which stays editable', (
      tester,
    ) async {
      await pump(tester);
      await _tap(tester, find.byKey(const Key('mission.ideas')));
      expect(find.text('Mission ideas'), findsOneWidget);
      expect(find.text('Learn · 2 ★ · 15 XP'), findsOneWidget);

      await _tap(tester, find.byKey(const Key('idea.p1')));
      expect(
        find.widgetWithText(TextFormField, 'Brush your teeth'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, '15'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('mission.stars')), '4');
      expect(find.widgetWithText(TextFormField, '4'), findsOneWidget);
    });

    testWidgets(
      'an idea is only a starting point: nothing is saved until Save',
      (tester) async {
        final h = await pump(tester);
        await _tap(tester, find.byKey(const Key('mission.ideas')));
        await _tap(tester, find.byKey(const Key('idea.p1')));
        expect(h.backend.requestsTo('POST', '/api/v1/tasks'), isEmpty);
      },
    );

    testWidgets('an empty library says so', (tester) async {
      await pump(tester, presets: <Map<String, Object?>>[]);
      await _tap(tester, find.byKey(const Key('mission.ideas')));
      expect(find.text('No ideas available right now.'), findsOneWidget);
    });

    testWidgets('editing an existing mission offers no ideas', (tester) async {
      await pump(tester, mission: Mission.fromJson(Fx.task()));
      expect(find.byKey(const Key('mission.ideas')), findsNothing);
    });
  });
}
