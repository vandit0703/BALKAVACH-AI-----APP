import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _tid = 'aaaaaaaa-1111-4111-8111-000000000001';
const _vid = 'bbbbbbbb-2222-4222-8222-000000000001';

Map<String, Object?> _summary({bool published = false}) => {
  'id': _tid,
  'slug': 'cat1_plants',
  'theme': 'monday_sound_detective',
  'mission_type': 'offline',
  'is_surprise': false,
  'is_published': published,
  'star_reward': 1,
  'xp_reward': 10,
  'mystery_bonus': null,
  'assignment_count': 0,
  'variation_count': 9,
  'missing': <String>[],
  'is_complete': true,
};

Map<String, Object?> _variation({
  List<Map<String, String>> errors = const [],
  List<Map<String, String>> warnings = const [],
}) => {
  'id': _vid,
  'age_band': '4_6',
  'locale': 'en',
  'variation_key': 'c1',
  'title': 'Plant Watch',
  'description': 'Look at a plant.',
  'instructions': '1. Find a plant.\n2. Look closely.\n3. Draw it.',
  'required_materials': ['A small plant'],
  'duration_minutes': 8,
  'safety_instructions': 'Ask a grown-up first.',
  'completion_criteria': 'A drawing is shared.',
  'learning_objective': null,
  'steps': ['Find a plant.', 'Look closely.', 'Draw it.'],
  'observation_guidance': null,
  'submission_requirements': 'Show your drawing.',
  'instruction_status': errors.isEmpty ? 'ready' : 'incomplete',
  'issues': {'errors': errors, 'warnings': warnings},
  'preview': 'Look at a plant.\n\n1. Find a plant.',
};

FakeServer _server({
  List<String> permissions = const ['*'],
  List<Map<String, String>> errors = const [],
  List<Map<String, String>> warnings = const [
    {'code': 'objective_missing', 'message': 'No objective'},
  ],
}) => baseServer(permissions: permissions)
  ..reply('GET', '/api/v1/admin/tasks', <Object?>[])
  ..reply('GET', '/api/v1/admin/daily-missions/templates', [_summary()])
  ..reply('GET', '/api/v1/admin/daily-missions/templates/$_tid', {
    ..._summary(),
    'variations': [_variation(errors: errors, warnings: warnings)],
  })
  ..reply(
    'PATCH',
    '/api/v1/admin/daily-missions/templates/$_tid/variations/$_vid',
    {'id': _vid, 'template_id': _tid},
  )
  ..reply('POST', '/api/v1/admin/daily-missions/variations/preview', {
    'errors': <Object?>[],
    'warnings': [
      {'code': 'objective_missing', 'message': 'No objective'},
    ],
    'publishable': true,
    'content': <String, Object?>{},
    'task_text': '',
  });

Future<void> _openDetail(WidgetTester tester, FakeServer server) async {
  await pumpAdmin(tester, server);
  await openSection(tester, 'Missions');
  await tester.tap(find.byType(ExpansionTile));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('catalog.view.$_tid')));
  await tester.pumpAndSettle();
}

