import 'package:balkavach_app/core/routing/app_routes.dart';
import 'package:balkavach_app/core/theme/app_theme.dart';
import 'package:balkavach_app/features/learning/data/learning_repository.dart';
import 'package:balkavach_app/features/learning/data/playable_video.dart';
import 'package:balkavach_app/features/learning/presentation/learning_hub_screen.dart';
import 'package:balkavach_app/features/learning/presentation/learning_screen.dart';
import 'package:balkavach_app/features/learning/presentation/stories_tab.dart';
import 'package:balkavach_app/features/quizzes/data/quiz_repository.dart';
import 'package:balkavach_app/features/quizzes/presentation/quiz_intro_screen.dart';
import 'package:balkavach_app/features/quizzes/presentation/quiz_result_screen.dart';
import 'package:balkavach_app/features/quizzes/presentation/quiz_take_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _quizId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
const _attemptId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1';
const _q1 = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1';
const _q2 = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2';

Map<String, Object?> _quiz({
  String id = _quizId,
  String title = 'Animals quiz',
  String status = 'pending',
  int stars = 10,
  int xp = 15,
  bool claimed = false,
  bool canStart = true,
  int attempts = 0,
  int? best,
}) => {
  'id': id,
  'title': title,
  'description': 'Learn about animals',
  'subject': 'science',
  'difficulty': 'easy',
  'language_code': 'en',
  'age_min': 4,
  'age_max': 15,
  'question_count': 2,
  'pass_percent': 60,
  'star_reward': stars,
  'xp_reward': xp,
  'allow_retry': true,
  'status': status,
  'attempts': attempts,
  'best_score_percent': best,
  'reward_claimed': claimed,
  'can_start': canStart,
};

Map<String, Object?> _attempt() => {
  'attempt_id': _attemptId,
  'quiz_id': _quizId,
  'title': 'Animals quiz',
  'pass_percent': 60,
  'star_reward': 10,
  'xp_reward': 15,
  'started_at': '2026-10-12T12:00:00',
  'questions': [
    {
      'id': _q1,
      'position': 1,
      'prompt': 'Which animal gives us milk?',
      'question_type': 'single',
      'options': [
        {'id': 'o1', 'text': 'Cat'},
        {'id': 'o2', 'text': 'Cow'},
      ],
    },
    {
      'id': _q2,
      'position': 2,
      'prompt': 'Which are fruits?',
      'question_type': 'multiple',
      'options': [
        {'id': 'o3', 'text': 'Apple'},
        {'id': 'o4', 'text': 'Carrot'},
        {'id': 'o5', 'text': 'Mango'},
      ],
    },
  ],
};

Map<String, Object?> _result({
  bool passed = true,
  int stars = 10,
  int xp = 15,
  int correct = 2,
  bool canRetry = true,
  bool withReview = true,
}) => {
  'attempt_id': _attemptId,
  'quiz_id': _quizId,
  'quiz_title': 'Animals quiz',
  'status': 'submitted',
  'total_questions': 2,
  'correct_count': correct,
  'incorrect_count': 2 - correct,
  'score_percent': correct * 50,
  'passed': passed,
  'pass_percent': 60,
  'stars_awarded': stars,
  'xp_awarded': xp,
  'submitted_at': '2026-10-12T12:05:00',
  'can_retry': canRetry,
  'review': withReview
      ? [
          {
            'question_id': _q1,
            'position': 1,
            'prompt': 'Which animal gives us milk?',
            'question_type': 'single',
            'explanation': 'Cows give milk.',
            'selected_option_ids': ['o1'],
            'correct_option_ids': ['o2'],
            'is_correct': false,
            'options': [
              {'id': 'o1', 'text': 'Cat', 'is_correct': false},
              {'id': 'o2', 'text': 'Cow', 'is_correct': true},
            ],
          },
        ]
      : null,
};

Map<String, Object?> _story({String id = 'story-1', String? text}) => {
  'id': id,
  'title': 'The Kind Lion',
  'description':
      text ?? List.filled(130, 'word').join(' '), // 130 words: 2 minutes
  'content_type': 'article',
  'category_id': null,
  'language_code': 'en',
  'content_url': null,
  'thumbnail_url': null,
  'video_id': null,
  'collection_id': null,
  'requires_entitlement': false,
  'is_active': true,
  'metered_video_id': null,
};

