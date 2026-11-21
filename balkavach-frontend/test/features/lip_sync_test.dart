// Viseme mapping and the audio-driven lip-sync timeline.
//
// Unit tests with a fake clock: no audio, no device. They prove the *logic* that follows the speech
// engine's callbacks; whether a real engine sends those callbacks is a device question
// (see docs/panda-talking-companion.md).
import 'package:balkavach_app/features/companion/domain/lip_sync.dart';
import 'package:balkavach_app/features/companion/domain/viseme.dart';
import 'package:balkavach_app/features/companion/domain/viseme_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

class _Clock {
  Duration now = Duration.zero;
  Duration call() => now;
  void advance(int ms) => now += Duration(milliseconds: ms);
}

SpokenWord _word(String w) => SpokenWord(word: w);

void main() {
  group('visemesForWord', () {
    test('English letters give the shapes of their sounds', () {
      expect(visemesForWord('mama'), [
        Viseme.mbp,
        Viseme.ah,
        Viseme.mbp,
        Viseme.ah,
      ]);
      expect(visemesForWord('hello'), [
        Viseme.tl,
        Viseme.ee,
        Viseme.tl,
        Viseme.oh,
      ]);
      expect(visemesForWord('five'), [Viseme.fv, Viseme.ee, Viseme.fv]);
      expect(visemesForWord('moon'), [Viseme.mbp, Viseme.oo, Viseme.tl]);
      expect(visemesForWord('the'), [Viseme.tl, Viseme.ee]);
    });

    test('a silent final e makes no shape; case does not matter', () {
      expect(visemesForWord('Joke'), visemesForWord('joke'));
      expect(visemesForWord('joke').last, Viseme.tl);
      expect(visemesForWord('make'), [Viseme.mbp, Viseme.ah, Viseme.tl]);
    });

    test('lip closures survive in words that contain them', () {
      for (final w in ['bubble', 'happy', 'mission', 'panda', 'baby']) {
        expect(visemesForWord(w), contains(Viseme.mbp), reason: w);
      }
    });

    test('Hindi: vowels, matras and the inherent a', () {
      expect(visemesForWord('मामा'), [
        Viseme.mbp,
        Viseme.ah,
        Viseme.mbp,
        Viseme.ah,
      ]);
      expect(visemesForWord('पानी'), [
        Viseme.mbp,
        Viseme.ah,
        Viseme.tl,
        Viseme.ee,
      ]);
      expect(visemesForWord('नमस्ते'), contains(Viseme.mbp));
      expect(visemesForWord('ओम'), [Viseme.oh, Viseme.mbp]);
    });

    test('Gujarati uses the same sound classes as Hindi', () {
      expect(visemesForWord('મામા'), visemesForWord('मामा'));
      final pani = visemesForWord('પાણી');
      expect(pani.first, Viseme.mbp);
      expect(pani[1], Viseme.ah);
      expect(visemesForWord('વા'), [Viseme.fv, Viseme.ah]);
    });

    test('digits make a vowel-like shape; punctuation makes none', () {
      expect(visemesForWord('3'), [Viseme.ah]);
      expect(visemesForWord('!?'), isEmpty);
      expect(visemesForWord(''), isEmpty);
    });

    test('never two equal shapes in a row', () {
      for (final w in ['mmm', 'oooh', 'aaaa', 'Mississippi', 'ખુશ', 'खुशी']) {
        final shapes = visemesForWord(w);
        for (var i = 1; i < shapes.length; i++) {
          expect(shapes[i], isNot(shapes[i - 1]), reason: w);
        }
      }
    });
  });

  group('LipSyncController: word boundaries', () {
    late _Clock clock;
    late LipSyncController sync;
    setUp(() {
      clock = _Clock();
      sync = LipSyncController(clock: clock.call);
    });
    tearDown(() => sync.dispose());

    test('the mouth rests until the engine says something', () {
      sync.begin('Hello there');
      expect(sync.mode, LipSyncMode.waiting);
      sync.update();
      expect(sync.viseme.value, Viseme.rest);
      clock.advance(300);
      sync.update();
      expect(sync.viseme.value, Viseme.rest, reason: 'no audio started yet');
    });

    test("each word signal starts that word's shapes at that moment", () {
      sync.begin('mama go');
      sync.audioStarted();
      sync.wordStarted(_word('mama'));
      expect(sync.mode, LipSyncMode.boundaries);
      sync.update();
      expect(sync.viseme.value, Viseme.mbp, reason: 'first shape of "mama"');

      // "mama" has 4 letters: 280 ms at the default rate, 70 ms per shape.
      clock.advance(80);
      sync.update();
      expect(sync.viseme.value, Viseme.ah);

      clock.advance(400);
      sync.wordStarted(_word('go'));
      sync.update();
      expect(sync.viseme.value, Viseme.tl, reason: 'g');
      clock.advance(120);
      sync.update();
      expect(sync.viseme.value, Viseme.oh, reason: 'o');
      expect(sync.wordsHeard, 2);
    });

    test('a signal takes over from whatever was scheduled before it', () {
      sync.begin('mama ba');
      sync.audioStarted();
      sync.wordStarted(_word('mama'));
      clock.advance(10); // still inside the first word
      sync.wordStarted(_word('ba'));
      sync.update();
      expect(sync.viseme.value, Viseme.mbp);
      clock.advance(80);
      sync.update();
      expect(sync.viseme.value, Viseme.ah, reason: 'the "a" of "ba"');
    });

    test('the mouth closes between words if the next signal is late', () {
      sync.begin('ba ba');
      sync.audioStarted();
      sync.wordStarted(_word('ba'));
      clock.advance(2000);
      sync.update();
      expect(sync.viseme.value, Viseme.rest);
    });

    test('speaking rate is learned from the gaps between signals', () {
      // Slow speech: 4-letter words 600 ms apart (150 ms per letter).
      final slow = LipSyncController(clock: clock.call)..begin('x');
      slow.audioStarted();
      for (var i = 0; i < 5; i++) {
        slow.wordStarted(_word('mama'));
        clock.advance(600);
      }
      slow.wordStarted(_word('mama'));
      clock.advance(
        300,
      ); // 300 ms into a word the slow speaker takes ~600 ms for
      slow.update();
      final slowShape = slow.viseme.value;
      slow.dispose();

      // Fast speech: the same word 150 ms apart.
      final fast = LipSyncController(clock: clock.call)..begin('x');
      fast.audioStarted();
      for (var i = 0; i < 5; i++) {
        fast.wordStarted(_word('mama'));
        clock.advance(150);
      }
      fast.wordStarted(_word('mama'));
      clock.advance(300); // long after a fast speaker's word is over
      fast.update();
      final fastShape = fast.viseme.value;
      fast.dispose();

      expect(fastShape, Viseme.rest, reason: 'the fast word is already over');
      expect(slowShape, isNot(Viseme.rest), reason: 'the slow word goes on');
    });
  });

  group('LipSyncController: engines without word signals', () {
    test('the line is laid out from its text, anchored to the real audio '
        'start, and the mode says so', () {
      final clock = _Clock();
      final sync = LipSyncController(clock: clock.call)
        ..begin('Mama, go home.');
      clock.advance(500); // audio starts half a second after begin()
      sync.audioStarted();
      expect(sync.mode, LipSyncMode.estimated);
      expect(sync.viseme.value, Viseme.mbp, reason: 'first shape of "Mama"');
      final seen = <Viseme>{};
      for (var i = 0; i < 60; i++) {
        sync.update();
        seen.add(sync.viseme.value);
        clock.advance(40);
      }
      expect(seen, containsAll([Viseme.mbp, Viseme.ah, Viseme.rest]));
      expect(sync.mode, LipSyncMode.estimated, reason: 'no word signal came');
      sync.dispose();
    });

    test('the mouth is still before the audio starts', () {
      final clock = _Clock();
      final sync = LipSyncController(clock: clock.call)..begin('Mama');
      clock.advance(700);
      sync.update();
      expect(sync.viseme.value, Viseme.rest);
      expect(sync.mode, LipSyncMode.waiting);
      sync.dispose();
    });

    test('a real word signal replaces the estimate', () {
      final clock = _Clock();
      final sync = LipSyncController(clock: clock.call)..begin('ba ba ba');
      sync.audioStarted();
      expect(sync.mode, LipSyncMode.estimated);
      clock.advance(100);
      sync.wordStarted(_word('ba'));
      expect(sync.mode, LipSyncMode.boundaries);
      sync.dispose();
    });

    test('the estimate ends with the line: finish closes it at once', () {
      final clock = _Clock();
      final sync = LipSyncController(clock: clock.call)..begin('Mama mama');
      sync.audioStarted();
      clock.advance(100);
      sync.update();
      expect(sync.viseme.value, isNot(Viseme.rest));
      sync.finish();
      expect(sync.viseme.value, Viseme.rest);
      sync.dispose();
    });
  });

  group('LipSyncController: stopping', () {
    test('cancel closes the mouth at once and ignores late signals', () {
      final clock = _Clock();
      final sync = LipSyncController(clock: clock.call)..begin('ma ma');
      sync.audioStarted();
      sync.wordStarted(_word('ma'));
      sync.update();
      expect(sync.viseme.value, Viseme.mbp);

      sync.cancel();
      expect(sync.viseme.value, Viseme.rest);
      expect(sync.isSpeaking, isFalse);
      expect(sync.mode, LipSyncMode.idle);

      sync.wordStarted(_word('ma')); // a late callback from the stopped line
      sync.update();
      expect(sync.viseme.value, Viseme.rest);
      expect(sync.wordsHeard, 0);
      sync.dispose();
    });

    test('finish closes the mouth at once', () {
      final clock = _Clock();
      final sync = LipSyncController(clock: clock.call)..begin('ma');
      sync.audioStarted();
      sync.wordStarted(_word('ma'));
      sync.update();
      sync.finish();
      expect(sync.viseme.value, Viseme.rest);
      expect(sync.isSpeaking, isFalse);
      sync.dispose();
    });

    test('cancel is idempotent and safe after dispose', () {
      final sync = LipSyncController()..begin('x');
      sync.cancel();
      sync.cancel();
      sync.dispose();
      sync.cancel();
      sync.wordStarted(_word('a'));
      sync.update();
      expect(sync.isSpeaking, isFalse);
    });

    test('a new line starts clean after an interrupted one', () {
      final clock = _Clock();
      final sync = LipSyncController(clock: clock.call)..begin('one');
      sync.audioStarted();
      sync.wordStarted(_word('one'));
      sync.cancel();
      sync.begin('ma');
      expect(sync.wordsHeard, 0);
      sync.audioStarted();
      sync.wordStarted(_word('ma'));
      sync.update();
      expect(sync.viseme.value, Viseme.mbp);
      sync.dispose();
    });
  });
}
