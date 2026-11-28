import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../data/companion_chat_repository.dart';
import '../data/speech_services.dart';
import 'lip_sync.dart';

/// What Panda is doing. Exactly one at a time.
enum PandaPhase {
  idle,
  greeting,
  requestingPermission,
  initializing,
  listening,
  thinking,
  speaking,
  happy,
  curious,
  sleepy,
  error,
}

/// Child-friendly problems Panda can explain.
enum PandaProblem {
  micDenied,
  micPermanentlyDenied,
  micUnavailable,
  listenLanguageMissing,
  notHeard,
  listenTimeout,
  speechFailed,
  network,
  busy,

  /// A parent has not agreed to the microphone (or withdrew it). Typing to
  /// Panda still works.
  voiceNeedsParent,

  /// A parent turned talking to Panda off (applies to every recogniser).
  voiceTurnedOff,

  /// A parent has not approved text chat, or has since revoked it.
  chatNeedsParent,
}

/// Allowed moves. Anything else is ignored, so a late callback can never put
/// Panda in an impossible state (for example speaking while listening).
const pandaTransitions = <PandaPhase, Set<PandaPhase>>{
  PandaPhase.idle: {
    PandaPhase.greeting,
    PandaPhase.requestingPermission,
    PandaPhase.initializing,
    PandaPhase.listening,
    PandaPhase.thinking,
    PandaPhase.error,
  },
  PandaPhase.greeting: {
    PandaPhase.idle,
    PandaPhase.requestingPermission,
    PandaPhase.initializing,
    PandaPhase.listening,
    PandaPhase.thinking,
    PandaPhase.happy,
    PandaPhase.curious,
    PandaPhase.sleepy,
    PandaPhase.error,
  },
  PandaPhase.requestingPermission: {
    PandaPhase.idle,
    PandaPhase.initializing,
    PandaPhase.listening,
    PandaPhase.error,
  },
  PandaPhase.initializing: {
    PandaPhase.idle,
    PandaPhase.listening,
    PandaPhase.error,
  },
  PandaPhase.listening: {
    PandaPhase.idle,
    PandaPhase.thinking,
    PandaPhase.error,
  },
  PandaPhase.thinking: {PandaPhase.idle, PandaPhase.speaking, PandaPhase.error},
  PandaPhase.speaking: {
    PandaPhase.idle,
    PandaPhase.requestingPermission,
    PandaPhase.initializing,
    PandaPhase.listening,
    PandaPhase.thinking,
    PandaPhase.happy,
    PandaPhase.curious,
    PandaPhase.sleepy,
  },
  PandaPhase.happy: {
    PandaPhase.idle,
    PandaPhase.requestingPermission,
    PandaPhase.initializing,
    PandaPhase.listening,
    PandaPhase.thinking,
    PandaPhase.error,
  },
  PandaPhase.curious: {
    PandaPhase.idle,
    PandaPhase.requestingPermission,
    PandaPhase.initializing,
    PandaPhase.listening,
    PandaPhase.thinking,
    PandaPhase.error,
  },
  PandaPhase.sleepy: {
    PandaPhase.idle,
    PandaPhase.requestingPermission,
    PandaPhase.initializing,
    PandaPhase.listening,
    PandaPhase.thinking,
    PandaPhase.error,
  },
  PandaPhase.error: {
    PandaPhase.idle,
    PandaPhase.requestingPermission,
    PandaPhase.initializing,
    PandaPhase.listening,
    PandaPhase.thinking,
  },
};

@immutable
class PandaTalkState {
  const PandaTalkState({
    this.phase = PandaPhase.idle,
    this.mood = PandaReplyMood.talking,
    this.heard = '',
    this.childText = '',
    this.pandaText = '',
    this.suggestions = const [],
    this.problem,
    this.voiceMissing = false,
    this.typing = false,
    this.spokenWords = 0,
    this.voiceAllowed,
    this.onDeviceSpeech,
  });

  final PandaPhase phase;
  final PandaReplyMood mood;

  /// Live words while listening.
  final String heard;

