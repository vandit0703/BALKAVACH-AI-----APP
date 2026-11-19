import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/models/app_assets.dart';
import '../../data/playback_guard.dart';
import '../../data/video_feed_repository.dart';

/// The app's root messenger, so the low-time notice shows above whichever
/// screen (or player) the child is on.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Shows Panda's gentle "nearly done" notice when the server's remaining time
/// first drops to two minutes or less. Purely informative: it never pauses,
/// extends or unlocks anything; the server keeps deciding.
class LowTimeNoticeListener extends ConsumerWidget {
  const LowTimeNoticeListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<LowTimeNotice?>(lowTimeNoticeProvider, (previous, next) {
      if (next == null || next.serial == previous?.serial) return;
      // Cards showing the allowance re-read the server's figure.
      ref.invalidate(videoAllowanceProvider);
      final messenger = rootMessengerKey.currentState;
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('video.lowTime.notice'),
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            content: LowTimeNoticeContent(minutes: next.minutes),
          ),
        );
    });
    return child;
  }
}

class LowTimeNoticeContent extends StatelessWidget {
  const LowTimeNoticeContent({required this.minutes, super.key});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = l10n.videoLowTimeNotice(minutes);
    return Semantics(
      liveRegion: true,
      label: '${l10n.pandaName}: $text',
      child: ExcludeSemantics(
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: context.colors.primaryContainer,
              backgroundImage: const AssetImage(AppImages.pandaHoodie),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(text, key: const Key('video.lowTime.text'))),
          ],
        ),
      ),
    );
  }
}
