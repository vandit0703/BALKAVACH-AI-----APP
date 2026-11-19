import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/app_assets.dart';
import '../domain/companion_director.dart';

/// Panda saying one authored line for [event], in the app's language.
///
/// The line is chosen once when the bubble first appears (so rebuilds do not
/// change it) by the shared [CompanionDirector]. When the director says the
/// event spoke very recently, nothing is drawn.
class PandaBubble extends ConsumerStatefulWidget {
  const PandaBubble({required this.event, this.minutes = 15, super.key});

  final CompanionEvent event;
  final int minutes;

  @override
  ConsumerState<PandaBubble> createState() => _PandaBubbleState();
}

class _PandaBubbleState extends ConsumerState<PandaBubble> {
  late final int? _variant = ref
      .read(companionDirectorProvider)
      .next(widget.event);

  @override
  Widget build(BuildContext context) {
    final variant = _variant;
    if (variant == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label:
          '${l10n.pandaName}: ${pandaLine(l10n, widget.event, variant, minutes: widget.minutes)}',
      child: ExcludeSemantics(
        child: Row(
          key: const Key('panda.bubble'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: colors.primaryContainer,
              backgroundImage: const AssetImage(AppImages.pandaCheering),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    pandaLine(
                      l10n,
                      widget.event,
                      variant,
                      minutes: widget.minutes,
                    ),
                    key: const Key('panda.line'),
                    style: context.text.bodyMedium,
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
