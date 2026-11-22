import 'dart:convert';
import 'dart:io';

import 'package:balkavach_app/features/missions/domain/daily_mission_models.dart';
import 'package:balkavach_app/features/missions/presentation/widgets/mission_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

/// The real catalogue exported by `scripts/export_catalogue_fixture.py`
/// (42 templates x 3 age bands x en/gu/hi = 378 localized versions).
final _entries =
    (jsonDecode(
              File(
                'test/fixtures/daily_mission_catalogue.json',
              ).readAsStringSync(),
            )
            as List<dynamic>)
        .cast<Map<String, dynamic>>();

const _placeholder =
    'Try the steps, notice what you discover, and tell a trusted grown-up what you learned.';

Map<String, dynamic> _json({Map<String, Object?> over = const {}}) => {
  'title': 'Plants',
  'description': 'Look at a plant.',
  'instructions': '1. a\n2. b',
  'required_materials': ['Water'],
  'duration_minutes': 10,
  'safety_instructions': 'Ask a grown-up.',
  'completion_criteria': 'Show it.',
  'mission_type': 'offline',
  'theme': 't',
  'star_reward': 10,
  'xp_reward': 15,
  ...over,
};

DailyMissionContent _content(
  String slug,
  String age,
  String locale, {
  String? submit,
}) => DailyMissionContent.fromJson({
  ..._entries.firstWhere(
        (e) =>
            e['slug'] == slug && e['age_band'] == age && e['locale'] == locale,
      )['content']
      as Map<String, dynamic>,
  'submission_requirements': ?submit,
});

Future<void> _pump(
  WidgetTester tester,
  DailyMissionContent content, {
  double width = 393,
  double textScale = 1,
  String locale = 'en',
}) => pumpScreen(
  tester,
  Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: MissionGuide(content: content),
    ),
  ),
  overrides: const [],
  size: Size(width, 900),
  textScale: textScale,
  locale: Locale(locale),
);

