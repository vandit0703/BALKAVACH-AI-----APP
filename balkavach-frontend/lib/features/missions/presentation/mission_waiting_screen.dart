import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/illustration.dart';
import '../../../shared/widgets/state_views.dart';
import '../domain/mission_status.dart';
import 'mission_providers.dart';

/// Waiting for parent approval. The outcome is read from the child's review
/// notifications; "Check again" re-fetches them. There is no push channel.
class MissionWaitingScreen extends ConsumerWidget {
  const MissionWaitingScreen({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(missionStatusesProvider);
    final stars =
        ref.watch(childMissionProvider(taskId)).value?.starReward ?? 0;
    final status = snapshot.value?.statusOf(taskId) ?? MissionStatus.pending;
    final checking = snapshot.isLoading;

    final (title, body, icon, tint) = switch (status) {
      MissionStatus.approved => (
        l10n.waitingApprovedTitle,
        l10n.waitingApprovedBody(stars),
        Icons.verified_rounded,
        context.colors.secondaryContainer,
      ),
      MissionStatus.rejected => (
        l10n.waitingRejectedTitle,
        l10n.waitingRejectedBody,
        Icons.sentiment_neutral_rounded,
        context.colors.errorContainer,
      ),
      MissionStatus.resubmissionRequested => (
        l10n.waitingResubmitTitle,
        l10n.waitingResubmitBody,
        Icons.replay_rounded,
        context.colors.surfaceContainerHigh,
      ),
      _ => (
        l10n.waitingTitle,
        l10n.waitingBody,
        Icons.hourglass_top_rounded,
        context.colors.tertiaryFixed,
      ),
    };

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => context.go(AppRoutes.childMissions),
        ),
      ),
      body: ScrollablePage(
        maxWidth: ContentWidth.form,
        spacing: AppSpacing.lg,
        children: [
          const Illustration(
            asset: AppImages.pandaCheering,
            aspectRatio: 16 / 9,
          ),
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: tint,
              child: Icon(icon, size: 36, color: context.colors.onSurface),
            ),
          ),
          Semantics(
            liveRegion: true,
            child: Text(
              title,
              key: const Key('waiting.title'),
              textAlign: TextAlign.center,
              style: context.text.headlineMedium,
            ),
          ),
          Text(
            body,
            textAlign: TextAlign.center,
            style: context.text.bodyLarge?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (snapshot.value case MissionStatusSnapshot(
            reviewsAvailable: false,
          ))
            InlineNotice(message: l10n.reviewsUnavailable),
          if (status == MissionStatus.pending)
            SecondaryButton(
              key: const Key('waiting.check'),
              label: l10n.waitingCheckAgain,
              icon: Icons.refresh_rounded,
              onPressed: checking
                  ? null
                  : () => ref.invalidate(childNotificationsProvider),
            ),
          PrimaryButton(
            label: l10n.waitingBackToMissions,
            onPressed: () => context.go(AppRoutes.childMissions),
          ),
        ],
      ),
    );
  }
}