  /// The last thing the child said or typed. Only kept on screen.
  final String childText;
  final String pandaText;
  final List<PandaSuggestion> suggestions;
  final PandaProblem? problem;

  /// The device has no voice for this language: Panda's line is shown only.
  final bool voiceMissing;

  /// Show the text box (chosen, or because speech is not possible).
  final bool typing;

  /// Words the voice engine has started saying in the current line. Each
  /// increment is a real word boundary and moves Panda's mouth once.
  final int spokenWords;

  /// Whether voice may be used, as last checked: null while unknown.
  /// Anything but true keeps the mic closed. True when no parent turned voice
  /// off and either the phone recognises speech on the device (audio never
  /// leaves it) or a parent agreed to the cloud recogniser.
  final bool? voiceAllowed;

  /// The phone has an on-device recogniser, which is then the one used.
  /// Null while unknown.
  final bool? onDeviceSpeech;

  bool get busy =>
      phase == PandaPhase.requestingPermission ||
      phase == PandaPhase.initializing ||
      phase == PandaPhase.listening ||
      phase == PandaPhase.thinking;

  bool get talking =>
      phase == PandaPhase.speaking || phase == PandaPhase.greeting;

  PandaTalkState copyWith({
    PandaPhase? phase,
    PandaReplyMood? mood,
    String? heard,
    String? childText,
    String? pandaText,
    List<PandaSuggestion>? suggestions,
    PandaProblem? problem,
    bool clearProblem = false,
    bool? voiceMissing,
    bool? typing,
    int? spokenWords,
    bool? voiceAllowed,
    bool clearVoiceAllowed = false,
    bool? onDeviceSpeech,
  }) => PandaTalkState(
    phase: phase ?? this.phase,
    mood: mood ?? this.mood,
    heard: heard ?? this.heard,
    childText: childText ?? this.childText,
    pandaText: pandaText ?? this.pandaText,
    suggestions: suggestions ?? this.suggestions,
    problem: clearProblem ? null : (problem ?? this.problem),
    voiceMissing: voiceMissing ?? this.voiceMissing,
    typing: typing ?? this.typing,
    spokenWords: spokenWords ?? this.spokenWords,
    voiceAllowed: clearVoiceAllowed
        ? null
        : (voiceAllowed ?? this.voiceAllowed),
    onDeviceSpeech: onDeviceSpeech ?? this.onDeviceSpeech,
  );
}

/// Runs one conversation with Panda: listen → think → speak → rest.
///
/// * Only one turn is ever in flight. Every async step carries an epoch; any
///   stop, interrupt or new turn bumps it, so late results are dropped and
///   audio never overlaps.
/// * Every waiting state has a watchdog, so Panda cannot get stuck.
/// * The microphone is used only between a tap and the end of that phrase.
class PandaTalkController extends Notifier<PandaTalkState> {
  static const listenWatchdog = Duration(seconds: 14);
  static const thinkWatchdog = Duration(seconds: 12);
  static const happyRest = Duration(milliseconds: 2500);

  late SpeechInput _input;
  late SpeechOutput _output;
  late CompanionChatRepository _chat;

  /// Panda's mouth. It follows the voice engine's own callbacks and is put at
  /// rest the moment speech stops, for any reason, so audio and animation end
  /// together.
  late final LipSyncController lipSync;

  int _epoch = 0;
  Timer? _watchdog;
  Timer? _rest;
  String _language = 'en';
  String? _followUp;
  bool _speechPrepared = false;
  bool _permanentlyDenied = false;

  /// Whether microphone permission was permanently denied in this session.
  bool get isMicPermanentlyDenied => _permanentlyDenied;

  @override
  PandaTalkState build() {
    _input = ref.watch(speechInputProvider);
    _output = ref.watch(speechOutputProvider);
    _chat = ref.watch(companionChatRepositoryProvider);
    lipSync = LipSyncController();
    ref.onDispose(() {
      _epoch++;
      _watchdog?.cancel();
      _rest?.cancel();
      lipSync.dispose();
      unawaited(_input.cancel().catchError((_) {}));
      unawaited(_output.stop());
    });
    return const PandaTalkState();
  }

