import 'dart:convert';
import 'dart:io';

import 'package:balkavach_app/features/missions/domain/daily_mission_models.dart';
import 'package:balkavach_app/features/missions/presentation/child_shell.dart';
import 'package:balkavach_app/features/missions/presentation/mission_detail_screen.dart';
import 'package:balkavach_app/features/missions/presentation/missions_screen.dart';
import 'package:balkavach_app/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

/// The real localized catalogue (`balkavach-backend/app/content/daily_missions`), exported by
/// `scripts/export_catalogue_fixture.py`: 42 templates (6 per weekday theme) x 3 age bands x en/gu/hi = 378 localized versions.
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
const _slugs = [
  'cat1_monday_sound_detective',
  'cat1_monday_look_closer',
  'cat1_tuesday_memory_master',
  'cat1_tuesday_picnic_memory',
  'cat1_wednesday_magic_story_maker',
  'cat1_wednesday_mystery_clues',
  'cat1_thursday_paper_architect',
  'cat1_thursday_paper_flight',
  'cat1_friday_emotion_detective',
  'cat1_friday_kind_clues',
  'cat1_saturday_rhythm_rockstar',
  'cat1_saturday_mirror_moves',
  'cat1_sunday_future_inventor',
  'cat1_sunday_helper_plan',
];

Map<String, dynamic> _content(String slug, String age, String locale) =>
    _entries.firstWhere(
          (e) =>
              e['slug'] == slug &&
              e['age_band'] == age &&
              e['locale'] == locale,
        )['content']
        as Map<String, dynamic>;

Map<String, Object?> _today(String age, String locale, List<String> slugs) => {
  'local_date': '2026-10-02',
  'timezone': 'Asia/Kolkata',
  'age_band': age,
  'selected_assignment_id': null,
  'choices': [
    for (var i = 0; i < slugs.length; i++)
      {
        'id': '99999999-9999-4999-8999-00000000000${i + 1}',
        'local_date': '2026-10-02',
        'choice_slot': i + 1,
        'age_band': age,
        'status': 'available',
        'task_id': null,
        'content': _content(slugs[i], age, locale),
      },
  ],
};

/// The 28 templates added in milestone C2 part 2 (everything in the fixture that is not one of the first 14).
final _newSlugs = [
  for (final slug in {for (final e in _entries) e['slug'] as String})
    if (!_slugs.contains(slug)) slug,
];

/// Three choices at a time, rotating so every template is shown.
const _triples = [
  [0, 1, 2],
  [3, 4, 5],
  [6, 7, 8],
  [9, 10, 11],
  [12, 13, 0],
];

