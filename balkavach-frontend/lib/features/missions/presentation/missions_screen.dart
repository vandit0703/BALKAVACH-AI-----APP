import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/async/refresh_quietly.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gamification.dart';
import '../../../shared/widgets/lazy_list_page.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../companion/domain/companion_director.dart';
import '../../companion/presentation/panda_companion.dart';
import '../../progress/data/progress_repository.dart';
import '../data/missions_repository.dart';
import '../domain/daily_mission_models.dart';
import '../domain/mission_models.dart';
import '../domain/mission_status.dart';
import 'mission_providers.dart';
import 'widgets/mission_card.dart';
import 'widgets/mission_motion.dart';
import 'widgets/mission_tracker.dart';
import 'widgets/mission_visuals.dart';

/// Child Missions: today's progress, missions to continue, today's choices,
/// the child's other missions, and completed ones. Everything shown comes from
/// the server: missions from `/tasks` and `/daily-missions`, statuses from the
/// child's submissions, and today's totals from `/progress` (the day row the
/// server writes when a mission is approved).
class MissionsScreen extends ConsumerStatefulWidget {
  const MissionsScreen({super.key});

  @override
  ConsumerState<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends ConsumerState<MissionsScreen> {
  String? _categoryFilter;

  Future<void> _refresh() async {
    final childId = ref.read(activeChildIdProvider);
    ref
      ..invalidate(childMissionsProvider)
      ..invalidate(childNotificationsProvider)
      ..invalidate(unfinishedMissionsProvider)
      ..invalidate(dailyMissionChoicesProvider)
      ..invalidate(mySubmissionsProvider)
      ..invalidate(taskCategoriesProvider);
    if (childId != null) ref.invalidate(childProgressProvider(childId));
    await refreshQuietly(ref.read(childMissionsProvider.future));
  }

  @override
  Widget build(BuildContext context) {
    final missions = ref.watch(childMissionsProvider);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: switch (missions) {
        AsyncData(:final value) => _content(context, value),
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

  Widget _content(BuildContext context, List<Mission> allMissions) {
    final l10n = AppLocalizations.of(context);
    final unfinished = [
      for (final a
          in ref.watch(unfinishedMissionsProvider).value ??
              const <DailyMissionAssignment>[])
        if (a.taskId != null) a,
    ];
    final today = ref.watch(dailyMissionChoicesProvider).value;
    // A chosen daily mission is shown on its own card (today's choice or
    // "continue"), so it is not repeated in the general list.
    final linkedTaskIds = {
      for (final a in unfinished) a.taskId!,
      for (final c in today?.choices ?? const <DailyMissionAssignment>[])
        if (c.taskId != null) c.taskId!,
    };
    final categories =
        ref.watch(taskCategoriesProvider).value ?? const <TaskCategory>[];
    final byId = {for (final c in categories) c.id: c};
    final snapshot = ref.watch(missionStatusesProvider).value;
    MissionStatus statusOf(Mission m) =>
        snapshot?.statusOf(m.id) ?? MissionStatus.notStarted;

    final listed = [
      for (final m in allMissions)
        if (!linkedTaskIds.contains(m.id)) m,
    ];
    final usedCategories = categories
        .where((c) => listed.any((m) => m.categoryId == c.id))
        .toList();
    bool inFilter(Mission m) =>
        _categoryFilter == null || m.categoryId == _categoryFilter;
    final active = [
      for (final m in listed)
        if (statusOf(m) != MissionStatus.approved && inFilter(m)) m,
    ];
    final completed = [
      for (final m in listed)
        if (statusOf(m) == MissionStatus.approved && inFilter(m)) m,
    ];

    // What each approved mission actually earned (newest approved attempt).
    final earned = <String, TaskSubmission>{};
    for (final s
        in ref.watch(mySubmissionsProvider).value ?? const <TaskSubmission>[]) {
      if (s.status != 'approved') continue;
      final seen = earned[s.taskId];
      if (seen == null || s.submissionNumber > seen.submissionNumber) {
        earned[s.taskId] = s;
      }
    }

    // Still to do: every mission not yet approved, plus today's daily mission
    // when none has been chosen yet.
    final open =
        allMissions.where((m) => statusOf(m) != MissionStatus.approved).length +
        (today != null &&
                today.selectedAssignmentId == null &&
                today.choices.any((c) => c.isSelectable)
            ? 1
            : 0);

    Widget card(Mission mission) {
      final attempt = earned[mission.id];
      return MissionCard(
        key: Key('mission.${mission.id}'),
        mission: mission,
        category: byId[mission.categoryId],
        status: statusOf(mission),
        starsEarned: attempt?.starsAwarded,
        xpEarned: attempt?.xpAwarded,
        onOpen: () => context.push(AppRoutes.childMission(mission.id)),
      );
    }

    final nothingAtAll =
        allMissions.isEmpty &&
        unfinished.isEmpty &&
        (today?.choices.isEmpty ?? true);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 2 : 1;
        // Lazy rows: section titles and rows of `columns` cards.
        final rows = <Widget Function(BuildContext)>[];
        void section(
          List<Mission> items, {
          required String title,
          required IconData icon,
          required Key key,
        }) {
          if (items.isEmpty) return;
          rows.add(
            (_) => _SectionTitle(
              key: key,
              title: title,
              icon: icon,
              count: items.length,
            ),
          );
          for (var i = 0; i < items.length; i += columns) {
            final first = i;
            rows.add((_) {
              Widget cell(int index) =>
                  EntranceFade(index: index - first, child: card(items[index]));
              if (columns == 1) return cell(first);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.md,
                children: [
                  Expanded(child: cell(first)),
                  Expanded(
                    child: first + 1 < items.length
                        ? cell(first + 1)
                        : const SizedBox.shrink(),
                  ),
                ],
              );
            });
          }
        }

        section(
          active,
          title: l10n.missionsForYouTitle,
          icon: Icons.rocket_launch_rounded,
          key: const Key('missions.forYou'),
        );
        section(
          completed,
          title: l10n.missionsCompletedTitle,
          icon: Icons.emoji_events_rounded,
          key: const Key('missions.completed'),
        );

        return LazyListPage(
          maxWidth: columns == 2 ? ContentWidth.wide : ContentWidth.list,
          spacing: AppSpacing.md,
          // One header block, built as a whole: it is short (at most three
          // daily choices and 20 unfinished missions), and every choice must
          // exist even on a small screen with large text. The long lists below
          // stay lazy.
          header: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.md,
              children: [
                _MissionsHeader(
                  open: open,
                  showPanda: allMissions.isNotEmpty || unfinished.isNotEmpty,
                ),
                if (snapshot != null && !snapshot.reviewsAvailable)
                  InlineNotice(message: l10n.reviewsUnavailable),
                // Missions the child already chose come first: they are
                // commitments, and today's menu below is always there.
                const _UnfinishedMissions(),
                const _DailyChoices(),
                if (usedCategories.isNotEmpty)
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      _FilterChip(
                        label: l10n.missionsFilterAll(listed.length),
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
                if (nothingAtAll)
                  EmptyView(message: l10n.missionsEmpty)
                else if (listed.isNotEmpty &&
                    active.isEmpty &&
                    completed.isEmpty)
                  EmptyView(message: l10n.missionsFilterEmpty),
              ],
            ),
          ],
          itemCount: rows.length,
          itemBuilder: (context, index) => rows[index](context),
        );
      },
    );
  }
}

