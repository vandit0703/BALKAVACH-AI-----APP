import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/async/refresh_quietly.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/adaptive_wrap.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/illustration.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../missions/presentation/mission_providers.dart';
import '../../progress/data/progress_repository.dart';

/// Growth stage shown in the garden, derived from the missions a parent
/// approved in the last seven days. The backend keeps a `garden_progress`
/// value but does not expose it (B9), so the stage is presentation only.
enum GardenStage {
  seed(0, Icons.grass_rounded),
  sprout(1, Icons.eco_rounded),
  sapling(3, Icons.park_rounded),
  bloomingTree(6, Icons.forest_rounded);

  const GardenStage(this.minMissions, this.icon);

  final int minMissions;
  final IconData icon;

  static GardenStage forWeeklyMissions(int count) =>
      values.lastWhere((stage) => count >= stage.minMissions);

  /// The next stage, or `null` at the top.
  GardenStage? get next => index + 1 < values.length ? values[index + 1] : null;
}

/// Streak lengths that unlock garden milestones (from `longest_streak`).
const kStreakMilestones = [3, 7, 14, 30];

/// My Garden (Stitch `my_garden`). Watering, sunlight and decorations from the
/// design have no backend support and are not shown.
class GardenScreen extends ConsumerWidget {
  const GardenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childId = ref.watch(activeChildIdProvider);
    final session = ref.watch(sessionControllerProvider).value;
    if (childId == null || session == null) return const LoadingView();
    final progress = ref.watch(childProgressProvider(childId));
    final today = ref.watch(clockProvider)();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(childProgressProvider(childId));
        await refreshQuietly(ref.read(childProgressProvider(childId).future));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ResponsiveContent(
            child: switch (progress) {
              AsyncData(:final value) => _Garden(
                name: session.user.fullName,
                progress: value,
                weeklyMissions: value
                    .week(today)
                    .fold<int>(0, (sum, d) => sum + d.completedTasks),
              ),
              AsyncError(:final error) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(childProgressProvider(childId)),
              ),
              _ => const LoadingView(),
            },
          ),
        ],
      ),
    );
  }
}

class _Garden extends StatelessWidget {
  const _Garden({
    required this.name,
    required this.progress,
    required this.weeklyMissions,
  });

