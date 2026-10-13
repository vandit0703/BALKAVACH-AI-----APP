import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// Equal-width tiles that wrap into as many columns as fit.
///
/// The column count accounts for the system text scale, so tiles stack to one
/// column on narrow screens or with large text instead of overflowing.
class AdaptiveWrap extends StatelessWidget {
  const AdaptiveWrap({
    required this.children,
    this.minTileWidth = 150,
    this.maxColumns = 4,
    this.spacing = AppSpacing.md,
    super.key,
  });

  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final columns = (constraints.maxWidth / (minTileWidth * textScale))
            .floor()
            .clamp(1, maxColumns);
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}