/// "Ready for an adventure?" with today's real totals: missions approved
/// today and the stars and XP they earned (the server's day row for the
/// family-local date), and a bar of done against still-to-do.
class _MissionsHeader extends ConsumerWidget {
  const _MissionsHeader({required this.open, required this.showPanda});

  /// Missions still to do (not approved yet).
  final int open;

  /// Panda's "missions are ready" line (only when there are missions).
  final bool showPanda;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final childId = ref.watch(activeChildIdProvider);
    final progress = childId == null
        ? null
        : ref.watch(childProgressProvider(childId)).value;
    // The family-local "today" as the server computes it; the device's date
    // only until the daily missions have loaded.
    final localDate =
        ref.watch(dailyMissionChoicesProvider).value?.localDate ??
        ref.watch(clockProvider)();
    ActivityDay? day;
    for (final d in progress?.activityDays ?? const <ActivityDay>[]) {
      if (d.date.year == localDate.year &&
          d.date.month == localDate.month &&
          d.date.day == localDate.day) {
        day = d;
      }
    }
    final done = day?.completedTasks ?? 0;
    final total = done + open;
    final message = total == 0
        ? null
        : done == 0
        ? l10n.missionsProgressStart
        : open == 0
        ? l10n.missionsProgressAllDone
        : l10n.missionsProgressKeepGoing;

