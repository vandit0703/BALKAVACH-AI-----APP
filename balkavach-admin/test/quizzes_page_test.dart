import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _id = '11111111-1111-4111-8111-111111111111';

Map<String, Object?> _row({bool published = false}) => {
  'id': _id,
  'title': 'Animals quiz',
  'subject': 'science',
  'difficulty': 'easy',
  'language_code': 'en',
  'age_min': 4,
  'age_max': 15,
  'pass_percent': 60,
  'star_reward': 5,
  'xp_reward': 8,
  'allow_retry': true,
  'is_published': published,
  'question_count': 1,
  'attempt_count': 0,
  'revision': 1,
  'created_at': '2026-10-01T10:00:00',
  'updated_at': '2026-10-01T10:00:00',
};

Map<String, Object?> _detail({bool published = false}) => {
  ..._row(published: published),
  'description': 'About animals',
  'questions': [
    {
      'id': '22222222-2222-4222-8222-222222222222',
      'position': 1,
      'prompt': 'Which animal gives us milk?',
      'question_type': 'single',
      'explanation': 'Cows give milk.',
      'options': [
        {'id': 'o1', 'position': 1, 'text': 'Cat', 'is_correct': false},
        {'id': 'o2', 'position': 2, 'text': 'Cow', 'is_correct': true},
      ],
    },
  ],
};

FakeServer _server({bool published = false, List<String>? permissions}) =>
    (permissions == null ? baseServer() : baseServer(permissions: permissions))
      ..reply('GET', '/api/v1/admin/quizzes', [_row(published: published)])
      ..reply(
        'GET',
        '/api/v1/admin/quizzes/$_id',
        _detail(published: published),
      );