void main() {
  test('the fixture holds all 378 localized versions and every one parses', () {
    expect(_entries, hasLength(378));
    expect(_newSlugs, hasLength(28));
    for (final entry in _entries) {
      final choices = DailyMissionChoices.fromJson(
        _today(entry['age_band'] as String, entry['locale'] as String, [
          entry['slug'] as String,
        ]),
      );
      final content = choices.choices.single.content;
      expect(content.locale, entry['locale']);
      expect(content.title, isNotEmpty);
      expect(content.durationMinutes, inInclusiveRange(5, 15));
      expect(content.requiredMaterials, isNotEmpty);
    }
  });

  test(
    'Gujarati and Hindi cards carry their own script, never romanised text',
    () {
      final gujarati = RegExp(r'[઀-૿]');
      final devanagari = RegExp(r'[ऀ-ॿ]');
      for (final entry in _entries) {
        final c = entry['content'] as Map<String, dynamic>;
        final text = '${c['title']} ${c['description']}';
        switch (entry['locale']) {
          case 'gu':
            expect(gujarati.hasMatch(text), isTrue, reason: text);
          case 'hi':
            expect(devanagari.hasMatch(text), isTrue, reason: text);
          default:
            expect(RegExp(r'^[\x20-\x7e]+$').hasMatch(text), isTrue);
        }
      }
    },
  );

  group('three daily choices render without overflow', () {
    const sizes = [
      Size(280, 640),
      Size(320, 640),
      Size(393, 852),
      Size(840, 1000),
    ];
    const scales = [1.0, 2.0];
    for (final age in _ages) {
      for (final locale in _locales) {
        for (final triple in _triples) {
          for (final size in sizes) {
            for (final scale in scales) {
              testWidgets(
                '$age $locale themes $triple ${size.width.toInt()}px x$scale',
                (tester) async {
                  final h = await Harness.create(
                    session: Fx.childSession(),
                    prefs: onboardedPrefs,
                  );
                  final themes = [for (final i in triple) _slugs[i]];
                  h.backend.reply(
                    'GET',
                    '/api/v1/daily-missions/today',
                    _today(age, locale, themes),
                  );
                  await pumpScreen(
                    tester,
                    const ChildShell(
                      location: '/child/missions',
                      child: MissionsScreen(),
                    ),
                    overrides: h.overrides,
                    size: size,
                    textScale: scale,
                    locale: Locale(locale),
                  );

                  expect(tester.takeException(), isNull);
                  for (final theme in themes) {
                    final content = _content(theme, age, locale);
                    expect(
                      find.text(
                        content['title'] as String,
                        skipOffstage: false,
                      ),
                      findsOneWidget,
                      reason: 'title of $theme',
                    );
                    final card = find.ancestor(
                      of: find.text(content['title'] as String),
                      matching: find.byType(AppCard),
                    );
                    expect(
                      tester.getRect(card.first).right,
                      lessThanOrEqualTo(size.width),
                      reason:
                          'card for $theme fits inside the ${size.width}px screen',
                    );
                    expect(
                      find.text(
                        content['description'] as String,
                        skipOffstage: false,
                      ),
                      findsOneWidget,
                    );
                  }
                },
              );
            }
          }
        }
      }
    }
  });

  group('the 28 new templates render without overflow', () {
    const sizes = [Size(280, 640), Size(393, 852)];
    for (final age in _ages) {
      for (final locale in _locales) {
        for (var start = 0; start < _newSlugs.length; start += 3) {
          for (final size in sizes) {
            testWidgets(
              '$age $locale from template $start ${size.width.toInt()}px',
              (tester) async {
                final themes = [
                  for (var i = 0; i < 3; i++)
                    _newSlugs[(start + i) % _newSlugs.length],
                ];
                final h = await Harness.create(
                  session: Fx.childSession(),
                  prefs: onboardedPrefs,
                );
                h.backend.reply(
                  'GET',
                  '/api/v1/daily-missions/today',
                  _today(age, locale, themes),
                );
                await pumpScreen(
                  tester,
                  const ChildShell(
                    location: '/child/missions',
                    child: MissionsScreen(),
                  ),
                  overrides: h.overrides,
                  size: size,
                  textScale: size.width < 300 ? 2.0 : 1.0,
                  locale: Locale(locale),
                );
                expect(tester.takeException(), isNull);
                for (final theme in themes) {
                  expect(
                    find.text(
                      _content(theme, age, locale)['title'] as String,
                      skipOffstage: false,
                    ),
                    findsOneWidget,
                    reason: 'title of $theme',
                  );
                }
              },
            );
          }
        }
      }
    }
  });

  group('the longest new mission shows full instructions and parent check', () {
    for (final locale in _locales) {
      for (final age in _ages) {
        testWidgets('$age $locale at 320px x2', (tester) async {
          final longest = _newSlugs.reduce((a, b) {
            int size(String slug) {
              final c = _content(slug, age, locale);
              return '${c['description']}${c['instructions']}${c['completion_criteria']}'
                  .length;
            }

            return size(a) >= size(b) ? a : b;
          });
          final h = await Harness.create(
            session: Fx.childSession(),
            prefs: onboardedPrefs,
          );
          final c = _content(longest, age, locale);
          final description =
              '${c['description']}\n\n${c['instructions']}\n\n${c['completion_criteria']}';
          h.backend.reply('GET', '/api/v1/tasks', [
            Fx.task(title: c['title'] as String, description: description),
          ]);
          await pumpScreen(
            tester,
            const MissionDetailScreen(taskId: Fx.taskId),
            overrides: h.overrides,
            size: const Size(320, 640),
            textScale: 2,
            locale: Locale(locale),
          );
          expect(tester.takeException(), isNull, reason: longest);
          final lastLine = (c['completion_criteria'] as String)
              .split('\n')
              .last;
          expect(
            find.textContaining(lastLine.substring(0, 12), skipOffstage: false),
            findsWidgets,
            reason: 'parent check line is shown for $longest',
          );
        });
      }
    }
  });

  group('the chosen mission shows full instructions and the parent check', () {
    for (final locale in _locales) {
      for (final age in _ages) {
        testWidgets('$age $locale at 320px x2', (tester) async {
          final h = await Harness.create(
            session: Fx.childSession(),
            prefs: onboardedPrefs,
          );
          final c = _content('cat1_thursday_paper_architect', age, locale);
          // The backend builds the Task description exactly like this (task_description()).
          final description =
              '${c['description']}\n\n${c['instructions']}\n\n${c['completion_criteria']}';
          h.backend.reply('GET', '/api/v1/tasks', [
            Fx.task(title: c['title'] as String, description: description),
          ]);
          await pumpScreen(
            tester,
            const MissionDetailScreen(taskId: Fx.taskId),
            overrides: h.overrides,
            size: const Size(320, 640),
            textScale: 2,
            locale: Locale(locale),
          );
          expect(tester.takeException(), isNull);
          expect(find.text(c['title'] as String), findsWidgets);
          final lastLine = (c['completion_criteria'] as String)
              .split('\n')
              .last;
          expect(
            find.textContaining(lastLine.substring(0, 12), skipOffstage: false),
            findsWidgets,
            reason: 'parent check line is shown',
          );
        });
      }
    }
  });
}
