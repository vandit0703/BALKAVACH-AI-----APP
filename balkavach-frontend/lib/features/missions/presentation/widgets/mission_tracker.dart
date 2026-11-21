import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/daily_mission_models.dart';
import '../../domain/mission_status.dart';

/// How far a mission is along "Start -> Sent -> Done", from real statuses:
/// 0 nothing yet, 1 started, 2 sent to a parent, 3 approved.
int missionStage({MissionStatus? status, String? assignmentStatus}) {
  if (status == MissionStatus.approved || assignmentStatus == 'approved') {
    return 3;
  }
  if (status == MissionStatus.pending ||
      assignmentStatus == 'pending_parent_approval') {
    return 2;
  }
  // A reviewed-but-not-approved attempt, or a started daily mission, is past
  // the start but has nothing waiting with a parent.
  if (status == MissionStatus.rejected ||
      status == MissionStatus.resubmissionRequested ||
      assignmentStatus == 'in_progress' ||
      assignmentStatus == 'rejected') {
    return 1;
  }
  return 0;
}

/// The stage of a daily assignment on its own (no task status known).
int assignmentStage(DailyMissionAssignment a) =>
    missionStage(assignmentStatus: a.status);

/// Three-step progress: Start, Sent, Done.
class MissionTracker extends StatelessWidget {
  const MissionTracker({required this.stage, this.compact = false, super.key});

  /// 0..3, see [missionStage].
  final int stage;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final labels = [
      l10n.missionTrackStart,
      l10n.missionTrackSent,
      l10n.missionTrackDone,
    ];
    final dot = compact ? 26.0 : 34.0;

    Widget step(int i) {
      final done = stage > i;
      final current = stage == i;
      final fill = done
          ? colors.secondary
          : current
          ? colors.primary
          : colors.surfaceContainerHighest;
      final fg = done || current ? colors.onPrimary : colors.onSurfaceVariant;
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: i == 0
                      ? const SizedBox.shrink()
                      : Container(
                          height: 4,
                          color: stage >= i
                              ? colors.secondary
                              : colors.surfaceContainerHighest,
                        ),
                ),
                Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: done
                      ? Icon(Icons.check_rounded, size: dot * 0.6, color: fg)
                      : Text(
                          '${i + 1}',
                          style: context.text.labelLarge?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                Expanded(
                  child: i == labels.length - 1
                      ? const SizedBox.shrink()
                      : Container(
                          height: 4,
                          color: stage >= i + 1
                              ? colors.secondary
                              : colors.surfaceContainerHighest,
                        ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              labels[i],
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium?.copyWith(
                fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                color: done || current
                    ? colors.onSurface
                    : colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      label: labels
          .asMap()
          .entries
          .map((e) => '${e.value}${stage > e.key ? ' ✓' : ''}')
          .join(', '),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (var i = 0; i < 3; i++) step(i)],
      ),
    );
  }
}
