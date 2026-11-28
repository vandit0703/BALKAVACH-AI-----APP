import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/app_assets.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../learning/data/video_feed_repository.dart';
import '../data/companion_chat_repository.dart';
import '../data/panda_chat_access_repository.dart';
import '../data/speech_services.dart';
import '../domain/companion_director.dart';
import '../domain/panda_interaction.dart';
import 'panda_character.dart';

/// Small Panda button for the child app bar. Opens the talk panel; takes no
/// room on the screens themselves.
class PandaTalkButton extends StatelessWidget {
  const PandaTalkButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Tooltip(
      message: l10n.pandaTalkOpen,
      child: Semantics(
        button: true,
        label: l10n.pandaTalkOpen,
        child: InkResponse(
          key: const Key('panda.talk.open'),
          radius: 28,
          onTap: () => showPandaTalk(context),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.primaryContainer,
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      AppImages.pandaHoodie,
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.mic_rounded,
                      size: 12,
                      color: colors.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens Panda's talk panel. Closing it stops listening and speaking.
Future<void> showPandaTalk(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => const PandaTalkSheet(),
);

/// Permission explanation is shown once per app run before the system prompt.
bool _micExplainedThisRun = false;

@visibleForTesting
void resetPandaMicExplanation() => _micExplainedThisRun = false;

class PandaTalkSheet extends ConsumerStatefulWidget {
  const PandaTalkSheet({super.key});

  @override
  ConsumerState<PandaTalkSheet> createState() => _PandaTalkSheetState();
}

class _PandaTalkSheetState extends ConsumerState<PandaTalkSheet>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  bool _greeted = false;
  PandaChatAccessStatus? _chatAccess;
  bool _chatAccessLoading = true;
  bool _requestingChatAccess = false;
  bool _chatAccessFailed = false;

  PandaTalkController get _controller =>
      ref.read(pandaTalkControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.setLanguage(Localizations.localeOf(context).languageCode);
    if (!_greeted) {
      _greeted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_greet());
        // Greys the mic when no parent has agreed; typing always works.
        unawaited(_controller.refreshVoiceConsent());
        unawaited(_refreshChatAccess());
      });
    }
  }

