import 'package:flutter/foundation.dart';

import 'viseme.dart';
import 'viseme_mapper.dart';

/// A word the voice engine reports it has started saying.
@immutable
class SpokenWord {
  const SpokenWord({required this.word, this.start = 0, this.end = 0});

  /// The word's text, as the engine reports it.
  final String word;

  /// Character range of the word in the spoken line.
  final int start;
  final int end;
}

/// Where the mouth timing comes from.
enum LipSyncMode {
  /// Not speaking: the mouth rests.
  idle,

  /// A line is about to be spoken; the audio has not started yet.
  waiting,

  /// **Word boundaries**: every shape is scheduled from a real
  /// "starting word N" signal of the voice engine. This is the accurate mode.
  boundaries,

  /// The audio has started but no word signal has arrived (yet): the line's
  /// mouth shapes are laid out from its text and speaking rate, **anchored to
  /// the real start of the audio and ended by its real completion or stop**.
  /// If the engine sends word signals, the first one switches to
  /// [boundaries]. If it never does, the whole line stays estimated: less
  /// accurate, because it cannot follow pauses or speed changes inside the line.
  estimated,
}

/// Drives Panda's mouth from the speech engine's own callbacks.
///
/// **What the platform gives us.** `flutter_tts` reports, for each word, the
/// moment the engine starts saying it (Android 8+ `onRangeStart`, iOS
/// `willSpeakRange`) plus the start and completion of the whole line. It does
/// **not** give phonemes, audio samples or amplitude. So this is a *viseme
/// approximation*: when a word starts, the mouth shapes spelled by that word
/// (see [visemesForWord]) are spread over the time the word is expected to
/// take, which is learned from the gap between earlier word signals. The next
/// real signal always takes over, so drift cannot accumulate.
///
/// Stopping is immediate and synchronous: [cancel] and [finish] put the mouth
/// at rest before returning, so audio and animation end together.
class LipSyncController {
  LipSyncController({Duration Function()? clock})
    : _clock = clock ?? _stopwatchClock();

  static Duration Function() _stopwatchClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  /// The shortest a mouth shape is held; a fast word drops its weakest shapes.
  static const minShape = Duration(milliseconds: 70);

  /// First guess of how long one letter takes at Panda's speaking rate.
  static const defaultMsPerChar = 70.0;

  final Duration Function() _clock;

  /// The shape the mouth should show right now.
  final ValueNotifier<Viseme> viseme = ValueNotifier(Viseme.rest);

  LipSyncMode _mode = LipSyncMode.idle;
  String _line = '';
  Duration? _audioStart;
  Duration? _lastWordAt;
  int _lastWordLength = 0;
  double _msPerChar = defaultMsPerChar;
  int _wordsHeard = 0;
  bool _disposed = false;
  List<_Cue> _cues = const [];

  LipSyncMode get mode => _mode;

  /// Whether a line is being spoken (audio started or about to).
  bool get isSpeaking => _mode != LipSyncMode.idle;

  /// Word signals received for the current line.
  int get wordsHeard => _wordsHeard;

  /// A line is about to be spoken. The mouth stays at rest until the audio
  /// actually starts ([audioStarted]) or a word signal arrives: without either
  /// there is nothing real to anchor the movement to.
  void begin(String line) {
    if (_disposed) return;
    _reset();
    _line = line;
    _mode = LipSyncMode.waiting;
  }

  /// The engine reports the audio has started.
  void audioStarted() {
    if (_disposed || _mode != LipSyncMode.waiting) return;
    final start = _clock();
    _audioStart = start;
    _layoutEstimate(start); // provisional, until the first real word signal
    update();
  }

  /// The engine reports it is starting [word].
  void wordStarted(SpokenWord word) {
    if (_disposed ||
        (_mode != LipSyncMode.waiting &&
            _mode != LipSyncMode.boundaries &&
            _mode != LipSyncMode.estimated)) {
      return; // a late signal after the line ended moves nothing
    }
    final now = _clock();
    _audioStart ??= now;
    if (_mode != LipSyncMode.boundaries) {
      _mode = LipSyncMode.boundaries;
      _cues = const [];
    }
    final previous = _lastWordAt;
    if (previous != null && _lastWordLength > 0) {
      final gap = (now - previous).inMilliseconds;
      // Learn the speaking rate from real gaps, ignoring pauses and glitches.
      if (gap >= 40 && gap <= 1500) {
        final observed = gap / _lastWordLength;
        _msPerChar = (_msPerChar * 0.5 + observed * 0.5).clamp(25.0, 220.0);
      }
    }
    _lastWordAt = now;
    _lastWordLength = word.word.length;
    _wordsHeard++;
    final shapes = visemesForWord(word.word);
    final span = Duration(
      milliseconds: (word.word.length * _msPerChar).round().clamp(110, 900),
    );
    _cues = _layout([(shapes, span, Duration.zero)], now, trailingRest: true);
    update();
  }

