import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../domain/lip_sync.dart' show SpokenWord;

/// Whether the device can listen right now.
enum SpeechAvailability { ready, denied, unavailable }

/// Why a listen ended without words.
enum SpeechInputError { notHeard, denied, failed }

/// Tap-to-talk speech recognition. One listen at a time, never in the
/// background, and no audio is kept by the app: only the recognised words
/// come back.
abstract class SpeechInput {
  /// Initialises the recogniser. On the first call the system asks the child
  /// (or parent) for microphone permission.
  Future<SpeechAvailability> prepare();

  /// Whether microphone permission was already granted (no prompt shown).
  Future<bool> hasPermission();

  /// Whether the phone has an on-device (offline) recogniser, so audio never
  /// leaves the device. False when unknown: the stricter cloud rules apply.
  Future<bool> onDeviceAvailable();

  /// The best recogniser locale for [languageCode] (`en`, `hi`, `gu`), or
  /// `null` when the device cannot recognise that language.
  Future<String?> localeFor(String languageCode);

  /// Listens once. Exactly one of [onFinal] or [onError] is called.
  ///
  /// [onDevice] asks for the on-device recogniser. Only pass true after
  /// [onDeviceAvailable] said so: the plugin would otherwise fall back to the
  /// cloud recogniser without telling anyone.
  Future<void> listen({
    required String localeId,
    required void Function(String words) onPartial,
    required void Function(String words) onFinal,
    required void Function(SpeechInputError error) onError,
    bool onDevice = false,
  });

  /// Ends listening and keeps what was heard so far.
  Future<void> stop();

  /// Ends listening and discards everything.
  Future<void> cancel();
}

/// How one spoken line ended.
enum SpeakOutcome { completed, interrupted, unsupported, failed }

/// Panda's voice (platform text-to-speech).
abstract class SpeechOutput {
  /// Speaks [text]. Completes when speech ends for any reason.
  ///
  /// [onStart] fires when the engine reports the audio has started, and
  /// [onWord] each time it reports starting a word (with the word's text).
  /// Together they drive Panda's mouth. The platform engines give word
  /// boundaries only: no phonemes and no audio levels. Some engines send no
  /// word callbacks at all; then only [onStart] and completion are real.
  Future<SpeakOutcome> speak(
    String text, {
    required String languageCode,
    void Function()? onStart,
    void Function(SpokenWord word)? onWord,
  });

  Future<void> stop();
}

/// Preferred platform locales, most local first.
const _ttsLocales = {
  'en': ['en-IN', 'en-GB', 'en-US'],
  'hi': ['hi-IN'],
  'gu': ['gu-IN'],
};

class PlatformSpeechInput implements SpeechInput {
  PlatformSpeechInput([SpeechToText? stt]) : _stt = stt ?? SpeechToText();

  final SpeechToText _stt;
  bool _ready = false;
  void Function(String)? _onFinal;
  void Function(SpeechInputError)? _onError;
  String _lastWords = '';

  void _finish({String? words, SpeechInputError? error}) {
    final onFinal = _onFinal;
    final onError = _onError;
    _onFinal = null;
    _onError = null;
    if (words != null && words.trim().isNotEmpty) {
      onFinal?.call(words);
    } else if (onFinal != null || onError != null) {
      onError?.call(error ?? SpeechInputError.notHeard);
    }
  }

  void _status(String status) {
    if (status == SpeechToText.doneStatus) {
      // Ended without a final result: use what was heard, if anything.
      _finish(words: _lastWords);
    }
  }

  void _error(SpeechRecognitionError error) {
    final msg = error.errorMsg;
    final kind = switch (msg) {
      'error_no_match' || 'error_speech_timeout' => SpeechInputError.notHeard,
      'error_permission' ||
      'error_insufficient_permissions' => SpeechInputError.denied,
      _ => SpeechInputError.failed,
    };
    if (error.permanent || kind != SpeechInputError.failed) {
      _finish(error: kind);
    }
  }

  @override
  Future<SpeechAvailability> prepare() async {
    try {
      _ready = await _stt.initialize(onStatus: _status, onError: _error);
    } catch (error) {
      debugPrint('Panda: speech init failed (${error.runtimeType})');
      _ready = false;
    }
    if (_ready) return SpeechAvailability.ready;
    final permitted = await _stt.hasPermission.catchError((_) => false);
    return permitted
        ? SpeechAvailability.unavailable
        : SpeechAvailability.denied;
  }

