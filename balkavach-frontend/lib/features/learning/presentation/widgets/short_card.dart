import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../data/playable_video.dart';
import 'video_actions.dart' show VideoThumbnail;

/// A portrait Shorts card: thumbnail, "Short" pill, title, and a lock while
/// the child has no video time. Used by Home's Quick videos row and the
/// Learning Hub's Shorts tab.
class ShortCard extends StatelessWidget {
  const ShortCard({
    required this.video,
    required this.onTap,
    this.width = 132,
    this.keyPrefix = 'watch.short',
    super.key,
  });

  final PlayableVideo video;
  final VoidCallback onTap;

  /// Fixed width for a horizontal row; `null` fills the parent (grid cells).
  final double? width;

  /// The tap target is keyed `<keyPrefix>.<video key>`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: width,
      child: Material(
        color: AppPalette.navy,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('$keyPrefix.${video.key}'),
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoThumbnail(
                url: video.thumbnailUrl,
                placeholderColor: AppPalette.navy,
                iconColor: AppPalette.onPrimary,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)],
                    stops: [0.45, 1],
                  ),
                ),
              ),
              if (!video.isPlayable)
                const Center(
                  child: Icon(
                    Icons.lock_rounded,
                    key: Key('watch.short.locked'),
                    size: 36,
                    color: AppPalette.onPrimary,
                  ),
                ),
              Positioned(
                top: AppSpacing.sm,
                left: AppSpacing.sm,
                child: EyebrowPill(
                  icon: Icons.bolt_rounded,
                  label: l10n.videoBadgeShort,
                  background: AppPalette.star,
                  foreground: AppPalette.navy,
                ),
              ),
              Positioned(
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: Text(
                  video.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(
                    color: AppPalette.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
