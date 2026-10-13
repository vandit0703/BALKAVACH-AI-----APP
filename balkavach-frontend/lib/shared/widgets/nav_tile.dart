import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'app_card.dart';

/// Tappable row: round icon, title, optional subtitle and a chevron.
///
/// [tonal] renders the quieter in-card variant (no shadow, tinted fill);
/// otherwise the tile is a standalone elevated card.
class NavTile extends StatelessWidget {
  const NavTile({
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.tonal = false,
    super.key,
  });

  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      onTap: onTap,
      color: tonal ? colors.surfaceContainerLow : null,
      elevated: !tonal,
      radius: tonal ? BorderRadius.circular(AppRadius.md) : AppRadius.card,
      padding: EdgeInsets.all(tonal ? AppSpacing.md - 4 : AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            radius: tonal ? 22 : 24,
            backgroundColor: tint,
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: context.text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }
}
