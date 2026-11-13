import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/video_feed_repository.dart';

class VideoAllowanceCard extends ConsumerWidget {
  const VideoAllowanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowanceAsync = ref.watch(videoAllowanceProvider);
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return allowanceAsync.maybeWhen(
      data: (allowance) {
        final remainingMinutes = allowance.remainingMinutes;
        final hasTime = allowance.remainingSeconds > 0 && !allowance.isExhausted;

        return Container(
          key: const Key('watch.allowance.card'),
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: hasTime
                ? colors.primary.withValues(alpha: 0.08)
                : colors.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasTime
                  ? colors.primary.withValues(alpha: 0.25)
                  : colors.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: hasTime
                      ? colors.primary.withValues(alpha: 0.15)
                      : colors.outline.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasTime ? Icons.hourglass_top_rounded : Icons.lock_clock_rounded,
                  color: hasTime ? colors.primary : colors.onSurfaceVariant,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasTime
                          ? l10n.videoAllowanceRemaining(remainingMinutes)
                          : l10n.videoAllowanceLocked,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: hasTime ? colors.primary : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasTime
                          ? '${allowance.activeEntitlementsCount} mission reward(s) today'
                          : l10n.videoAllowanceUnlockHint,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!hasTime) ...[
                const SizedBox(width: AppSpacing.sm),
                FilledButton.tonal(
                  key: const Key('watch.allowance.toMissions'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  ),
                  onPressed: () => context.go(AppRoutes.childMissions),
                  child: Text(
                    l10n.videoGoToMissions,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
