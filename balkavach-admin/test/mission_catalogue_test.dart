import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _complete = 'aaaaaaaa-1111-4111-8111-000000000001';
const _partial = 'aaaaaaaa-1111-4111-8111-000000000002';

Map<String, Object?> _summary(
  String id,
  String slug, {
  required List<String> missing,
  bool published = false,
}) => {
  'id': id,
  'slug': slug,
  'theme': 'monday_sound_detective',
  'mission_type': 'offline',
  'is_surprise': false,
  'is_published': published,
  'star_reward': 1,
  'xp_reward': 10,
  'mystery_bonus': null,
  'assignment_count': 12,
  'variation_count': 9 - missing.length,
  'missing': missing,
  'is_complete': missing.isEmpty,
};

Map<String, Object?> _variation(
  String band,
  String locale,
  String title,
  String body,
) => {
  'id': '$band-$locale',
  'age_band': band,
  'locale': locale,
  'variation_key': 'c1',
  'title': title,
  'description': body,
  'instructions': '1. $body',
  'required_materials': ['Paper'],
  'duration_minutes': 8,
  'safety_instructions': 'Stay inside.',
  'completion_criteria': 'Show it.',
  'preview': '$body\n\n1. $body\n\nShow it.',
};

FakeServer _server({List<String> permissions = const ['*']}) {
  const hindiMissing = ['4_6:hi', '7_10:hi', '11_15:hi'];
  return baseServer(permissions: permissions)
    ..reply('GET', '/api/v1/admin/tasks', <Object?>[])
    ..reply('GET', '/api/v1/admin/daily-missions/templates', [
      _summary(_complete, 'cat1_complete', missing: const []),
      _summary(_partial, 'cat1_partial', missing: hindiMissing),
    ])
    ..reply('GET', '/api/v1/admin/daily-missions/templates/$_partial', {
      ..._summary(_partial, 'cat1_partial', missing: hindiMissing),
      'variations': [
        for (final band in ['4_6', '7_10', '11_15']) ...[
          _variation(
            band,
            'en',
            'Three Sounds Hunt',
            'Listen for three sounds.',
          ),
          _variation(band, 'gu', 'ત્રણ અવાજની શોધ', 'ત્રણ અવાજ શોધો.'),
        ],
      ],
    })
    ..reply(
      'PATCH',
      '/api/v1/admin/daily-missions/templates/$_complete/publish',
      {'id': _complete, 'is_published': true},
    );
}

