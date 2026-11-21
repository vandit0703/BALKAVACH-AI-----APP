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

  rewardFormTests();

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
      // The idea's suggested reward is ignored; the configured amount stays explicit.
      expect(find.text('Learn'), findsWidgets);
      expect(find.text('Learn · 2 ★ · 15 XP'), findsNothing);

      await _tap(tester, find.byKey(const Key('idea.p1')));
      expect(
        find.widgetWithText(TextFormField, 'Brush your teeth'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('mission.stars')), findsOneWidget);
      expect(find.byKey(const Key('mission.xp')), findsOneWidget);
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

// The parent form submits configured rewards; the server validates and pays them.
void rewardFormTests() {
  group('rewards on the parent form', () {
    Future<Harness> pump(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      Size size = const Size(393, 1400),
      double textScale = 1,
    }) async {
      final h = await Harness.create(
        session: Fx.parentSession(),
        prefs: onboardedPrefs,
      );
      h.backend.reply('GET', '/api/v1/tasks/presets', [_preset()]);
      await pumpScreen(
        tester,
        const CreateMissionScreen(),
        overrides: h.overrides,
        locale: locale,
        size: size,
        textScale: textScale,
      );
      return h;
    }

    testWidgets('shows editable star and XP rewards', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('mission.stars')), findsOneWidget);
      expect(find.byKey(const Key('mission.xp')), findsOneWidget);
    });

    testWidgets('a created mission sends its configured rewards', (
      tester,
    ) async {
      final h = await pump(tester);
      h.backend.reply('POST', '/api/v1/tasks', {
        ...Fx.task(),
        'star_reward': 10,
        'xp_reward': 15,
      }, status: 201);
      await tester.enterText(find.byKey(const Key('mission.title')), 'Tidy up');
      await _tap(tester, find.byKey(const Key('mission.submit')));
      final body =
          h.backend.requestsTo('POST', '/api/v1/tasks').single.data
              as Map<String, dynamic>;
      expect(body['star_reward'], 10);
      expect(body['xp_reward'], 15);
      expect(body.containsKey('required_video_seconds'), isFalse);
      expect(body['title'], 'Tidy up');
    });

    testWidgets('a video-required mission sends seconds, not client progress', (
      tester,
    ) async {
      final h = await pump(tester);
      h.backend.reply('POST', '/api/v1/tasks', Fx.task(), status: 201);
      await tester.enterText(find.byKey(const Key('mission.title')), 'Watch');
      await tester.ensureVisible(
        find.byKey(const Key('mission.video.required')),
      );
      await tester.tap(find.byKey(const Key('mission.video.required')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('mission.video.minutes')),
        '15',
      );
      await tester.ensureVisible(find.byKey(const Key('mission.submit')));
      await _tap(tester, find.byKey(const Key('mission.submit')));

      final body =
          h.backend.requestsTo('POST', '/api/v1/tasks').single.data
              as Map<String, dynamic>;
      expect(body['required_video_seconds'], 900);
      expect(body.containsKey('verified_video_seconds'), isFalse);
      expect(body['star_reward'], 10);
      expect(body['xp_reward'], 15);
    });

    for (final locale in const ['en', 'gu', 'hi']) {
      for (final (size, scale) in const [
        (Size(320, 1600), 2.0),
        (Size(393, 1400), 1.0),
        (Size(840, 1200), 1.0),
      ]) {
        testWidgets('$locale ${size.width.toInt()}px x$scale fits', (
          tester,
        ) async {
          await pump(
            tester,
            locale: Locale(locale),
            size: size,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('mission.stars')), findsOneWidget);
          expect(find.byKey(const Key('mission.xp')), findsOneWidget);
        });
      }
    }
  });
}
