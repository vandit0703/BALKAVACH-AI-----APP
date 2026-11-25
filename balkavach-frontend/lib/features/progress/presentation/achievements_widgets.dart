import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/gamification.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/progress_repository.dart';

/// Where the child is in their level and how far the next one is. Every number
/// is the server's (`/progress/children/{id}/achievements`). It is decoration
/// around the garden, so while loading or on failure it simply is not shown.
class LevelProgressCard extends ConsumerWidget {
  const LevelProgressCard({required this.childId, super.key});

  final String childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(achievementsProvider(childId)).value?.level;
    if (level == null || level.levelNumber == null) {
      return const SizedBox.shrink();
    }
    return LevelProgressView(level: level);
  }
}

/// The level card itself, for a [LevelProgress] the caller already has.
class LevelProgressView extends StatelessWidget {
  const LevelProgressView({required this.level, super.key});

  final LevelProgress level;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final fraction = level.fraction;
    return AppCard(
      key: const Key('level.card'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up_rounded, color: colors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  [
                    l10n.childLevel(level.levelNumber!),
                    if (level.name != null) level.name!,
                  ].join(' · '),
                  key: const Key('level.title'),
                  style: context.text.titleMedium,
                ),
              ),
            ],
          ),
          if (fraction != null)
            PillProgressBar(
              value: fraction,
              semanticsLabel: l10n.levelXpToNext(
                level.xpToNext ?? 0,
                level.nextLevelNumber ?? 0,
              ),
            ),
          Text(
            level.isTopLevel
                ? l10n.levelMaxReached
                : l10n.levelXpToNext(
                    level.xpToNext ?? 0,
                    level.nextLevelNumber ?? 0,
                  ),
            key: const Key('level.next'),
            style: context.text.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badges not earned yet, each with the server's real progress towards it
/// when the criterion is measurable. Hidden when nothing is locked, while
/// loading, or when the list cannot be loaded.
class LockedBadgesSection extends ConsumerWidget {
  const LockedBadgesSection({required this.childId, super.key});

  final String childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked =
        ref.watch(achievementsProvider(childId)).value?.locked ?? const [];
    if (locked.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const Key('badges.locked'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        SectionHeader(
          title: l10n.achievementsLockedTitle,
          icon: Icons.lock_outline_rounded,
        ),
        for (final badge in locked) LockedBadgeTile(badge: badge),
      ],
    );
  }
}

/// A parent's read-only view of one child's level and badges, from the
/// server's family-authorized `/progress/children/{id}/achievements`. It
/// calculates nothing: progress bars appear only where the server sent a
/// measurable target, and every state (loading, error, empty) is shown.
class ParentAchievementsSection extends ConsumerWidget {
  const ParentAchievementsSection({required this.childId, super.key});

  final String childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const Key('parent.achievements'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        SectionHeader(
          title: l10n.parentAchievementsTitle,
          icon: Icons.military_tech_rounded,
        ),
        switch (ref.watch(achievementsProvider(childId))) {
          AsyncData(:final value) => _content(context, l10n, value),
          AsyncError(:final error) => ErrorView(
            key: const Key('parent.achievements.error'),
            error: error,
            onRetry: () => ref.invalidate(achievementsProvider(childId)),
          ),
          _ => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ],
    );
  }

  Widget _content(
    BuildContext context,
    AppLocalizations l10n,
    Achievements data,
  ) {
    final earned = [
      for (final badge in data.badges)
        if (badge.unlocked) badge,
    ];
    final locked = data.locked;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        if (data.level.levelNumber != null)
          LevelProgressView(level: data.level)
        else
          Text(
            l10n.parentLevelUnavailable,
            key: const Key('parent.level.none'),
            style: context.text.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        if (data.badges.isEmpty)
          Text(
            l10n.parentNoBadgesDefined,
            key: const Key('parent.badges.none'),
            style: context.text.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          )
        else ...[
          Text(l10n.parentBadgesEarnedTitle, style: context.text.titleSmall),
          if (earned.isEmpty)
            Text(
              l10n.parentNoBadgesEarned,
              key: const Key('parent.badges.noneEarned'),
              style: context.text.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else
            for (final badge in earned) _EarnedBadgeTile(badge: badge),
          if (locked.isNotEmpty) ...[
            Text(l10n.achievementsLockedTitle, style: context.text.titleSmall),
            for (final badge in locked) LockedBadgeTile(badge: badge),
          ],
        ],
      ],
    );
  }
}

class _EarnedBadgeTile extends StatelessWidget {
  const _EarnedBadgeTile({required this.badge});

  final AchievementBadge badge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final description = badge.description?.trim();
    final at = badge.unlockedAt;
    return AppCard(
      key: Key('badge.earned.${badge.id}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colors.tertiaryFixed,
            child: Icon(Icons.military_tech_rounded, color: colors.tertiary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.xs,
              children: [
                Text(badge.name, style: context.text.titleSmall),
                if (description != null && description.isNotEmpty)
                  Text(
                    description,
                    style: context.text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                if (at != null)
                  Text(
                    l10n.parentBadgeEarnedOn(
                      DateFormat.yMMMd(
                        Localizations.localeOf(context).toString(),
                      ).format(at.toLocal()),
                    ),
                    style: context.text.labelMedium?.copyWith(
                      color: colors.primary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A badge the child has not earned, with real progress when measurable.
class LockedBadgeTile extends StatelessWidget {
  const LockedBadgeTile({required this.badge, super.key});

  final AchievementBadge badge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final description = badge.description?.trim();
    final fraction = badge.fraction;
    return AppCard(
      key: Key('badge.locked.${badge.id}'),
      color: colors.surfaceContainerLow,
      elevated: false,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colors.surfaceContainerHigh,
            child: Icon(
              Icons.lock_outline_rounded,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.xs,
              children: [
                Text(badge.name, style: context.text.titleSmall),
                if (description != null && description.isNotEmpty)
                  Text(
                    description,
                    style: context.text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                if (fraction != null) ...[
                  PillProgressBar(value: fraction),
                  Text(
                    l10n.achievementsProgress(
                      badge.current!.clamp(0, badge.threshold!),
                      badge.threshold!,
                    ),
                    style: context.text.labelMedium,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