Future<void> _open(WidgetTester tester, FakeServer server) async {
  await pumpAdmin(tester, server);
  await openSection(tester, 'Missions');
  await tester.tap(find.byType(ExpansionTile));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every template shows whether all nine versions exist', (
    tester,
  ) async {
    await _open(tester, _server());
    expect(
      tester
          .widget<Text>(find.byKey(const Key('catalog.status.$_complete')))
          .data,
      'All 9 age and language versions are present',
    );
    final partial = tester
        .widget<Text>(find.byKey(const Key('catalog.status.$_partial')))
        .data!;
    expect(partial, startsWith('3 of 9 versions missing'));
    expect(partial, contains('4–6 HI'));
    expect(partial, contains('11–15 HI'));
  });

  testWidgets('an incomplete template cannot be published and says why', (
    tester,
  ) async {
    final server = _server();
    await _open(tester, server);
    await tester.tap(find.byKey(const Key('catalog.publish.$_partial')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('Cannot publish yet. Missing:'),
      ),
      findsOneWidget,
    );

    expect(
      server.to(
        'PATCH',
        '/api/v1/admin/daily-missions/templates/$_partial/publish',
      ),
      isEmpty,
    );
  });

  testWidgets('a complete template publishes', (tester) async {
    final server = _server();
    await _open(tester, server);
    await tester.tap(find.byKey(const Key('catalog.publish.$_complete')));
    await tester.pumpAndSettle();
    final sent = server.to(
      'PATCH',
      '/api/v1/admin/daily-missions/templates/$_complete/publish',
    );
    expect(sent.single.queryParameters['publish'], true);
  });

  testWidgets('the server refusing a publish is shown to the admin', (
    tester,
  ) async {
    final server = _server()
      ..reply(
        'PATCH',
        '/api/v1/admin/daily-missions/templates/$_complete/publish',
        {
          'error': {
            'code': 'daily_template_incomplete',
            'message':
                'Publish requires English, Gujarati, and Hindi content for all age bands',
          },
        },
        status: 422,
      );
    await _open(tester, server);
    await tester.tap(find.byKey(const Key('catalog.publish.$_complete')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This mission is missing versions'),
      findsOneWidget,
    );
  });

  testWidgets('read-only admins can inspect versions but not publish', (
    tester,
  ) async {
    await _open(tester, _server(permissions: ['tasks:read']));
    expect(find.byKey(const Key('catalog.view.$_complete')), findsOneWidget);
    expect(find.byKey(const Key('catalog.publish.$_complete')), findsNothing);
  });

  testWidgets(
    'versions can be inspected per age band and language, with a preview',
    (tester) async {
      await _open(tester, _server());
      await tester.tap(find.byKey(const Key('catalog.view.$_partial')));
      await tester.pumpAndSettle();

      // the first selected version is English, ages 4-6
      expect(
        tester
            .widget<Text>(find.byKey(const Key('catalog.preview.title')))
            .data,
        'Three Sounds Hunt',
      );
      expect(
        find.text('Preview (what the child and the reviewing parent see)'),
        findsOneWidget,
      );

      // Gujarati renders as Gujarati
      await tester.tap(find.byKey(const Key('catalog.cell.4_6.gu')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('catalog.preview.title')))
            .data,
        'ત્રણ અવાજની શોધ',
      );
      expect(find.textContaining('ત્રણ અવાજ શોધો.'), findsWidgets);

      // a missing translation is flagged and previews as missing
      expect(find.textContaining('हिन्दी · Missing'), findsNWidgets(3));
      await tester.tap(find.byKey(const Key('catalog.cell.7_10.hi')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('catalog.preview.missing')), findsOneWidget);
    },
  );

  testWidgets('the version dialog scrolls in a short window', (tester) async {
    await _open(tester, _server());
    await tester.tap(find.byKey(const Key('catalog.view.$_partial')));
    await tester.pumpAndSettle();
    // shrink the window with the dialog open: it must scroll, not overflow
    tester.view.physicalSize = const Size(700, 360);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('catalog.preview.title')), findsOneWidget);
  });

  group('rotation capacity', () {
    Map<String, Object?> theme(String key, int eligible, {int min = 6}) => {
      'theme': key,
      'templates': eligible,
      'published': eligible,
      'eligible': eligible,
      'insufficient': eligible < min,
      'shortfall': eligible < min ? min - eligible : 0,
      'age_bands': {'4_6': eligible, '7_10': eligible, '11_15': eligible},
      'locales': {'en': eligible, 'gu': eligible, 'hi': eligible},
      'unpublished': <String>[],
      'incomplete': <String>[],
    };

    FakeServer withHealth({int fallbacks = 3}) =>
        _server()
          ..reply('GET', '/api/v1/admin/daily-missions/catalogue-health', {
            'min_eligible_per_theme': 6,
            'themes': [
              theme('monday_sound_detective', 2),
              theme('tuesday_memory_master', 6),
            ],
            'templates': <Object?>[],
            'fallbacks': {
              'days': 14,
              'count': fallbacks,
              'children': 1,
              'by_template': <Object?>[],
            },
            'warnings': <String>[],
          });

    testWidgets('a theme with fewer than six eligible templates is flagged', (
      tester,
    ) async {
      await _open(tester, withHealth());
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('catalog.health.monday_sound_detective')),
            )
            .data,
        'Monday: sound detective: 2 eligible, 2 published, 2 in total',
      );
      expect(
        find.text(
          'Fewer than 6 eligible templates: missions will repeat (publish 4 more)',
        ),
        findsOneWidget,
      );
      expect(find.text('Enough templates for rotation'), findsOneWidget);
      expect(
        find.byIcon(Icons.warning_amber_rounded),
        findsOneWidget,
        reason: 'only the short theme gets a warning icon',
      );
    });

    testWidgets(
      'recent cooldown fallbacks and assignment frequency are shown',
      (tester) async {
        await _open(tester, withHealth(fallbacks: 9));
        expect(
          tester
              .widget<Text>(find.byKey(const Key('catalog.health.fallbacks')))
              .data,
          '9 cooldown fallbacks in the last 14 days',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const Key('catalog.shown.$_complete')))
              .data,
          'Shown 12 times',
        );
      },
    );

    testWidgets(
      'six eligible rows are only healthy when they are six verified activities',
      (tester) async {
        Map<String, Object?> checked(
          String key, {
          required int distinct,
          List<String> unverified = const [],
        }) => {
          ...theme(key, 6),
          'verified_distinct': distinct,
          'unverified': unverified,
          'duplicate_activities': <Object?>[],
          'healthy': distinct >= 6,
        };

        await _open(
          tester,
          _server()
            ..reply('GET', '/api/v1/admin/daily-missions/catalogue-health', {
              'min_eligible_per_theme': 6,
              'themes': [
                checked('monday_sound_detective', distinct: 6),
                checked(
                  'tuesday_memory_master',
                  distinct: 0,
                  unverified: ['a', 'b', 'c', 'd', 'e', 'f'],
                ),
              ],
              'templates': <Object?>[],
              'totals': {
                'templates': 12,
                'published': 11,
                'unpublished': 1,
                'complete': 11,
                'incomplete': 1,
                'never_assigned': 12,
                'most_assigned': 0,
              },
              'fallbacks': {
                'days': 14,
                'count': 0,
                'children': 0,
                'by_template': <Object?>[],
              },
              'warnings': <String>[],
              'activity_warnings': <String>['x'],
            }),
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(
                  const Key('catalog.health.activities.monday_sound_detective'),
                ),
              )
              .data,
          '6 of 6 activities verified as different',
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(
                  const Key('catalog.health.activities.tuesday_memory_master'),
                ),
              )
              .data,
          '0 of 6 activities verified as different',
        );
        expect(
          find.text(
            '6 template(s) are not in the catalogue source, so their activity cannot be checked',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(find.byKey(const Key('catalog.health.totals')))
              .data,
          '11 published, 1 unpublished, 1 incomplete, of 12 templates',
        );
      },
    );

    testWidgets('the template list still works when the health view fails', (
      tester,
    ) async {
      await _open(tester, _server()); // no health route: 404
      expect(find.byKey(const Key('catalog.health')), findsNothing);
      expect(
        find.byKey(const Key('catalog.status.$_complete')),
        findsOneWidget,
      );
    });
  });
}
