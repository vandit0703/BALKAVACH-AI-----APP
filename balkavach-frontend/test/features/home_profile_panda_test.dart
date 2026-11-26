// Home and Profile have no Panda greeting or avatar bubble; Talk to Panda and Panda in missions stay.
//
// Mock/fake tests: the app runs against `FakeBackend` with fake speech services (no server, no device).
import 'package:balkavach_app/app.dart';
import 'package:balkavach_app/features/companion/data/speech_services.dart';
import 'package:balkavach_app/features/companion/domain/lip_sync.dart';
import 'package:balkavach_app/features/companion/presentation/panda_companion.dart';
import 'package:balkavach_app/features/missions/presentation/mission_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

class _QuietInput implements SpeechInput {
  @override
  Future<SpeechAvailability> prepare() async => SpeechAvailability.ready;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<bool> onDeviceAvailable() async => false;
  @override
  Future<String?> localeFor(String languageCode) async => '${languageCode}_IN';
  @override
  Future<void> listen({
    required String localeId,
    required void Function(String words) onPartial,
    required void Function(String words) onFinal,
    required void Function(SpeechInputError error) onError,
    bool onDevice = false,
  }) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
}

class _QuietOutput implements SpeechOutput {
  @override
  Future<SpeakOutcome> speak(
    String text, {
    required String languageCode,
    void Function()? onStart,
    void Function(SpokenWord word)? onWord,
  }) async => SpeakOutcome.completed;
  @override
  Future<void> stop() async {}
}

Map<String, Object?> _video(String id, String title, int seconds) => {
  'id': id,
  'title': title,
  'description': null,
  'thumbnail_url': null,
  'duration_seconds': seconds,
  'category_id': null,
  'video_source': 'hosted',
  'youtube_video_id': null,
  'channel_name': null,
  'last_position_seconds': 0,
  'video_format': seconds <= 60 ? 'short' : 'regular',
};

Future<Harness> _child({String language = 'en'}) async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: {...onboardedPrefs, 'app.language_code': language},
  );
  h.backend
    ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
    ..reply('GET', '/api/v1/video-access/allowance', {
      'child_id': Fx.childId,
      'local_date': '2026-11-21',
      'timezone': 'UTC',
      'total_earned_today_seconds': 900,
      'consumed_today_seconds': 0,
      'remaining_seconds': 900,
      'daily_cap_seconds': 3600,
      'is_exhausted': false,
      'active_entitlements_count': 1,
    })
    ..reply('GET', '/api/v1/videos/shorts', [
      _video('aaaaaaaa-0000-4000-8000-000000000001', 'Short one', 30),
    ])
    ..reply('GET', '/api/v1/videos/feed', [
      _video('aaaaaaaa-0000-4000-8000-000000000002', 'Long one', 300),
    ])
    ..reply('GET', '/api/v1/videos/watch-history/continue-watching', [])
    ..reply('GET', '/api/v1/daily-missions/today', {
      'local_date': '2026-11-21',
      'timezone': 'UTC',
      'age_band': '4_6',
      'selected_assignment_id': null,
      'choices': <Object?>[],
    })
    ..reply('GET', '/api/v1/daily-missions/unfinished', <Object?>[])
    ..reply('GET', '/api/v1/tasks/submissions/mine', <Object?>[])
    ..reply('GET', '/api/v1/companion/voice-consent', {'allowed': false});
  return h;
}

Future<void> _pumpApp(
  WidgetTester tester,
  Harness h, {
  Size size = const Size(393, 852),
  double scale = 1,
}) async {
  setWindow(tester, size);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...h.overrides,
        speechInputProvider.overrideWithValue(_QuietInput()),
        speechOutputProvider.overrideWithValue(_QuietOutput()),
      ],
      retry: (_, _) => null,
      child: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: const BalKavachApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _tabs = {
  'en': ['Home', 'Missions', 'Profile'],
  'hi': ['होम', 'मिशन', 'प्रोफ़ाइल'],
  'gu': ['હોમ', 'મિશન', 'પ્રોફાઇલ'],
};

