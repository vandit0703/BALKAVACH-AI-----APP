// Talk to Panda: the interaction state machine, speech failures, duplicate
// turns, interruptions, languages, reduced motion and the talk panel.

import 'dart:async';

import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/features/companion/data/companion_chat_repository.dart';
import 'package:balkavach_app/features/companion/data/speech_services.dart';
import 'package:balkavach_app/features/companion/domain/panda_interaction.dart';
import 'package:balkavach_app/features/companion/presentation/panda_character.dart';
import 'package:balkavach_app/features/companion/presentation/panda_talk_sheet.dart';
import 'package:balkavach_app/features/learning/data/video_feed_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

class FakeInput implements SpeechInput {
  SpeechAvailability availability = SpeechAvailability.ready;
  bool permission = true;
  Map<String, String> locales = {'en': 'en_IN', 'hi': 'hi_IN', 'gu': 'gu_IN'};
  int prepares = 0;
  int listens = 0;
  int cancels = 0;
  int stops = 0;
  String? lastLocale;
  void Function(String)? partial;
  void Function(String)? done;
  void Function(SpeechInputError)? failed;

  @override
  Future<SpeechAvailability> prepare() async {
    prepares++;
    return availability;
  }

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<String?> localeFor(String languageCode) async => locales[languageCode];

  @override
  Future<void> listen({
    required String localeId,
    required void Function(String words) onPartial,
    required void Function(String words) onFinal,
    required void Function(SpeechInputError error) onError,
  }) async {
    listens++;
    lastLocale = localeId;
    partial = onPartial;
    done = onFinal;
    failed = onError;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> cancel() async => cancels++;
}

class FakeOutput implements SpeechOutput {
  final spoken = <(String, String)>[];
  final supported = {'en', 'hi', 'gu'};
  Completer<SpeakOutcome>? current;
  void Function()? word;
  int stops = 0;

  /// When true, lines finish immediately.
  bool instant = false;

  @override
  Future<SpeakOutcome> speak(
    String text, {
    required String languageCode,
    void Function()? onWord,
  }) {
    spoken.add((text, languageCode));
    if (!supported.contains(languageCode)) {
      return Future.value(SpeakOutcome.unsupported);
    }
    if (instant) return Future.value(SpeakOutcome.completed);
    word = onWord;
    return (current = Completer<SpeakOutcome>()).future;
  }

  void finish() {
    final c = current;
    current = null;
    if (c != null && !c.isCompleted) c.complete(SpeakOutcome.completed);
  }

  @override
  Future<void> stop() async {
    stops++;
    final c = current;
    current = null;
    if (c != null && !c.isCompleted) c.complete(SpeakOutcome.interrupted);
  }
}

class FakeChat extends CompanionChatRepository {
  FakeChat() : super(Dio());

  final calls = <({String text, String locale, String? context, bool voice})>[];
  Completer<PandaChatReply>? pending;
  Object? error;
  bool hold = false;

  /// Parental microphone consent as the server reports it.
  bool consent = true;
  Object? consentError;
  int consentChecks = 0;
  PandaChatReply reply = const PandaChatReply(
    text: 'Why are fish smart? They live in schools! Want another one?',
    locale: 'en',
    mood: PandaReplyMood.happy,
    intent: 'joke',
    followUp: 'joke',
    suggestions: [PandaSuggestion.fact, PandaSuggestion.draw],
  );

  @override
  Future<PandaChatReply> chat({
    required String text,
    required String locale,
    required String turnId,
    String? contextIntent,
    bool voice = false,
  }) async {
    calls.add((
      text: text,
      locale: locale,
      context: contextIntent,
      voice: voice,
    ));
    if (error != null) throw error!;
    if (hold) return (pending = Completer<PandaChatReply>()).future;
    return reply;
  }

  @override
  Future<bool> voiceConsent() async {
    consentChecks++;
    if (consentError != null) throw consentError!;
    return consent;
  }
}

class World {
  final input = FakeInput();
  final output = FakeOutput();
  final chat = FakeChat();

  List<Override> get overrides => [
    speechInputProvider.overrideWithValue(input),
    speechOutputProvider.overrideWithValue(output),
    companionChatRepositoryProvider.overrideWithValue(chat),
  ];

  late ProviderContainer container;

