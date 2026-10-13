import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/async/refresh_quietly.dart';
import '../../../shared/platform/text_sharer.dart';
import '../../../shared/widgets/adaptive_wrap.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/brand_header.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/illustration.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../child_profile/domain/family_models.dart';
import '../../child_profile/presentation/family_providers.dart';
import '../data/progress_repository.dart';

/// Parent Overview / weekly report (Stitch `parent_dashboard_reports`).
///
/// Every number comes from `GET /progress/children/{id}`, which only counts
/// parent-approved missions. Reading hours and the habit-area split from the
/// design are not tracked by the backend and are not shown; the PDF export
/// is replaced by copying a text summary.
class WeeklyReportScreen extends ConsumerStatefulWidget {
  const WeeklyReportScreen({this.initialChildId, super.key});

  final String? initialChildId;

  @override
  ConsumerState<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends ConsumerState<WeeklyReportScreen> {
  late String? _childId = widget.initialChildId;
  int _weeksBack = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final family = ref.watch(currentFamilyProvider);
    return Scaffold(
      appBar: AppBar(title: BrandTitle(title: l10n.reportsAppBar)),
      body: switch (family) {
        AsyncData(value: final f?) => _body(context, l10n, f.id),
        AsyncData() => EmptyView(message: l10n.familyMissing),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(currentFamilyProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, String familyId) {
    final children = ref.watch(familyChildrenProvider(familyId));
    return switch (children) {
      AsyncData(:final value) when value.isEmpty => EmptyView(
        message: l10n.childrenEmpty,
        action: SecondaryButton(
          label: l10n.childrenAdd,
          icon: Icons.person_add_alt_1_rounded,
          onPressed: () => context.push(AppRoutes.parentNewChild),
        ),
      ),
      AsyncData(:final value) => _report(
        context,
        l10n,
        value,
        value.where((c) => c.id == _childId).firstOrNull ?? value.first,
      ),
      AsyncError(:final error) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(familyChildrenProvider(familyId)),
      ),
      _ => const LoadingView(),
    };
  }

  Widget _report(
    BuildContext context,
    AppLocalizations l10n,
    List<ChildProfile> children,
    ChildProfile child,
  ) {
    final session = ref.watch(sessionControllerProvider).value;
    final progress = ref.watch(childProgressProvider(child.id));
    final today = ref.watch(clockProvider)();
    final query = ReportQuery(child.id, _weeksBack);
    // `null` data means the server has no weekly endpoint (older backend).
    final reportState = ref.watch(weeklyReportProvider(query));
    final report = reportState.value;

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(childProgressProvider(child.id))
          ..invalidate(weeklyReportProvider(query));
        await refreshQuietly(ref.read(childProgressProvider(child.id).future));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ResponsiveContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.md,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.reportsEyebrow,
                      style: context.text.labelLarge?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    if (session != null)
                      Text(
                        l10n.reportsWelcome(session.user.fullName),
                        style: context.text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
                _ChildAndRange(
                  children: children,
                  selected: child,
                  today: today,
                  report: report,
                  onSelected: (id) => setState(() {
                    _childId = id;
                    _weeksBack = 0;
                  }),
                ),
                if (report != null)
                  _WeekNavigator(
                    weeksBack: _weeksBack,
                    onChanged: (value) => setState(() => _weeksBack = value),
                  ),
                switch (progress) {
                  AsyncData() when reportState.isLoading => const LoadingView(),
                  AsyncData(:final value) => _ReportBody(
                    child: child,
                    progress: value,
                    today: today,
                    report: report,
                  ),
                  AsyncError(:final error) => ErrorView(
                    error: error,
                    onRetry: () =>
                        ref.invalidate(childProgressProvider(child.id)),
                  ),
                  _ => const LoadingView(),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChildAndRange extends ConsumerWidget {
  const _ChildAndRange({
    required this.children,
    required this.selected,
    required this.today,
    required this.onSelected,
    this.report,
  });

  final List<ChildProfile> children;
  final ChildProfile selected;
  final DateTime today;
  final WeeklyReport? report;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final avatar = ref.watch(childAvatarProvider(selected.id));
    final age = selected.ageOn(today);
    final label = age == null
        ? selected.displayName
        : l10n.childNameWithAge(selected.displayName, age);

    final picker = children.length == 1
        ? Text(label, style: context.text.titleMedium)
        : DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const Key('reports.child'),
              value: selected.id,
              isDense: true,
              borderRadius: AppRadius.card,
              items: [
                for (final c in children)
                  DropdownMenuItem(value: c.id, child: Text(c.displayName)),
              ],
              onChanged: (id) {
                if (id != null) onSelected(id);
              },
            ),
          );

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: AppShadows.tier1,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, AppSpacing.md, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChildAvatar(
                  name: selected.displayName,
                  option: avatar,
                  size: 36,
                  ring: false,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(child: picker),
              ],
            ),
          ),
        ),
        EyebrowPill(
          icon: Icons.calendar_month_rounded,
          label: report == null
              ? weekRangeLabel(context, today)
              : reportRangeLabel(context, report!),
        ),
      ],
    );
  }
}

