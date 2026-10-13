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
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
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
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _RequestsTab(familyId: familyId),
                _CatalogTab(familyId: familyId),
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
      ref.invalidate(familyRedemptionsProvider(widget.familyId));
      final childId = widget.redemption.childId;
      if (childId != null) ref.invalidate(childProgressProvider(childId));
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
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
              const SizedBox(width: AppSpacing.sm),
              StarPill(count: r.starCost),
            ],
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
            child: Column(
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
          const SizedBox(width: AppSpacing.sm),
          StarPill(count: reward.starCost),
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
