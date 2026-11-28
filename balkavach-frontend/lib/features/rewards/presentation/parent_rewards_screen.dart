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
import '../../../shared/widgets/state_views.dart';
import '../../child_profile/presentation/family_providers.dart';
import '../../progress/data/progress_repository.dart';
import '../data/rewards_repository.dart';
import 'reward_title_row.dart';

/// Parent Rewards: answer the children's requests and manage the catalog.
///
/// Every decision goes to the server, which moves the stars (approving takes
/// them once; cancelling an approved request gives them back once).
class ParentRewardsScreen extends ConsumerWidget {
  const ParentRewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final family = ref.watch(currentFamilyProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.parentRewardsTitle)),
      body: switch (family) {
        AsyncData(value: final f?) => _Tabs(familyId: f.id),
        AsyncData() => EmptyView(message: l10n.familyMissing),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(currentFamilyProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _Tabs extends ConsumerWidget {
  const _Tabs({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(pendingRedemptionCountProvider(familyId));
    // Three equal slots cut labels off on a phone: there each tab takes the
    // width its label needs, and the row scrolls if they do not all fit.
    final compact = WindowSize.of(context).isCompact;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            isScrollable: compact,
            tabAlignment: compact ? TabAlignment.center : null,
            labelPadding: compact
                ? const EdgeInsets.symmetric(horizontal: AppSpacing.md - 4)
                : null,
            tabs: [
              Tab(
                key: const Key('rewards.tab.requests'),
                text: pending == null || pending == 0
                    ? l10n.rewardsTabRequests
                    : '${l10n.rewardsTabRequests} ($pending)',
              ),
              Tab(
                key: const Key('rewards.tab.catalog'),
                text: l10n.rewardsTabCatalog,
              ),
              Tab(
                key: const Key('rewards.tab.history'),
                text: l10n.rewardsTabHistory,
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _RequestsTab(familyId: familyId),
                _CatalogTab(familyId: familyId),
                _HistoryTab(familyId: familyId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final requests = ref.watch(familyRedemptionsProvider(familyId));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(familyRedemptionsProvider(familyId));
        await refreshQuietly(
          ref.read(familyRedemptionsProvider(familyId).future),
        );
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ResponsiveContent(
            child: switch (requests) {
              AsyncData(:final value) when value.isEmpty => EmptyView(
                message: l10n.rewardsRequestsEmpty,
              ),
              AsyncData(:final value) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.md,
                children: [
                  for (final r in value)
                    _RequestCard(
                      key: Key('request.${r.id}'),
                      familyId: familyId,
                      redemption: r,
                    ),
                ],
              ),
              AsyncError(:final error) => ErrorView(
                error: error,
                onRetry: () =>
                    ref.invalidate(familyRedemptionsProvider(familyId)),
              ),
              _ => const LoadingView(),
            },
          ),
        ],
      ),
    );
  }
}

/// Finished requests: handed over, declined or cancelled. Read-only: nothing
/// here can approve, refund or create a request. Not every status carries
/// every date, so only the dates the server sent are shown.
class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(familyRedemptionHistoryProvider(familyId));
    // A request carries no description; the catalog has one while the reward
    // is still offered. Optional: history never waits or fails because of it.
    final descriptions = <String, String>{
      for (final reward
          in ref.watch(familyRewardsProvider(familyId)).value ??
              const <Reward>[])
        if (reward.description?.trim().isNotEmpty ?? false)
          reward.id: reward.description!.trim(),
    };
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(familyRedemptionHistoryProvider(familyId));
        await refreshQuietly(
          ref.read(familyRedemptionHistoryProvider(familyId).future),
        );
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ResponsiveContent(
            child: switch (history) {
              AsyncData(:final value) when value.isEmpty => EmptyView(
                key: const Key('history.empty'),
                message: l10n.rewardsHistoryEmpty,
              ),
              AsyncData(:final value) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.md,
                children: [
                  for (final r in value)
                    _HistoryCard(
                      key: Key('history.${r.id}'),
                      redemption: r,
                      description: descriptions[r.rewardId],
                    ),
                ],
              ),
              AsyncError(:final error) => ErrorView(
                key: const Key('history.error'),
                error: error,
                onRetry: () =>
                    ref.invalidate(familyRedemptionHistoryProvider(familyId)),
              ),
              _ => const LoadingView(),
            },
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.redemption, this.description, super.key});

  final Redemption redemption;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final r = redemption;
    final dates = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    String date(DateTime value) => dates.format(value.toLocal());
    final (label, icon, background, foreground) = switch (r.status) {
      'fulfilled' => (
        l10n.rewardStatusFulfilled,
        Icons.card_giftcard_rounded,
        colors.primaryFixed,
        colors.primary,
      ),
      'rejected' => (
        l10n.rewardStatusRejected,
        Icons.block_rounded,
        colors.errorContainer,
        colors.onErrorContainer,
      ),
      _ => (
        l10n.rewardStatusCancelled,
        Icons.cancel_outlined,
        colors.surfaceContainer,
        colors.onSurfaceVariant,
      ),
    };
    final note = r.reviewNote?.trim();
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.xs,
        children: [
          Text(
            r.rewardName ?? l10n.rewardHistoryUnnamed,
            style: context.text.titleMedium,
          ),
          if (description != null)
            Text(
              description!,
              key: Key('history.description.${r.id}'),
              style: context.text.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          StatusChip(
            label: label,
            icon: icon,
            background: background,
            foreground: foreground,
          ),
          if (r.childName != null)
            Text(
              '${r.childName} · ${l10n.quizRewardStars(r.starCost)}',
              style: context.text.bodyMedium,
            )
          else
            Text(
              l10n.quizRewardStars(r.starCost),
              style: context.text.bodyMedium,
            ),
          Text(
            l10n.rewardHistoryRequested(date(r.requestedAt)),
            style: context.text.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (r.reviewedAt != null)
            Text(
              l10n.rewardHistoryDecided(date(r.reviewedAt!)),
              style: context.text.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          if (r.fulfilledAt != null)
            Text(
              l10n.rewardHistoryFulfilled(date(r.fulfilledAt!)),
              style: context.text.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          if (note != null && note.isNotEmpty)
            Text(
              l10n.rewardHistoryNote(note),
              key: Key('history.note.${r.id}'),
              style: context.text.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({
    required this.familyId,
    required this.redemption,
    super.key,
  });

  final String familyId;
  final Redemption redemption;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _busy = false;

  Future<String?> _askNote() {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.rewardsDeclineTitle),
        content: TextField(
          key: const Key('request.note'),
          controller: controller,
          maxLength: 2000,
          maxLines: 3,
          decoration: InputDecoration(labelText: l10n.rewardsNoteOptional),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('request.decline.confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.rewardsDecline),
          ),
        ],
      ),
    );
  }

  Future<void> _run(
    Future<Object?> Function(RewardsRepository repository) action,
    String successMessage,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action(ref.read(rewardsRepositoryProvider));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(successMessage)));
    } on ConflictException catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              error.code == 'redemption_already_reviewed'
                  ? l10n.rewardsAlreadyReviewed
                  : describeError(l10n, error),
            ),
          ),
        );
    } on ApiException catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      ref
        ..invalidate(familyRedemptionsProvider(widget.familyId))
        ..invalidate(familyRedemptionHistoryProvider(widget.familyId));
      final childId = widget.redemption.childId;
      if (childId != null) {
        ref
          ..invalidate(childProgressProvider(childId))
          // Star badges follow the balance this decision just changed.
          ..invalidate(achievementsProvider(childId));
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final r = widget.redemption;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final child = r.childName ?? l10n.someChild;
    final reward = r.rewardName ?? l10n.rewardsRequest;
    return AppCard(
      radius: AppRadius.hero,
      padding: const EdgeInsets.all(AppSpacing.md + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          RewardTitleRow(
            crossAxisAlignment: CrossAxisAlignment.start,
            stars: r.starCost,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  l10n.rewardsAskedBy(child, reward),
                  style: context.text.titleMedium,
                ),
                Text(
                  DateFormat.MMMd(
                    locale,
                  ).add_jm().format(r.requestedAt.toLocal()),
                  style: context.text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (r.isPending) ...[
            PrimaryButton(
              key: const Key('request.approve'),
              label: l10n.rewardsApprove(r.starCost),
              icon: Icons.check_circle_outline_rounded,
              backgroundColor: colors.secondary,
              loading: _busy,
              onPressed: _busy
                  ? null
                  : () => _run(
                      (repo) => repo.approve(r.id),
                      l10n.rewardsApprovedToast(r.starCost),
                    ),
            ),
            TextButton(
              key: const Key('request.decline'),
              onPressed: _busy
                  ? null
                  : () async {
                      final note = await _askNote();
                      if (note == null || !mounted) return;
                      await _run(
                        (repo) => repo.reject(r.id, note: note),
                        l10n.rewardsDeclinedToast,
                      );
                    },
              child: Text(l10n.rewardsDecline),
            ),
          ] else ...[
            StatusChip(
              label: l10n.statusApproved,
              icon: Icons.verified_rounded,
              background: colors.secondaryContainer,
              foreground: colors.onSecondaryContainer,
            ),
            PrimaryButton(
              key: const Key('request.fulfill'),
              label: l10n.rewardsMarkGiven,
              icon: Icons.celebration_rounded,
              loading: _busy,
              onPressed: _busy
                  ? null
                  : () => _run(
                      (repo) => repo.fulfill(r.id),
                      l10n.rewardsGivenToast,
                    ),
            ),
            TextButton(
              key: const Key('request.refund'),
              onPressed: _busy
                  ? null
                  : () => _run(
                      (repo) => repo.cancelAsParent(r.id),
                      l10n.rewardsRefundedToast,
                    ),
              child: Text(l10n.rewardsCancelRefund),
            ),
          ],
        ],
      ),
    );
  }
}