/// "Oct 12 – Oct 18" for the report's own Monday-to-Sunday period.
String reportRangeLabel(BuildContext context, WeeklyReport report) {
  final format = DateFormat.MMMd(
    Localizations.localeOf(context).toLanguageTag(),
  );
  return '${format.format(report.periodStart)} – ${format.format(report.periodEnd)}';
}

/// Previous / next week controls. The server keeps every past week.
class _WeekNavigator extends StatelessWidget {
  const _WeekNavigator({required this.weeksBack, required this.onChanged});

  final int weeksBack;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A Wrap, not a Row: with large text the centre button drops to its own
    // line instead of overflowing.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: AppSpacing.xs,
      children: [
        IconButton.filledTonal(
          key: const Key('reports.previous'),
          tooltip: l10n.reportsPreviousWeek,
          onPressed: weeksBack >= 52 ? null : () => onChanged(weeksBack + 1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        TextButton(
          key: const Key('reports.current'),
          onPressed: weeksBack == 0 ? null : () => onChanged(0),
          child: Text(l10n.reportsThisWeek),
        ),
        IconButton.filledTonal(
          key: const Key('reports.next'),
          tooltip: l10n.reportsNextWeek,
          onPressed: weeksBack == 0 ? null : () => onChanged(weeksBack - 1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

/// "Oct 18 – Oct 24" for the seven UTC days ending on [today]'s UTC day.
String weekRangeLabel(BuildContext context, DateTime today) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final format = DateFormat.MMMd(locale);
  final end = utcDay(today);
  final start = end.subtract(const Duration(days: 6));
  return '${format.format(start)} – ${format.format(end)}';
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.child,
    required this.progress,
    required this.today,
    this.report,
  });

  final ChildProfile child;
  final ChildProgress progress;
  final DateTime today;

  /// The server's week in the family's time zone; `null` falls back to a
  /// UTC week derived from [progress].
  final WeeklyReport? report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final report = this.report;
    final week = report?.days ?? progress.week(today);
    final missions =
        report?.completedTasks ??
        week.fold<int>(0, (sum, d) => sum + d.completedTasks);
    final stars =
        report?.starsEarned ??
        week.fold<int>(0, (sum, d) => sum + d.starsEarned);
    final xp =
        report?.xpEarned ?? week.fold<int>(0, (sum, d) => sum + d.xpEarned);
    final activeDays = week.where((d) => d.completedTasks > 0).length;
    final range = report == null
        ? weekRangeLabel(context, today)
        : reportRangeLabel(context, report);

    final tiles = [
      _MetricTile(
        icon: Icons.task_alt_rounded,
        iconBackground: colors.surfaceContainerHigh,
        iconColor: colors.primary,
        value: '$missions',
        label: l10n.reportsMissionsDone,
        footer: l10n.reportsActiveDays(activeDays),
      ),
      _MetricTile(
        icon: Icons.stars_rounded,
        iconBackground: colors.tertiaryFixed,
        iconColor: colors.tertiary,
        value: '$stars',
        label: l10n.reportsStarsAwarded,
        footer: l10n.reportsStarBalance(progress.starBalance),
      ),
      _MetricTile(
        icon: Icons.local_fire_department_rounded,
        iconBackground: colors.secondaryContainer,
        iconColor: colors.onSecondaryContainer,
        value: l10n.statStreakValue(progress.currentStreak),
        label: l10n.reportsStreak,
        footer: l10n.reportsLongestStreak(progress.longestStreak),
      ),
      _MetricTile(
        icon: Icons.bolt_rounded,
        iconBackground: colors.primaryFixed,
        iconColor: colors.primary,
        value: '$xp',
        label: l10n.reportsXpEarned,
        footer: progress.levelNumber == null
            ? l10n.reportsTotalXp(progress.totalXp)
            : l10n.reportsLevel(
                progress.levelNumber!,
                progress.levelName ?? '',
              ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.md,
      children: [
        AdaptiveWrap(children: tiles),
        _WeekChartCard(week: week),
        if (report != null) ...[
          _ReportNotes(report: report),
          _CategoriesCard(categories: report.categories),
        ],
        _BadgesCard(progress: progress),
        _VerifiedCard(
          summary: l10n.reportsSummaryText(
            child.displayName,
            range,
            missions,
            stars,
            xp,
            progress.currentStreak,
          ),
          subject: l10n.reportsShareSubject(child.displayName),
        ),
      ],
    );
  }
}

/// What is still open this week, and which time zone the days follow.
class _ReportNotes extends StatelessWidget {
  const _ReportNotes({required this.report});

  final WeeklyReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        if (report.pendingSubmissions > 0)
          InlineNotice(
            icon: Icons.hourglass_top_rounded,
            message: l10n.reportsPendingNote(report.pendingSubmissions),
          ),
        if (report.rejectedSubmissions > 0)
          InlineNotice(
            icon: Icons.replay_rounded,
            message: l10n.reportsRetryNote(report.rejectedSubmissions),
          ),
        Text(
          l10n.reportsTimezoneNote(report.timezone),
          key: const Key('reports.timezone'),
          style: context.text.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Approved missions per category for the week (real data only).
class _CategoriesCard extends StatelessWidget {
  const _CategoriesCard({required this.categories});

  final List<ReportCategory> categories;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final top = categories.fold<int>(
      0,
      (m, c) => c.completedTasks > m ? c.completedTasks : m,
    );
    return AppCard(
      key: const Key('reports.categories'),
      radius: AppRadius.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm + 4,
        children: [
          SectionHeader(
            title: l10n.reportsCategoriesTitle,
            icon: Icons.category_rounded,
          ),
          if (categories.isEmpty)
            Text(
              l10n.reportsCategoriesEmpty,
              style: context.text.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else
            for (final category in categories)
              MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.xs,
                  children: [
                    // Wrap: with large text the count moves under the name.
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.sm,
                      children: [
                        Text(
                          category.categoryId == null
                              ? l10n.reportsUncategorised
                              : category.name,
                          style: context.text.titleSmall,
                        ),
                        Text(
                          l10n.reportsCategoryCount(category.completedTasks),
                          style: context.text.labelLarge?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        value: top == 0 ? 0 : category.completedTasks / top,
                        minHeight: 8,
                        backgroundColor: colors.surfaceContainerHigh,
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

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.footer,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String value;
  final String label;
  final String footer;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      semanticLabel: '$value $label. $footer',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.xs,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: iconBackground,
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              style: context.text.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(label, style: context.text.labelLarge),
            Text(
              footer,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekChartCard extends StatelessWidget {
  const _WeekChartCard({required this.week});

  final List<ActivityDay> week;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dayFormat = DateFormat.E(locale);
    final maxCount = week.fold<int>(
      0,
      (m, d) => d.completedTasks > m ? d.completedTasks : m,
    );
    final best = maxCount == 0
        ? null
        : week.lastWhere((d) => d.completedTasks == maxCount);
    final summary = [
      for (final d in week) '${dayFormat.format(d.date)} ${d.completedTasks}',
    ].join(', ');

    return AppCard(
      radius: AppRadius.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: l10n.reportsChartTitle),
              Text(
                l10n.reportsChartSubtitle,
                style: context.text.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Semantics(
            label: summary,
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: AppSpacing.sm,
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
                          height: 120,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: maxCount == 0
                                  ? 0.06
                                  : (day.completedTasks / maxCount).clamp(
                                      0.06,
                                      1.0,
                                    ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: day == best
                                      ? colors.secondary
                                      : day.completedTasks > 0
                                      ? colors.primary
                                      : colors.surfaceContainerHigh,
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
          ),
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

class _BadgesCard extends StatelessWidget {
  const _BadgesCard({required this.progress});

  final ChildProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return AppCard(
      radius: AppRadius.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm + 4,
        children: [
          SectionHeader(
            title: l10n.badgesTitle,
            icon: Icons.military_tech_rounded,
            trailing: EyebrowPill(
              label: l10n.badgesUnlocked(progress.badgeCount),
            ),
          ),
          if (progress.badges.isEmpty)
            Text(
              l10n.reportsNoBadges,
              style: context.text.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final badge in progress.badges.take(6))
                  Chip(
                    avatar: Icon(
                      Icons.workspace_premium_rounded,
                      color: colors.tertiary,
                      size: 18,
                    ),
                    label: Text(badge.name),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _VerifiedCard extends ConsumerWidget {
  const _VerifiedCard({required this.summary, required this.subject});

  final String summary;
  final String subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return AppCard(
      color: colors.surfaceContainer,
      elevated: false,
      radius: AppRadius.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.surfaceContainerLowest,
                child: Icon(Icons.verified_user_rounded, color: colors.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.xs,
                  children: [
                    Text(
                      l10n.reportsVerifiedTitle,
                      style: context.text.titleMedium,
                    ),
                    Text(
                      l10n.reportsVerifiedBody,
                      style: context.text.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          PrimaryButton(
            key: const Key('reports.share'),
            label: l10n.reportsShare,
            icon: Icons.ios_share_rounded,
            onPressed: () async {
              final opened = await ref
                  .read(textSharerProvider)
                  .share(summary, subject: subject);
              if (opened || !context.mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text(l10n.reportsShareFailed)),
                );
            },
          ),
          SecondaryButton(
            key: const Key('reports.copy'),
            label: l10n.reportsCopySummary,
            icon: Icons.copy_all_rounded,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: summary));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text(l10n.reportsSummaryCopied)),
                );
            },
          ),
        ],
      ),
    );
  }
}
