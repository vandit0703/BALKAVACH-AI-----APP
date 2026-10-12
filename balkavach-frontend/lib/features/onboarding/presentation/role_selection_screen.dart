import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/brand_header.dart';
import '../../../shared/widgets/buttons.dart';

/// Not in the Stitch export; composed from its components. A child cannot sign
/// in directly: the backend issues child sessions only to a signed-in parent.
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wide = !WindowSize.of(context).isCompact;
    final cards = [
      _RoleCard(
        key: const Key('role.parent'),
        icon: Icons.shield_rounded,
        tint: context.colors.surfaceContainerHigh,
        iconColor: context.colors.primary,
        title: l10n.roleParent,
        body: l10n.roleParentBody,
        onTap: () => context.go(AppRoutes.parentAuth),
      ),
      _RoleCard(
        key: const Key('role.child'),
        image: AppImages.pandaHoodie,
        tint: context.colors.secondaryContainer,
        iconColor: context.colors.onSecondaryContainer,
        title: l10n.roleChild,
        body: l10n.roleChildBody,
        onTap: () => context.go(AppRoutes.childStart),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: ResponsiveContent(
            maxWidth: wide ? ContentWidth.list : ContentWidth.form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.md,
              children: [
                const BrandWordmark(),
                const SizedBox(height: AppSpacing.sm),
                Text(l10n.roleTitle, style: context.text.headlineMedium),
                Text(
                  l10n.roleSubtitle,
                  style: context.text.bodyLarge?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                if (wide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: AppSpacing.md,
                      children: [for (final c in cards) Expanded(child: c)],
                    ),
                  )
                else
                  ...cards,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.tint,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.onTap,
    this.icon,
    this.image,
    super.key,
  });

  final IconData? icon;
  final String? image;
  final Color tint;
  final Color iconColor;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return AppCard(
      onTap: onTap,
      semanticLabel: title,
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: tint,
            child: image == null
                ? Icon(icon, color: iconColor, size: 32)
                : ClipOval(
                    child: Image.asset(
                      image!,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      cacheWidth: (64 * dpr).round(),
                      excludeFromSemantics: true,
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleLarge),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.colors.primary),
        ],
      ),
    );
  }
}

class ChildStartScreen extends StatelessWidget {
  const ChildStartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(AppRoutes.role)),
      ),
      body: ScrollablePage(
        maxWidth: ContentWidth.form,
        spacing: AppSpacing.lg,
        children: [
          ClipRRect(
            borderRadius: AppRadius.hero,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.asset(
                AppImages.pandaHoodie,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
          ),
          Text(l10n.childStartTitle, style: context.text.headlineMedium),
          Text(
            l10n.childStartBody,
            style: context.text.bodyLarge?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          PrimaryButton(
            label: l10n.childStartParentSignIn,
            icon: Icons.lock_outline_rounded,
            onPressed: () => context.go(AppRoutes.parentAuth),
          ),
        ],
      ),
    );
  }
}