void main() {
  group('DailyMissionContent structured fields', () {
    test('every one of the 378 catalogue versions parses with real steps', () {
      expect(_entries, hasLength(378));
      for (final e in _entries) {
        final c = DailyMissionContent.fromJson(
          e['content'] as Map<String, dynamic>,
        );
        expect(c.instructionsReady, isTrue, reason: '${e['slug']}');
        expect(c.steps.length, greaterThanOrEqualTo(3));
        expect(c.materials, isNotEmpty);
        // Reviewer-facing text is never handed to the child: until a child-facing
        // "what to submit" is authored the field is null and the section is omitted.
        expect(c.submissionRequirements, isNull);
      }
    });

    test('an older server (no structured fields) still yields its steps', () {
      final c = DailyMissionContent.fromJson(_json());
      expect(c.steps, ['a', 'b']);
      expect(c.instructionStatus, 'ready');
      expect(c.learningObjective, isNull);
      expect(c.materials, ['Water']);
    });

    test('placeholder text yields no steps and an incomplete status', () {
      final c = DailyMissionContent.fromJson(
        _json(over: {'instructions': _placeholder}),
      );
      expect(c.steps, isEmpty);
      expect(c.instructionsReady, isFalse);
    });

    test('server values win; blank text becomes null, never filler', () {
      final c = DailyMissionContent.fromJson(
        _json(
          over: {
            'steps': ['First', ' ', 'Second'],
            'learning_objective': '  ',
            'observation_guidance': 'Look closely.',
            'materials': ['Nothing needed'],
            'instruction_status': 'ready',
          },
        ),
      );
      expect(c.steps, ['First', 'Second']);
      expect(c.learningObjective, isNull);
      expect(c.observationGuidance, 'Look closely.');
      expect(c.materials, ['Nothing needed']);
    });

    test('the reward fields are untouched (10 Stars and 15 XP)', () {
      final c = DailyMissionContent.fromJson(_json());
      expect((c.starReward, c.xpReward), (10, 15));
    });
  });

  group('MissionGuide', () {
    testWidgets('shows every section with numbered steps', (tester) async {
      final base = _content('cat1_monday_sound_detective', '7_10', 'en');
      final content = DailyMissionContent.fromJson({
        ..._entries.firstWhere(
              (e) =>
                  e['slug'] == 'cat1_monday_sound_detective' &&
                  e['age_band'] == '7_10' &&
                  e['locale'] == 'en',
            )['content']
            as Map<String, dynamic>,
        'learning_objective': 'Notice sounds around you.',
        'observation_guidance': 'Which sound is loudest?',
        'submission_requirements': 'Tell a grown-up your three sounds.',
      });
      await _pump(tester, content);
      expect(find.text('What you will learn'), findsOneWidget);
      expect(find.text('What you need'), findsOneWidget);
      expect(find.text('Steps'), findsOneWidget);
      expect(find.text('What to observe'), findsOneWidget);
      expect(find.text('What to submit'), findsOneWidget);
      expect(find.text('Safety'), findsOneWidget);
      expect(find.byKey(const Key('mission.guide.time')), findsOneWidget);
      for (var i = 1; i <= base.steps.length; i++) {
        expect(find.text('$i'), findsWidgets);
      }
      expect(find.text(base.steps.first), findsOneWidget);
      expect(find.text('Tell a grown-up your three sounds.'), findsOneWidget);
    });

    testWidgets('sections the mission does not have are left out', (
      tester,
    ) async {
      await _pump(tester, _content('cat1_monday_sound_detective', '4_6', 'en'));
      expect(find.text('What you will learn'), findsNothing);
      expect(find.text('What to observe'), findsNothing);
      expect(find.text('What to submit'), findsNothing);
      expect(find.text('Steps'), findsOneWidget);
    });

    testWidgets('a mission without real steps shows an honest notice', (
      tester,
    ) async {
      await _pump(
        tester,
        DailyMissionContent.fromJson(
          _json(over: {'instructions': _placeholder}),
        ),
      );
      expect(find.byKey(const Key('mission.guide.incomplete')), findsOneWidget);
      expect(find.text('These instructions are not ready yet'), findsOneWidget);
      expect(find.text('Steps'), findsNothing);
      expect(find.textContaining('learning adventure'), findsNothing);
    });

    testWidgets('Hindi and Gujarati use their own section titles', (
      tester,
    ) async {
      await _pump(
        tester,
        _content(
          'cat1_monday_sound_detective',
          '7_10',
          'hi',
          submit: 'अपनी आवाज़ें बताओ।',
        ),
        locale: 'hi',
      );
      expect(find.text('चरण'), findsOneWidget);
      expect(find.text('क्या जमा करना है'), findsOneWidget);
      expect(find.text('Steps'), findsNothing);
      await _pump(
        tester,
        _content(
          'cat1_monday_sound_detective',
          '7_10',
          'gu',
          submit: 'તમારા અવાજો કહો.',
        ),
        locale: 'gu',
      );
      expect(find.text('પગલાં'), findsOneWidget);
      expect(find.text('શું જમા કરવાનું છે'), findsOneWidget);
    });

    for (final width in [320.0, 360.0, 411.0, 600.0, 840.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'no overflow at ${width.toInt()} px, text x$scale, all ages and languages',
          (tester) async {
            for (final age in ['4_6', '7_10', '11_15']) {
              for (final locale in ['en', 'gu', 'hi']) {
                await _pump(
                  tester,
                  _content('cat1_monday_sound_detective', age, locale),
                  width: width,
                  textScale: scale,
                  locale: locale,
                );
                expect(
                  tester.takeException(),
                  isNull,
                  reason: '$age/$locale at $width x$scale',
                );
              }
            }
          },
        );
      }
    }

    testWidgets('long steps wrap on the narrowest screen at 2x text', (
      tester,
    ) async {
      final long = DailyMissionContent.fromJson(
        _json(
          over: {
            'steps': [
              for (var i = 0; i < 7; i++)
                'Step ${i + 1}: ${'a rather long sentence about careful observation ' * 4}',
            ],
            'learning_objective': 'x ' * 80,
            'observation_guidance': 'y ' * 80,
            'submission_requirements': 'z ' * 80,
            'materials': [for (var i = 0; i < 8; i++) 'A fairly long item $i'],
            'instruction_status': 'ready',
          },
        ),
      );
      await _pump(tester, long, width: 320, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });
}