Map<String, Object?> _short(int i) => {
  'id': 's$i',
  'title': 'Short number $i',
  'description': null,
  'thumbnail_url': null,
  'duration_seconds': 40,
  'category_id': null,
  'language_code': 'en',
  'content_rating': 'educational',
  'video_source': 'youtube',
  'youtube_video_id': 'abcdefghi${i.toString().padLeft(2, '0')}',
  'channel_name': 'Kids Channel',
};

Future<Harness> _harness({
  List<Object?> quizzes = const [],
  List<Object?> content = const [],
  List<Object?> shorts = const [],
}) async {
  final h = await Harness.create(session: Fx.childSession());
  h.backend
    ..reply('GET', '/api/v1/quizzes', quizzes)
    ..reply('GET', '/api/v1/quizzes/history', <Object?>[])
    ..reply('GET', '/api/v1/educational-content', content)
    ..reply('GET', '/api/v1/videos/feed', <Object?>[])
    ..reply('GET', '/api/v1/videos/shorts', shorts)
    ..reply('GET', '/api/v1/video-access/allowance', Fx.allowance());
  return h;
}

GoRouter _router(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: AppRoutes.childHome,
      builder: (_, _) => const Scaffold(body: Text('HOME')),
      routes: [
        GoRoute(
          path: 'learn',
          builder: (_, state) => Scaffold(
            body: LearningHubScreen(
              initialTab: state.uri.queryParameters['tab'] ?? 'videos',
            ),
          ),
          routes: [
            GoRoute(
              path: ':itemId',
              builder: (_, state) =>
                  LearningDetailScreen(item: state.extra! as LearningItem),
            ),
          ],
        ),
        // Stands in for the full-screen Shorts player: records what it was
        // opened with (real playback is covered by watch_home_test).
        GoRoute(
          path: 'shorts',
          builder: (_, state) {
            final launch = state.extra! as ShortsLaunch;
            return Scaffold(
              body: Text(
                'SHORTS ${launch.initialIndex} of '
                '${launch.initialVideos.length}',
              ),
            );
          },
        ),
        GoRoute(
          path: 'quizzes/result/:attemptId',
          builder: (_, state) => QuizResultScreen(
            attemptId: state.pathParameters['attemptId']!,
            result: state.extra is QuizResult
                ? state.extra! as QuizResult
                : null,
          ),
        ),
        GoRoute(
          path: 'quizzes/:quizId',
          builder: (_, state) =>
              QuizIntroScreen(quizId: state.pathParameters['quizId']!),
          routes: [
            GoRoute(
              path: 'take',
              builder: (_, state) =>
                  QuizTakeScreen(quizId: state.pathParameters['quizId']!),
            ),
          ],
        ),
      ],
    ),
  ],
);

