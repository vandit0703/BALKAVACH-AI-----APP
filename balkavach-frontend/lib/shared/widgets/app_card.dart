import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Borderless white card with the tier-1 blue ambient shadow.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md + 4),
    this.color,
    this.gradient,
    this.radius = AppRadius.card,
    this.onTap,
    this.elevated = true,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Gradient? gradient;
  final BorderRadius radius;
  final VoidCallback? onTap;
  final bool elevated;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: gradient == null
              ? (color ?? context.colors.surfaceContainerLowest)
              : null,
          gradient: gradient,
          borderRadius: radius,
          boxShadow: elevated ? AppShadows.tier1 : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: onTap == null
              ? body
              : InkWell(borderRadius: radius, onTap: onTap, child: body),
        ),
      ),
    );
  }
}

/// Eyebrow pill used above titles ("BAL KAVACH ECOSYSTEM", "PLAYFUL SAFETY").
class EyebrowPill extends StatelessWidget {
  const EyebrowPill({
    required this.label,
    this.icon,
    this.background,
    this.foreground,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? context.colors.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: context.text.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section title with an optional trailing action/label.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.trailing,
    this.icon,
    super.key,
  });

  final String title;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: context.colors.primary),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: Semantics(
            header: true,
            child: Text(title, style: context.text.titleLarge),
          ),
        ),
      ],
    );
    if (trailing == null) return heading;
    // Wrap lets the action drop under the title on narrow screens or with
    // large text instead of overflowing.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [heading, trailing!],
    );
  }
}