  @override
  Future<bool> hasPermission() => _stt.hasPermission.catchError((_) => false);

  static const _channel = MethodChannel('balkavach/speech');

  @override
  Future<bool> onDeviceAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('onDeviceAvailable') ?? false;
    } on Object {
      return false; // unknown: treat as cloud, which needs a parent's consent
    }
  }

  @override
  Future<String?> localeFor(String languageCode) async {
    final locales = await _stt.locales().catchError((_) => <LocaleName>[]);
    String norm(String id) => id.replaceAll('-', '_').toLowerCase();
    final ids = [for (final l in locales) norm(l.localeId)];
    for (final wanted in _ttsLocales[languageCode] ?? const <String>[]) {
      final i = ids.indexOf(norm(wanted));
      if (i >= 0) return locales[i].localeId;
    }
    final i = ids.indexWhere((id) => id.startsWith('${languageCode}_'));
    return i >= 0 ? locales[i].localeId : null;
  }

  @override
  Future<void> listen({
    required String localeId,
    required void Function(String words) onPartial,
    required void Function(String words) onFinal,
    required void Function(SpeechInputError error) onError,
    bool onDevice = false,
  }) async {
    _onFinal = onFinal;
    _onError = onError;
    _lastWords = '';
    try {
      await _stt.listen(
        onResult: (SpeechRecognitionResult result) {
          _lastWords = result.recognizedWords;
          if (result.finalResult) {
            _finish(words: result.recognizedWords);
          } else {
            onPartial(result.recognizedWords);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(seconds: 10),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.confirmation,
          onDevice: onDevice,
        ),
      );
    } catch (error) {
      debugPrint('Panda: listen failed (${error.runtimeType})');
      _finish(error: SpeechInputError.failed);
    }
  }

  @override
  Future<void> stop() => _stt.stop();

  @override
  Future<void> cancel() async {
    _onFinal = null;
    _onError = null;
    await _stt.cancel();
  }
}

class PlatformSpeechOutput implements SpeechOutput {
  PlatformSpeechOutput([FlutterTts? tts]) : _tts = tts ?? FlutterTts() {
    _tts
      ..setCompletionHandler(() => _end(SpeakOutcome.completed))
      ..setCancelHandler(() => _end(SpeakOutcome.interrupted))
      ..setErrorHandler((_) => _end(SpeakOutcome.failed))
      ..setStartHandler(() => _onStart?.call())
      ..setProgressHandler(
        (text, start, end, word) =>
            _onWord?.call(SpokenWord(word: word, start: start, end: end)),
      );
  }

  final FlutterTts _tts;
  final _languageReady = <String, String?>{};
  Completer<SpeakOutcome>? _current;
  void Function()? _onStart;
  void Function(SpokenWord word)? _onWord;

  void _end(SpeakOutcome outcome) {
    _onStart = null;
    _onWord = null;
    final c = _current;
    _current = null;
    if (c != null && !c.isCompleted) c.complete(outcome);
  }

  Future<String?> _language(String code) async {
    if (_languageReady.containsKey(code)) return _languageReady[code];
    String? found;
    for (final locale in _ttsLocales[code] ?? const <String>[]) {
      try {
        if (await _tts.isLanguageAvailable(locale) == true) {
          found = locale;
          break;
        }
      } catch (_) {}
    }
    return _languageReady[code] = found;
  }

  @override
  Future<SpeakOutcome> speak(
    String text, {
    required String languageCode,
    void Function()? onStart,
    void Function(SpokenWord word)? onWord,
  }) async {
    await stop();
    final locale = await _language(languageCode);
    if (locale == null) return SpeakOutcome.unsupported;
    final completer = _current = Completer<SpeakOutcome>();
    _onStart = onStart;
    _onWord = onWord;
    try {
      await _tts.setLanguage(locale);
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.15);
      final started = await _tts.speak(text);
      if (started != 1) _end(SpeakOutcome.failed);
    } catch (error) {
      debugPrint('Panda: speak failed (${error.runtimeType})');
      _end(SpeakOutcome.failed);
    }
    return completer.future;
  }

  @override
  Future<void> stop() async {
    _end(SpeakOutcome.interrupted);
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

final speechInputProvider = Provider<SpeechInput>(
  (ref) => PlatformSpeechInput(),
);

final speechOutputProvider = Provider<SpeechOutput>((ref) {
  final output = PlatformSpeechOutput();
  ref.onDispose(output.stop);
  return output;
});
