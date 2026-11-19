import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../learning/data/video_feed_repository.dart';

int _minutes(int seconds) => (seconds / 60).floor();

/// Parent's read-only view of today's video time for one child.
///
/// Nothing here is calculated on the device: earned, watched, left, the cap
/// and the missions that earned time are all what the server returned.
class ParentVideoSummaryCard extends ConsumerWidget {
  const ParentVideoSummaryCard({required this.childId, super.key});

  final String childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summary = ref.watch(parentVideoSummaryProvider(childId));
    return AppCard(
      key: const Key('parent.videoSummary'),
      child: switch (summary) {
        AsyncData(:final value) => _Body(summary: value),
        AsyncError() => Row(
          children: [
            Expanded(child: Text(l10n.parentVideoSummaryFailed)),
            TextButton(
              key: const Key('parent.videoSummary.retry'),
              onPressed: () =>
                  ref.invalidate(parentVideoSummaryProvider(childId)),
              child: Text(l10n.videoRetry),
            ),
          ],
        ),
        _ => const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Center(child: CircularProgressIndicator()),
        ),
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.summary});

  final VideoAllowanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allowance = summary.allowance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        Text(l10n.parentVideoSummaryTitle, style: context.text.titleMedium),
        Row(
          children: [
            _Figure(
              key: const Key('parent.videoSummary.earned'),
              label: l10n.parentVideoEarned,
              minutes: _minutes(allowance.totalEarnedTodaySeconds),
            ),
            _Figure(
              key: const Key('parent.videoSummary.watched'),
              label: l10n.parentVideoWatched,
              minutes: _minutes(allowance.consumedTodaySeconds),
            ),
            _Figure(
              key: const Key('parent.videoSummary.left'),
              label: l10n.parentVideoLeft,
              minutes: _minutes(allowance.remainingSeconds),
            ),
          ],
        ),
        Text(
          l10n.parentVideoCap(_minutes(allowance.dailyCapSeconds)),
          style: context.text.bodySmall,
        ),
        Text(
          l10n.parentVideoFree(_minutes(summary.freeAllowanceSeconds)),
          style: context.text.bodySmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.parentVideoMissionsTitle, style: context.text.titleSmall),
        if (summary.rewards.isEmpty)
          Text(
            l10n.parentVideoNoMissions,
            key: const Key('parent.videoSummary.noMissions'),
          )
        else
          for (final reward in summary.rewards)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reward.taskTitle ?? '—'),
                Text(
                  l10n.parentVideoMissionUsed(
                    _minutes(reward.consumedSeconds),
                    _minutes(reward.grantedSeconds),
                  ),
                  style: context.text.bodySmall,
                ),
              ],
            ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.minutes, super.key});

  final String label;
  final int minutes;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text('$minutes', style: context.text.headlineSmall),
        Text(label, style: context.text.bodySmall),
      ],
    ),
  );
}