  /// The app language. Replies, voice and recognition all follow it.
  void setLanguage(String code) =>
      _language = const {'en', 'hi', 'gu'}.contains(code) ? code : 'en';

  bool _go(PandaPhase next) {
    final from = state.phase;
    if (from == next) return true;
    if (!(pandaTransitions[from]?.contains(next) ?? false)) {
      debugPrint('Panda: ignored $from -> $next');
      return false;
    }
    state = state.copyWith(phase: next);
    return true;
  }

  void _arm(Duration after, int epoch, void Function() onTimeout) {
    _watchdog?.cancel();
    _watchdog = Timer(after, () {
      if (epoch == _epoch) onTimeout();
    });
  }

  /// Says the opening line (authored on the device, chosen from real state).
  Future<void> greet(
    String line, {
    PandaReplyMood mood = PandaReplyMood.happy,
  }) async {
    if (state.phase != PandaPhase.idle) return;
    final epoch = ++_epoch;
    state = state.copyWith(pandaText: line, mood: mood);
    _go(PandaPhase.greeting);
    await _say(line, mood, epoch);
  }

  /// Asks the phone which recogniser it has and the server what the parent
  /// decided. Voice is allowed unless a parent turned it off, when either the
  /// recogniser is on-device (no audio leaves the phone, so no grown-up step)
  /// or a parent agreed to the cloud recogniser. Throws [ApiException].
  Future<PandaVoiceConsent> _evaluateVoice() async {
    final onDevice = await _input.onDeviceAvailable();
    final consent = await _chat.voiceConsentStatus();
    state = state.copyWith(
      onDeviceSpeech: onDevice,
      voiceAllowed: !consent.refused && (onDevice || consent.granted),
    );
    return consent;
  }

  /// Updates [PandaTalkState.voiceAllowed] quietly (panel opened, app
  /// resumed): no message, never touches the microphone.
  Future<void> refreshVoiceConsent() async {
    try {
      await _evaluateVoice();
    } on ApiException {
      // Unknown stays unknown; the mic tap checks again.
    }
  }

  /// Checks, right before the microphone could open, that voice is allowed
  /// ([_evaluateVoice]). False (with a message, typing shown) when not, or
  /// when the server cannot be asked: the microphone stays closed either way.
  Future<bool> checkVoiceConsent() async {
    if (state.busy) return false;
    final PandaVoiceConsent consent;
    try {
      consent = await _evaluateVoice();
    } on ApiException {
      _fail(PandaProblem.network, typing: true);
      return false;
    }
    final allowed = state.voiceAllowed == true;
    if (!allowed) {
      _fail(
        consent.refused
            ? PandaProblem.voiceTurnedOff
            : PandaProblem.voiceNeedsParent,
        typing: true,
      );
    }
    return allowed;
  }

