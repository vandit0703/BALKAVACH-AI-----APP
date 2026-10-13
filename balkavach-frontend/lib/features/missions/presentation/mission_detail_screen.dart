import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gamification.dart';
import '../../../shared/widgets/state_views.dart';
import '../domain/mission_models.dart';
import '../domain/mission_status.dart';
import 'mission_providers.dart';
import 'widgets/mission_visuals.dart';

/// Mission Details (Stitch `mission_details_custom_mission`). The API has a
/// single free-text description, so "Mission Steps" shows that text.
class MissionDetailScreen extends ConsumerWidget {
  const MissionDetailScreen({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mission = ref.watch(childMissionProvider(taskId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.missionDetailTitle)),
      body: switch (mission) {
        AsyncData(value: final Mission m) => _Body(mission: m),
        AsyncData() => Center(child: EmptyView(message: l10n.missionNotFound)),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(childMissionsProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.mission});

  final Mission mission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final categories =
        ref.watch(taskCategoriesProvider).value ?? const <TaskCategory>[];
    final category = categories
        .where((c) => c.id == mission.categoryId)
        .firstOrNull;
    final status =
        ref.watch(missionStatusesProvider).value?.statusOf(mission.id) ??
        MissionStatus.notStarted;
    final description = mission.description?.trim();
    final locale = Localizations.localeOf(context).toLanguageTag();
    final visual = CategoryVisual.of(context, category);

    return ScrollablePage(
      children: [
        _Hero(mission: mission, category: category),
        AppCard(
          color: context.colors.surfaceContainerLow,
          elevated: false,
          child: Row(
            children: [
              CategoryIcon(visual: visual, size: 52),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l10n.missionEarn(mission.starReward),
                  style: context.text.bodyLarge,
                ),
              ),
            ],
          ),
        ),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.sm + 4,
            children: [
              Text(l10n.missionWhatToDo, style: context.text.headlineSmall),
              Text(
                (description == null || description.isEmpty)
                    ? l10n.missionNoDescription
                    : description,
                style: context.text.bodyLarge,
              ),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  StarPill(count: mission.starReward),
                  if (mission.xpReward > 0)
                    EyebrowPill(
                      label: l10n.missionXpCount(mission.xpReward),
                      icon: Icons.bolt_rounded,
                    ),
                  if (mission.dueAt != null)
                    EyebrowPill(
                      label: l10n.missionDue(
                        DateFormat.MMMd(
                          locale,
                        ).add_jm().format(mission.dueAt!.toLocal()),
                      ),
                      icon: Icons.schedule_rounded,
                    ),
                ],
              ),
            ],
          ),
        ),
        ?missionStatusChip(context, status),
        _AttemptHistory(taskId: mission.id),
        PrimaryButton(
          key: const Key('mission.start'),
          label: switch (status) {
            MissionStatus.pending => l10n.missionWaitingButton,
            MissionStatus.notStarted => l10n.missionStartMission,
            _ => l10n.missionDoAgain,
          },
          icon: status == MissionStatus.pending
              ? Icons.hourglass_top_rounded
              : Icons.rocket_launch_rounded,
          childSized: true,
          onPressed: status == MissionStatus.pending
              ? () => context.push(AppRoutes.childMissionWaiting(mission.id))
              : () => context.push(AppRoutes.childMissionSubmit(mission.id)),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.mission, required this.category});

  final Mission mission;
  final TaskCategory? category;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: AppRadius.hero,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                AppImages.pandaDrawing,
                fit: BoxFit.cover,
                cacheWidth: (constraints.maxWidth * dpr).round(),
                excludeFromSemantics: true,
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // Dark enough behind the whole title block, however many
                    // lines it wraps to (WCAG contrast for white text).
                    colors: [
                      Color(0x00041B3C),
                      Color(0xB3041B3C),
                      Color(0xEB041B3C),
                    ],
                    stops: [0.1, 0.45, 1],
                  ),
                ),
              ),
            ),
            // Height grows with the title (long titles, large text) instead
            // of clipping it; the image fills whatever height results.
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxWidth * 9 / 16,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: AppSpacing.xxl),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        if (category != null)
                          EyebrowPill(
                            label: category!.name.toUpperCase(),
                            background: context.colors.secondaryContainer,
                            foreground: context.colors.onSecondaryContainer,
                          ),
                        StarPill(count: mission.starReward),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      mission.title,
                      style: context.text.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The child's earlier tries at this mission, with the parent's notes.
class _AttemptHistory extends ConsumerWidget {
  const _AttemptHistory({required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attempts = ref.watch(missionAttemptsProvider(taskId)).value;
    if (attempts == null || attempts.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return AppCard(
      key: const Key('mission.history'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.md,
        children: [
          Text(l10n.historyTitle, style: context.text.headlineSmall),
          for (final attempt in attempts)
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.xs,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l10n.historyAttempt(attempt.submissionNumber),
                        style: context.text.titleSmall,
                      ),
                      EyebrowPill(
                        label: switch (MissionStatus.fromSubmissionStatus(
                          attempt.status,
                        )) {
                          MissionStatus.approved => l10n.statusApprovedShort,
                          MissionStatus.rejected => l10n.statusRejectedShort,
                          MissionStatus.resubmissionRequested =>
                            l10n.statusResubmitShort,
                          _ => l10n.statusPendingShort,
                        },
                      ),
                      Text(
                        DateFormat.MMMd(
                          locale,
                        ).add_jm().format(attempt.submittedAt.toLocal()),
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                  if (attempt.reviewNote != null &&
                      attempt.reviewNote!.trim().isNotEmpty)
                    Text(
                      '${l10n.historyParentNote}: ${attempt.reviewNote!.trim()}',
                      style: context.text.bodyMedium,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
