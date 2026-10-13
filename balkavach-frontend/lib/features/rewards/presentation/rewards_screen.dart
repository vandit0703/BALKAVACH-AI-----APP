import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/async/refresh_quietly.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/adaptive_wrap.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gamification.dart';
import '../../../shared/widgets/state_views.dart';
import '../../missions/presentation/mission_providers.dart';
import '../../progress/data/progress_repository.dart';
import '../data/rewards_repository.dart';

/// Child Rewards & Achievements (Stitch `child_rewards_achievements`).
///
/// Star balance, streak and badges come from `/progress`; past reward
/// requests from `/redemptions/mine`; the catalog from `GET /rewards`. The
/// child only ever *asks*; the parent decides and the server moves the stars.
class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childId = ref.watch(activeChildIdProvider);
    if (childId == null) return const LoadingView();
    final progress = ref.watch(childProgressProvider(childId));

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(childProgressProvider(childId))
          ..invalidate(myRedemptionsProvider);
        await refreshQuietly(ref.read(childProgressProvider(childId).future));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ResponsiveContent(
            child: switch (progress) {
              AsyncData(:final value) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.md,
                children: [
                  _VaultCard(progress: value),
                  _CatalogSection(balance: value.starBalance),
                  _BadgesSection(badges: value.badges),
                ],
              ),
              AsyncError(:final error) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(childProgressProvider(childId)),
              ),
              _ => const LoadingView(),
            },
          ),
        ],
      ),
    );
  }
}

class _VaultCard extends StatelessWidget {
  const _VaultCard({required this.progress});

  final ChildProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final onVault = colors.onPrimary;
    final streakDots = progress.currentStreak.clamp(0, 7);

    return AppCard(
      radius: AppRadius.hero,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors.primary, colors.primaryContainer],
      ),
      padding: const EdgeInsets.all(AppSpacing.lg - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: EyebrowPill(
              icon: Icons.stars_rounded,
              label: l10n.rewardsVault,
              background: onVault.withValues(alpha: 0.18),
              foreground: onVault,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: l10n.rewardsBalanceSemantics(progress.starBalance),
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.rewardsBalance,
                        style: context.text.labelLarge?.copyWith(
                          color: onVault.withValues(alpha: 0.85),
                        ),
                      ),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            color: context.brand.star,
                            size: 40,
                          ),
                          Text(
                            '${progress.starBalance}',
                            style: context.text.displaySmall?.copyWith(
                              color: onVault,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            l10n.statStars,
                            style: context.text.titleLarge?.copyWith(
                              color: onVault.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.asset(
                  AppImages.treasureChest,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  cacheWidth: (72 * dpr).round(),
                  excludeFromSemantics: true,
                ),
              ),
            ],
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: onVault.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department_rounded,
                        color: colors.tertiaryFixedDim,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          l10n.rewardsStreak(progress.currentStreak),
                          style: context.text.titleSmall?.copyWith(
                            color: onVault,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 4,
                      children: [
                        for (var i = 0; i < 7; i++)
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < streakDots
                                  ? colors.secondaryContainer
                                  : onVault.withValues(alpha: 0.3),
                            ),
                          ),
                      ],
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

/// Rewards the child can ask for, and the child's own requests.
///
/// Stars are never spent by the app: asking creates a request, the parent
/// decides, and the server deducts the stars on approval. Stars already
/// promised to other pending requests are not offered twice.
class _CatalogSection extends ConsumerStatefulWidget {
  const _CatalogSection({required this.balance});

  final int balance;

  @override
  ConsumerState<_CatalogSection> createState() => _CatalogSectionState();
}

class _CatalogSectionState extends ConsumerState<_CatalogSection> {
  /// One key per reward being asked for, kept until the request succeeds so a
  /// retry after a lost response cannot create a second request.
  final _keys = <String, String>{};
  final _busy = <String>{};

