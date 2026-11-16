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
import '../../../shared/widgets/lazy_list_page.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/missions_repository.dart';
import '../domain/daily_mission_models.dart';
import '../domain/mission_models.dart';
import '../domain/mission_status.dart';
import 'mission_providers.dart';
import 'widgets/mission_card.dart';

/// Child Missions (Stitch `today_s_missions`).
class MissionsScreen extends ConsumerStatefulWidget {
  const MissionsScreen({super.key});

  @override
  ConsumerState<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends ConsumerState<MissionsScreen> {
  String? _categoryFilter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final missions = ref.watch(childMissionsProvider);

    Future<void> refresh() async {
      ref
        ..invalidate(childMissionsProvider)
        ..invalidate(childNotificationsProvider)
        ..invalidate(taskCategoriesProvider);
      await refreshQuietly(ref.read(childMissionsProvider.future));
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: switch (missions) {
        AsyncData(:final value) => _list(context, l10n, value),
        AsyncError(:final error) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ErrorView(
              error: error,
              onRetry: () => ref.invalidate(childMissionsProvider),
            ),
          ],
        ),
        _ => const LoadingView(),
      },
    );
  }

  Widget _list(
    BuildContext context,
    AppLocalizations l10n,
    List<Mission> missions,
  ) {
    final categories =
        ref.watch(taskCategoriesProvider).value ?? const <TaskCategory>[];
    final snapshot = ref.watch(missionStatusesProvider).value;
    final byId = {for (final c in categories) c.id: c};
    final usedCategories = categories
        .where((c) => missions.any((m) => m.categoryId == c.id))
        .toList();
    final visible = _categoryFilter == null
        ? missions
        : missions.where((m) => m.categoryId == _categoryFilter).toList();

    Widget card(Mission mission) => MissionCard(
      key: Key('mission.${mission.id}'),
      mission: mission,
      category: byId[mission.categoryId],
      status: snapshot?.statusOf(mission.id) ?? MissionStatus.notStarted,
      onOpen: () => context.push(AppRoutes.childMission(mission.id)),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 2 : 1;
        // One list row holds `columns` cards, so the list stays lazy.
        final rows = (visible.length / columns).ceil();
        return LazyListPage(
          maxWidth: columns == 2 ? ContentWidth.wide : ContentWidth.list,
          header: [
            const _DailyChoices(),
            if (snapshot != null && !snapshot.reviewsAvailable)
              InlineNotice(message: l10n.reviewsUnavailable),
            if (usedCategories.isNotEmpty)
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _FilterChip(
                    label: l10n.missionsFilterAll(missions.length),
                    selected: _categoryFilter == null,
                    onTap: () => setState(() => _categoryFilter = null),
                  ),
                  for (final category in usedCategories)
                    _FilterChip(
                      label: category.name,
                      selected: _categoryFilter == category.id,
                      onTap: () =>
                          setState(() => _categoryFilter = category.id),
                    ),
                ],
              ),
            if (missions.isEmpty)
              EmptyView(message: l10n.missionsEmpty)
            else if (visible.isEmpty)
              EmptyView(message: l10n.missionsFilterEmpty),
          ],
          itemCount: rows,
          itemBuilder: (context, row) {
            final first = row * columns;
            if (columns == 1) return card(visible[first]);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.md,
              children: [
                Expanded(child: card(visible[first])),
                Expanded(
                  child: first + 1 < visible.length
                      ? card(visible[first + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            );
          },
          footer: [
            MascotBubble(
              image: AppImages.pandaMissions,
              title: l10n.pandaSays,
              message: l10n.pandaEncourage,
            ),
          ],
        );
      },
    );
  }
}

class _DailyChoices extends ConsumerStatefulWidget {
  const _DailyChoices();

  @override
  ConsumerState<_DailyChoices> createState() => _DailyChoicesState();
}

class _DailyChoicesState extends ConsumerState<_DailyChoices> {
  String? _selecting;

  Future<void> _select(String assignmentId) async {
    if (_selecting != null) return;
    setState(() => _selecting = assignmentId);
    final selected = await AsyncValue.guard<DailyMissionAssignment>(
      () => ref.read(missionsRepositoryProvider).selectDailyMission(assignmentId),
    );
    if (!mounted) return;
    setState(() => _selecting = null);
    final taskId = selected.value?.taskId;
    if (taskId != null) {
      ref.invalidate(dailyMissionChoicesProvider);
      await context.push(AppRoutes.childMission(taskId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = ref.watch(dailyMissionChoicesProvider);
    return switch (choices) {
      AsyncData(value: final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppLocalizations.of(context).missionsTitle,
            style: context.text.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final choice in value.choices)
                SizedBox(
                  width: 280,
                  child: AppCard(
                    color: choice.content.isSurprise
                        ? context.colors.tertiaryContainer
                        : context.colors.surfaceContainerLow,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          choice.content.isSurprise
                              ? Icons.auto_awesome_rounded
                              : Icons.explore_rounded,
                          color: context.colors.primary,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          choice.content.title,
                          style: context.text.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(choice.content.description),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          AppLocalizations.of(context).missionEarn(
                            choice.content.starReward,
                          ),
                          style: context.text.labelLarge,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        PrimaryButton(
                          label: AppLocalizations.of(context).missionStartMission,
                          icon: Icons.play_arrow_rounded,
                          loading: _selecting == choice.id,
                          onPressed: choice.isSelectable
                              ? () => _select(choice.id)
                              : choice.taskId == null
                              ? null
                              : () async => context.push(
                                AppRoutes.childMission(choice.taskId!),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      labelStyle: context.text.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: selected ? context.colors.onPrimary : context.colors.onSurface,
      ),
    );
  }
}