Future<void> _menu(WidgetTester tester, String action) async {
  await tapKey(tester, 'quizzes.menu.$_id');
  await tapKey(tester, 'quizzes.$action.$_id');
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists quizzes with status, reward and actions', (tester) async {
    final server = _server();
    await pumpAdmin(tester, server);
    await openSection(tester, 'Quizzes');
    expect(find.text('Animals quiz'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('5 ★ · 8 XP'), findsOneWidget);
    expect(find.byKey(const Key('quizzes.add')), findsOneWidget);
    await tapKey(tester, 'quizzes.menu.$_id');
    for (final action in ['preview', 'edit', 'publish', 'delete']) {
      expect(find.byKey(Key('quizzes.$action.$_id')), findsOneWidget);
    }
  });

  testWidgets('creates a quiz with a question, sending the correct answer', (
    tester,
  ) async {
    final server = _server()
      ..reply('POST', '/api/v1/admin/quizzes', _detail(), status: 201);
    await pumpAdmin(tester, server);
    await openSection(tester, 'Quizzes');
    await tapKey(tester, 'quizzes.add');

    // Saving an invalid quiz explains itself and sends nothing.
    await tapKey(tester, 'quiz.save');
    expect(find.byKey(const Key('quiz.error')), findsOneWidget);
    expect(server.to('POST', '/api/v1/admin/quizzes'), isEmpty);

    await _enter(tester, 'quiz.title', 'Animals quiz');
    await tapKey(tester, 'quiz.addQuestion');
    // A question without prompt/answers is rejected before saving.
    await tapKey(tester, 'quiz.save');
    expect(find.textContaining('Question 1 needs'), findsOneWidget);
    expect(server.to('POST', '/api/v1/admin/quizzes'), isEmpty);

    await _enter(tester, 'quiz.prompt.0', 'Which animal gives us milk?');
    await _enter(tester, 'quiz.optionText.0.0', 'Cow');
    await _enter(tester, 'quiz.optionText.0.1', 'Cat');
    await _enter(tester, 'quiz.stars', '5');
    await _enter(tester, 'quiz.xp', '8');
    await tapKey(tester, 'quiz.save');

    final body =
        server.to('POST', '/api/v1/admin/quizzes').single.data
            as Map<String, dynamic>;
    expect(body['title'], 'Animals quiz');
    expect(body['star_reward'], 5);
    expect(body['xp_reward'], 8);
    expect(body['pass_percent'], 60);
    final question = (body['questions'] as List).single as Map;
    expect(question['question_type'], 'single');
    expect(question['options'], [
      {'text': 'Cow', 'is_correct': true},
      {'text': 'Cat', 'is_correct': false},
    ]);
  });

  testWidgets('a draft can be edited with its questions loaded', (
    tester,
  ) async {
    final server = _server()
      ..reply('PUT', '/api/v1/admin/quizzes/$_id', _detail());
    await pumpAdmin(tester, server);
    await openSection(tester, 'Quizzes');
    await _menu(tester, 'edit');
    expect(find.text('Which animal gives us milk?'), findsOneWidget);
    await _enter(tester, 'quiz.title', 'Farm animals');
    await tapKey(tester, 'quiz.save');
    final body =
        server.to('PUT', '/api/v1/admin/quizzes/$_id').single.data
            as Map<String, dynamic>;
    expect(body['title'], 'Farm animals');
    final options = ((body['questions'] as List).single as Map)['options'];
    expect(options, [
      {'text': 'Cat', 'is_correct': false},
      {'text': 'Cow', 'is_correct': true},
    ]);
  });

  testWidgets('a published quiz cannot be edited, only unpublished', (
    tester,
  ) async {
    final server = _server(published: true)
      ..reply('PATCH', '/api/v1/admin/quizzes/$_id/published', _detail());
    await pumpAdmin(tester, server);
    await openSection(tester, 'Quizzes');
    await tapKey(tester, 'quizzes.menu.$_id');
    final edit = tester.widget<PopupMenuItem<String>>(
      find.byKey(const Key('quizzes.edit.$_id')),
    );
    expect(edit.enabled, isFalse);
    expect(find.text('Unpublish the quiz to edit it.'), findsOneWidget);
    expect(find.byKey(const Key('quizzes.delete.$_id')), findsNothing);
    await tapKey(tester, 'quizzes.publish.$_id');
    expect(
      server.to('PATCH', '/api/v1/admin/quizzes/$_id/published').single.data,
      {'is_published': false},
    );
  });

  testWidgets('publishing sends is_published true; the server may refuse', (
    tester,
  ) async {
    final server = _server()
      ..on(
        'PATCH',
        '/api/v1/admin/quizzes/$_id/published',
        (_) => Reply.error(
          422,
          'quiz_incomplete',
          'Add at least one question before publishing',
        ),
      );
    await pumpAdmin(tester, server);
    await openSection(tester, 'Quizzes');
    await _menu(tester, 'publish');
    expect(
      server.to('PATCH', '/api/v1/admin/quizzes/$_id/published').single.data,
      {'is_published': true},
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview shows the questions and marks the correct answer', (
    tester,
  ) async {
    await pumpAdmin(tester, _server());
    await openSection(tester, 'Quizzes');
    await _menu(tester, 'preview');
    expect(find.textContaining('Which animal gives us milk?'), findsOneWidget);
    expect(find.text('Correct'), findsOneWidget);
  });

  testWidgets('read-only admins see quizzes but no management buttons', (
    tester,
  ) async {
    await pumpAdmin(tester, _server(permissions: ['content:read']));
    await openSection(tester, 'Quizzes');
    expect(find.text('Animals quiz'), findsOneWidget);
    expect(find.byKey(const Key('quizzes.add')), findsNothing);
    await tapKey(tester, 'quizzes.menu.$_id');
    expect(find.byKey(const Key('quizzes.edit.$_id')), findsNothing);
    expect(find.byKey(const Key('quizzes.preview.$_id')), findsOneWidget);
  });

  testWidgets('admins without content access get the no-access page', (
    tester,
  ) async {
    await pumpAdmin(tester, _server(permissions: ['users:read']));
    // The sidebar hides sections the admin cannot use.
    expect(find.text('Quizzes'), findsNothing);
  });
}
