// Panda companion groundwork: the dialogue director, the bubble in all three
// languages, the lock-screen integration and the naming rule.

import 'dart:io';
import 'dart:math';

import 'package:balkavach_app/features/companion/domain/companion_director.dart';
import 'package:balkavach_app/features/companion/presentation/panda_bubble.dart';
import 'package:balkavach_app/features/companion/presentation/panda_companion.dart';
import 'package:balkavach_app/features/learning/presentation/video_lock_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  group('CompanionDirector', () {
    test('never repeats the same variant twice in a row', () {
      final director = CompanionDirector(
        cooldown: Duration.zero,
        random: Random(1),
      );
      int? previous;
      for (var i = 0; i < 200; i++) {
        final variant = director.next(CompanionEvent.greeting)!;
        expect(variant, isNot(previous));
        previous = variant;
      }
    });

    test('an event that just spoke stays quiet until the cooldown passes', () {
      var now = DateTime(2026, 11, 19, 9);
      final director = CompanionDirector(now: () => now);
      expect(director.next(CompanionEvent.greeting), isNotNull);
      now = now.add(const Duration(seconds: 10));
      expect(director.next(CompanionEvent.greeting), isNull);
      now = now.add(const Duration(seconds: 25));
      expect(director.next(CompanionEvent.greeting), isNotNull);
    });

    test('other events are not silenced by one speaking', () {
      final director = CompanionDirector();
      director.next(CompanionEvent.greeting);
      expect(director.next(CompanionEvent.missionApproved), isNotNull);
    });

    test('state changes the child must see are never throttled', () {
      final director = CompanionDirector();
      for (var i = 0; i < 5; i++) {
        expect(director.next(CompanionEvent.videoUp), isNotNull);
        expect(director.next(CompanionEvent.videoUnlocked), isNotNull);
      }
    });

    test('the same seed gives the same sequence', () {
      List<int?> run() {
        final d = CompanionDirector(cooldown: Duration.zero, random: Random(7));
        return [for (var i = 0; i < 20; i++) d.next(CompanionEvent.videoLow)];
      }

      expect(run(), run());
    });
  });

  group('authored lines', () {
    for (final code in ['en', 'hi', 'gu']) {
      test('every event has two distinct, non-empty lines in $code', () async {
        final l10n = await AppLocalizations.delegate.load(Locale(code));
        for (final event in CompanionEvent.values) {
          final a = pandaLine(l10n, event, 0, minutes: 15);
          final b = pandaLine(l10n, event, 1, minutes: 15);
          expect(a.trim(), isNotEmpty, reason: '$event');
          expect(b.trim(), isNotEmpty, reason: '$event');
          expect(a, isNot(b), reason: '$event in $code');
        }
      });

      test(
        'the unlock line carries the real number of minutes in $code',
        () async {
          final l10n = await AppLocalizations.delegate.load(Locale(code));
          expect(
            pandaLine(l10n, CompanionEvent.videoUnlocked, 0, minutes: 30),
            contains('30'),
          );
          expect(
            pandaLine(l10n, CompanionEvent.videoUnlocked, 1, minutes: 45),
            contains('45'),
          );
        },
      );
    }

    test(
      'lines are written in the right script for Hindi and Gujarati',
      () async {
        final hi = await AppLocalizations.delegate.load(const Locale('hi'));
        final gu = await AppLocalizations.delegate.load(const Locale('gu'));
        final devanagari = RegExp('[ऀ-ॿ]');
        final gujarati = RegExp('[઀-૿]');
        for (final event in CompanionEvent.values) {
          for (final v in [0, 1]) {
            expect(
              devanagari.hasMatch(pandaLine(hi, event, v)),
              isTrue,
              reason: '$event $v hi',
            );
            expect(
              gujarati.hasMatch(pandaLine(gu, event, v)),
              isTrue,
              reason: '$event $v gu',
            );
          }
        }
      },
    );

    test('the companion is called Panda, never a working name', () {
      for (final code in ['en', 'hi', 'gu']) {
        final text = File('lib/l10n/app_$code.arb').readAsStringSync();
        expect(text.contains('Mitu'), isFalse, reason: code);
        expect(text.contains('Kavach Panda'), isFalse, reason: code);
        expect(text.contains('कवच पांडा'), isFalse, reason: code);
        expect(text.contains('કવચ પાંડા'), isFalse, reason: code);
      }
      for (final code in ['hi', 'gu']) {
        final l10n = File('lib/l10n/app_$code.arb').readAsStringSync();
        expect(l10n.contains('"pandaName"'), isTrue);
      }
    });
  });

  group('PandaBubble', () {
    Future<void> pump(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      Size size = const Size(393, 852),
      double scale = 1,
    }) => pumpScreen(
      tester,
      const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(8),
          child: PandaBubble(event: CompanionEvent.videoUp),
        ),
      ),
      overrides: const [],
      locale: locale,
      size: size,
      textScale: scale,
    );

    testWidgets('shows one of the authored lines and keeps it on rebuild', (
      tester,
    ) async {
      await pump(tester);
      final first = tester
          .widget<Text>(find.byKey(const Key('panda.line')))
          .data;
      expect(first, isNotEmpty);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('panda.line'))).data,
        first,
      );
    });

    for (final (size, scale, locale) in [
      (const Size(320, 568), 2.0, const Locale('en')),
      (const Size(360, 640), 2.0, const Locale('hi')),
      (const Size(390, 844), 2.0, const Locale('gu')),
      (const Size(740, 360), 1.0, const Locale('gu')),
    ]) {
      testWidgets('wraps without overflow $size @ ${scale}x $locale', (
        tester,
      ) async {
        await pump(tester, size: size, scale: scale, locale: locale);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('the lock screen has Panda say the video-time-up line', (
    tester,
  ) async {
    await pumpScreen(tester, const VideoLockScreen(), overrides: const []);
    expect(find.byKey(const Key('panda.bubble')), findsOneWidget);
    expect(find.byKey(const Key('video.lock.toMissions')), findsOneWidget);
  });

  group('personal lines', () {
    for (final code in ['en', 'hi', 'gu']) {
      test('the name, mission and stars appear in $code', () async {
        final l10n = await AppLocalizations.delegate.load(Locale(code));
        for (final v in [0, 1]) {
          expect(
            pandaLine(l10n, CompanionEvent.greetingNamed, v, name: 'Aarav'),
            contains('Aarav'),
          );
          expect(
            pandaLine(
              l10n,
              CompanionEvent.missionIntro,
              v,
              missionTitle: 'Tidy toys',
            ),
            contains('Tidy toys'),
          );
          expect(
            pandaLine(l10n, CompanionEvent.rewardExplain, v, stars: 5),
            contains('5'),
          );
        }
      });
    }

    test('the moods fit the news', () {
      expect(
        pandaMoodFor(CompanionEvent.missionApproved),
        PandaMood.celebrating,
      );
      expect(pandaMoodFor(CompanionEvent.videoUnlocked), PandaMood.celebrating);
      expect(pandaMoodFor(CompanionEvent.videoUp), PandaMood.sleepy);
      expect(pandaMoodFor(CompanionEvent.greetingNamed), PandaMood.talking);
    });
  });

  group('PandaCompanion', () {
    Future<void> pump(
      WidgetTester tester, {
      CompanionEvent event = CompanionEvent.greetingNamed,
      Locale locale = const Locale('en'),
      Size size = const Size(393, 852),
      double scale = 1,
      bool settle = true,
    }) => pumpScreen(
      tester,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: PandaCompanion(
            event: event,
            name: 'Aarav',
            missionTitle: 'Tidy toys',
            stars: 5,
          ),
        ),
      ),
      overrides: const [],
      locale: locale,
      size: size,
      textScale: scale,
      settle: settle,
    );

    String shown(WidgetTester tester) => tester
        .widgetList<Text>(
          find.byWidgetPredicate((w) {
            final k = w.key;
            return k is ValueKey<String> && k.value.startsWith('panda.line.');
          }),
        )
        .single
        .data!;

    testWidgets('greets the child by name and then settles', (tester) async {
      await pump(tester); // pumpAndSettle: the animation must finish
      expect(shown(tester), contains('Aarav'));
    });

    testWidgets('tapping Panda shows the other line', (tester) async {
      await pump(tester);
      final first = shown(tester);
      await tester.tap(find.byKey(const Key('panda.avatar')));
      await tester.pumpAndSettle();
      expect(shown(tester), isNot(first));
      await tester.tap(find.byKey(const Key('panda.avatar')));
      await tester.pumpAndSettle();
      expect(shown(tester), first);
    });

    testWidgets('does not move when reduced motion is requested', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pump(tester, event: CompanionEvent.missionApproved, settle: false);
      await tester.pump(const Duration(milliseconds: 300));
      final transform = tester.widget<Transform>(
        find
            .descendant(
              of: find.byKey(const Key('panda.avatar')),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(transform.transform.getTranslation().y, 0);
    });

    for (final event in [
      CompanionEvent.missionApproved,
      CompanionEvent.videoUp,
      CompanionEvent.rewardExplain,
    ]) {
      for (final (size, scale, locale) in [
        (const Size(320, 568), 2.0, const Locale('en')),
        (const Size(360, 640), 2.0, const Locale('hi')),
        (const Size(390, 844), 1.3, const Locale('gu')),
        (const Size(740, 360), 1.0, const Locale('gu')),
      ]) {
        testWidgets('no overflow: $event $size @ ${scale}x $locale', (
          tester,
        ) async {
          await pump(
            tester,
            event: event,
            size: size,
            scale: scale,
            locale: locale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
