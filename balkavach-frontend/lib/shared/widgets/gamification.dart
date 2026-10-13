import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Gold capsule with a star and a count ("⭐ 10").
class StarPill extends StatelessWidget {
  const StarPill({
    required this.count,
    this.prefix = '',
    this.label,
    super.key,
  });

  final int count;
  final String prefix;

  /// Replaces the "`prefix``count`" text, e.g. "240 Available Stars".
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.tertiaryFixed,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.stars_rounded, size: 18, color: colors.tertiary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label ?? '$prefix$count',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onTertiaryFixed,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One cell of the child stats dock (stars / streak / XP).
class StatTile extends StatelessWidget {
  const StatTile({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.footer,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$value $label',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: iconColor),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              if (footer != null) ...[const SizedBox(height: 6), footer!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded progress bar (missions done, XP).
class PillProgressBar extends StatelessWidget {
  const PillProgressBar({
    required this.value,
    this.height = 10,
    this.color,
    this.semanticsLabel,
    super.key,
  });

  final double value;
  final double height;
  final Color? color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: height,
        color: color ?? context.colors.primary,
        backgroundColor: context.colors.surfaceContainerHighest,
        semanticsLabel: semanticsLabel,
      ),
    );
  }
}

/// Status capsule ("Pending Approval ⏳", "Approved ✅").
class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: context.text.labelMedium?.copyWith(
                  color: foreground,
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

/// Mascot image next to a speech bubble ("Panda Kavach says:").
class MascotBubble extends StatelessWidget {
  const MascotBubble({
    required this.image,
    required this.message,
    this.title,
    this.imageSize = 72,
    super.key,
  });

  final String image;
  final String message;
  final String? title;
  final double imageSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primaryFixed,
            colors.surfaceContainer,
            colors.surfaceContainerHigh,
          ],
        ),
        borderRadius: AppRadius.card,
        boxShadow: AppShadows.tier1,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: imageSize,
              height: imageSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surfaceContainerLowest,
                boxShadow: AppShadows.tier1,
              ),
              padding: const EdgeInsets.all(3),
              child: ClipOval(
                child: Image.asset(
                  image,
                  fit: BoxFit.cover,
                  cacheWidth: (imageSize * dpr).round(),
                  excludeFromSemantics: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLowest.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: context.text.titleSmall?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                      Text(message, style: context.text.bodyMedium),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