    final progressBlock = message == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  Text(
                    message,
                    style: context.text.titleSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    l10n.missionsDone(done, total),
                    style: context.text.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              AnimatedPillProgress(
                value: done / total,
                color: colors.secondary,
                background: colors.surfaceContainerHighest,
                semanticsLabel: l10n.missionsDone(done, total),
              ),
            ],
          );
    final stats = progress == null
        ? null
        : Row(
            spacing: AppSpacing.sm,
            children: [
              Expanded(
                child: StatTile(
                  key: const Key('missions.today.done'),
                  icon: Icons.task_alt_rounded,
                  iconColor: colors.secondary,
                  value: '$done',
                  label: l10n.missionsStatDone,
                ),
              ),
              Expanded(
                child: StatTile(
                  key: const Key('missions.today.stars'),
                  icon: Icons.stars_rounded,
                  iconColor: colors.tertiary,
                  value: '${day?.starsEarned ?? 0}',
                  label: l10n.missionsStatStars,
                ),
              ),
              Expanded(
                child: StatTile(
                  key: const Key('missions.today.xp'),
                  icon: Icons.bolt_rounded,
                  iconColor: colors.primary,
                  value: '${day?.xpEarned ?? 0}',
                  label: l10n.missionsStatXp,
                ),
              ),
            ],
          );

    return Semantics(
      container: true,
      child: DecoratedBox(
        key: const Key('missions.header'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.primaryFixed, colors.surfaceContainerLowest],
          ),
          borderRadius: AppRadius.hero,
          boxShadow: AppShadows.tier1,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg - 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              // Side by side when there is room, so the missions themselves
              // start above the fold on short windows.
              final wide = constraints.maxWidth / textScale >= 560;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.missionsHeroTitle,
                      style: context.text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Panda greets the child here when there is something to
                  // do; otherwise a plain encouraging line.
                  if (showPanda)
                    const PandaCompanion(
                      event: CompanionEvent.missionsReady,
                      avatarSize: 60,
                    )
                  else
                    Text(
                      l10n.missionsHeroSubtitle,
                      style: context.text.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  if (progressBlock != null || stats != null)
                    const SizedBox(height: AppSpacing.md),
                  if (wide && progressBlock != null && stats != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      spacing: AppSpacing.lg,
                      children: [
                        Expanded(child: progressBlock),
                        Expanded(child: stats),
                      ],
                    )
                  else ...[
                    ?progressBlock,
                    if (progressBlock != null && stats != null)
                      const SizedBox(height: AppSpacing.md),
                    ?stats,
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.icon,
    this.subtitle,
    this.count,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.primary, size: 24),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Semantics(
                  header: true,
                  child: Text(title, style: context.text.headlineSmall),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: AppSpacing.sm),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    child: Text(
                      '$count',
                      style: context.text.labelLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: context.text.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lays cards out in equal-width columns that fit the available width.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.children, this.minCardWidth = 300});

  final List<Widget> children;
  final double minCardWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.md;
        final max = constraints.maxWidth;
        final columns = ((max + gap) / (minCardWidth + gap)).floor().clamp(
          1,
          3,
        );
        Widget cell(int i) => EntranceFade(index: i, child: children[i]);
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: gap,
            children: [for (var i = 0; i < children.length; i++) cell(i)],
          );
        }
        // Cards in one row share its height, so the row reads as a set.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: gap,
          children: [
            for (var start = 0; start < children.length; start += columns)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: gap,
                  children: [
                    for (var i = start; i < start + columns; i++)
                      Expanded(
                        child: i < children.length
                            ? cell(i)
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
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
      () =>
          ref.read(missionsRepositoryProvider).selectDailyMission(assignmentId),
    );
    if (!mounted) return;
    setState(() => _selecting = null);
    if (selected case AsyncError(:final error)) {
      // Never fail silently: say why, and refresh the choices (another
      // mission may have been chosen on another device).
      showErrorSnackBar(context, error);
      ref.invalidate(dailyMissionChoicesProvider);
      return;
    }
    final taskId = selected.value?.taskId;
    // Choosing created a new task on the server: the cached lists predate it.
    ref
      ..invalidate(dailyMissionChoicesProvider)
      ..invalidate(childMissionsProvider)
      ..invalidate(missionStatusesProvider);
    if (taskId == null) return;
    await refreshQuietly(ref.read(childMissionsProvider.future));
    if (!mounted) return;
    await context.push(AppRoutes.childMission(taskId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final choices = ref.watch(dailyMissionChoicesProvider);
    return switch (choices) {
      AsyncData(:final value) when value.choices.isNotEmpty => Column(
        key: const Key('missions.today'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(
            title: l10n.todaysMissions,
            subtitle: value.selectedAssignmentId == null
                ? l10n.missionsChoosePrompt
                : null,
            icon: Icons.wb_sunny_rounded,
          ),
          const SizedBox(height: AppSpacing.md),
          _CardGrid(
            minCardWidth: 260,
            children: [
              for (final choice in value.choices)
                _ChoiceCard(
                  choice: choice,
                  anotherChosen:
                      value.selectedAssignmentId != null &&
                      value.selectedAssignmentId != choice.id,
                  selecting: _selecting == choice.id,
                  onSelect: () => _select(choice.id),
                ),
            ],
          ),
        ],
      ),
      // No birth date, a wrong one, or an age outside 4-15: say what is
      // needed (a grown-up can fix the birthday); never guess an age group.
      AsyncError(error: final ApiException error)
          when const {
            'birth_date_required',
            'birth_date_invalid',
            'daily_missions_age_range',
          }.contains(error.code) =>
        InlineNotice(
          key: const Key('missions.today.notice'),
          message: describeError(l10n, error),
          icon: Icons.cake_rounded,
        ),
      // Offline or a server error: say so (with a way to retry) instead of
      // quietly leaving the section out.
      AsyncError(:final error)
          when error is NetworkException ||
              error is RequestTimeoutException ||
              error is ServerException =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.sm,
          children: [
            InlineNotice(
              message: describeError(l10n, error),
              icon: Icons.cloud_off_rounded,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SecondaryButton(
                key: const Key('missions.today.retry'),
                label: l10n.retry,
                icon: Icons.refresh_rounded,
                onPressed: () => ref.invalidate(dailyMissionChoicesProvider),
              ),
            ),
          ],
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// One of today's daily choices, drawn from its real status:
/// * `available`: Start Mission (chooses it), or nothing to do when another
///   mission was already chosen today (the server allows one a day);
/// * `selected` / `in_progress` / `rejected`: Continue (opens the same task);
/// * `pending_parent_approval`: waiting for a parent;
/// * `approved`: done, with what it earned.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.choice,
    required this.anotherChosen,
    required this.selecting,
    required this.onSelect,
  });

  final DailyMissionAssignment choice;
  final bool anotherChosen;
  final bool selecting;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final content = choice.content;
    final taskId = choice.taskId;
    void open() => context.push(AppRoutes.childMission(taskId!));

    final approved = choice.status == 'approved';
    final pending = choice.status == 'pending_parent_approval';
    final inPlay =
        taskId != null &&
        const {'selected', 'in_progress', 'rejected'}.contains(choice.status);
    final muted = choice.isSelectable && anotherChosen;

    final visual = _choiceVisual(context, content);
    final Widget? chip = approved
        ? missionStatusChip(context, MissionStatus.approved)
        : pending
        ? missionStatusChip(context, MissionStatus.pending)
        : choice.status == 'rejected'
        ? missionStatusChip(context, MissionStatus.rejected)
        : null;

    final Widget? action = choice.isSelectable && !anotherChosen
        ? PrimaryButton(
            key: Key('missions.choice.start.${choice.id}'),
            label: l10n.missionStartMission,
            icon: Icons.play_arrow_rounded,
            loading: selecting,
            onPressed: onSelect,
          )
        : inPlay
        ? PrimaryButton(
            key: Key('missions.choice.open.${choice.id}'),
            label: l10n.missionContinue,
            icon: Icons.play_arrow_rounded,
            onPressed: open,
          )
        : pending && taskId != null
        ? SecondaryButton(
            key: Key('missions.choice.open.${choice.id}'),
            label: l10n.missionWaitingButton,
            icon: Icons.hourglass_top_rounded,
            onPressed: open,
          )
        : null;

    return AppCard(
      color: muted
          ? colors.surfaceContainerLow
          : approved
          ? colors.surfaceContainerLow
          : null,
      elevated: !muted && !approved,
      onTap: taskId != null && (approved || pending || inPlay) ? open : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (approved)
                const CelebrationPop(child: CompletedBadge(size: 52))
              else
                CategoryTile(visual: visual, size: 52),
              const SizedBox(width: AppSpacing.sm),
              if (content.durationMinutes > 0)
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: EyebrowPill(
                      label: l10n.missionMinutes(content.durationMinutes),
                      icon: Icons.schedule_rounded,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(content.childTitle, style: context.text.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            content.description,
            style: context.text.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ?chip,
              ...missionRewardPills(
                context,
                content.starReward,
                content.xpReward,
              ),
            ],
          ),
          if (muted) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.missionsChoiceTaken,
              style: context.text.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            action,
          ],
        ],
      ),
    );
  }
}