  PandaTalkController get controller =>
      container.read(pandaTalkControllerProvider.notifier);
  PandaTalkState get state => container.read(pandaTalkControllerProvider);

  void start() {
    container = ProviderContainer(overrides: overrides);
    container.listen(pandaTalkControllerProvider, (_, _) {});
  }
}

Future<void> flush(WidgetTester tester) => tester.pump(Duration.zero);

/// A controller test whose container is disposed (cancelling Panda's timers)
/// before the test framework checks for pending timers.
void pandaTest(
  String name,
  Future<void> Function(WidgetTester tester, World w) body,
) => testWidgets(name, (tester) async {
  final w = World()..start();
  await body(tester, w);
  w.container.dispose();
});

void main() {
  group('transition table', () {
    test('every state can always go back to idle or start over', () {
      for (final phase in PandaPhase.values) {
        if (phase == PandaPhase.idle) continue;
        expect(
          pandaTransitions[phase],
          contains(PandaPhase.idle),
          reason: '$phase',
        );
      }
    });

    test('impossible moves are not allowed', () {
      expect(
        pandaTransitions[PandaPhase.listening],
        isNot(contains(PandaPhase.speaking)),
      );
      expect(
        pandaTransitions[PandaPhase.thinking],
        isNot(contains(PandaPhase.listening)),
      );
      expect(
        pandaTransitions[PandaPhase.idle],
        isNot(contains(PandaPhase.speaking)),
      );
    });
  });

  group('PandaTalkController', () {
    pandaTest('greeting speaks, then Panda rests happy and returns to idle', (
      tester,
      w,
    ) async {
      unawaited(w.controller.greet('Hi Aarav!'));
      await flush(tester);
      expect(w.state.phase, PandaPhase.greeting);
      expect(w.output.spoken.single, ('Hi Aarav!', 'en'));
      w.output.finish();
      await flush(tester);
      expect(w.state.phase, PandaPhase.happy);
      await tester.pump(PandaTalkController.happyRest);
      expect(w.state.phase, PandaPhase.idle);
    });

    pandaTest('a full voice turn: listen, think, speak with word beats, rest', (
      tester,
      w,
    ) async {
      w.chat.reply = const PandaChatReply(
        text: 'Fun fact: an octopus has three hearts!',
        locale: 'en',
        mood: PandaReplyMood.curious,
        intent: 'fact',
        followUp: 'fact',
      );
      unawaited(w.controller.startListening());
      await flush(tester);
      expect(w.state.phase, PandaPhase.listening);
      expect(w.input.lastLocale, 'en_IN');

      w.input.partial!('tell me');
      expect(w.state.heard, 'tell me');

      w.input.done!('tell me a fact');
      await flush(tester);
      expect(w.chat.calls.single.text, 'tell me a fact');
      expect(w.state.phase, PandaPhase.speaking);
      expect(w.state.childText, 'tell me a fact');
      expect(w.state.pandaText, contains('octopus'));

      final onWord = w.output.word!;
      onWord();
      onWord();
      expect(w.state.spokenWords, 2);

      w.output.finish();
      await flush(tester);
      // A word callback arriving after the line ended moves nothing.
      onWord();
      expect(w.state.spokenWords, 2);
      expect(w.state.phase, PandaPhase.curious);

      // "yes" next turn carries the follow-up topic.
      unawaited(w.controller.send('yes'));
      await flush(tester);
      expect(w.chat.calls.last.context, 'fact');
      w.output.finish();
      await flush(tester);
    });

    pandaTest('microphone permission denied: Panda explains, text box opens', (
      tester,
      w,
    ) async {
      w.input.availability = SpeechAvailability.denied;
      await w.controller.startListening();
      expect(w.state.phase, PandaPhase.error);
      expect(w.state.problem, PandaProblem.micDenied);
      expect(w.state.typing, isTrue);
      expect(w.input.listens, 0);
    });

    pandaTest('speech recognition failures', (tester, w) async {
      await w.controller.startListening();
      w.input.failed!(SpeechInputError.notHeard);
      expect(w.state.problem, PandaProblem.notHeard);
      expect(w.state.typing, isFalse);

      await w.controller.startListening();
      expect(w.state.phase, PandaPhase.listening);
      w.input.failed!(SpeechInputError.failed);
      expect(w.state.problem, PandaProblem.micUnavailable);
      expect(w.state.typing, isTrue);
      expect(w.chat.calls, isEmpty);
    });

    pandaTest('a device without the language offers typing instead', (
      tester,
      w,
    ) async {
      w.input.locales.remove('gu');
      w.controller.setLanguage('gu');
      await w.controller.startListening();
      expect(w.state.problem, PandaProblem.listenLanguageMissing);
      expect(w.state.typing, isTrue);
      expect(w.input.listens, 0);
    });

    pandaTest('empty or blank input never reaches the server', (
      tester,
      w,
    ) async {
      await w.controller.startListening();
      w.input.done!('   ');
      await flush(tester);
      expect(w.state.problem, PandaProblem.notHeard);
      expect(w.chat.calls, isEmpty);
      await w.controller.send('');
      expect(w.chat.calls, isEmpty);
    });

    pandaTest('listening never gets stuck: the watchdog ends it', (
      tester,
      w,
    ) async {
      await w.controller.startListening();
      await tester.pump(PandaTalkController.listenWatchdog);
      expect(w.state.phase, PandaPhase.error);
      expect(w.state.problem, PandaProblem.notHeard);
      expect(w.input.cancels, greaterThan(0));
    });

    pandaTest('duplicate requests: one listen, one chat call per turn', (
      tester,
      w,
    ) async {
      await w.controller.startListening();
      await w.controller.startListening();
      expect(w.input.listens, 1);
      expect(w.input.prepares, 1);

      w.chat.hold = true;
      w.input.done!('joke');
      await flush(tester);
      expect(w.state.phase, PandaPhase.thinking);
      unawaited(w.controller.send('joke'));
      await flush(tester);
      unawaited(w.controller.send('joke'));
      await flush(tester);
      await w.controller.startListening();
      expect(w.chat.calls, hasLength(1));
      expect(w.input.listens, 1);
      w.chat.pending!.complete(w.chat.reply);
      await flush(tester);
      w.output.finish();
      await flush(tester);
    });

    pandaTest('tapping the mic while Panda talks interrupts the voice', (
      tester,
      w,
    ) async {
      unawaited(w.controller.send('joke'));
      await flush(tester);
      expect(w.state.phase, PandaPhase.speaking);

      await w.controller.startListening();
      expect(w.output.stops, greaterThan(0));
      expect(w.state.phase, PandaPhase.listening);
      // The interrupted line ending late changes nothing.
      w.output.finish();
      await flush(tester);
      expect(w.state.phase, PandaPhase.listening);
    });

    pandaTest('Stop silences Panda, cancels listening and drops late replies', (
      tester,
      w,
    ) async {
      w.chat.hold = true;
      unawaited(w.controller.send('joke'));
      await flush(tester);
      expect(w.state.phase, PandaPhase.thinking);
      await w.controller.stop();
      expect(w.state.phase, PandaPhase.idle);
      expect(w.input.cancels, 1);
      w.chat.pending!.complete(w.chat.reply);
      await flush(tester);
      expect(w.state.phase, PandaPhase.idle);
      expect(w.output.spoken, isEmpty);
    });

    pandaTest('network trouble and rate limits get friendly errors', (
      tester,
      w,
    ) async {
      w.chat.error = const NetworkException();
      unawaited(w.controller.send('hello'));
      await flush(tester);
      expect(w.state.problem, PandaProblem.network);

      w.chat.error = const UnknownApiException(message: 'x', statusCode: 429);
      unawaited(w.controller.send('hello'));
      await flush(tester);
      expect(w.state.problem, PandaProblem.busy);
    });

    pandaTest('a reply that never comes ends in an error, not a hang', (
      tester,
      w,
    ) async {
      w.chat.hold = true;
      unawaited(w.controller.send('hello'));
      await flush(tester);
      await tester.pump(PandaTalkController.thinkWatchdog);
      expect(w.state.phase, PandaPhase.error);
      expect(w.state.problem, PandaProblem.network);
      w.chat.pending!.complete(w.chat.reply);
      await flush(tester);
      expect(w.output.spoken, isEmpty);
    });

    for (final code in ['en', 'hi', 'gu']) {
      pandaTest('$code: recognition, request and voice use $code', (
        tester,
        w,
      ) async {
        w.output.instant = true;
        w.controller.setLanguage(code);
        await w.controller.startListening();
        expect(w.input.lastLocale, '${code}_IN');
        w.input.done!('hello');
        await flush(tester);
        expect(w.chat.calls.single.locale, code);
        expect(w.output.spoken.single.$2, code);
      });
    }

    pandaTest('no voice for the language: the line is still shown', (
      tester,
      w,
    ) async {
      w.output.supported.remove('gu');
      w.controller.setLanguage('gu');
      unawaited(w.controller.send('joke'));
      await flush(tester);
      expect(w.state.voiceMissing, isTrue);
      expect(w.state.pandaText, isNotEmpty);
      expect(w.state.phase, PandaPhase.happy);
    });

    pandaTest('sleepy reply leaves Panda sleepy (video time is over)', (
      tester,
      w,
    ) async {
      w.output.instant = true;
      w.chat.reply = const PandaChatReply(
        text: 'Video time is finished for today.',
        locale: 'en',
        mood: PandaReplyMood.sleepy,
        intent: 'video_exhausted',
      );
      unawaited(w.controller.send('more video please'));
      await flush(tester);
      expect(w.state.phase, PandaPhase.sleepy);
    });

    pandaTest('closing the panel cancels listening and silences Panda', (
      tester,
      w,
    ) async {
      await w.controller.startListening();
      w.container.dispose();
      expect(w.input.cancels, greaterThan(0));
      expect(w.output.stops, greaterThan(0));
      w.container = ProviderContainer(); // for the tear-down
    });
  });

  group('parental microphone consent', () {
    pandaTest('without consent the microphone never opens; typing works', (
      tester,
      w,
    ) async {
      w.chat.consent = false;
      await w.controller.startListening();
      await flush(tester);

      expect(w.input.prepares, 0);
      expect(w.input.listens, 0);
      expect(w.state.problem, PandaProblem.voiceNeedsParent);
      expect(w.state.voiceAllowed, isFalse);
      expect(w.state.typing, isTrue, reason: 'the text box is offered');

      unawaited(w.controller.send('hello'));
      await flush(tester);
      expect(w.chat.calls.single.voice, isFalse);
      expect(w.state.phase, PandaPhase.speaking);
    });

    pandaTest('when consent cannot be checked the microphone stays closed', (
      tester,
      w,
    ) async {
      w.chat.consentError = const NetworkException();
      await w.controller.startListening();
      await flush(tester);

      expect(w.input.listens, 0);
      expect(w.state.problem, PandaProblem.network);
      expect(w.state.voiceAllowed, isNull);
    });

    pandaTest('consent is checked with the server before listening', (
      tester,
      w,
    ) async {
      unawaited(w.controller.startListening());
      await flush(tester);
      expect(w.chat.consentChecks, 1);
      expect(w.state.phase, PandaPhase.listening);
      w.input.done!('hello panda');
      await flush(tester);
      expect(w.chat.calls.single.voice, isTrue, reason: 'sent as a voice turn');
    });

    pandaTest('a withdrawal refused by the server stops listening and '
        'speaking at once; typing still works', (tester, w) async {
      unawaited(w.controller.startListening());
      await flush(tester);
      w.chat.error = const ForbiddenException(
        message: 'no consent',
        code: kPandaVoiceConsentRequired,
      );
      w.input.done!('hello panda');
      await flush(tester);

      expect(w.state.problem, PandaProblem.voiceNeedsParent);
      expect(w.state.voiceAllowed, isFalse);
      expect(w.input.cancels, greaterThanOrEqualTo(1));
      expect(w.output.stops, greaterThanOrEqualTo(1));
      expect(w.state.typing, isTrue);

      // The next mic tap asks the server again and stays closed.
      w.chat
        ..error = null
        ..consent = false;
      final listensBefore = w.input.listens;
      await w.controller.startListening();
      await flush(tester);
      expect(w.input.listens, listensBefore);

      unawaited(w.controller.send('tell me a joke'));
      await flush(tester);
      expect(w.chat.calls.last.voice, isFalse);
      expect(w.state.pandaText, contains('schools'));
    });
  });

  test('turn ids are fresh v4 UUIDs', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final ids = {for (var i = 0; i < 50; i++) newTurnId()};
    expect(ids, hasLength(50));
    expect(ids.every(pattern.hasMatch), isTrue);
  });

