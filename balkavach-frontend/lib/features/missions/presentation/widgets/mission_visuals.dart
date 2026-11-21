import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/gamification.dart';
import '../../domain/mission_models.dart';
import '../../domain/mission_status.dart';

/// Icon and tint for a category. The backend's category names and
/// `icon_name` values are data, not an enum, so we match loosely and fall back
/// to a neutral rocket.
class CategoryVisual {
  const CategoryVisual(this.icon, this.tint, this.iconColor);

  final IconData icon;
  final Color tint;
  final Color iconColor;

  static CategoryVisual of(BuildContext context, TaskCategory? category) {
    final brand = context.brand;
    final colors = context.colors;
    final key = '${category?.iconName ?? ''} ${category?.name ?? ''}'
        .toLowerCase();
    if (_matches(key, ['learn', 'read', 'study', 'book', 'menu_book'])) {
      return CategoryVisual(
        Icons.menu_book_rounded,
        brand.learnTint,
        colors.primary,
      );
    }
    if (_matches(key, [
      'move',
      'sport',
      'yoga',
      'play',
      'outdoor',
      'run',
      'exercise',
    ])) {
      return CategoryVisual(
        Icons.directions_run_rounded,
        brand.moveTint,
        colors.onSecondaryContainer,
      );
    }
    if (_matches(key, ['help', 'chore', 'clean', 'home', 'volunteer'])) {
      return CategoryVisual(
        Icons.volunteer_activism_rounded,
        brand.helpTint,
        colors.tertiary,
      );
    }
    if (_matches(key, ['create', 'art', 'draw', 'craft', 'palette', 'music'])) {
      return CategoryVisual(
        Icons.palette_rounded,
        brand.createTint,
        colors.primary,
      );
    }
    if (_matches(key, ['habit', 'health', 'water', 'sleep', 'mind'])) {
      return CategoryVisual(
        Icons.water_drop_rounded,
        colors.surfaceContainerHigh,
        colors.primary,
      );
    }
    return CategoryVisual(
      Icons.rocket_launch_rounded,
      colors.surfaceContainerHigh,
      colors.primary,
    );
  }

  static bool _matches(String key, List<String> words) =>
      words.any(key.contains);

  /// Text colour for the category name: the icon colour, which keeps
  /// WCAG AA contrast on the white card.
  Color get labelColor => iconColor;
}

/// Category icon in a soft rounded tile (the card's illustration slot).
class CategoryTile extends StatelessWidget {
  const CategoryTile({required this.visual, this.size = 60, super.key});

  final CategoryVisual visual;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: visual.tint,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(visual.icon, color: visual.iconColor, size: size * 0.5),
    );
  }
}

/// Green check medal shown on a completed mission.
class CompletedBadge extends StatelessWidget {
  const CompletedBadge({this.size = 60, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.secondaryContainer,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(
        Icons.check_circle_rounded,
        color: context.colors.onSecondaryContainer,
        size: size * 0.55,
      ),
    );
  }
}

/// "15 XP" capsule matching [StarPill].
class XpPill extends StatelessWidget {
  const XpPill({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryFixed,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: 18, color: colors.primary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reward a mission pays on approval, as the server reports it
/// ("10 Stars", "15 XP"). Zero values are left out.
List<Widget> missionRewardPills(BuildContext context, int stars, int xp) {
  final l10n = AppLocalizations.of(context);
  return [
    if (stars > 0) StarPill(count: stars, label: l10n.missionStarsCount(stars)),
    if (xp > 0) XpPill(label: l10n.missionXpCount(xp)),
  ];
}

/// The first paragraph of a mission's description: the short "what is it"
/// line. (A chosen daily mission's description also carries its numbered
/// instructions and the parent check; those belong on the detail screen.)
String? missionSummary(String? description) {
  final text = description?.trim();
  if (text == null || text.isEmpty) return null;
  final first = text.split(RegExp(r'\n\s*\n')).first.trim();
  return first.isEmpty ? null : first;
}

class CategoryIcon extends StatelessWidget {
  const CategoryIcon({required this.visual, this.size = 56, super.key});

  final CategoryVisual visual;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: visual.tint, shape: BoxShape.circle),
      child: Icon(visual.icon, color: visual.iconColor, size: size * 0.5),
    );
  }
}

/// Chip for a reviewed or pending mission; `null` when not started.
Widget? missionStatusChip(BuildContext context, MissionStatus status) {
  final l10n = AppLocalizations.of(context);
  final colors = context.colors;
  return switch (status) {
    MissionStatus.notStarted => null,
    MissionStatus.pending => StatusChip(
      label: l10n.statusPending,
      icon: Icons.hourglass_top_rounded,
      background: colors.tertiaryFixed,
      foreground: colors.onTertiaryFixed,
    ),
    MissionStatus.approved => StatusChip(
      label: l10n.statusApproved,
      icon: Icons.verified_rounded,
      background: colors.secondaryContainer,
      foreground: colors.onSecondaryContainer,
    ),
    MissionStatus.rejected => StatusChip(
      label: l10n.statusRejected,
      icon: Icons.do_not_disturb_on_outlined,
      background: colors.errorContainer,
      foreground: colors.onErrorContainer,
    ),
    MissionStatus.resubmissionRequested => StatusChip(
      label: l10n.statusResubmit,
      icon: Icons.replay_rounded,
      background: colors.surfaceContainerHigh,
      foreground: colors.primary,
    ),
  };
}