  /// The child tapped the mic (or Panda). Interrupts Panda if talking.
  /// Voice must be allowed ([checkVoiceConsent]): always re-checked from the
  /// authoritative server source for cloud speech, and checked if unknown or
  /// changed for on-device speech.
  Future<void> startListening() async {
    if (state.busy) return; // a turn is already in flight
    if (_permanentlyDenied) {
      _fail(PandaProblem.micPermanentlyDenied, typing: true);
      return;
    }
    _rest?.cancel();
    lipSync.cancel(); // the mouth stops with the voice, before anything awaits
    // Always check whether on-device speech is still available. If it is not,
    // we must never quietly fall back to the cloud recogniser without consent.
    final onDeviceNow = await _input.onDeviceAvailable();
    if (onDeviceNow != state.onDeviceSpeech) {
      state = state.copyWith(clearVoiceAllowed: true, onDeviceSpeech: onDeviceNow);
    }
    // For cloud speech, always verify active parent consent from the server so
    // a recent withdrawal is respected immediately.
    if (!onDeviceNow || state.voiceAllowed != true) {
      if (!await checkVoiceConsent()) return;
    }
    final onDevice = state.onDeviceSpeech == true;
    final epoch = ++_epoch;
    if (state.talking) await _output.stop();
    if (epoch != _epoch) return;

    if (!_speechPrepared) {
      final hasPerm = await _input.hasPermission();
      if (epoch != _epoch) return;
      if (!_go(
        hasPerm
            ? PandaPhase.initializing
            : PandaPhase.requestingPermission,
      )) {
        return;
      }
      final availability = await _input.prepare();
      if (epoch != _epoch) return;
      if (availability != SpeechAvailability.ready) {
        _speechPrepared = false;
        if (availability == SpeechAvailability.permanentlyDenied) {
          _permanentlyDenied = true;
          _fail(PandaProblem.micPermanentlyDenied, typing: true);
        } else {
          _fail(
            availability == SpeechAvailability.denied
                ? PandaProblem.micDenied
                : PandaProblem.micUnavailable,
            typing: true,
          );
        }
        return;
      }
      _speechPrepared = true;
    } else if (!_go(PandaPhase.initializing)) {
      return;
    }

    final localeId = await _input.localeFor(_language);
    if (epoch != _epoch) return;
    if (localeId == null) {
      _fail(PandaProblem.listenLanguageMissing, typing: true);
      return;
    }

    if (!_go(PandaPhase.listening)) return;
    state = state.copyWith(heard: '', clearProblem: true, spokenWords: 0);
    _arm(listenWatchdog, epoch, () {
      unawaited(_input.cancel().catchError((_) {}));
      _fail(PandaProblem.listenTimeout, typing: true);
    });
    await _input.listen(
      localeId: localeId,
      onPartial: (words) {
        if (epoch == _epoch && state.phase == PandaPhase.listening) {
          state = state.copyWith(heard: words);
        }
      },
      onFinal: (words) {
        if (epoch == _epoch && state.phase == PandaPhase.listening) {
          unawaited(_respond(words, epoch, voice: true, onDevice: onDevice));
        }
      },
      onError: (error) {
        if (epoch != _epoch || state.phase != PandaPhase.listening) return;
        switch (error) {
          case SpeechInputError.denied:
            _speechPrepared = false;
            _fail(PandaProblem.micDenied, typing: true);
          case SpeechInputError.permanentlyDenied:
            _speechPrepared = false;
            _permanentlyDenied = true;
            _fail(PandaProblem.micPermanentlyDenied, typing: true);
          case SpeechInputError.engineUnavailable:
            _speechPrepared = false;
            _fail(PandaProblem.micUnavailable, typing: true);
          case SpeechInputError.unsupportedLanguage:
            _fail(PandaProblem.listenLanguageMissing, typing: true);
          case SpeechInputError.timeout:
            _fail(PandaProblem.listenTimeout, typing: true);
          case SpeechInputError.network:
            _fail(PandaProblem.network, typing: true);
          case SpeechInputError.notHeard:
            _fail(PandaProblem.notHeard);
          case SpeechInputError.failed:
            _speechPrepared = false;
            _fail(PandaProblem.speechFailed, typing: true);
        }
      },
      // Never retried through the cloud recogniser if this fails: the child
      // is offered typing instead.
      onDevice: onDevice,
    );
  }

  /// The child finished talking early: keep what was heard.
  Future<void> finishListening() async {
    if (state.phase == PandaPhase.listening) await _input.stop();
  }

  /// Typed text or a suggestion chip.
  Future<void> send(String text) async {
    if (state.busy) return; // no duplicate turns
    final epoch = ++_epoch;
    _rest?.cancel();
    lipSync.cancel();
    if (state.talking) await _output.stop();
    if (epoch != _epoch) return;
    await _respond(text, epoch);
  }