  Future<void> _ask(Reward reward) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.rewardsConfirmTitle(reward.name)),
        content: Text(l10n.rewardsConfirmBody(reward.starCost)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('reward.confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.rewardsConfirmYes),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy.add(reward.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(rewardsRepositoryProvider)
          .requestReward(
            reward.id,
            _keys.putIfAbsent(reward.id, newIdempotencyKey),
          );
      _keys.remove(reward.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.rewardsAsked)));
    } on ApiException catch (error) {
      // A definite answer from the server ends this intent; a lost
      // connection keeps the key so the retry is safe.
      if (error is! NetworkException && error is! RequestTimeoutException) {
        _keys.remove(reward.id);
      }
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      ref.invalidate(myRedemptionsProvider);
      ref.invalidate(childCatalogProvider);
      final childId = ref.read(activeChildIdProvider);
      if (childId != null) ref.invalidate(childProgressProvider(childId));
      if (mounted) setState(() => _busy.remove(reward.id));
    }
  }

  Future<void> _cancel(Redemption redemption) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(rewardsRepositoryProvider).cancelMine(redemption.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.rewardsRequestCancelled)));
    } on ApiException catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      ref.invalidate(myRedemptionsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(childCatalogProvider);
    final redemptions = ref.watch(myRedemptionsProvider);
    final requests = redemptions.value ?? const <Redemption>[];
    final reserved = requests
        .where((r) => r.isPending)
        .fold<int>(0, (sum, r) => sum + r.starCost);
    final pendingRewardIds = {
      for (final r in requests)
        if (r.isPending) r.rewardId,
    };
    final names = {
      for (final r in catalog.value ?? const <Reward>[]) r.id: r.name,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm + 4,
      children: [
        SectionHeader(title: l10n.rewardsCatalog, icon: Icons.redeem_rounded),
        switch (catalog) {
          AsyncData(:final value) when value.isEmpty => EmptyView(
            message: l10n.rewardsCatalogEmpty,
            image: AppImages.treasureChest,
          ),
          AsyncData(:final value) => AdaptiveWrap(
            spacing: AppSpacing.sm,
            children: [
              for (final reward in value)
                _RewardCard(
                  key: Key('reward.${reward.id}'),
                  reward: reward,
                  available: widget.balance - reserved,
                  alreadyAsked: pendingRewardIds.contains(reward.id),
                  busy: _busy.contains(reward.id),
                  onAsk: () => _ask(reward),
                ),
            ],
          ),
          // A server that predates the child catalog answers 403/404.
          AsyncError(:final error)
              when error is ForbiddenException || error is NotFoundException =>
            const _ShopNotReady(),
          AsyncError(:final error) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(childCatalogProvider),
          ),
          _ => const LoadingView(),
        },
        switch (redemptions) {
          AsyncData(:final value) when value.isEmpty => const SizedBox.shrink(),
          AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.sm,
            children: [
              Text(l10n.rewardsMyRequests, style: context.text.titleMedium),
              for (final r in value.take(10))
                _RedemptionTile(
                  redemption: r,
                  rewardName: names[r.rewardId],
                  onCancel: r.isPending ? () => _cancel(r) : null,
                ),
            ],
          ),
          AsyncError() => InlineNotice(
            icon: Icons.cloud_off_rounded,
            message: l10n.rewardsRequestsUnavailable,
          ),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }
}

class _ShopNotReady extends StatelessWidget {
  const _ShopNotReady();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return AppCard(
      color: colors.surfaceContainerLow,
      elevated: false,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Image.asset(
              AppImages.treasureChest,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              cacheWidth: (64 * dpr).round(),
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.xs,
              children: [
                Text(
                  l10n.rewardsCatalogSoonTitle,
                  style: context.text.titleMedium,
                ),
                Text(
                  l10n.rewardsCatalogSoonBody,
                  style: context.text.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
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

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.reward,
    required this.available,
    required this.alreadyAsked,
    required this.busy,
    required this.onAsk,
    super.key,
  });

  final Reward reward;
  final int available;
  final bool alreadyAsked;
  final bool busy;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final missing = reward.starCost - available;
    final description = reward.description?.trim();
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(reward.name, style: context.text.titleMedium),
              ),
              const SizedBox(width: AppSpacing.sm),
              StarPill(count: reward.starCost),
            ],
          ),
          if (description != null && description.isNotEmpty)
            Text(
              description,
              style: context.text.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          if (alreadyAsked)
            StatusChip(
              label: l10n.rewardsAlreadyAsked,
              icon: Icons.hourglass_top_rounded,
              background: colors.tertiaryFixed,
              foreground: colors.onTertiaryFixed,
            )
          else if (missing > 0)
            Text(
              l10n.rewardsNeedMore(missing),
              key: const Key('reward.need'),
              style: context.text.labelLarge?.copyWith(color: colors.primary),
            )
          else
            PrimaryButton(
              key: const Key('reward.ask'),
              label: l10n.rewardsAsk,
              icon: Icons.redeem_rounded,
              childSized: true,
              loading: busy,
              onPressed: busy ? null : onAsk,
            ),
        ],
      ),
    );
  }
}