Future<GoRouter> _pump(
  WidgetTester tester,
  Harness h, {
  String initial = '/child/learn',
  Size size = const Size(393, 852),
  double textScale = 1,
  Locale locale = const Locale('en'),
}) async {
  setWindow(tester, size);
  final router = _router(initial);
  await tester.pumpWidget(
    ProviderScope(
      // A fresh scope per pump: a test may mount two different backends.
      key: UniqueKey(),
      overrides: h.overrides,
      retry: (_, _) => null,
      child: MaterialApp.router(
        routerConfig: router,
        theme: buildAppTheme(),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  // Like a child would: scroll until the control is on screen.
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _wireQuizFlow(Harness h, {Map<String, Object?>? result}) {
  h.backend
    ..reply('GET', '/api/v1/quizzes/$_quizId', _quiz())
    ..reply(
      'POST',
      '/api/v1/quizzes/$_quizId/attempts',
      _attempt(),
      status: 201,
    )
    ..reply(
      'POST',
      '/api/v1/quizzes/attempts/$_attemptId/submit',
      result ?? _result(),
    );
}

void main() {
  group('QuizRepository', () {
    test('parses a summary and never derives a status itself', () {
      final quiz = QuizSummary.fromJson(_quiz(status: 'passed', claimed: true));
      expect(quiz.status, QuizStatus.passed);
      expect(quiz.hasOpenReward, isFalse); // already claimed: nothing to earn
      expect(QuizSummary.fromJson(_quiz()).hasOpenReward, isTrue);
      expect(QuizSummary.fromJson(_quiz(stars: 0, xp: 0)).hasOpenReward, false);
    });

    test('submit sends option ids only: no score, no stars', () async {
      final h = await _harness();
      _wireQuizFlow(h);
      await h.container().read(quizRepositoryProvider).submit(_attemptId, {
        _q1: ['o2'],
        _q2: ['o3', 'o5'],
      });
      final request = h.backend
          .requestsTo('POST', '/api/v1/quizzes/attempts/$_attemptId/submit')
          .single;
      expect(request.data, {
        'answers': [
          {
            'question_id': _q1,
            'option_ids': ['o2'],
          },
          {
            'question_id': _q2,
            'option_ids': ['o3', 'o5'],
          },
        ],
      });
    });

    test('a result without a review (quiz was edited) parses as null', () {
      expect(QuizResult.fromJson(_result(withReview: false)).review, isNull);
    });
  });

  group('Learning Hub', () {
    testWidgets('shows Videos, Quizzes and Shorts as three working tabs', (
      tester,
    ) async {
      final h = await _harness(quizzes: [_quiz()], shorts: [_short(1)]);
      await _pump(tester, h);
      for (final key in ['videos', 'quizzes', 'shorts']) {
        expect(find.byKey(Key('hub.tab.$key')), findsOneWidget);
      }
      expect(find.byKey(const Key('hub.tab.stories')), findsNothing);
      // Videos is the first tab; its empty state is a real, working view.
      expect(find.byKey(const Key('videos.learn.empty')), findsOneWidget);

      // Switching repeatedly keeps every tab working.
      for (var i = 0; i < 3; i++) {
        await _tap(tester, find.byKey(const Key('hub.tab.quizzes')));
        expect(find.byKey(const Key('quiz.$_quizId')), findsOneWidget);
        await _tap(tester, find.byKey(const Key('hub.tab.shorts')));
        expect(find.byKey(const Key('hub.short.feed:s1')), findsOneWidget);
        await _tap(tester, find.byKey(const Key('hub.tab.videos')));
        expect(find.byKey(const Key('videos.learn.empty')), findsOneWidget);
      }
    });

    testWidgets('can open directly on a tab', (tester) async {
      final h = await _harness(quizzes: [_quiz()]);
      await _pump(tester, h, initial: AppRoutes.childLearnTab('quizzes'));
      expect(find.byKey(const Key('quiz.$_quizId')), findsOneWidget);
    });

    testWidgets('quizzes: status, best score and reward are shown', (
      tester,
    ) async {
      final h = await _harness(
        quizzes: [
          _quiz(),
          _quiz(
            id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
            title: 'Done quiz',
            status: 'passed',
            claimed: true,
            attempts: 2,
            best: 100,
          ),
        ],
      );
      await _pump(tester, h, initial: AppRoutes.childLearnTab('quizzes'));
      expect(find.text('Animals quiz'), findsOneWidget);
      expect(find.text('To do'), findsOneWidget);
      expect(find.text('Passed'), findsOneWidget);
      expect(find.text('Best: 100%'), findsOneWidget);
      expect(find.text('First pass earns 10 Stars + 15 XP'), findsOneWidget);
      // A claimed quiz never advertises a reward it will not pay again.
      expect(find.textContaining('First pass earns'), findsOneWidget);
    });

    testWidgets('quizzes: empty and error states, with retry', (tester) async {
      final h = await _harness();
      await _pump(tester, h, initial: AppRoutes.childLearnTab('quizzes'));
      expect(find.byKey(const Key('quizzes.empty')), findsOneWidget);

      final failing = await Harness.create(session: Fx.childSession());
      failing.backend
        ..on(
          'GET',
          '/api/v1/quizzes',
          (_) => const FakeReply.fail(DioExceptionType.connectionError),
        )
        ..reply('GET', '/api/v1/educational-content', <Object?>[])
        ..reply('GET', '/api/v1/videos/feed', <Object?>[]);
      await _pump(tester, failing, initial: AppRoutes.childLearnTab('quizzes'));
      expect(find.byKey(const Key('quizzes.error')), findsOneWidget);

      // Retry makes a real new request, and a recovered server shows quizzes.
      final requestsBefore = failing.backend
          .requestsTo('GET', '/api/v1/quizzes')
          .length;
      failing.backend.reply('GET', '/api/v1/quizzes', [_quiz()]);
      await _tap(tester, find.text('Try again'));
      expect(
        failing.backend.requestsTo('GET', '/api/v1/quizzes').length,
        greaterThan(requestsBefore),
      );
      expect(find.byKey(const Key('quiz.$_quizId')), findsOneWidget);
    });

    testWidgets('quizzes: a server without the quiz feature (404) says so '
        'instead of a generic not-found', (tester) async {
      final h = await _harness();
      h.backend.reply('GET', '/api/v1/quizzes', {
        'error': {'code': 'http_error', 'message': 'Not Found'},
      }, status: 404);
      await _pump(tester, h, initial: AppRoutes.childLearnTab('quizzes'));
      expect(find.byKey(const Key('quizzes.error')), findsOneWidget);
      expect(
        find.text("Quizzes aren't ready yet. Please try again later."),
        findsOneWidget,
      );
      expect(find.text("We couldn't find that."), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('shorts: grid of approved Shorts opens the Shorts player at '
        'the tapped Short; empty state', (tester) async {
      final h = await _harness(shorts: [_short(0), _short(1), _short(2)]);
      await _pump(tester, h, initial: AppRoutes.childLearnTab('shorts'));
      expect(find.byKey(const Key('hub.shorts.grid')), findsOneWidget);
      expect(find.text('Short number 1'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('hub.short.feed:s1')));
      // The server confirmed time remains before anything opened.
      expect(
        h.backend.requestsTo('GET', '/api/v1/video-access/allowance'),
        isNotEmpty,
      );
      expect(find.text('SHORTS 1 of 3'), findsOneWidget);

      final empty = await _harness();
      await _pump(tester, empty, initial: AppRoutes.childLearnTab('shorts'));
      expect(find.byKey(const Key('hub.shorts.empty')), findsOneWidget);
    });

    testWidgets('shorts: a failed load can be retried', (tester) async {
      final h = await _harness();
      h.backend.on(
        'GET',
        '/api/v1/videos/shorts',
        (_) => const FakeReply.fail(DioExceptionType.connectionError),
      );
      await _pump(tester, h, initial: AppRoutes.childLearnTab('shorts'));
      expect(find.byKey(const Key('hub.shorts.error')), findsOneWidget);
      h.backend.reply('GET', '/api/v1/videos/shorts', [_short(4)]);
      await _tap(tester, find.text('Try again'));
      expect(find.byKey(const Key('hub.short.feed:s4')), findsOneWidget);
    });

    testWidgets('stories stay readable in the app from the Videos tab', (
      tester,
    ) async {
      final h = await _harness(content: [_story()]);
      final router = await _pump(tester, h);
      expect(find.text('The Kind Lion'), findsOneWidget);
      await _tap(tester, find.text('The Kind Lion'));
      // The story is read in the app: text shown, nothing opens outside it.
      expect(find.byKey(const Key('story.text')), findsOneWidget);
      expect(find.byKey(const Key('learn.open')), findsNothing);
      expect(find.byKey(const Key('learn.blocker')), findsNothing);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('The Kind Lion'), findsOneWidget);
    });

    testWidgets('curated items stay reachable from Videos', (tester) async {
      final link = _story(id: 'link-1')
        ..['content_type'] = 'link'
        ..['title'] = 'A curated link'
        ..['content_url'] = 'https://example.org/x';
      final h = await _harness(content: [link, _story()]);
      await _pump(tester, h);
      expect(find.text('More to explore'), findsOneWidget);
      expect(find.text('A curated link'), findsOneWidget);
      // With no Stories tab, stories are listed here too.
      expect(find.text('The Kind Lion'), findsOneWidget);
    });

    test('reading time is at least a minute and grows with length', () {
      expect(storyReadingMinutes('short'), 1);
      expect(storyReadingMinutes(List.filled(121, 'w').join(' ')), 2);
      expect(storyReadingMinutes(List.filled(600, 'w').join(' ')), 5);
    });

    for (final (locale, videos, quizzes, shorts) in [
      (const Locale('hi'), 'वीडियो', 'क्विज़', 'शॉर्ट्स'),
      (const Locale('gu'), 'વિડિઓ', 'ક્વિઝ', 'શોર્ટ્સ'),
    ]) {
      testWidgets('tabs are localised for ${locale.languageCode}', (
        tester,
      ) async {
        final h = await _harness(quizzes: [_quiz()]);
        await _pump(tester, h, locale: locale);
        expect(find.text(videos), findsOneWidget);
        expect(find.text(quizzes), findsOneWidget);
        expect(find.text(shorts), findsOneWidget);
        await _tap(tester, find.byKey(const Key('hub.tab.quizzes')));
        expect(find.textContaining('10'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    for (final (name, size, scale) in [
      ('small phone, large text', const Size(320, 568), 2.0),
      ('tablet', const Size(800, 1280), 1.0),
    ]) {
      testWidgets('quiz list does not overflow: $name', (tester) async {
        final h = await _harness(quizzes: [_quiz()]);
        await _pump(
          tester,
          h,
          initial: AppRoutes.childLearnTab('quizzes'),
          size: size,
          textScale: scale,
          locale: const Locale('gu'),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('shorts grid does not overflow: $name', (tester) async {
        final h = await _harness(shorts: [_short(0), _short(1), _short(2)]);
        await _pump(
          tester,
          h,
          initial: AppRoutes.childLearnTab('shorts'),
          size: size,
          textScale: scale,
          locale: const Locale('gu'),
        );
        expect(find.byKey(const Key('hub.shorts.grid')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Taking a quiz', () {
    testWidgets('intro → questions → server result → home', (tester) async {
      final h = await _harness(quizzes: [_quiz()]);
      _wireQuizFlow(h);
      await _pump(tester, h, initial: AppRoutes.childLearnTab('quizzes'));

      await _tap(tester, find.byKey(const Key('quiz.$_quizId')));
      expect(find.byKey(const Key('quiz.reward')), findsOneWidget);
      expect(find.text('Pass mark: 60%'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('quiz.start')));

      // Question 1 (single choice). Next needs an answer first.
      expect(find.text('Question 1 of 2'), findsOneWidget);
      InkWell next() => tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(const Key('quiz.next')),
          matching: find.byType(InkWell),
        ),
      );
      expect(next().onTap, isNull);
      await _tap(tester, find.byKey(const Key('quiz.option.o1')));
      // Single choice: picking another option replaces the first.
      await _tap(tester, find.byKey(const Key('quiz.option.o2')));
      expect(next().onTap, isNotNull);
      await _tap(tester, find.byKey(const Key('quiz.next')));

      // Question 2 (multiple): options toggle independently.
      expect(find.text('Question 2 of 2'), findsOneWidget);
      expect(find.text('Choose all the right answers'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('quiz.option.o3')));
      await _tap(tester, find.byKey(const Key('quiz.option.o5')));
      await _tap(tester, find.byKey(const Key('quiz.option.o3'))); // untick
      // Going back keeps the earlier answer.
      await _tap(tester, find.byKey(const Key('quiz.previous')));
      expect(find.text('Question 1 of 2'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('quiz.next')));
      await _tap(tester, find.byKey(const Key('quiz.submit')));

      final submit = h.backend
          .requestsTo('POST', '/api/v1/quizzes/attempts/$_attemptId/submit')
          .single;
      expect(submit.data, {
        'answers': [
          {
            'question_id': _q1,
            'option_ids': ['o2'],
          },
          {
            'question_id': _q2,
            'option_ids': ['o5'],
          },
        ],
      });

      // A passed quiz is celebrated first, with what the server paid.
      expect(find.byKey(const Key('celebration.card')), findsOneWidget);
      expect(find.text('Quiz complete!'), findsOneWidget);
      expect(find.text('Animals quiz'), findsWidgets);
      expect(find.text('+ 10 Stars + 15 XP'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('celebration.continue')));
      expect(find.byKey(const Key('celebration.card')), findsNothing);

      // The result shows what the server returned.
      expect(find.byKey(const Key('quiz.result.panda')), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('You got 2 of 2 right'), findsOneWidget);
      expect(find.text('You earned 10 Stars and 15 XP!'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('quiz.result.home')));
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('a retake that pays nothing says so, and a fail can retry', (
      tester,
    ) async {
      final h = await _harness(quizzes: [_quiz()]);
      _wireQuizFlow(h, result: _result(stars: 0, xp: 0));
      await _pump(tester, h, initial: AppRoutes.childQuiz(_quizId));
      await _tap(tester, find.byKey(const Key('quiz.start')));
      await _tap(tester, find.byKey(const Key('quiz.option.o2')));
      await _tap(tester, find.byKey(const Key('quiz.next')));
      await _tap(tester, find.byKey(const Key('quiz.option.o3')));
      await _tap(tester, find.byKey(const Key('quiz.submit')));
      expect(find.byKey(const Key('celebration.card')), findsOneWidget);
      expect(find.byKey(const Key('celebration.rewards')), findsNothing);
      await _tap(tester, find.byKey(const Key('celebration.continue')));
      expect(find.byKey(const Key('quiz.result.earned')), findsNothing);
      expect(
        find.text('Rewards are given once, the first time you pass.'),
        findsOneWidget,
      );
    });

    testWidgets('the celebration can go Home and appears only once', (
      tester,
    ) async {
      final h = await _harness(quizzes: [_quiz()]);
      _wireQuizFlow(h);
      await _pump(tester, h, initial: AppRoutes.childQuiz(_quizId));
      await _tap(tester, find.byKey(const Key('quiz.start')));
      await _tap(tester, find.byKey(const Key('quiz.option.o2')));
      await _tap(tester, find.byKey(const Key('quiz.next')));
      await _tap(tester, find.byKey(const Key('quiz.option.o3')));
      await _tap(tester, find.byKey(const Key('quiz.submit')));
      expect(find.byKey(const Key('celebration.card')), findsOneWidget);
      // Time passing and rebuilds do not bring it back or duplicate it.
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const Key('celebration.card')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('celebration.home')));
      expect(find.text('HOME'), findsOneWidget);
      expect(find.byKey(const Key('celebration.card')), findsNothing);
      // Only the one submit was sent: showing the Panda granted nothing.
      expect(
        h.backend.requests
            .where((r) => r.method == 'POST' && r.uri.path.endsWith('/submit'))
            .length,
        1,
      );
    });

    testWidgets('a failed result shows the review and offers another try', (
      tester,
    ) async {
      final h = await _harness(quizzes: [_quiz()]);
      _wireQuizFlow(
        h,
        result: _result(passed: false, stars: 0, xp: 0, correct: 0),
      );
      await _pump(tester, h, initial: AppRoutes.childQuiz(_quizId));
      await _tap(tester, find.byKey(const Key('quiz.start')));
      await _tap(tester, find.byKey(const Key('quiz.option.o1')));
      await _tap(tester, find.byKey(const Key('quiz.next')));
      await _tap(tester, find.byKey(const Key('quiz.option.o4')));
      await _tap(tester, find.byKey(const Key('quiz.submit')));
      expect(find.byKey(const Key('celebration.card')), findsNothing);
      expect(find.byKey(const Key('quiz.result.panda')), findsNothing);
      expect(find.byKey(const Key('quiz.result.needMore')), findsOneWidget);
      expect(find.byKey(const Key('quiz.result.retry')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Right answer'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Right answer: Cow'), findsOneWidget);
      expect(find.text('Cows give milk.'), findsOneWidget);
    });

    testWidgets('a changed quiz explains itself and restarts cleanly', (
      tester,
    ) async {
      final h = await _harness(quizzes: [_quiz()]);
      _wireQuizFlow(h);
      h.backend.reply('POST', '/api/v1/quizzes/attempts/$_attemptId/submit', {
        'error': {'code': 'quiz_changed', 'message': 'changed'},
      }, status: 409);
      await _pump(tester, h, initial: AppRoutes.childQuiz(_quizId));
      await _tap(tester, find.byKey(const Key('quiz.start')));
      await _tap(tester, find.byKey(const Key('quiz.option.o2')));
      await _tap(tester, find.byKey(const Key('quiz.next')));
      await _tap(tester, find.byKey(const Key('quiz.option.o3')));
      await _tap(tester, find.byKey(const Key('quiz.submit')));
      expect(
        find.text('This quiz was updated. Please start it again.'),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const Key('quiz.restart')));
      expect(find.text('Question 1 of 2'), findsOneWidget);
      expect(
        h.backend.requestsTo('POST', '/api/v1/quizzes/$_quizId/attempts'),
        hasLength(2),
      );
    });

    testWidgets('Android Back asks before discarding answers', (tester) async {
      final h = await _harness(quizzes: [_quiz()]);
      _wireQuizFlow(h);
      await _pump(tester, h, initial: AppRoutes.childLearnTab('quizzes'));
      await _tap(tester, find.byKey(const Key('quiz.$_quizId')));
      await _tap(tester, find.byKey(const Key('quiz.start')));
      // Nothing answered yet: Back leaves without asking.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quiz.start')), findsOneWidget);

      await _tap(tester, find.byKey(const Key('quiz.start')));
      await _tap(tester, find.byKey(const Key('quiz.option.o2')));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Leave the quiz?'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('quiz.leave.stay')));
      expect(find.text('Question 1 of 2'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('quiz.leave.confirm')));
      // Back on the intro, then on the Quizzes tab of the hub.
      expect(find.byKey(const Key('quiz.start')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quiz.$_quizId')), findsOneWidget);
    });

    testWidgets('a stored result opens from the history without a grant', (
      tester,
    ) async {
      final h = await _harness(quizzes: [_quiz()]);
      h.backend
        ..reply('GET', '/api/v1/quizzes/$_quizId', _quiz(status: 'passed'))
        ..reply('GET', '/api/v1/quizzes/history', [
          {
            'attempt_id': _attemptId,
            'quiz_id': _quizId,
            'quiz_title': 'Animals quiz',
            'score_percent': 100,
            'correct_count': 2,
            'total_questions': 2,
            'passed': true,
            'stars_awarded': 10,
            'xp_awarded': 15,
            'submitted_at': '2026-10-12T12:05:00',
          },
        ])
        ..reply('GET', '/api/v1/quizzes/attempts/$_attemptId', _result());
      await _pump(tester, h, initial: AppRoutes.childQuiz(_quizId));
      await _tap(tester, find.byKey(const Key('quiz.attempt.$_attemptId')));
      expect(find.text('100%'), findsOneWidget);
      // Reopening a stored result never celebrates (and never pays).
      expect(find.byKey(const Key('celebration.card')), findsNothing);
      // Reopening only reads: no submit and no attempt were sent.
      expect(h.backend.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('a one-attempt quiz that was taken cannot be started', (
      tester,
    ) async {
      final h = await _harness(quizzes: [_quiz()]);
      h.backend.reply(
        'GET',
        '/api/v1/quizzes/$_quizId',
        _quiz(status: 'attempted', canStart: false, attempts: 1),
      );
      await _pump(tester, h, initial: AppRoutes.childQuiz(_quizId));
      expect(find.byKey(const Key('quiz.start')), findsNothing);
      expect(find.byKey(const Key('quiz.once')), findsOneWidget);
    });

    testWidgets('questions fit a small phone with large Gujarati text', (
      tester,
    ) async {
      final h = await _harness(quizzes: [_quiz()]);
      _wireQuizFlow(h);
      await _pump(
        tester,
        h,
        initial: AppRoutes.childQuiz(_quizId),
        size: const Size(320, 568),
        textScale: 2,
        locale: const Locale('gu'),
      );
      await _tap(tester, find.byKey(const Key('quiz.start')));
      expect(find.text('પ્રશ્ન 1 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
