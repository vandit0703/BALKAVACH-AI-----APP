import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';

/// Home's always-visible way into the Learning Hub: three big tiles that open
/// the hub on Videos, Quizzes or Shorts. Shown whatever the feeds contain, so
/// quizzes stay reachable even when there are no grown-up picks.
class LearnHubEntry extends StatelessWidget {
  const LearnHubEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final tiles = [
      (
        'videos',
        Icons.smart_display_rounded,
        l10n.hubTabVideos,
        colors.primaryFixed,
        colors.primary,
      ),
      (
        'quizzes',
        Icons.quiz_rounded,
        l10n.hubTabQuizzes,
        colors.tertiaryFixed,
        colors.onTertiaryFixed,
      ),
      (
        'shorts',
        Icons.bolt_rounded,
        l10n.hubTabShorts,
        colors.secondaryContainer,
        colors.secondary,
      ),
    ];
    return Padding(
      key: const Key('watch.learnHub'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          Text(
            l10n.learnHubEntryTitle,
            style: context.text.titleLarge,
            semanticsLabel: l10n.learnHubEntryTitle,
          ),
          Row(
            spacing: AppSpacing.sm,
            children: [
              for (final (tab, icon, label, background, foreground) in tiles)
                Expanded(
                  child: _HubTile(
                    key: Key('watch.learnHub.$tab'),
                    icon: icon,
                    label: label,
                    background: background,
                    foreground: foreground,
                    onTap: () => context.push(AppRoutes.childLearnTab(tab)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            // Comfortably above the 48 dp touch target, even on 320 dp phones.
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: AppSpacing.xs,
                children: [
                  Icon(icon, size: 32, color: foreground),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
