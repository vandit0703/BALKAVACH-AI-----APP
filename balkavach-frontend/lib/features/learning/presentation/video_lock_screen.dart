import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../companion/domain/companion_director.dart';
import '../../companion/domain/panda_interaction.dart';
import '../../companion/presentation/panda_bubble.dart';
import '../../companion/presentation/panda_still.dart';
import '../../missions/presentation/mission_providers.dart'
    show childNotificationsProvider;
import '../data/video_feed_repository.dart';

/// Full-screen, child-friendly "video time is done" page.
///
/// It explains, shows the way back (a mission **approved by a grown-up**) and
/// keeps asking the server, so time a parent approves while the child waits
/// shows up here without restarting the app. It never grants or unlocks
/// anything itself: opening a video always asks the server again first.
class VideoLockScreen extends ConsumerStatefulWidget {
  const VideoLockScreen({super.key, this.allowance});

  /// The latest server figures, when the caller already has them.
  final VideoAllowance? allowance;

  /// How often the open page re-asks the server for new time. Cheap (one
  /// small GET) and stops when the page closes or the app is in the
  /// background.
  static const refreshEvery = Duration(seconds: 45);

  @override
  ConsumerState<VideoLockScreen> createState() => _VideoLockScreenState();
}

class _VideoLockScreenState extends ConsumerState<VideoLockScreen>
    with WidgetsBindingObserver {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startRefresh();
  }

  void _startRefresh() {
    _refresh?.cancel();
    _refresh = Timer.periodic(VideoLockScreen.refreshEvery, (_) => _check());
  }

  void _check() {
    if (!mounted) return;
    ref
      ..invalidate(childNotificationsProvider)
      ..invalidate(videoAllowanceProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check();
      _startRefresh();
    } else {
      _refresh?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final live = ref.watch(videoAllowanceProvider);
    final data = live.value ?? widget.allowance;
    final timeBack =
        data != null && !data.isExhausted && data.remainingSeconds >= 60;
    final minutesLeft = data == null ? 0 : data.remainingSeconds ~/ 60;
    final failed = live.hasError && !live.isLoading;
    final checking = live.isLoading;

    final width = MediaQuery.sizeOf(context).width;
    final stageWidth = (width - 2 * AppSpacing.lg).clamp(200.0, 360.0);

    return Scaffold(
      key: const Key('video.lock.screen'),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(key: Key('video.lock.back')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SizedBox(
                      width: stageWidth,
                      child: ExcludeSemantics(
                        child: PandaStill(
                          key: const Key('video.lock.panda'),
                          phase: timeBack
                              ? PandaPhase.happy
                              : PandaPhase.sleepy,
                          spokenWords: 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // A new key when the state flips, so Panda says the
                  // matching line instead of keeping the old one.
                  PandaBubble(
                    key: ValueKey('video.lock.bubble.$timeBack'),
                    event: timeBack
                        ? CompanionEvent.videoUnlocked
                        : CompanionEvent.videoUp,
                    minutes: minutesLeft,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(
                      timeBack
                          ? l10n.videoLockTimeBackTitle
                          : l10n.videoTimeExhaustedTitle,
                      key: Key(
                        timeBack ? 'video.lock.timeBack' : 'video.lock.title',
                      ),
                      textAlign: TextAlign.center,
                      style: context.text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    timeBack
                        ? l10n.videoLockTimeBackBody(minutesLeft)
                        : l10n.videoTimeExhaustedBody,
                    textAlign: TextAlign.center,
                    style: context.text.bodyLarge,
                  ),
                  if (data != null && !timeBack) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      key: const Key('video.lock.summary'),
                      l10n.videoLockSummary(
                        (data.consumedTodaySeconds / 60).floor(),
                        (data.totalEarnedTodaySeconds / 60).floor(),
                      ),
                      textAlign: TextAlign.center,
                      style: context.text.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (!timeBack) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const _HowToEarnMore(),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  _CheckStatus(
                    checking: checking,
                    failed: failed,
                    onCheck: _check,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (timeBack)
                    FilledButton.icon(
                      key: const Key('video.lock.watchNow'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      // Home asks the server again before any video opens.
                      onPressed: () => context.go(AppRoutes.childHome),
                      icon: const Icon(Icons.play_circle_rounded),
                      label: Text(l10n.videoLockWatchNow),
                    )
                  else
                    FilledButton.icon(
                      key: const Key('video.lock.toMissions'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: () => context.go(AppRoutes.childMissions),
                      icon: const Icon(Icons.rocket_launch_rounded),
                      label: Text(l10n.videoGoToMissions),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    key: const Key('video.lock.close'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(l10n.videoBackToHome),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pick a mission → finish and send it → a grown-up approves. The last step
/// is the one that earns time; sending a mission alone does not.
class _HowToEarnMore extends StatelessWidget {
  const _HowToEarnMore();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final steps = [
      (Icons.rocket_launch_rounded, l10n.videoLockStep1),
      (Icons.check_circle_rounded, l10n.videoLockStep2),
      (Icons.verified_user_rounded, l10n.videoLockStep3),
    ];
    return DecoratedBox(
      key: const Key('video.lock.steps'),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.videoLockStepsTitle,
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final (index, (icon, label)) in steps.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: colors.primary,
                      child: Text(
                        '${index + 1}',
                        style: context.text.labelLarge?.copyWith(
                          color: colors.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(icon, size: 20, color: colors.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: Text(label, style: context.text.bodyLarge)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.videoLockStepsNote,
              style: context.text.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckStatus extends StatelessWidget {
  const _CheckStatus({
    required this.checking,
    required this.failed,
    required this.onCheck,
  });

  final bool checking;
  final bool failed;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (checking) {
      return Row(
        key: const Key('video.lock.checking'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: Text(l10n.videoLockChecking)),
        ],
      );
    }
    return Column(
      children: [
        if (failed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              l10n.videoTimeCheckFailed,
              key: const Key('video.lock.checkFailed'),
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.error,
              ),
            ),
          ),
        OutlinedButton.icon(
          key: Key(failed ? 'video.lock.retry' : 'video.lock.checkAgain'),
          onPressed: onCheck,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.videoLockCheckAgain),
        ),
      ],
    );
  }
}

/// Opens the lock page above the current route.
Future<void> showVideoLockScreen(
  BuildContext context, {
  VideoAllowance? allowance,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => VideoLockScreen(allowance: allowance),
  ),
);

/// Asks the server for today's allowance before a video is opened.
///
/// Returns true only when the server confirms time remains. If the server says
/// none is left the lock page is shown; if it cannot be reached the child is
/// told and playback does not start: an unanswered question is never a yes.
Future<bool> ensureVideoAllowance(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  try {
    // Straight to the server: a provider nobody is listening to would be
    // disposed mid-load. Invalidate afterwards so any allowance card refreshes.
    final allowance = await ref
        .read(videoFeedRepositoryProvider)
        .getAllowance();
    ref.invalidate(videoAllowanceProvider);
    if (allowance.isExhausted || allowance.remainingSeconds <= 0) {
      if (context.mounted) {
        await showVideoLockScreen(context, allowance: allowance);
      }
      return false;
    }
    return true;
  } on ApiException {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.videoTimeCheckFailed)));
    return false;
  }
}
