import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../companion/domain/companion_director.dart';
import '../../companion/presentation/panda_bubble.dart';
import '../data/video_feed_repository.dart';

/// Full-screen, child-friendly "video time is used up" page.
///
/// It only explains and points the child to missions. It never grants time:
/// the server decides whether a video may play, and re-checks on every report.
class VideoLockScreen extends StatelessWidget {
  const VideoLockScreen({super.key, this.allowance});

  /// The latest server figures, when known, for the "you watched" line.
  final VideoAllowance? allowance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final data = allowance;

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
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.hourglass_bottom_rounded,
                      size: 72,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const PandaBubble(event: CompanionEvent.videoUp),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    l10n.videoTimeExhaustedTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.videoTimeExhaustedBody,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (data != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      key: const Key('video.lock.summary'),
                      l10n.videoLockSummary(
                        (data.consumedTodaySeconds / 60).floor(),
                        (data.totalEarnedTodaySeconds / 60).floor(),
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('video.lock.toMissions'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: () => context.go(AppRoutes.childMissions),
                      icon: const Icon(Icons.rocket_launch_rounded),
                      label: Text(l10n.videoGoToMissions),
                    ),
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
