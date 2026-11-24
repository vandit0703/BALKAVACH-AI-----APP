import 'package:balkavach_app/core/theme/app_theme.dart';
import 'package:balkavach_app/features/learning/data/learning_repository.dart';
import 'package:balkavach_app/features/learning/presentation/learning_screen.dart';
import 'package:balkavach_app/features/missions/presentation/mission_submit_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:balkavach_app/shared/celebration/activity_completion.dart';
import 'package:balkavach_app/shared/celebration/panda_celebration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

/// A screen with one button that shows the celebration and records how the
/// child left it.
class _Host extends StatefulWidget {
  const _Host(this.completion);

  final ActivityCompletion completion;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  CelebrationAction? left;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          key: const Key('host.show'),
          onPressed: () async {
            final action = await showPandaCelebration(
              context,
              widget.completion,
            );
            setState(() => left = action);
          },
          child: const Text('show'),
        ),
        Text('left: ${left?.name}'),
      ],
    ),
  );
}

Future<void> _show(
  WidgetTester tester,
  ActivityCompletion completion, {
  Locale locale = const Locale('en'),
  Size size = const Size(393, 852),
  double scale = 1,
  bool reduceMotion = false,
}) async {
  setWindow(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduceMotion,
        ),
        child: app!,
      ),
      home: _Host(completion),
    ),
  );
  await tester.tap(find.byKey(const Key('host.show')));
  await tester.pumpAndSettle();
}

const _quiz = ActivityCompletion(
  kind: ActivityKind.quiz,
  title: 'Animals quiz',
  stars: 10,
  xp: 15,
  offerHome: true,
);

