import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/gamification.dart';

/// A reward's title with its star cost.
///
/// Side by side when there is room; on a narrow card or with large text the
/// star pill moves under the title, so a long reward name is never squeezed
/// into a sliver beside the pill (it wrapped to a word or two per line).
class RewardTitleRow extends StatelessWidget {
  const RewardTitleRow({
    required this.title,
    required this.stars,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    super.key,
  });

  final Widget title;
  final int stars;

  /// Vertical alignment of title and pill when side by side (as each card
  /// had it before).
  final CrossAxisAlignment crossAxisAlignment;

  /// Width, at 1x text, below which the pill goes under the title.
  static const sideBySideMinWidth = 220.0;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= sideBySideMinWidth * textScale) {
          return Row(
            crossAxisAlignment: crossAxisAlignment,
            children: [
              Expanded(child: title),
              const SizedBox(width: AppSpacing.sm),
              StarPill(count: stars),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.xs,
          children: [
            title,
            StarPill(count: stars),
          ],
        );
      },
    );
  }
}
