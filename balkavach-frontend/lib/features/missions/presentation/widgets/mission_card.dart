import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/gamification.dart';
import '../../domain/mission_models.dart';
import '../../domain/mission_status.dart';
import 'mission_motion.dart';
import 'mission_visuals.dart';

/// One mission (a backend task) in "Missions for You" or "Completed".
///
/// What it shows is what the server says: the reward is the task's
/// `star_reward` / `xp_reward` (the standard reward the backend pays), and a
/// completed card shows what the approval actually earned when the server
/// reports it ([starsEarned] / [xpEarned]). An approved mission offers no
/// "do it again": the server refuses a second submission of a one-time task.
class MissionCard extends StatelessWidget {
  const MissionCard({
    required this.mission,
    required this.category,
    required this.status,
    required this.onOpen,
    this.starsEarned,
    this.xpEarned,
    super.key,
  });

  final Mission mission;
  final TaskCategory? category;
  final MissionStatus status;
  final VoidCallback onOpen;
  final int? starsEarned;
  final int? xpEarned;

  bool get _completed => status == MissionStatus.approved;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final visual = CategoryVisual.of(context, category);
    final chip = missionStatusChip(context, status);
    final summary = missionSummary(mission.description);

    final action = switch (status) {
      MissionStatus.notStarted => l10n.missionStartMission,
      MissionStatus.rejected ||
      MissionStatus.resubmissionRequested => l10n.missionDoAgain,
      // Waiting for a parent, or done: the card itself still opens.
      MissionStatus.pending || MissionStatus.approved => null,
    };

    final rewards = _completed
        ? (starsEarned == null
              ? const <Widget>[]
              : [
                  StarPill(
                    count: starsEarned!,
                    label: l10n.missionsStarsEarned(starsEarned!),
                  ),
                  if ((xpEarned ?? 0) > 0)
                    XpPill(label: l10n.missionXpCount(xpEarned!)),
                ])
        : missionRewardPills(context, mission.starReward, mission.xpReward);

    return AppCard(
      onTap: onOpen,
      semanticLabel: mission.childTitle,
      color: _completed ? colors.surfaceContainerLow : null,
      elevated: !_completed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_completed)
                const CelebrationPop(child: CompletedBadge())
              else
                CategoryTile(visual: visual),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (category != null)
                      Text(
                        category!.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          color: visual.labelColor,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    Text(
                      mission.childTitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleLarge,
                    ),
                    if (summary != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (rewards.isNotEmpty || chip != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [?chip, ...rewards],
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: PrimaryButton(
                label: action,
                trailingIcon: Icons.rocket_launch_rounded,
                onPressed: onOpen,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
