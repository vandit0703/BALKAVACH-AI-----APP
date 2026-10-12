import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/health_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/app_localizations.dart';

/// Connectivity line from `/health` + `/ready`. It reports server and
/// database reachability only, and says so.
class ServerStatusBadge extends ConsumerWidget {
  const ServerStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final health = ref.watch(serverHealthProvider);

    final (icon, color, label) = switch (health) {
      AsyncData(value: ServerHealth(databaseReady: true)) => (
        Icons.cloud_done_outlined,
        colors.secondary,
        l10n.serverOnline,
      ),
      AsyncData() => (
        Icons.cloud_queue_rounded,
        colors.tertiary,
        l10n.serverDbDown,
      ),
      AsyncError() => (
        Icons.cloud_off_rounded,
        colors.error,
        l10n.serverUnreachable,
      ),
      _ => (
        Icons.cloud_sync_outlined,
        colors.onSurfaceVariant,
        l10n.serverChecking,
      ),
    };

    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  key: const Key('server.status'),
                  style: context.text.labelMedium?.copyWith(color: color),
                ),
                Text(
                  l10n.serverStatusNote,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (health.hasError)
            IconButton(
              tooltip: l10n.retry,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.invalidate(serverHealthProvider),
            ),
        ],
      ),
    );
  }
}