  test('server replies parse, unknown values fall back safely', () {
    final reply = PandaChatReply.fromJson({
      'reply': 'Hi',
      'locale': 'hi',
      'mood': 'dancing',
      'intent': 'greeting',
      'follow_up': null,
      'safety': 'redirected',
      'suggestions': ['joke', 'unknown'],
    });
    expect(reply.mood, PandaReplyMood.talking);
    expect(reply.redirected, isTrue);
    expect(reply.suggestions, [PandaSuggestion.joke]);
  });

  group('PandaCharacter', () {
    Future<void> pump(WidgetTester tester, PandaPhase phase, int words) =>
        pumpScreen(
          tester,
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: PandaCharacter(phase: phase, spokenWords: words),
              ),
            ),
          ),
          overrides: const [],
          settle: false,
        );

    double scaleOf(WidgetTester tester) => tester
        .widget<Transform>(
          find
              .descendant(
                of: find.byKey(const Key('panda.talk.character')),
                matching: find.byType(Transform),
              )
              .last,
        )
        .transform
        .getMaxScaleOnAxis();

    testWidgets('each spoken word gives one talk beat', (tester) async {
      await pump(tester, PandaPhase.speaking, 0);
      expect(scaleOf(tester), closeTo(1, 0.001));
      await pump(tester, PandaPhase.speaking, 1); // 100 ms into a 180 ms beat
      expect(scaleOf(tester), greaterThan(1.005));
      await tester.pump(const Duration(milliseconds: 200));
      expect(scaleOf(tester), closeTo(1, 0.001));
    });

    testWidgets('reduced motion: words and happy news move nothing', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pump(tester, PandaPhase.speaking, 0);
      await pump(tester, PandaPhase.speaking, 3);
      await tester.pump(const Duration(milliseconds: 90));
      expect(scaleOf(tester), 1);
      await pump(tester, PandaPhase.happy, 3);
      await tester.pump(const Duration(milliseconds: 300));
      expect(scaleOf(tester), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('motion stops as soon as the words stop', (tester) async {
      await pump(tester, PandaPhase.speaking, 0);
      for (var words = 1; words <= 3; words++) {
        await pump(tester, PandaPhase.speaking, words);
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.hasRunningAnimations, isFalse);
      expect(scaleOf(tester), closeTo(1, 0.001));
    });

    testWidgets('idle breathing is bounded, so it cannot drain the battery', (
      tester,
    ) async {
      await pump(tester, PandaPhase.idle, 0);
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(minutes: 1));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('removing Panda mid-animation leaks no controller', (
      tester,
    ) async {
      await pump(tester, PandaPhase.happy, 0);
      await pump(tester, PandaPhase.speaking, 1);
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
      // An undisposed AnimationController would throw here.
      expect(tester.takeException(), isNull);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('each state uses the existing Panda artwork', (tester) async {
      for (final phase in PandaPhase.values) {
        expect(kPandaArt.poseFor(phase), startsWith('assets/images/panda_'));
      }
      await pump(tester, PandaPhase.happy, 0);
      expect(
        find.byKey(
          const ValueKey('panda.pose.assets/images/panda_cheering.jpg'),
        ),
        findsOneWidget,
      );
    });
  });

  group('talk panel', () {
    late World w;

    Future<void> open(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      Size size = const Size(393, 852),
      double scale = 1,
      bool exhausted = false,
      bool consent = true,
    }) async {
      resetPandaMicExplanation();
      w = World();
      w.output.instant = true;
      w.chat.consent = consent;
      await pumpScreen(
        tester,
        const Scaffold(body: PandaTalkSheet()),
        overrides: [
          ...w.overrides,
          videoAllowanceProvider.overrideWith(
            (ref) async => VideoAllowance(
              childId: 'c',
              localDate: '2026-11-19',
              timezone: 'UTC',
              totalEarnedTodaySeconds: 900,
              consumedTodaySeconds: exhausted ? 900 : 0,
              remainingSeconds: exhausted ? 0 : 900,
              dailyCapSeconds: 4500,
              isExhausted: exhausted,
              activeEntitlementsCount: 1,
            ),
          ),
        ],
        locale: locale,
        size: size,
        textScale: scale,
      );
    }

    testWidgets('greets, then talks by typing', (tester) async {
      await open(tester);
      expect(w.output.spoken, hasLength(1));
      expect(find.byKey(const Key('panda.talk.reply')), findsOneWidget);

      await tester.tap(find.byKey(const Key('panda.talk.type')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('panda.talk.input')), 'joke');
      await tester.tap(find.byKey(const Key('panda.talk.send')));
      await tester.pumpAndSettle();
      expect(w.chat.calls.single.text, 'joke');
      expect(find.textContaining('schools'), findsOneWidget);
      expect(find.byKey(const Key('panda.talk.child')), findsOneWidget);
    });

    testWidgets('suggestion chips send their topic', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('panda.talk.suggest.joke')));
      await tester.pumpAndSettle();
      expect(w.chat.calls.single.text, 'Tell a joke');
    });

    testWidgets('the mic is explained before permission is asked', (
      tester,
    ) async {
      await open(tester);
      w.input.permission = false;
      await tester.tap(find.byKey(const Key('panda.talk.mic')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panda.talk.micExplain')), findsOneWidget);
      // Honest disclosure: the platform speech service may be Google's.
      expect(find.textContaining('Google'), findsOneWidget);
      expect(find.textContaining('Nothing you say is recorded'), findsNothing);
      await tester.tap(find.byKey(const Key('panda.talk.micNotNow')));
      await tester.pumpAndSettle();
      expect(w.input.prepares, 0, reason: 'no system prompt after "Not now"');
      expect(find.byKey(const Key('panda.talk.input')), findsOneWidget);

      await tester.tap(find.byKey(const Key('panda.talk.mic')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('panda.talk.micAllow')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(w.input.prepares, 1);
      expect(
        find.byKey(const Key('panda.talk.status.listening')),
        findsOneWidget,
      );
      // The same button ends listening.
      await tester.tap(find.byKey(const Key('panda.talk.mic')));
      await tester.pump();
      expect(w.input.stops, 1);
    });

    testWidgets('denied permission shows the friendly message and a text box', (
      tester,
    ) async {
      await open(tester);
      w.input.availability = SpeechAvailability.denied;
      await tester.tap(find.byKey(const Key('panda.talk.mic')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panda.talk.problem')), findsOneWidget);
      expect(find.byKey(const Key('panda.talk.input')), findsOneWidget);
    });

    testWidgets('without parental consent the mic is shown off and never '
        'asks for the permission', (tester) async {
      await open(tester, consent: false);
      expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);

      w.input.permission = false;
      await tester.tap(find.byKey(const Key('panda.talk.mic')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('panda.talk.micExplain')), findsNothing);
      expect(w.input.prepares, 0);
      expect(w.input.listens, 0);
      expect(find.textContaining('grown-up’s OK'), findsOneWidget);
      expect(find.byKey(const Key('panda.talk.input')), findsOneWidget);
    });

    testWidgets('video time over: Panda opens sleepy and says so', (
      tester,
    ) async {
      await open(tester, exhausted: true);
      expect(find.byKey(const Key('panda.talk.status.sleepy')), findsOneWidget);
      expect(w.output.spoken.single.$1.toLowerCase(), contains('video time'));
    });

    testWidgets('time left: Panda opens with a happy hello', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('panda.talk.status.sleepy')), findsNothing);
      expect(
        w.output.spoken.single.$1.toLowerCase(),
        isNot(contains('video time')),
      );
    });

    testWidgets('app going to the background stops Panda', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('panda.talk.mic')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(w.input.listens, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(w.input.cancels, greaterThan(0));
      // A paused app draws no frames, so read the controller directly.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PandaTalkSheet)),
      );
      expect(
        container.read(pandaTalkControllerProvider).phase,
        PandaPhase.idle,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    for (final (size, scale, locale) in [
      (const Size(320, 568), 2.0, const Locale('en')),
      (const Size(360, 640), 2.0, const Locale('hi')),
      (const Size(390, 844), 1.3, const Locale('gu')),
      (const Size(740, 360), 1.0, const Locale('gu')),
      (const Size(1024, 768), 1.0, const Locale('hi')),
    ]) {
      testWidgets('no overflow $size @ ${scale}x $locale', (tester) async {
        await open(tester, size: size, scale: scale, locale: locale);
        await tester.ensureVisible(find.byKey(const Key('panda.talk.type')));
        await tester.tap(find.byKey(const Key('panda.talk.type')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(w.output.spoken.single.$2, locale.languageCode);
      });
    }
  });
}