  final String name;
  final ChildProgress progress;
  final int weeklyMissions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final stage = GardenStage.forWeeklyMissions(weeklyMissions);
    final next = stage.next;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.md,
      children: [
        AppCard(
          radius: AppRadius.hero,
          gradient: LinearGradient(
            colors: [colors.surfaceContainerLow, colors.surfaceContainerHigh],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.sm + 4,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: colors.secondaryContainer,
                    child: Icon(stage.icon, color: colors.secondary),
                  ),
                  const SizedBox(width: AppSpacing.sm + 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.gardenOwner(name),
                          style: context.text.headlineSmall,
                        ),
                        Text(
                          l10n.gardenStage(_stageName(l10n, stage)),
                          style: context.text.titleSmall?.copyWith(
                            color: colors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (progress.levelNumber != null)
                    EyebrowPill(
                      icon: Icons.spa_rounded,
                      label: l10n.childLevel(progress.levelNumber!),
                      background: colors.tertiaryFixed,
                      foreground: colors.onTertiaryFixed,
                    ),
                ],
              ),
              if (next != null) ...[
                Text(
                  l10n.gardenNextStage(
                    next.minMissions - weeklyMissions,
                    _stageName(l10n, next),
                  ),
                  style: context.text.labelLarge,
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: weeklyMissions / next.minMissions,
                    minHeight: 10,
                    color: colors.secondary,
                    backgroundColor: colors.surfaceContainerHighest,
                    semanticsLabel: l10n.gardenNextStage(
                      next.minMissions - weeklyMissions,
                      _stageName(l10n, next),
                    ),
                  ),
                ),
              ] else
                Text(l10n.gardenFullBloom, style: context.text.labelLarge),
              InlineNotice(
                icon: Icons.verified_outlined,
                message: l10n.gardenGrowsHint,
              ),
            ],
          ),
        ),
        AppCard(
          radius: AppRadius.hero,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Illustration(
                asset: AppImages.gardenScene,
                aspectRatio: 4 / 3,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.xl),
                ),
                semanticLabel: l10n.gardenImageLabel,
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md + 4),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: colors.secondaryContainer,
                          child: Icon(
                            Icons.task_alt_rounded,
                            color: colors.secondary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.gardenWeeklyMissions(weeklyMissions),
                                style: context.text.titleLarge,
                              ),
                              Text(
                                l10n.gardenWeeklyBody,
                                style: context.text.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.statStreak.toUpperCase(),
                          style: context.text.labelSmall?.copyWith(
                            color: colors.secondary,
                          ),
                        ),
                        Text(
                          l10n.statStreakValue(progress.currentStreak),
                          style: context.text.titleLarge?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionHeader(
          title: l10n.gardenMilestones,
          icon: Icons.emoji_nature_rounded,
          trailing: Text(
            l10n.gardenMilestonesCount(
              kStreakMilestones
                  .where((m) => progress.longestStreak >= m)
                  .length,
              kStreakMilestones.length,
            ),
            style: context.text.labelMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        AdaptiveWrap(
          spacing: AppSpacing.sm,
          children: [
            for (final (i, days) in kStreakMilestones.indexed)
              _MilestoneTile(
                days: days,
                index: i,
                unlocked: progress.longestStreak >= days,
              ),
          ],
        ),
        if (progress.garden case final garden?) _Collection(garden: garden),
        AppCard(
          color: colors.surfaceContainer,
          elevated: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.surfaceContainerLowest,
                child: Icon(Icons.psychology_rounded, color: colors.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.xs,
                  children: [
                    Text(l10n.gardenTipTitle, style: context.text.titleMedium),
                    Text(l10n.gardenTipBody, style: context.text.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _stageName(AppLocalizations l10n, GardenStage stage) =>
      switch (stage) {
        GardenStage.seed => l10n.gardenStageSeed,
        GardenStage.sprout => l10n.gardenStageSprout,
        GardenStage.sapling => l10n.gardenStageSapling,
        GardenStage.bloomingTree => l10n.gardenStageTree,
      };
}

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile({
    required this.days,
    required this.index,
    required this.unlocked,
  });

  final int days;
  final int index;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final looks = [
      (Icons.wb_twilight_rounded, colors.secondaryContainer, colors.secondary),
      (Icons.local_florist_rounded, colors.tertiaryFixed, colors.tertiary),
      (Icons.cottage_rounded, colors.surfaceContainerHigh, colors.primary),
      (Icons.water_rounded, colors.primaryFixed, colors.primary),
    ];
    final (icon, tint, accent) = looks[index % looks.length];
    final title = [
      l10n.milestoneRainbow,
      l10n.milestoneSunflower,
      l10n.milestoneBirdhouse,
      l10n.milestoneFountain,
    ][index % 4];

    return Semantics(
      label:
          '$title. ${unlocked ? l10n.milestoneUnlocked : l10n.milestoneLocked(days)}',
      excludeSemantics: true,
      child: AppCard(
        color: unlocked ? null : colors.surfaceContainerLow,
        elevated: unlocked,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.sm,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: unlocked
                      ? tint
                      : colors.surfaceContainerHighest,
                  child: Icon(
                    unlocked ? icon : Icons.lock_outline_rounded,
                    color: unlocked ? accent : colors.onSurfaceVariant,
                  ),
                ),
                if (unlocked)
                  EyebrowPill(
                    label: l10n.milestoneActive,
                    background: tint,
                    foreground: colors.onSurface,
                  ),
              ],
            ),
            Text(
              title,
              style: context.text.titleMedium?.copyWith(
                color: unlocked ? null : colors.onSurfaceVariant,
              ),
            ),
            Text(
              unlocked
                  ? l10n.milestoneEarned(days)
                  : l10n.milestoneLocked(days),
              style: context.text.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _serverStageName(AppLocalizations l10n, String key) => switch (key) {
  'sprout' => l10n.gardenStageSprout,
  'sapling' => l10n.gardenStageSapling,
  'young-tree' => l10n.gardenStageYoungTree,
  'blossom' => l10n.gardenStageBlossom,
  'orchard' => l10n.gardenStageOrchard,
  _ => l10n.gardenStageSeed,
};

String _itemName(AppLocalizations l10n, String key) => switch (key) {
  'first-mission' => l10n.gardenItemFirstMission,
  'mission-master' => l10n.gardenItemMissionMaster,
  'star-collector' => l10n.gardenItemStarCollector,
  'xp-climber' => l10n.gardenItemXpClimber,
  'three-day-streak' => l10n.gardenItemThreeDayStreak,
  'week-warrior' => l10n.gardenItemWeekWarrior,
  _ => l10n.gardenItemUnknown,
};

IconData _itemIcon(String key) => switch (key) {
  'first-mission' => Icons.fence_rounded,
  'mission-master' => Icons.door_front_door_outlined,
  'star-collector' => Icons.light_rounded,
  'xp-climber' => Icons.local_florist_rounded,
  'three-day-streak' => Icons.looks_rounded,
  'week-warrior' => Icons.water_drop_rounded,
  _ => Icons.eco_rounded,
};

/// Decorations unlocked by badges, and the server's garden size. Everything
/// here comes from the child's real, parent-approved progress.
class _Collection extends StatelessWidget {
  const _Collection({required this.garden});

  final Garden garden;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Column(
      key: const Key('garden.collection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm + 4,
      children: [
        SectionHeader(
          title: l10n.gardenCollection,
          icon: Icons.yard_rounded,
          trailing: Text(
            l10n.gardenCollectionCount(
              garden.unlockedCount,
              garden.items.length,
            ),
            style: context.text.labelMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          l10n.gardenServerStage(_serverStageName(l10n, garden.stageKey)),
          key: const Key('garden.serverStage'),
          style: context.text.titleMedium,
        ),
        if (garden.xpToNextStage != null)
          Text(
            l10n.gardenXpToNext(garden.xpToNextStage!),
            style: context.text.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        AdaptiveWrap(
          spacing: AppSpacing.sm,
          children: [
            for (final item in garden.items)
              Semantics(
                container: true,
                label:
                    '${_itemName(l10n, item.key)}. ${item.unlocked ? l10n.milestoneUnlocked : l10n.gardenItemLocked(item.badge)}',
                excludeSemantics: true,
                child: AppCard(
                  key: Key('garden.item.${item.key}'),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  color: item.unlocked ? null : colors.surfaceContainerLow,
                  elevated: item.unlocked,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: item.unlocked
                            ? colors.secondaryContainer
                            : colors.surfaceContainerHigh,
                        child: Icon(
                          item.unlocked
                              ? _itemIcon(item.key)
                              : Icons.lock_outline_rounded,
                          color: item.unlocked
                              ? colors.onSecondaryContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _itemName(l10n, item.key),
                        textAlign: TextAlign.center,
                        style: context.text.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        item.unlocked
                            ? l10n.milestoneUnlocked
                            : l10n.gardenItemLocked(item.badge),
                        textAlign: TextAlign.center,
                        style: context.text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