  /// The opening line, authored on the device and picked from real state:
  /// sleepy when video time is over, otherwise a hello by name.
  Future<void> _greet() async {
    VideoAllowance? allowance;
    try {
      allowance = await ref
          .read(videoAllowanceProvider.future)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      allowance = null; // unknown: a plain hello, never a guess
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final fullName = ref.read(sessionControllerProvider).value?.user.fullName;
    final name = (fullName ?? '').trim().split(RegExp(r'\s+')).first;
    final event = allowance?.isExhausted == true
        ? CompanionEvent.videoUp
        : name.isNotEmpty
        ? CompanionEvent.greetingNamed
        : CompanionEvent.greeting;
    final director = ref.read(companionDirectorProvider);
    final variant = director.next(event) ?? director.current(event);
    await _controller.greet(
      pandaLine(l10n, event, variant, name: name),
      mood: event == CompanionEvent.videoUp
          ? PandaReplyMood.sleepy
          : PandaReplyMood.happy,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never listen or talk in the background.
    if (state != AppLifecycleState.resumed) {
      unawaited(_controller.stop());
    } else {
      // A parent may have changed the microphone consent meanwhile.
      unawaited(_controller.refreshVoiceConsent());
      unawaited(_refreshChatAccess());
    }
  }

  Future<void> _refreshChatAccess() async {
    try {
      final status = await ref
          .read(pandaChatAccessRepositoryProvider)
          .childStatus();
      if (!mounted) return;
      setState(() {
        _chatAccess = status;
        _chatAccessFailed = false;
        _chatAccessLoading = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _chatAccessFailed = true;
        _chatAccessLoading = false;
      });
    }
  }

  Future<void> _requestChatAccess() async {
    setState(() => _requestingChatAccess = true);
    try {
      final status = await ref
          .read(pandaChatAccessRepositoryProvider)
          .requestAccess();
      if (!mounted) return;
      setState(() {
        _chatAccess = status;
        _chatAccessFailed = false;
      });
    } on ApiException {
      if (mounted) setState(() => _chatAccessFailed = true);
    } finally {
      if (mounted) setState(() => _requestingChatAccess = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    super.dispose();
  }

  Future<void> _mic() async {
    if (_chatAccess?.approved != true) return;
    final state = ref.read(pandaTalkControllerProvider);
    if (state.phase == PandaPhase.listening) {
      await _controller.finishListening();
      return;
    }
    // Voice must be allowed first (on-device recogniser, or a parent's
    // consent for the cloud one, and not turned off by a parent): otherwise
    // the child is never asked for the permission and the mic never opens.
    if (!await _controller.checkVoiceConsent() || !mounted) return;
    if (!_micExplainedThisRun) {
      final granted = await ref.read(speechInputProvider).hasPermission();
      if (!mounted) return;
      if (!granted) {
        final allow = await _explainMic();
        if (!mounted) return;
        if (allow != true) {
          _controller.toggleTyping();
          return;
        }
      }
      _micExplainedThisRun = true;
    }
    await _controller.startListening();
  }

  Future<bool?> _explainMic() {
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('panda.talk.micExplain'),
        icon: const Icon(Icons.mic_rounded),
        title: Text(l10n.pandaMicExplainTitle),
        // On-device recognition keeps the audio on the phone; otherwise the
        // platform service may be Google's and use the internet.
        content: Text(
          ref.read(pandaTalkControllerProvider).onDeviceSpeech == true
              ? l10n.pandaMicExplainBodyOnDevice
              : l10n.pandaMicExplainBody,
        ),
        actions: [
          TextButton(
            key: const Key('panda.talk.micNotNow'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.pandaMicNotNow),
          ),
          FilledButton(
            key: const Key('panda.talk.micAllow'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.pandaMicAllow),
          ),
        ],
      ),
    );
  }

  void _send([String? value]) {
    if (_chatAccess?.approved != true) return;
    final text = (value ?? _text.text).trim();
    if (text.isEmpty) return;
    _text.clear();
    unawaited(_controller.send(text));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final state = ref.watch(pandaTalkControllerProvider);
    ref.listen(
      pandaTalkControllerProvider.select((value) => value.problem),
      (previous, next) {
        if (next == PandaProblem.chatNeedsParent) {
          unawaited(_refreshChatAccess());
        }
      },
    );
    // Keeps the real allowance loaded for the opening line.
    ref.watch(videoAllowanceProvider);
    final media = MediaQuery.of(context);
    final stageWidth = (media.size.height * 0.28 * 512 / 279).clamp(
      200.0,
      560.0,
    );

    final status = switch (state.phase) {
      PandaPhase.idle || PandaPhase.error => l10n.pandaStateIdle,
      PandaPhase.greeting || PandaPhase.speaking => l10n.pandaStateSpeaking,
      PandaPhase.listening => l10n.pandaStateListening,
      PandaPhase.thinking => l10n.pandaStateThinking,
      PandaPhase.happy => l10n.pandaStateHappy,
      PandaPhase.curious => l10n.pandaStateCurious,
      PandaPhase.sleepy => l10n.pandaStateSleepy,
    };
    final problem = switch (state.problem) {
      null => null,
      PandaProblem.micDenied => l10n.pandaErrorMicDenied,
      PandaProblem.micUnavailable => l10n.pandaErrorMicUnavailable,
      PandaProblem.listenLanguageMissing => l10n.pandaListenLanguageMissing,
      PandaProblem.notHeard => l10n.pandaErrorNotHeard,
      PandaProblem.network => l10n.pandaErrorNetwork,
      PandaProblem.busy => l10n.pandaErrorBusy,
      PandaProblem.voiceNeedsParent => l10n.pandaVoiceNeedsParent,
      PandaProblem.voiceTurnedOff => l10n.pandaVoiceTurnedOff,
      PandaProblem.chatNeedsParent => l10n.pandaChatAccessAskChild,
    };
    final chatAllowed = _chatAccess?.approved == true;
    final childSaid = state.phase == PandaPhase.listening
        ? state.heard
        : state.childText;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          key: const Key('panda.talk.sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.pandaTalkOpen,
                    style: context.text.titleLarge,
                  ),
                ),
                IconButton(
                  key: const Key('panda.talk.close'),
                  tooltip: l10n.pandaTalkClose,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: SizedBox(
                width: stageWidth,
                child: Semantics(
                  button: true,
                  label: '${l10n.pandaName}. ${l10n.pandaMicButton}',
                  child: PandaCharacter(
                    phase: state.phase,
                    lipSync: _controller.lipSync,
                    onTap: state.busy ? null : _mic,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (state.phase == PandaPhase.listening)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: Icon(Icons.hearing_rounded, color: colors.primary),
                    ),
                  if (state.talking)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: Icon(
                        Icons.volume_up_rounded,
                        color: colors.primary,
                      ),
                    ),
                  Flexible(
                    child: Text(
                      status,
                      key: Key('panda.talk.status.${state.phase.name}'),
                      textAlign: TextAlign.center,
                      style: context.text.titleMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (state.pandaText.isNotEmpty)
              _Bubble(
                key: const Key('panda.talk.reply'),
                label: l10n.pandaName,
                text: state.pandaText,
                fromPanda: true,
              ),
            if (childSaid.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _Bubble(
                key: const Key('panda.talk.child'),
                label: l10n.pandaYou,
                text: childSaid,
                fromPanda: false,
              ),
            ],
            if (problem != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _Notice(key: const Key('panda.talk.problem'), text: problem),
            ],
            if (state.voiceMissing) ...[
              const SizedBox(height: AppSpacing.sm),
              _Notice(
                key: const Key('panda.talk.voiceMissing'),
                text: l10n.pandaVoiceMissing,
              ),
            ],
            if (!chatAllowed) ...[
              const SizedBox(height: AppSpacing.md),
              _ChatAccessPrompt(
                status: _chatAccess?.status,
                loading: _chatAccessLoading,
                requesting: _requestingChatAccess,
                failed: _chatAccessFailed,
                onRequest: _requestChatAccess,
                onRefresh: _refreshChatAccess,
              ),
            ],
            if (chatAllowed && !state.busy) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  for (final s
                      in state.suggestions.isEmpty
                          ? const [
                              PandaSuggestion.mission,
                              PandaSuggestion.joke,
                              PandaSuggestion.fact,
                            ]
                          : state.suggestions)
                    ActionChip(
                      key: Key('panda.talk.suggest.${s.name}'),
                      label: Text(_suggestion(l10n, s)),
                      onPressed: () => _send(_suggestion(l10n, s)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            if (chatAllowed && state.typing)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('panda.talk.input'),
                        controller: _text,
                        maxLength: 300,
                        enabled: !state.busy,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _send,
                        decoration: InputDecoration(
                          hintText: l10n.pandaTypeHint,
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton.filled(
                      key: const Key('panda.talk.send'),
                      tooltip: l10n.pandaSend,
                      onPressed: state.busy ? null : _send,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            if (chatAllowed)
              Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (state.talking || state.busy)
                  OutlinedButton.icon(
                    key: const Key('panda.talk.stop'),
                    onPressed: () => unawaited(_controller.stop()),
                    icon: const Icon(Icons.stop_rounded),
                    label: Text(l10n.pandaStopButton),
                  ),
                if (state.phase != PandaPhase.thinking)
                  FilledButton.icon(
                    key: const Key('panda.talk.mic'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(140, 56),
                      backgroundColor: state.phase == PandaPhase.listening
                          ? colors.error
                          : null,
                    ),
                    onPressed: _mic,
                    icon: Icon(
                      state.phase == PandaPhase.listening
                          ? Icons.check_rounded
                          : state.voiceAllowed == false
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                    ),
                    label: Text(
                      state.phase == PandaPhase.listening
                          ? l10n.pandaStopButton
                          : l10n.pandaMicButton,
                    ),
                  ),
                TextButton.icon(
                  key: const Key('panda.talk.type'),
                  onPressed: _controller.toggleTyping,
                  icon: const Icon(Icons.keyboard_rounded),
                  label: Text(l10n.pandaTypeButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _suggestion(AppLocalizations l10n, PandaSuggestion s) => switch (s) {
  PandaSuggestion.mission => l10n.pandaSuggestMission,
  PandaSuggestion.video => l10n.pandaSuggestVideo,
  PandaSuggestion.joke => l10n.pandaSuggestJoke,
  PandaSuggestion.fact => l10n.pandaSuggestFact,
  PandaSuggestion.draw => l10n.pandaSuggestDraw,
  PandaSuggestion.stars => l10n.pandaSuggestStars,
};

class _ChatAccessPrompt extends StatelessWidget {
  const _ChatAccessPrompt({
    required this.status,
    required this.loading,
    required this.requesting,
    required this.failed,
    required this.onRequest,
    required this.onRefresh,
  });

  final String? status;
  final bool loading;
  final bool requesting;
  final bool failed;
  final VoidCallback onRequest;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = loading
        ? l10n.pandaChatAccessChecking
        : failed
        ? l10n.pandaChatAccessRequestFailed
        : switch (status) {
            'pending' => l10n.pandaChatAccessPendingChild,
            'rejected' => l10n.pandaChatAccessRejectedChild,
            'revoked' => l10n.pandaChatAccessRevokedChild,
            _ => l10n.pandaChatAccessAskChild,
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.sm),
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (status == 'pending' && !failed)
          Align(
            alignment: AlignmentDirectional.center,
            child: TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.pandaChatAccessCheckAgain),
            ),
          )
        else
          Align(
            alignment: AlignmentDirectional.center,
            child: FilledButton.icon(
              key: const Key('panda.talk.requestAccess'),
              onPressed: requesting
                  ? null
                  : failed
                  ? onRefresh
                  : onRequest,
              icon: requesting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(failed ? Icons.refresh_rounded : Icons.person_add_alt_1_rounded),
              label: Text(
                failed
                    ? l10n.pandaChatAccessCheckAgain
                    : l10n.pandaChatAccessRequestButton,
              ),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.label,
    required this.text,
    required this.fromPanda,
    super.key,
  });

  final String label;
  final String text;
  final bool fromPanda;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: fromPanda ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fromPanda
                ? colors.primaryContainer.withValues(alpha: 0.35)
                : colors.surfaceContainerHigh,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(fromPanda ? 4 : AppRadius.md),
              topRight: Radius.circular(fromPanda ? AppRadius.md : 4),
              bottomLeft: const Radius.circular(AppRadius.md),
              bottomRight: const Radius.circular(AppRadius.md),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm + 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.text.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(text, style: context.text.bodyLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm + 4),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: colors.onTertiaryContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(text, style: context.text.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