/// Icon and tint for a daily mission, from its kind (the daily catalogue has
/// no task category).
CategoryVisual _choiceVisual(BuildContext context, DailyMissionContent c) {
  final colors = context.colors;
  final brand = context.brand;
  if (c.isSurprise) {
    return CategoryVisual(
      Icons.auto_awesome_rounded,
      colors.tertiaryFixed,
      colors.tertiary,
    );
  }
  return switch (c.missionType) {
    'creative' => CategoryVisual(
      Icons.palette_rounded,
      brand.createTint,
      colors.primary,
    ),
    'interactive' => CategoryVisual(
      Icons.extension_rounded,
      brand.moveTint,
      colors.onSecondaryContainer,
    ),
    _ => CategoryVisual(Icons.explore_rounded, brand.learnTint, colors.primary),
  };
}

/// Missions chosen on an earlier day and not finished. They keep their task,
/// submissions and status, so "Continue" opens the same mission: nothing is
/// selected or created again, and finishing it uses the usual submission and
/// parent-approval flow.
class _UnfinishedMissions extends ConsumerWidget {
  const _UnfinishedMissions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final older =
        ref.watch(unfinishedMissionsProvider).value ??
        const <DailyMissionAssignment>[];
    final openable = [
      for (final a in older)
        if (a.taskId != null) a,
    ];
    if (openable.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final snapshot = ref.watch(missionStatusesProvider).value;

    return Column(
      key: const Key('missions.unfinished'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: l10n.missionsUnfinishedTitle,
          subtitle: l10n.missionsUnfinishedSubtitle,
          icon: Icons.replay_rounded,
          count: openable.length,
        ),
        const SizedBox(height: AppSpacing.md),
        _CardGrid(
          children: [
            for (final mission in openable)
              Builder(
                builder: (context) {
                  final status = snapshot?.statusOf(mission.taskId!);
                  final stage = missionStage(
                    status: status,
                    assignmentStatus: mission.status,
                  );
                  final chip = mission.status == 'rejected'
                      ? missionStatusChip(context, MissionStatus.rejected)
                      : status == null
                      ? null
                      : missionStatusChip(context, status);
                  return AppCard(
                    color: Color.alphaBlend(
                      colors.tertiaryFixed.withValues(alpha: 0.28),
                      colors.surfaceContainerLowest,
                    ),
                    onTap: () =>
                        context.push(AppRoutes.childMission(mission.taskId!)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.missionFromDay(
                            DateFormat.MMMd(locale).format(mission.localDate),
                          ),
                          style: context.text.labelLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          mission.content.childTitle,
                          style: context.text.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        MissionTracker(stage: stage, compact: true),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ?chip,
                            ...missionRewardPills(
                              context,
                              mission.content.starReward,
                              mission.content.xpReward,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: PrimaryButton(
                            key: Key('missions.unfinished.open.${mission.id}'),
                            label: l10n.missionContinue,
                            icon: Icons.play_arrow_rounded,
                            onPressed: () => context.push(
                              AppRoutes.childMission(mission.taskId!),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
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