  Future<void> _respond(
    String raw,
    int epoch, {
    bool voice = false,
    bool onDevice = false,
  }) async {
    final text = raw.trim();
    if (text.isEmpty) {
      _fail(PandaProblem.notHeard);
      return;
    }
    if (!_go(PandaPhase.thinking)) return;
    state = state.copyWith(childText: text, heard: '', clearProblem: true);
    _arm(thinkWatchdog, epoch, () => _fail(PandaProblem.network));
    try {
      final reply = await _chat.chat(
        text: text,
        locale: _language,
        turnId: newTurnId(),
        contextIntent: _followUp,
        voice: voice,
        onDevice: onDevice,
      );
      if (epoch != _epoch || state.phase != PandaPhase.thinking) return;
      _watchdog?.cancel();
      _followUp = reply.followUp;
      state = state.copyWith(
        pandaText: reply.text,
        mood: reply.mood,
        suggestions: reply.suggestions,
      );
      _go(PandaPhase.speaking);
      await _say(reply.text, reply.mood, epoch);
    } on ApiException catch (error) {
      if (epoch != _epoch) return;
      if (error.code == kPandaVoiceConsentRequired) {
        // Consent was withdrawn: no more listening or speaking this turn.
        state = state.copyWith(voiceAllowed: false);
        lipSync.cancel();
        await _input.cancel().catchError((_) {});
        await _output.stop();
        _fail(PandaProblem.voiceNeedsParent, typing: true);
        return;
      }
      if (error.code == kPandaChatAccessRequired) {
        _fail(PandaProblem.chatNeedsParent);
        return;
      }
      _fail(error.statusCode == 429 ? PandaProblem.busy : PandaProblem.network);
    }
  }

  Future<void> _say(String text, PandaReplyMood mood, int epoch) async {
    state = state.copyWith(spokenWords: 0);
    // Longest a line may take before Panda is considered stuck.
    final limit = Duration(
      milliseconds: (4000 + text.length * 120).clamp(4000, 30000),
    );
    _arm(limit, epoch, () {
      lipSync.cancel();
      unawaited(_output.stop());
    });
    lipSync.begin(text);
    final outcome = await _output.speak(
      text,
      languageCode: _language,
      onStart: () {
        if (epoch == _epoch && state.talking) lipSync.audioStarted();
      },
      onWord: (word) {
        if (epoch == _epoch && state.talking) {
          lipSync.wordStarted(word);
          state = state.copyWith(spokenWords: state.spokenWords + 1);
        }
      },
    );
    if (epoch != _epoch) return; // stop() already ended the mouth
    // Only a line that really played to the end closes the mouth gently; a
    // failed, unsupported or interrupted line never moved it (or stops it now).
    outcome == SpeakOutcome.completed ? lipSync.finish() : lipSync.cancel();
    _watchdog?.cancel();
    state = state.copyWith(voiceMissing: outcome == SpeakOutcome.unsupported);
    _restAfter(mood, epoch);
  }

  void _restAfter(PandaReplyMood mood, int epoch) {
    final next = switch (mood) {
      PandaReplyMood.happy => PandaPhase.happy,
      PandaReplyMood.curious => PandaPhase.curious,
      PandaReplyMood.sleepy => PandaPhase.sleepy,
      PandaReplyMood.talking || PandaReplyMood.concerned => PandaPhase.idle,
    };
    _go(next);
    if (next == PandaPhase.happy) {
      _rest?.cancel();
      _rest = Timer(happyRest, () {
        if (epoch == _epoch && state.phase == PandaPhase.happy) {
          _go(PandaPhase.idle);
        }
      });
    }
  }

  void _fail(PandaProblem problem, {bool typing = false}) {
    _watchdog?.cancel();
    lipSync.cancel();
    if (state.phase == PandaPhase.speaking) _go(PandaPhase.idle);
    _go(PandaPhase.error);
    state = state.copyWith(
      problem: problem,
      heard: '',
      typing: typing || state.typing,
    );
  }

  /// Shows or hides the text box.
  void toggleTyping() => state = state.copyWith(typing: !state.typing);

  /// Stops everything at once (Stop button, closing the panel, app paused).
  Future<void> stop() async {
    _epoch++;
    lipSync
        .cancel(); // synchronous: the mouth stops before the voice call returns
    _watchdog?.cancel();
    _rest?.cancel();
    await _input.cancel().catchError((_) {});
    await _output.stop();
    state = state.copyWith(phase: PandaPhase.idle, heard: '', spokenWords: 0);
  }
}

/// One conversation per open panel: closing it disposes the controller,
/// which cancels listening and silences Panda.
final pandaTalkControllerProvider =
    NotifierProvider.autoDispose<PandaTalkController, PandaTalkState>(
      PandaTalkController.new,
    );
