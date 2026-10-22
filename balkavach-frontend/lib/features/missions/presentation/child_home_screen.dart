import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/async/refresh_quietly.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gamification.dart';
import '../../../shared/widgets/illustration.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../child_profile/presentation/family_providers.dart';
import '../../progress/data/progress_repository.dart';
import '../domain/mission_models.dart';
import '../domain/mission_status.dart';
import 'mission_providers.dart';
import 'widgets/mission_visuals.dart';

/// The dashboard (Stitch `child_home_dashboard`). Only real data is shown:
/// stars, streak, XP and level come from `/progress`; missions from `/tasks`.
/// The garden card and quest-hub tiles are omitted until those APIs exist (B9).
///
/// This lived on Home until Home became the curated video experience; it is now
/// the body of Profile. It stays here, beside the mission providers it reads,
/// and `trailing` lets Profile add its own cards below it.
class ChildDashboard extends ConsumerWidget {
  const ChildDashboard({this.trailing = const [], super.key});

  /// Extra cards appended under the dashboard.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childId = ref.watch(activeChildIdProvider);
    final session = ref.watch(sessionControllerProvider).value;
    if (childId == null || session == null) return const LoadingView();

    Future<void> refresh() async {
      ref
        ..invalidate(childProgressProvider(childId))
        ..invalidate(childMissionsProvider)
        ..invalidate(childNotificationsProvider);
      await refreshQuietly(ref.read(childMissionsProvider.future));
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ResponsiveContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.md,
              children: [
                _Greeting(childId: childId, name: session.user.fullName),
                _StatsDock(childId: childId),
                const _TodayCard(),
                ...trailing,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting({required this.childId, required this.name});

  final String childId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final avatar = ref.watch(childAvatarProvider(childId));
    final level = ref.watch(childProgressProvider(childId)).value?.levelNumber;
    final levelName = ref
        .watch(childProgressProvider(childId))
        .value
        ?.levelName;

    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ChildAvatar(name: name, option: avatar, size: 72),
            if (level != null)
              Positioned(
                right: -4,
                bottom: -4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.tertiaryFixed,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Text(
                      l10n.childLevel(level),
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.onTertiaryFixed,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l10n.childHello(name)} 👋',
                style: context.text.headlineMedium,
              ),
              Text(
                levelName == null
                    ? l10n.childQuestReady
                    : l10n.childLevelName(levelName),
                style: context.text.labelLarge?.copyWith(
                  color: context.colors.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsDock extends ConsumerWidget {
  const _StatsDock({required this.childId});

  final String childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final progress = ref.watch(childProgressProvider(childId));
    return switch (progress) {
      AsyncData(:final value) => AppCard(
        padding: const EdgeInsets.all(6),
        radius: BorderRadius.circular(AppRadius.lg),
        child: Row(
          spacing: AppSpacing.xs,
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.stars_rounded,
                iconColor: context.colors.tertiary,
                value: '${value.starBalance}',
                label: l10n.statStars,
              ),
            ),
            Expanded(
              child: StatTile(
                icon: Icons.local_fire_department_rounded,
                iconColor: context.colors.tertiaryFixedDim,
                value: l10n.statStreakValue(value.currentStreak),
                label: l10n.statStreak,
              ),
            ),
            Expanded(
              child: StatTile(
                icon: Icons.bolt_rounded,
                iconColor: context.colors.primary,
                value: '${value.totalXp}',
                label: l10n.statXp,
              ),
            ),
          ],
        ),
      ),
      AsyncError(:final error) => AppCard(
        child: ErrorView(
          error: error,
          onRetry: () => ref.invalidate(childProgressProvider(childId)),
        ),
      ),
      _ => const AppCard(child: LoadingView()),
    };
  }
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final missions = ref.watch(childMissionsProvider);
    final statuses = ref.watch(missionStatusesProvider).value;
    final categories =
        ref.watch(taskCategoriesProvider).value ?? const <TaskCategory>[];

    return switch (missions) {
      AsyncData(:final value) => _content(
        context,
        l10n,
        value,
        statuses,
        categories,
      ),
      AsyncError(:final error) => AppCard(
        child: ErrorView(
          error: error,
          onRetry: () => ref.invalidate(childMissionsProvider),
        ),
      ),
      _ => const AppCard(child: LoadingView()),
    };
  }

  Widget _content(
    BuildContext context,
    AppLocalizations l10n,
    List<Mission> missions,
    MissionStatusSnapshot? statuses,
    List<TaskCategory> categories,
  ) {
    MissionStatus statusOf(Mission m) =>
        statuses?.statusOf(m.id) ?? MissionStatus.notStarted;
    final done = missions
        .where((m) => statusOf(m) == MissionStatus.approved)
        .length;
    final todo = missions.where((m) {
      final s = statusOf(m);
      return s == MissionStatus.notStarted ||
          s == MissionStatus.resubmissionRequested;
    }).toList();
    final total = missions.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.md,
      children: [
        MascotBubble(
          image: AppImages.pandaHoodie,
          title: l10n.mascotReady,
          message: l10n.mascotMissionsLeft(todo.length),
        ),
        if (statuses != null && !statuses.reviewsAvailable)
          InlineNotice(message: l10n.reviewsUnavailable),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.md,
            children: [
              SectionHeader(
                title: l10n.todaysMissions,
                trailing: total == 0
                    ? null
                    : EyebrowPill(label: l10n.missionsDone(done, total)),
              ),
              if (total == 0)
                EmptyView(message: l10n.missionsEmpty)
              else ...[
                PillProgressBar(
                  value: done / total,
                  semanticsLabel: l10n.missionsDone(done, total),
                ),
                for (final mission in todo.take(2))
                  _NextMissionRow(
                    mission: mission,
                    category: categories
                        .where((c) => c.id == mission.categoryId)
                        .firstOrNull,
                  ),
                SecondaryButton(
                  label: l10n.missionsSeeAll,
                  icon: Icons.rocket_launch_rounded,
                  onPressed: () => context.go(AppRoutes.childMissions),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NextMissionRow extends StatelessWidget {
  const _NextMissionRow({required this.mission, required this.category});

  final Mission mission;
  final TaskCategory? category;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = Row(
      children: [
        CategoryIcon(visual: CategoryVisual.of(context, category), size: 48),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mission.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleMedium,
              ),
              const SizedBox(height: 4),
              StarPill(count: mission.starReward, prefix: '+'),
            ],
          ),
        ),
      ],
    );
    final start = PrimaryButton(
      label: l10n.missionStart,
      onPressed: () => context.push(AppRoutes.childMission(mission.id)),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Inline "Start" as in Stitch when there is room; otherwise the
            // button moves under the title (small phones, large text).
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            if (constraints.maxWidth / textScale >= 300) {
              return Row(
                children: [
                  Expanded(child: summary),
                  const SizedBox(width: AppSpacing.sm),
                  start,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.sm + 4,
              children: [summary, start],
            );
          },
        ),
      ),
    );
  }
}
