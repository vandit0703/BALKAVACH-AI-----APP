import 'package:balkavach_app/features/missions/presentation/mission_providers.dart';
import 'package:balkavach_app/features/onboarding/presentation/onboarding_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

Map<String, Object?> _dailyChoices(String locale) {
  String t(String en, String gu, String hi) =>
      switch (locale) { 'gu' => gu, 'hi' => hi, _ => en };
  return {
    'local_date': '2026-11-19',
    'timezone': 'Asia/Kolkata',
    'age_band': '7_10',
    'selected_assignment_id': null,
    'choices': [
      {
        'id': 'a1111111-1111-4111-8111-111111111111',
        'local_date': '2026-11-19',
        'choice_slot': 1,
        'age_band': '7_10',
        'status': 'available',
        'task_id': null,
        'selected_at': null,
        'started_at': null,
        'skipped_at': null,
        'content': {
          'title': t('English Mission', 'Gujarati Mission', 'Hindi Mission'),
          'description': t('English desc', 'Gujarati desc', 'Hindi desc'),
          'instructions': t('English steps', 'Gujarati steps', 'Hindi steps'),
          'required_materials': <Object?>[],
          'duration_minutes': 10,
          'safety_instructions': 'safe',
          'completion_criteria': 'done',
          'mission_type': 'offline',
          'theme': 'monday_sound_detective',
          'star_reward': 10,
          'xp_reward': 20,
          'is_surprise': false,
          'locale': locale,
          'steps': [t('Step EN', 'Step GU', 'Step HI')],
          'materials': <String>[],
          'instruction_status': 'ready',
        },
      },
      {
        'id': 'a2222222-2222-4222-8222-222222222222',
        'local_date': '2026-11-19',
        'choice_slot': 2,
        'age_band': '7_10',
        'status': 'available',
        'task_id': null,
        'selected_at': null,
        'started_at': null,
        'skipped_at': null,
        'content': {
          'title': t('English Mission 2', 'Gujarati Mission 2', 'Hindi Mission 2'),
          'description': 'desc',
          'instructions': 'steps',
          'required_materials': <Object?>[],
          'duration_minutes': 10,
          'safety_instructions': 'safe',
          'completion_criteria': 'done',
          'mission_type': 'offline',
          'theme': 'tuesday_color_explorer',
          'star_reward': 12,
          'xp_reward': 22,
          'is_surprise': false,
          'locale': locale,
          'steps': ['step'],
          'materials': <String>[],
          'instruction_status': 'ready',
        },
      },
    ],
  };
}

void main() {
  test(
    'daily missions refresh immediately on language switch and restore English',
    () async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: {'app.language_code': 'en', ...onboardedPrefs},
      );
      h.backend.on('GET', '/api/v1/daily-missions/today', (options) {
        final locale =
            (options.headers['x-app-language'] ??
                    options.headers['accept-language'] ??
                    'en')
                .toString();
        return FakeReply(200, _dailyChoices(locale));
      });
      h.backend.reply('GET', '/api/v1/daily-missions/unfinished', <Object?>[]);

      final container = h.container();
      final onboarding = container.read(onboardingControllerProvider.notifier);

      Future<List<String>> titles() async {
        final choices = await container.read(dailyMissionChoicesProvider.future);
        return choices.choices.map((c) => c.content.title).toList();
      }

      expect(await titles(), ['English Mission', 'English Mission 2']);
      expect(
        h.backend
            .requestsTo('GET', '/api/v1/daily-missions/today')
            .last
            .headers['x-app-language'],
        'en',
      );

      await onboarding.chooseLanguage('gu');
      expect(await titles(), ['Gujarati Mission', 'Gujarati Mission 2']);

      await onboarding.chooseLanguage('en');
      expect(await titles(), ['English Mission', 'English Mission 2']);

      await onboarding.chooseLanguage('hi');
      expect(await titles(), ['Hindi Mission', 'Hindi Mission 2']);
      await onboarding.chooseLanguage('gu');
      expect(await titles(), ['Gujarati Mission', 'Gujarati Mission 2']);
      await onboarding.chooseLanguage('en');
      expect(await titles(), ['English Mission', 'English Mission 2']);

      final reqs = h.backend.requestsTo('GET', '/api/v1/daily-missions/today');
      expect(reqs.length, greaterThanOrEqualTo(6));
      expect(
        reqs.map((r) => r.headers['x-app-language']).toList(),
        containsAllInOrder(['en', 'gu', 'en', 'hi', 'gu', 'en']),
      );

      final choices = await container.read(dailyMissionChoicesProvider.future);
      expect(
        choices.choices.map((c) => c.id),
        [
          'a1111111-1111-4111-8111-111111111111',
          'a2222222-2222-4222-8222-222222222222',
        ],
      );
      expect(choices.selectedAssignmentId, isNull);
      expect(choices.choices.every((c) => c.status == 'available'), isTrue);
      expect(choices.choices.every((c) => c.content.starReward == 10 || c.content.starReward == 12), isTrue);
    },
  );

  test('language choice persists after app restart', () async {
    final h = await Harness.create(prefs: onboardedPrefs);
    await h.container().read(onboardingControllerProvider.notifier).chooseLanguage('hi');
    expect(h.prefs.languageCode, 'hi');
    expect(h.container().read(appLocaleProvider).languageCode, 'hi');
  });
}
