import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/gamification.dart';
import '../../domain/mission_models.dart';
import '../../domain/mission_status.dart';
import 'mission_visuals.dart';

/// One row in "Today's Missions" (Stitch `today_s_missions`).
class MissionCard extends StatelessWidget {
  const MissionCard({
    required this.mission,
    required this.category,
    required this.status,
    required this.onOpen,
    super.key,
  });

  final Mission mission;
  final TaskCategory? category;
  final MissionStatus status;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visual = CategoryVisual.of(context, category);
    final chip = missionStatusChip(context, status);

    return AppCard(
      onTap: onOpen,
      semanticLabel: mission.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CategoryIcon(visual: visual),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mission.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleLarge,
                    ),
                    if (category != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        category!.name,
                        style: context.text.labelLarge?.copyWith(
                          color: visual.iconColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StarPill(count: mission.starReward),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              ?chip,
              if (status != MissionStatus.pending)
                PrimaryButton(
                  label: status.isReviewed
                      ? l10n.missionDoAgain
                      : l10n.missionStartMission,
                  trailingIcon: Icons.rocket_launch_rounded,
                  onPressed: onOpen,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