Future<void> _openEditor(WidgetTester tester, FakeServer server) async {
  await _openDetail(tester, server);
  await tester.ensureVisible(find.byKey(const Key('catalog.edit')));
  await tester.tap(find.byKey(const Key('catalog.edit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the version dialog lists what is missing in the panel language',
    (tester) async {
      await _openDetail(
        tester,
        _server(
          errors: [
            {'code': 'submission_missing', 'message': 'No submission'},
          ],
        ),
      );
      expect(find.text('Fix before publishing'), findsOneWidget);
      expect(find.textContaining('What to submit is missing'), findsOneWidget);
      expect(
        find.textContaining('No “what you will learn” sentence'),
        findsOneWidget,
      );
    },
  );

  testWidgets('read-only admins cannot edit a version', (tester) async {
    await _openDetail(tester, _server(permissions: ['tasks:read']));
    expect(find.byKey(const Key('catalog.edit')), findsNothing);
  });

  testWidgets(
    'the editor shows the stored steps, materials and a child preview',
    (tester) async {
      await _openEditor(tester, _server());
      expect(find.byKey(const Key('editor.step.0')), findsOneWidget);
      expect(find.byKey(const Key('editor.step.2')), findsOneWidget);
      expect(find.byKey(const Key('editor.step.3')), findsNothing);
      expect(find.byKey(const Key('editor.material.0')), findsOneWidget);
      expect(find.byKey(const Key('editor.preview')), findsOneWidget);
      expect(find.textContaining('1. Find a plant.'), findsWidgets);
    },
  );

  testWidgets(
    'steps can be reordered, added and removed; the preview follows',
    (tester) async {
      await _openEditor(tester, _server());
      await tester.ensureVisible(find.byKey(const Key('editor.step.down.0')));
      await tester.tap(find.byKey(const Key('editor.step.down.0')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editor.step.0')))
            .controller!
            .text,
        'Look closely.',
      );
      await tester.ensureVisible(find.byKey(const Key('editor.step.add')));
      await tester.tap(find.byKey(const Key('editor.step.add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor.step.3')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('editor.step.remove.3')));
      await tester.tap(find.byKey(const Key('editor.step.remove.3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor.step.3')), findsNothing);
      expect(find.textContaining('1. Look closely.'), findsWidgets);
    },
  );

  testWidgets(
    'save PATCHes the same variation id with structured fields only',
    (tester) async {
      final server = _server();
      await _openEditor(tester, server);
      await tester.ensureVisible(find.byKey(const Key('editor.step.down.0')));
      await tester.tap(find.byKey(const Key('editor.step.down.0')));
      await tester.enterText(
        find.byKey(const Key('editor.objective')),
        'Notice how plants look.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor.save')));
      await tester.pumpAndSettle();

      final sent = server.to(
        'PATCH',
        '/api/v1/admin/daily-missions/templates/$_tid/variations/$_vid',
      );
      expect(sent, hasLength(1));
      final body = sent.single.data as Map<String, dynamic>;
      expect(body['steps'], ['Look closely.', 'Find a plant.', 'Draw it.']);
      expect(body['learning_objective'], 'Notice how plants look.');
      expect(body['required_materials'], ['A small plant']);
      expect(body.containsKey('instructions'), isFalse);
      expect(body.containsKey('age_band'), isFalse);
    },
  );

  testWidgets('Check shows what the server says without saving', (
    tester,
  ) async {
    final server = _server();
    await _openEditor(tester, server);
    await tester.ensureVisible(find.byKey(const Key('editor.check')));
    await tester.tap(find.byKey(const Key('editor.check')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('editor.ready')), findsOneWidget);
    expect(
      find.textContaining('No “what you will learn” sentence'),
      findsWidgets,
    );
    expect(
      server.to(
        'PATCH',
        '/api/v1/admin/daily-missions/templates/$_tid/variations/$_vid',
      ),
      isEmpty,
    );
    expect(
      server.to('POST', '/api/v1/admin/daily-missions/variations/preview'),
      hasLength(1),
    );
  });

  testWidgets('"Nothing needed" can be set explicitly for materials', (
    tester,
  ) async {
    await _openEditor(tester, _server());
    await tester.ensureVisible(find.byKey(const Key('editor.material.none')));
    await tester.tap(find.byKey(const Key('editor.material.none')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('editor.material.0')))
          .controller!
          .text,
      'Nothing needed',
    );
  });

  testWidgets('a publish refused for missing instructions lists the problems', (
    tester,
  ) async {
    final server = _server()
      ..reply('PATCH', '/api/v1/admin/daily-missions/templates/$_tid/publish', {
        'error': {
          'code': 'daily_template_instructions_incomplete',
          'message': 'Publish requires real steps',
          'details': {
            'problems': [
              {
                'age_band': '7_10',
                'locale': 'hi',
                'variation_id': _vid,
                'code': 'steps_missing',
                'message': 'No numbered steps',
              },
              {
                'age_band': null,
                'locale': 'en',
                'variation_id': null,
                'code': 'bands_identical',
                'message': 'Ages 4-6 reuse the steps of 7-10',
              },
            ],
          },
        },
      }, status: 422);
    await pumpAdmin(tester, server);
    await openSection(tester, 'Missions');
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog.publish.$_tid')));
    await tester.pumpAndSettle();
    expect(find.text('Publishing blocked'), findsOneWidget);
    expect(find.textContaining('7_10 hi · No numbered steps'), findsOneWidget);
    expect(
      find.textContaining('Two age groups share the same steps'),
      findsOneWidget,
    );
  });
}