void main() {
  group('ActivityCompletion', () {
    test('knows whether anything was earned', () {
      expect(_quiz.hasRewards, isTrue);
      expect(
        const ActivityCompletion(
          kind: ActivityKind.story,
          title: 's',
        ).hasRewards,
        isFalse,
      );
      expect(
        const ActivityCompletion(
          kind: ActivityKind.quiz,
          title: 'q',
          xp: 3,
        ).hasRewards,
        isTrue,
      );
    });

    test('rewards can never be negative', () {
      expect(
        () =>
            ActivityCompletion(kind: ActivityKind.quiz, title: 'q', stars: -1),
        throwsAssertionError,
      );
    });
  });

  group('PandaCelebration', () {
    testWidgets('shows the official Panda, the activity and what was earned', (
      tester,
    ) async {
      await _show(tester, _quiz);
      final panda = tester.widget<Image>(
        find.byKey(const Key('celebration.panda')),
      );
      expect((panda.image as AssetImage).assetName, contains('panda_cheering'));
      expect(find.text('Quiz complete!'), findsOneWidget);
      expect(find.text('Animals quiz'), findsOneWidget);
      expect(find.text('+ 10 Stars + 15 XP'), findsOneWidget);
      expect(find.text('Great job! Keep going!'), findsOneWidget);
    });

    for (final (kind, headline) in [
      (ActivityKind.mission, 'Mission complete!'),
      (ActivityKind.quiz, 'Quiz complete!'),
      (ActivityKind.video, 'Video done!'),
      (ActivityKind.story, 'Story finished!'),
      (ActivityKind.garden, 'Your garden is growing!'),
    ]) {
      testWidgets('has a headline for ${kind.name}', (tester) async {
        await _show(tester, ActivityCompletion(kind: kind, title: 'T'));
        expect(find.text(headline), findsOneWidget);
      });
    }

    testWidgets('shows only the rewards that were earned', (tester) async {
      await _show(
        tester,
        const ActivityCompletion(kind: ActivityKind.quiz, title: 'q', stars: 4),
      );
      expect(find.text('+ 4 Stars'), findsOneWidget);
      expect(find.textContaining('XP'), findsNothing);
    });

    testWidgets('shows no reward line when nothing was paid', (tester) async {
      await _show(
        tester,
        const ActivityCompletion(kind: ActivityKind.video, title: 'v'),
      );
      expect(find.byKey(const Key('celebration.rewards')), findsNothing);
      expect(find.textContaining('Stars'), findsNothing);
    });

    testWidgets('a custom note replaces the generic cheer', (tester) async {
      await _show(
        tester,
        const ActivityCompletion(
          kind: ActivityKind.mission,
          title: 'm',
          note: 'Wait for your parent',
        ),
      );
      expect(find.text('Wait for your parent'), findsOneWidget);
      expect(find.text('Great job! Keep going!'), findsNothing);
    });

    testWidgets('Continue dismisses and reports continue', (tester) async {
      await _show(tester, _quiz);
      await tester.tap(find.byKey(const Key('celebration.continue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('celebration.card')), findsNothing);
      expect(find.text('left: continueOn'), findsOneWidget);
    });

    testWidgets('Home reports home, and exists only when offered', (
      tester,
    ) async {
      await _show(tester, _quiz);
      await tester.tap(find.byKey(const Key('celebration.home')));
      await tester.pumpAndSettle();
      expect(find.text('left: home'), findsOneWidget);

      await _show(
        tester,
        const ActivityCompletion(kind: ActivityKind.story, title: 's'),
      );
      expect(find.byKey(const Key('celebration.home')), findsNothing);
    });

    testWidgets('system Back counts as Continue', (tester) async {
      await _show(tester, _quiz);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('celebration.card')), findsNothing);
      expect(find.text('left: continueOn'), findsOneWidget);
    });

    for (final (locale, headline, cont) in [
      (const Locale('hi'), 'क्विज़ पूरी!', 'जारी रखें'),
      (const Locale('gu'), 'ક્વિઝ પૂરી!', 'ચાલુ રાખો'),
    ]) {
      testWidgets('is localised for ${locale.languageCode}', (tester) async {
        await _show(tester, _quiz, locale: locale);
        expect(find.text(headline), findsOneWidget);
        expect(find.text(cont), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('reduced motion keeps the content and skips the burst', (
      tester,
    ) async {
      await _show(tester, _quiz, reduceMotion: true);
      expect(find.byKey(const Key('celebration.panda')), findsOneWidget);
      expect(find.text('Quiz complete!'), findsOneWidget);
      expect(find.byKey(const Key('celebration.continue')), findsOneWidget);
    });

    testWidgets('fits a small phone with large text', (tester) async {
      await _show(
        tester,
        _quiz,
        size: const Size(320, 480),
        scale: 2,
        locale: const Locale('gu'),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('celebration.continue')));
      expect(find.byKey(const Key('celebration.continue')), findsOneWidget);
    });

    testWidgets('the Continue button is a comfortable touch target', (
      tester,
    ) async {
      await _show(tester, _quiz);
      final size = tester.getSize(
        find.byKey(const Key('celebration.continue')),
      );
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('Mission submission', () {
    testWidgets('celebrates the hand-in without showing any reward', (
      tester,
    ) async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend
        ..reply('GET', '/api/v1/tasks', [Fx.task()])
        ..reply(
          'POST',
          '/api/v1/tasks/${Fx.taskId}/submissions',
          Fx.submission(),
          status: 201,
        );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const MissionSubmitScreen(taskId: Fx.taskId),
          ),
          GoRoute(
            path: '/child/missions/:taskId/waiting',
            builder: (_, _) => const Scaffold(body: Text('WAITING')),
          ),
        ],
      );
      setWindow(tester, const Size(393, 1200));
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          retry: (_, _) => null,
          child: MaterialApp.router(
            routerConfig: router,
            theme: buildAppTheme(),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submit.button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('celebration.card')), findsOneWidget);
      expect(find.text('Mission complete!'), findsOneWidget);
      // Rewards come only with the parent's approval, so none appear here.
      expect(find.byKey(const Key('celebration.rewards')), findsNothing);
      expect(
        find.text('Your parent will check it, then your rewards arrive.'),
        findsOneWidget,
      );
      expect(find.text('WAITING'), findsNothing);
      await tester.tap(find.byKey(const Key('celebration.continue')));
      await tester.pumpAndSettle();
      expect(find.text('WAITING'), findsOneWidget);
      expect(
        h.backend.requestsTo('POST', '/api/v1/tasks/${Fx.taskId}/submissions'),
        hasLength(1),
      );
    });

    testWidgets('a failed submission is not celebrated', (tester) async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend
        ..reply('GET', '/api/v1/tasks', [Fx.task()])
        ..reply('POST', '/api/v1/tasks/${Fx.taskId}/submissions', {
          'error': {'code': 'internal_error', 'message': 'boom'},
        }, status: 500);
      await pumpScreen(
        tester,
        const MissionSubmitScreen(taskId: Fx.taskId),
        overrides: h.overrides,
        size: const Size(393, 1200),
      );
      await tester.tap(find.byKey(const Key('submit.button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('celebration.card')), findsNothing);
      expect(find.byType(MissionSubmitScreen), findsOneWidget);
    });
  });

  group('Story reading', () {
    LearningItem story(String text) => LearningItem.fromJson({
      'id': 'story-1',
      'title': 'The Kind Lion',
      'description': text,
      'content_type': 'article',
      'requires_entitlement': false,
    });

    String words(int n) => List.filled(n, 'word').join(' ');

    Future<void> open(WidgetTester tester, LearningItem item, Size size) async {
      final h = await Harness.create(session: Fx.childSession());
      await pumpScreen(
        tester,
        LearningDetailScreen(item: item),
        overrides: h.overrides,
        size: size,
      );
    }

    testWidgets('a short story is celebrated once, after enough reading time', (
      tester,
    ) async {
      await open(tester, story(words(40)), const Size(393, 1400));
      expect(find.byKey(const Key('story.text')), findsOneWidget);
      // Opening it is not finishing it: no celebration straight away.
      await tester.pump(const Duration(seconds: 10));
      expect(find.byKey(const Key('celebration.card')), findsNothing);
      // A 1-minute story: 40% of the reading time is 24 seconds.
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      expect(find.text('Story finished!'), findsOneWidget);
      expect(find.text('The Kind Lion'), findsWidgets);
      expect(find.byKey(const Key('celebration.rewards')), findsNothing);
      await tester.tap(find.byKey(const Key('celebration.continue')));
      await tester.pumpAndSettle();
      // Never twice for the same reading.
      await tester.pump(const Duration(minutes: 2));
      expect(find.byKey(const Key('celebration.card')), findsNothing);
    });

    testWidgets('a long story needs the end to be reached, not just time', (
      tester,
    ) async {
      await open(tester, story(words(900)), const Size(393, 500));
      await tester.pump(const Duration(seconds: 90));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('celebration.card')),
        findsNothing,
        reason: 'enough time, but the child has not reached the end',
      );
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -20000),
      );
      await tester.pumpAndSettle();
      expect(find.text('Story finished!'), findsOneWidget);
    });

    testWidgets('scrolling to the end too early does not count', (
      tester,
    ) async {
      await open(tester, story(words(900)), const Size(393, 500));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -20000),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('celebration.card')), findsNothing);
    });

    testWidgets('leaving early never celebrates', (tester) async {
      await open(tester, story(words(130)), const Size(393, 1400));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a link-only article is not a story to finish', (tester) async {
      final item = LearningItem.fromJson({
        'id': 'a',
        'title': 'Read this',
        'description': null,
        'content_type': 'article',
        'content_url': 'https://example.org/x',
        'requires_entitlement': false,
      });
      await open(tester, item, const Size(393, 852));
      await tester.pump(const Duration(minutes: 2));
      expect(find.byKey(const Key('celebration.card')), findsNothing);
    });
  });
}