  /// Advances the mouth to the shape due now. Call it on every animation tick.
  void update() {
    if (_disposed) return;
    final now = _clock();
    var shape = Viseme.rest;
    for (final cue in _cues) {
      if (cue.at > now) break;
      shape = cue.viseme;
    }
    _set(shape);
  }

  /// The line ended normally: mouth to rest, now.
  void finish() => _stop();

  /// Speech was stopped, interrupted, failed or never started: mouth to rest,
  /// now. Safe to call at any time, any number of times.
  void cancel() => _stop();

  void _stop() {
    if (_disposed) return;
    _reset();
    _set(Viseme.rest);
  }

  void dispose() {
    if (_disposed) return;
    _reset();
    _disposed = true;
    viseme.dispose();
  }

  void _reset() {
    _mode = LipSyncMode.idle;
    _line = '';
    _audioStart = null;
    _lastWordAt = null;
    _lastWordLength = 0;
    _wordsHeard = 0;
    _msPerChar = defaultMsPerChar;
    _cues = const [];
  }

  void _set(Viseme shape) {
    if (viseme.value != shape) viseme.value = shape;
  }

  /// Lays the whole line out from its text, starting at the audio start.
  void _layoutEstimate(Duration start) {
    _mode = LipSyncMode.estimated;
    final words = <(List<Viseme>, Duration, Duration)>[];
    for (final token in _line.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final letters = token.replaceAll(
        RegExp(r'[^\p{L}\p{M}\p{N}]', unicode: true),
        '',
      );
      if (letters.isEmpty) continue;
      final span = Duration(
        milliseconds: (letters.length * defaultMsPerChar).round().clamp(
          110,
          900,
        ),
      );
      final endsClause = RegExp(r'[.,!?;:।]$').hasMatch(token);
      words.add((
        visemesForWord(letters),
        span,
        Duration(milliseconds: endsClause ? 260 : 40),
      ));
    }
    _cues = _layout(words, start, trailingRest: true);
  }

  /// Schedules each word's shapes one after another from [origin].
  List<_Cue> _layout(
    List<(List<Viseme>, Duration, Duration)> words,
    Duration origin, {
    required bool trailingRest,
  }) {
    final cues = <_Cue>[];
    var t = origin;
    for (final (shapes, span, pause) in words) {
      var use = shapes;
      // Too many shapes for the time: drop the weakest, keeping lip closures.
      while (use.length > 1 &&
          span.inMilliseconds / use.length < minShape.inMilliseconds) {
        final weak = use.indexWhere((v) => v == Viseme.tl || v == Viseme.ee);
        use = [
          for (var i = 0; i < use.length; i++)
            if (i != (weak >= 0 ? weak : use.length - 1)) use[i],
        ];
      }
      if (use.isEmpty) {
        t += span + pause;
        continue;
      }
      final step = span.inMicroseconds / use.length;
      for (var i = 0; i < use.length; i++) {
        cues.add(_Cue(t + Duration(microseconds: (step * i).round()), use[i]));
      }
      // Lips settle just before the next word, so words read as separate (but
      // never before the word's own last shape has had its time).
      final lastShape =
          t + Duration(microseconds: (step * (use.length - 1)).round());
      final settleAt =
          t + Duration(microseconds: (span.inMicroseconds * 0.88).round());
      final afterLast =
          lastShape + Duration(microseconds: (step * 0.7).round());
      cues.add(_Cue(afterLast > settleAt ? afterLast : settleAt, Viseme.rest));
      t += span + pause;
    }
    if (trailingRest) cues.add(_Cue(t, Viseme.rest));
    return cues;
  }
}

@immutable
class _Cue {
  const _Cue(this.at, this.viseme);

  final Duration at;
  final Viseme viseme;
}
