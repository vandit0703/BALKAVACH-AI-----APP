import 'dart:convert';
import 'dart:io';

import 'package:balkavach_app/features/missions/presentation/mission_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

/// The real catalogue (`scripts/export_catalogue_fixture.py`), including the structured fields and the authored
/// child-facing "what to submit" text.
final _entries =
    (jsonDecode(
              File(
                'test/fixtures/daily_mission_catalogue.json',
              ).readAsStringSync(),
            )
            as List<dynamic>)
        .cast<Map<String, dynamic>>();

const _ages = ['4_6', '7_10', '11_15'];
const _locales = ['en', 'gu', 'hi'];
const _titles = {
  'en': ('Steps', 'What to submit', 'Safety', 'What you need'),
  'hi': ('चरण', 'क्या जमा करना है', 'सुरक्षा', 'आपको क्या चाहिए'),
  'gu': ('પગલાં', 'શું જમા કરવાનું છે', 'સલામતી', 'તમને શું જોઈશે'),
};

Map<String, dynamic> _content(String slug, String age, String locale) =>
    _entries.firstWhere(
          (e) =>
              e['slug'] == slug &&
              e['age_band'] == age &&
              e['locale'] == locale,
        )['content']
        as Map<String, dynamic>;

Future<Harness> _harness(Map<String, dynamic> c, String age) async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  h.backend
    ..reply('GET', '/api/v1/tasks', [
      {
        ...Fx.task(
          title: c['title'] as String,
          description: c['description'] as String,
        ),
        // What an approval pays: exactly 10 stars and 15 XP.
        'star_reward': 10,
        'xp_reward': 15,
      },
    ])
    ..reply('GET', '/api/v1/daily-missions/today', {
      'local_date': '2026-11-22',
      'timezone': 'Asia/Kolkata',
      'age_band': age,
      'selected_assignment_id': '99999999-9999-4999-8999-000000000001',
      'choices': [
        {
          'id': '99999999-9999-4999-8999-000000000001',
          'local_date': '2026-11-22',
          'choice_slot': 1,
          'age_band': age,
          'status': 'selected',
          'task_id': Fx.taskId,
          'content': c,
        },
      ],
    });
  return h;
}

void main() {
  const slug = 'cat1_monday_sound_detective';
  for (final locale in _locales) {
    for (final age in _ages) {
      for (final size in const [Size(320, 640), Size(840, 700)]) {
        testWidgets(
          '$age $locale at ${size.width.toInt()}px, text x2: the guide, the reward and the start button',
          (tester) async {
            final c = _content(slug, age, locale);
            final h = await _harness(c, age);
            await pumpScreen(
              tester,
              const MissionDetailScreen(taskId: Fx.taskId),
              overrides: h.overrides,
              size: size,
              textScale: 2,
              locale: Locale(locale),
            );
            expect(tester.takeException(), isNull);
            final (steps, submit, safety, need) = _titles[locale]!;
            for (final title in [steps, submit, safety, need]) {
              expect(
                find.text(title, skipOffstage: false),
                findsOneWidget,
                reason: title,
              );
            }
            // the authored child-facing submission, not the reviewer sentence
            expect(
              find.text(
                c['submission_requirements'] as String,
                skipOffstage: false,
              ),
              findsOneWidget,
            );
            for (final step in (c['steps'] as List<dynamic>).cast<String>()) {
              expect(find.text(step, skipOffstage: false), findsOneWidget);
            }
            expect(
              find.byKey(const Key('mission.guide.incomplete')),
              findsNothing,
            );
            // unchanged: progress tracker, reward and the start button
            expect(
              find.byKey(const Key('mission.progress'), skipOffstage: false),
              findsOneWidget,
            );
            expect(
              find.textContaining('10', skipOffstage: false),
              findsWidgets,
            );
            expect(
              find.textContaining('15', skipOffstage: false),
              findsWidgets,
            );
            expect(
              find.byKey(const Key('mission.start'), skipOffstage: false),
              findsOneWidget,
            );
          },
        );
      }
    }
  }

  testWidgets('English shows the exact reward sentence: 10 stars and 15 XP', (
    tester,
  ) async {
    final c = _content(slug, '7_10', 'en');
    final h = await _harness(c, '7_10');
    await pumpScreen(
      tester,
      const MissionDetailScreen(taskId: Fx.taskId),
      overrides: h.overrides,
      textScale: 1,
    );
    expect(
      find.text('Finish this mission to earn 10 stars and 15 XP.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a placeholder mission shows the honest notice, never generic text',
    (tester) async {
      final c =
          {
            ..._content(slug, '7_10', 'en'),
            'description': 'A creative learning adventure for ages 7 to 10.',
            'instructions':
                'Try the steps, notice what you discover, and tell a trusted grown-up what you learned.',
            'completion_criteria':
                'Complete the steps and share one thing you discovered.',
          }..removeWhere(
            (k, _) => const {
              'steps',
              'submission_requirements',
              'instruction_status',
              'materials',
            }.contains(k),
          );
      final h = await _harness(c, '7_10');
      await pumpScreen(
        tester,
        const MissionDetailScreen(taskId: Fx.taskId),
        overrides: h.overrides,
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('mission.guide.incomplete')), findsOneWidget);
      expect(find.textContaining('learning adventure'), findsNothing);
      expect(find.textContaining('Try the steps'), findsNothing);
    },
  );
}
