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
import '../../../shared/widgets/state_views.dart';
import '../../companion/domain/companion_director.dart';
import '../../companion/presentation/panda_companion.dart';
import '../data/missions_repository.dart';
import '../domain/daily_mission_models.dart';
import '../domain/mission_models.dart';
import '../domain/mission_status.dart';
import 'mission_providers.dart';
import 'widgets/mission_motion.dart';
import 'widgets/mission_steps.dart';
import 'widgets/mission_tracker.dart';
import 'widgets/mission_visuals.dart';

/// Mission Details (Stitch `mission_details_custom_mission`): what to do, step
/// by step, how far along it is, what it pays, and the one action its real
/// status allows (start / continue, wait for a parent, try again, or done).
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
        // Not listed any more (finished, removed, or for another child): say
        // so and offer a way back, never an empty page.
        AsyncData() => Center(
          child: EmptyView(
            message: l10n.missionNotFound,
            action: SecondaryButton(
              key: const Key('mission.notFound.back'),
              label: l10n.waitingBackToMissions,
              icon: Icons.arrow_back_rounded,
              onPressed: () => context.go(AppRoutes.childMissions),
            ),
          ),
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref
            ..invalidate(childMissionsProvider)
            ..invalidate(childMissionProvider(taskId)),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

/// The daily assignment behind [taskId], if this mission was a daily choice
/// (today's or an unfinished one from an earlier day).
DailyMissionAssignment? _assignmentFor(WidgetRef ref, String taskId) {
  final today =
      ref.watch(dailyMissionChoicesProvider).value?.choices ??
      const <DailyMissionAssignment>[];
  final older =
      ref.watch(unfinishedMissionsProvider).value ??
      const <DailyMissionAssignment>[];
  for (final a in [...today, ...older]) {
    if (a.taskId == taskId) return a;
  }
  return null;
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.mission});

  final Mission mission;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _starting = false;

  /// Opens the submission form. A chosen daily mission is first marked as
  /// started on the server (`selected` -> `in_progress`, no reward). That
  /// bookkeeping never blocks the child: submitting does not require it.
  Future<void> _start(DailyMissionAssignment? assignment) async {
    if (_starting) return;
    if (assignment != null && assignment.status == 'selected') {
      setState(() => _starting = true);
      try {
        await ref
            .read(missionsRepositoryProvider)
            .startDailyMission(assignment.id);
        ref
          ..invalidate(dailyMissionChoicesProvider)
          ..invalidate(unfinishedMissionsProvider);
      } on Object catch (error) {
        debugPrint(
          'Could not mark daily mission ${assignment.id} started: $error',
        );
      }
      if (!mounted) return;
      setState(() => _starting = false);
    }
    await context.push(AppRoutes.childMissionSubmit(widget.mission.id));
  }

  @override
  Widget build(BuildContext context) {
    final mission = widget.mission;
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final categories =
        ref.watch(taskCategoriesProvider).value ?? const <TaskCategory>[];
    final category = categories
        .where((c) => c.id == mission.categoryId)
        .firstOrNull;
    final status =
        ref.watch(missionStatusesProvider).value?.statusOf(mission.id) ??
        MissionStatus.notStarted;
    final assignment = _assignmentFor(ref, mission.id);
    final stage = missionStage(
      status: status,
      assignmentStatus: assignment?.status,
    );
    final attempts =
        ref.watch(missionAttemptsProvider(mission.id)).value ??
        const <TaskSubmission>[];
    final approvedAttempt = attempts
        .where((a) => a.status == 'approved')
        .firstOrNull;
    final description = mission.description?.trim();
    final locale = Localizations.localeOf(context).toLanguageTag();
    final visual = CategoryVisual.of(context, category);
    final started = assignment?.status == 'in_progress';

    return ScrollablePage(
      children: [
        _Hero(mission: mission, category: category),
        AppCard(
          key: const Key('mission.progress'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md + 4,
          ),
          child: MissionTracker(stage: stage),
        ),
        if (status == MissionStatus.approved)
          _CompletedBanner(attempt: approvedAttempt)
        else ...[
          AppCard(
            color: colors.surfaceContainerLow,
            elevated: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.sm + 4,
              children: [
                Row(
                  children: [
                    CategoryTile(visual: visual, size: 52),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        l10n.missionEarnBoth(
                          mission.starReward,
                          mission.xpReward,
                        ),
                        style: context.text.bodyLarge,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: missionRewardPills(
                    context,
                    mission.starReward,
                    mission.xpReward,
                  ),
                ),
              ],
            ),
          ),
          if (status == MissionStatus.notStarted)
            PandaCompanion(
              event: CompanionEvent.rewardExplain,
              stars: mission.starReward,
            ),
        ],
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.md,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.missionWhatToDo,
                  style: context.text.headlineSmall,
                ),
              ),
              if (description == null || description.isEmpty)
                Text(l10n.missionNoDescription, style: context.text.bodyLarge)
              else
                InstructionsView(text: description),
              if (mission.dueAt != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: EyebrowPill(
                    label: l10n.missionDue(
                      DateFormat.MMMd(
                        locale,
                      ).add_jm().format(mission.dueAt!.toLocal()),
                    ),
                    icon: Icons.schedule_rounded,
                  ),
                ),
            ],
          ),
        ),
        if (status != MissionStatus.approved)
          ?missionStatusChip(context, status),
        _AttemptHistory(taskId: mission.id),
        switch (status) {
          // Done: no second submission (the server refuses one for a
          // one-time mission), just the way back.
          MissionStatus.approved => SecondaryButton(
            key: const Key('mission.back'),
            label: l10n.waitingBackToMissions,
            icon: Icons.arrow_back_rounded,
            onPressed: () => context.go(AppRoutes.childMissions),
          ),
          MissionStatus.pending => PrimaryButton(
            key: const Key('mission.start'),
            label: l10n.missionWaitingButton,
            icon: Icons.hourglass_top_rounded,
            childSized: true,
            onPressed: () =>
                context.push(AppRoutes.childMissionWaiting(mission.id)),
          ),
          MissionStatus.notStarted => PrimaryButton(
            key: const Key('mission.start'),
            label: started ? l10n.missionContinue : l10n.missionStartMission,
            icon: Icons.rocket_launch_rounded,
            childSized: true,
            loading: _starting,
            onPressed: () => _start(assignment),
          ),
          MissionStatus.rejected ||
          MissionStatus.resubmissionRequested => PrimaryButton(
            key: const Key('mission.start'),
            label: l10n.missionDoAgain,
            icon: Icons.rocket_launch_rounded,
            childSized: true,
            onPressed: () =>
                context.push(AppRoutes.childMissionSubmit(mission.id)),
          ),
        },
      ],
    );
  }
}

/// "Mission complete!" with what the approval actually earned (from the
/// server's ledgers, when it reports them).
class _CompletedBanner extends StatelessWidget {
  const _CompletedBanner({required this.attempt});

  final TaskSubmission? attempt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final stars = attempt?.starsAwarded;
    final xp = attempt?.xpAwarded;
    return AppCard(
      key: const Key('mission.completed'),
      color: Color.alphaBlend(
        colors.secondaryContainer.withValues(alpha: 0.45),
        colors.surfaceContainerLowest,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          const CelebrationPop(child: CompletedBadge(size: 64)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.xs,
                children: [
                  Text(
                    l10n.missionCompleteTitle,
                    style: context.text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (stars != null && xp != null && (stars > 0 || xp > 0))
                    Text(
                      l10n.missionEarnedBoth(stars, xp),
                      style: context.text.bodyLarge,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
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
                    if (category != null)
                      EyebrowPill(
                        label: category!.name.toUpperCase(),
                        background: context.colors.secondaryContainer,
                        foreground: context.colors.onSecondaryContainer,
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    EntranceFade(
                      child: Text(
                        mission.childTitle,
                        style: context.text.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
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
