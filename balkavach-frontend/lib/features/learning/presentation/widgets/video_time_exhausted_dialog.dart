import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';

/// Shows a dialog informing the child that their video viewing allowance
/// for today has been exhausted, prompting them to complete daily missions.
Future<void> showVideoTimeExhaustedDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final colors = Theme.of(context).colorScheme;

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.hourglass_bottom_rounded,
          size: 48,
          color: colors.primary,
        ),
      ),
      title: Text(
        l10n.videoTimeExhaustedTitle,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Text(l10n.videoTimeExhaustedBody, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowButtonSpacing: AppSpacing.sm,
      actions: [
        FilledButton.icon(
          key: const Key('video.exhausted.toMissions'),
          onPressed: () {
            Navigator.of(dialogContext).pop();
            context.go(AppRoutes.childMissions);
          },
          icon: const Icon(Icons.rocket_launch_rounded),
          label: Text(l10n.videoGoToMissions),
        ),
        TextButton(
          key: const Key('video.exhausted.close'),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.videoBackToHome),
        ),
      ],
    ),
  );
}
