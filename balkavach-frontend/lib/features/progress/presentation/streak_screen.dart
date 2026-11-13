import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/async/refresh_quietly.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/presentation/session_controller.dart';
import '../data/progress_repository.dart';
import 'streak_card.dart';

/// Full screen streak view displaying current streak metrics, grace period countdown,
/// and weekly activity calendar.
class StreakScreen extends ConsumerWidget {
  const StreakScreen({required this.childId, super.key});

  final String childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final streakAsync = ref.watch(streakInfoProvider(childId));
    final progressAsync = ref.watch(childProgressProvider(childId));
    final today = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.streakTitle),
      ),
      body: switch ((streakAsync, progressAsync)) {
        (AsyncError(:final error), _) => ErrorView(
            error: error,
            onRetry: () {
              ref.invalidate(streakInfoProvider(childId));
              ref.invalidate(childProgressProvider(childId));
            },
          ),
        (_, AsyncError(:final error)) => ErrorView(
            error: error,
            onRetry: () {
              ref.invalidate(streakInfoProvider(childId));
              ref.invalidate(childProgressProvider(childId));
            },
          ),
        (
          AsyncData(value: final StreakInfo streak),
          AsyncData(value: final ChildProgress progress)
        ) =>
          RefreshIndicator(
            onRefresh: () async {
              ref
                ..invalidate(streakInfoProvider(childId))
                ..invalidate(childProgressProvider(childId));
              await Future.wait([
                refreshQuietly(ref.read(streakInfoProvider(childId).future)),
                refreshQuietly(ref.read(childProgressProvider(childId).future)),
              ]);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                ResponsiveContent(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StreakCard(
                          streakInfo: streak,
                          activityDays: progress.activityDays,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _StreakWeeklyActivityCard(
                          progress: progress,
                          today: today,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        _ => const LoadingView(),
      },
    );
  }
}

/// Adapts the weekly activity chart from weekly report to show the 7-day bar breakdown.
class _StreakWeeklyActivityCard extends StatelessWidget {
  const _StreakWeeklyActivityCard({
    required this.progress,
    required this.today,
  });

  final ChildProgress progress;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dayFormat = DateFormat.E(locale);

    final week = progress.week(today);
    final maxCount = week.fold<int>(
      0,
      (max, d) => d.completedTasks > max ? d.completedTasks : max,
    );
    final best = maxCount == 0
        ? null
        : week.lastWhere((d) => d.completedTasks == maxCount);

    return AppCard(
      radius: AppRadius.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: l10n.reportsChartTitle),
          Text(
            l10n.reportsChartSubtitle,
            style: context.text.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in week)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${day.completedTasks}',
                        style: context.text.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: day.completedTasks == 0
                              ? colors.onSurfaceVariant
                              : colors.primary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      SizedBox(
                        height: 100,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: maxCount == 0
                                ? 0.08
                                : (day.completedTasks / maxCount)
                                    .clamp(0.08, 1.0),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: day == best
                                    ? colors.secondary
                                    : (day.completedTasks > 0
                                        ? colors.primary
                                        : colors.surfaceContainerHigh),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        dayFormat.format(day.date),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(Icons.emoji_events_rounded, color: colors.secondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      best == null
                          ? l10n.reportsNoActivity
                          : l10n.reportsBestDay(
                              DateFormat.EEEE(locale).format(best.date),
                              best.completedTasks,
                            ),
                      style: context.text.labelLarge,
                    ),
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