void main() {
  for (final language in ['en', 'hi', 'gu']) {
    for (final (size, scale) in const [
      (Size(393, 852), 1.0),
      (Size(320, 640), 2.0),
      (Size(840, 1100), 1.0),
    ]) {
      group('$language ${size.width.toInt()}px x$scale', () {
        testWidgets('Home has no Panda greeting or avatar bubble, and keeps '
            'the allowance card and the feeds', (tester) async {
          final h = await _child(language: language);
          await _pumpApp(tester, h, size: size, scale: scale);

          expect(find.byType(PandaCompanion), findsNothing);
          expect(find.byKey(const Key('panda.avatar')), findsNothing);
          // Lists are lazy: on a small, large-text screen scroll down to them.
          for (final key in const [
            'watch.allowance.card',
            'watch.shorts.header',
          ]) {
            await tester.scrollUntilVisible(
              find.byKey(Key(key)),
              200,
              scrollable: find
                  .descendant(
                    of: find.byKey(const Key('watch.scroll')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            expect(find.byKey(Key(key)), findsOneWidget);
          }
          expect(find.byKey(const Key('panda.talk.open')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });

        testWidgets('Profile has no Panda greeting or avatar bubble, and '
            'keeps its functions', (tester) async {
          final h = await _child(language: language);
          h.backend.reply('GET', '/api/v1/tasks', [Fx.task()]);
          await _pumpApp(tester, h, size: size, scale: scale);
          final nav = _tabs[language]!;
          await tester.tap(find.text(nav[2]).last);
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('profile.dashboard')), findsOneWidget);
          expect(find.byType(PandaCompanion), findsNothing);
          expect(find.byKey(const Key('panda.avatar')), findsNothing);
          expect(find.byKey(const Key('profile.language')), findsOneWidget);
          expect(find.byKey(const Key('profile.language.hi')), findsOneWidget);
          expect(find.byKey(const Key('panda.talk.open')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });
    }
  }

  testWidgets('Profile with no missions at all has no Panda either', (
    tester,
  ) async {
    final h = await _child();
    h.backend.reply('GET', '/api/v1/tasks', <Object?>[]);
    await _pumpApp(tester, h);
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.byType(PandaCompanion), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Talk to Panda still opens from Home, works by typing, and '
      'keeps the microphone closed without parental consent', (tester) async {
    final h = await _child();
    h.backend.reply('POST', '/api/v1/companion/chat', {
      'reply': 'Why are fish smart? They live in schools!',
      'locale': 'en',
      'mood': 'happy',
      'intent': 'joke',
      'follow_up': 'joke',
      'safety': 'ok',
      'suggestions': ['fact'],
    });
    await _pumpApp(tester, h);

    await tester.tap(find.byKey(const Key('panda.talk.open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panda.talk.sheet')), findsOneWidget);
    expect(find.byKey(const Key('panda.rig')), findsOneWidget);

    // Typing works.
    await tester.tap(find.byKey(const Key('panda.talk.type')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('panda.talk.input')), 'joke');
    await tester.tap(find.byKey(const Key('panda.talk.send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('fish smart'), findsWidgets);
    expect(
      h.backend.requestsTo('POST', '/api/v1/companion/chat'),
      hasLength(1),
    );

    // The microphone: consent is asked of the server first and refused.
    await tester.tap(find.byKey(const Key('panda.talk.mic')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panda.talk.micExplain')), findsNothing);
    expect(find.byKey(const Key('panda.talk.problem')), findsOneWidget);

    await tester.tap(find.byKey(const Key('panda.talk.close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panda.talk.sheet')), findsNothing);
  });

  testWidgets('Panda is still part of the mission experience', (tester) async {
    final h = await _child();
    h.backend.reply('GET', '/api/v1/tasks', [Fx.task()]);
    await _pumpApp(tester, h);
    await tester.tap(find.text('Missions').last);
    await tester.pumpAndSettle();
    expect(find.byType(PandaCompanion), findsWidgets);

    await tester.tap(find.text('Read a Storybook'));
    await tester.pumpAndSettle();
    expect(find.byType(MissionDetailScreen), findsOneWidget);
    expect(find.byType(PandaCompanion), findsOneWidget);
  });
}