class _CatalogTab extends ConsumerWidget {
  const _CatalogTab({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final rewards = ref.watch(familyRewardsProvider(familyId));
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(familyRewardsProvider(familyId));
            await refreshQuietly(
              ref.read(familyRewardsProvider(familyId).future),
            );
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              ResponsiveContent(
                child: switch (rewards) {
                  AsyncData(:final value) when value.isEmpty => EmptyView(
                    message: l10n.rewardsCatalogEmpty,
                  ),
                  AsyncData(:final value) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.sm,
                    children: [
                      for (final reward in value)
                        _RewardRow(
                          key: Key('catalog.${reward.id}'),
                          familyId: familyId,
                          reward: reward,
                        ),
                    ],
                  ),
                  AsyncError(:final error) => ErrorView(
                    error: error,
                    onRetry: () =>
                        ref.invalidate(familyRewardsProvider(familyId)),
                  ),
                  _ => const LoadingView(),
                },
              ),
            ],
          ),
        ),
        PositionedDirectional(
          end: AppSpacing.md,
          bottom: AppSpacing.md,
          child: FloatingActionButton.extended(
            key: const Key('rewards.add'),
            onPressed: () => context.push(AppRoutes.parentNewReward),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.rewardsAddReward),
          ),
        ),
      ],
    );
  }
}

class _RewardRow extends ConsumerWidget {
  const _RewardRow({required this.familyId, required this.reward, super.key});

  final String familyId;
  final Reward reward;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final description = reward.description?.trim();
    return AppCard(
      onTap: () => context.push(AppRoutes.parentEditReward(reward.id)),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: RewardTitleRow(
              stars: reward.starCost,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.xs,
                children: [
                  Text(reward.name, style: context.text.titleMedium),
                  if (description != null && description.isNotEmpty)
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            key: Key('catalog.remove.${reward.id}'),
            tooltip: l10n.rewardsRemove,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _remove(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.rewardsRemove),
        content: Text(l10n.rewardsRemoveConfirm(reward.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('catalog.remove.confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.rewardsRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(rewardsRepositoryProvider).removeReward(reward.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.rewardsRemoved)));
    } on ApiException catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    } finally {
      ref.invalidate(familyRewardsProvider(familyId));
    }
  }
}