class _RedemptionTile extends StatelessWidget {
  const _RedemptionTile({
    required this.redemption,
    required this.rewardName,
    required this.onCancel,
  });

  final Redemption redemption;
  final String? rewardName;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final (label, icon, background, foreground) = switch (redemption.status) {
      'pending' => (
        '${l10n.statusPending} ⏳',
        Icons.hourglass_top_rounded,
        colors.tertiaryFixed,
        colors.onTertiaryFixed,
      ),
      'approved' => (
        l10n.statusApproved,
        Icons.verified_rounded,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      'fulfilled' => (
        l10n.rewardsFulfilled,
        Icons.celebration_rounded,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      'rejected' => (
        l10n.statusRejected,
        Icons.do_not_disturb_on_outlined,
        colors.errorContainer,
        colors.onErrorContainer,
      ),
      _ => (
        l10n.rewardsCancelled,
        Icons.close_rounded,
        colors.surfaceContainerHigh,
        colors.onSurfaceVariant,
      ),
    };
    final note = redemption.reviewNote?.trim();
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.sm,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rewardName == null
                          ? l10n.rewardsRequest
                          : l10n.rewardsRequestNamed(rewardName!),
                      style: context.text.titleMedium,
                    ),
                    Text(
                      DateFormat.yMMMd(
                        locale,
                      ).format(redemption.requestedAt.toLocal()),
                      style: context.text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              StarPill(count: redemption.starCost),
            ],
          ),
          StatusChip(
            label: label,
            icon: icon,
            background: background,
            foreground: foreground,
          ),
          if (note != null && note.isNotEmpty)
            Text(l10n.rewardsParentNote(note), style: context.text.bodyMedium),
          if (onCancel != null)
            TextButton.icon(
              key: Key('reward.cancel.${redemption.id}'),
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded),
              label: Text(l10n.rewardsCancelRequest),
            ),
        ],
      ),
    );
  }
}

class _BadgesSection extends StatelessWidget {
  const _BadgesSection({required this.badges});

  final List<EarnedBadge> badges;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm + 4,
      children: [
        SectionHeader(
          title: l10n.badgesTitle,
          icon: Icons.military_tech_rounded,
          trailing: Text(
            l10n.badgesUnlocked(badges.length),
            style: context.text.labelMedium?.copyWith(
              color: context.colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (badges.isEmpty)
          EmptyView(message: l10n.badgesEmpty, image: AppImages.pandaCheering)
        else
          AdaptiveWrap(
            spacing: AppSpacing.sm,
            children: [
              for (final (i, badge) in badges.indexed)
                BadgeTile(badge: badge, index: i),
            ],
          ),
      ],
    );
  }
}

/// One unlocked badge. The backend's `icon_url` is not loaded (it may point
/// anywhere); tiles cycle through the Stitch badge colours instead.
class BadgeTile extends StatelessWidget {
  const BadgeTile({required this.badge, required this.index, super.key});

  final EarnedBadge badge;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final tints = [
      (colors.tertiaryFixed, colors.tertiary, Icons.auto_stories_rounded),
      (colors.secondaryContainer, colors.secondary, Icons.handshake_rounded),
      (colors.surfaceContainerHigh, colors.primary, Icons.self_improvement),
      (colors.primaryFixed, colors.primary, Icons.palette_rounded),
    ];
    final (tint, accent, icon) = tints[index % tints.length];

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Stack(
        children: [
          PositionedDirectional(
            top: 0,
            end: 0,
            child: Icon(Icons.verified_rounded, color: accent, size: 18),
          ),
          Column(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: tint,
                child: Icon(icon, color: accent, size: 28),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                badge.name,
                textAlign: TextAlign.center,
                style: context.text.titleMedium,
              ),
              if (badge.description != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  badge.description!,
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              EyebrowPill(
                label: l10n.badgeUnlockedOn(
                  DateFormat.MMMd(locale).format(badge.unlockedAt.toLocal()),
                ),
                background: tint,
                foreground: colors.onSurface,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
