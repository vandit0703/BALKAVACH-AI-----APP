import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../data/learning_repository.dart';
import '../data/video_playback_controller.dart';
import 'learning_screen.dart';

/// Formats a playback position as m:ss (or h:mm:ss for long content).
String formatPlaybackTime(Duration value) {
  final seconds = value.inSeconds.clamp(0, const Duration(days: 1).inSeconds);
  final minutes = seconds ~/ 60;
  final hours = minutes ~/ 60;
  final ss = (seconds % 60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${(minutes % 60).toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

/// Plays one curated educational video inside the app.
///
/// Only content the server chose to hand over is playable here: the backend
/// withholds the URL for hosted and entitlement-gated videos, which still go
/// through the authorised playback-session API and are not reachable from this
/// screen. Nothing here reports viewing progress, because an unauthorised
/// player has no server-accepted session to report against.
class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({required this.item, super.key});

  final LearningItem item;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen>
    with WidgetsBindingObserver {
  VideoPlaybackController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    final uri = widget.item.openableUri;
    if (uri == null) return;
    final controller = ref.read(videoPlaybackControllerFactoryProvider)(uri);
    setState(() => _controller = controller);
    controller.listenable.addListener(_onPlayerChanged);
    await controller.initialise();
    if (!mounted) return;
    // Autoplay only once the decoder is ready and healthy.
    if (controller.isInitialised && controller.errorMessage == null) {
      await controller.play();
    }
  }

  void _onPlayerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _retry() async {
    final previous = _controller;
    setState(() => _controller = null);
    previous?.listenable.removeListener(_onPlayerChanged);
    await previous?.dispose();
    if (mounted) await _start();
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.isInitialised) return;
    if (controller.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding must stop playback: audio continuing behind another app is
    // both wrong for a child app and would be time nobody is watching.
    if (state != AppLifecycleState.resumed) {
      _controller?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    controller?.listenable.removeListener(_onPlayerChanged);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _Stage(
              controller: controller,
              onRetry: _retry,
              hasSource: item.openableUri != null,
            ),
            const SizedBox(height: AppSpacing.md),
            if (controller != null &&
                controller.isInitialised &&
                controller.errorMessage == null)
              _Controls(controller: controller, onTogglePlay: _togglePlay),
            const SizedBox(height: AppSpacing.md),
            Text(item.title, style: context.text.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                EyebrowPill(label: learningTypeName(l10n, item.contentType)),
              ],
            ),
            if ((item.description ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(item.description!.trim(), style: context.text.bodyLarge),
            ],
          ],
        ),
      ),
    );
  }
}

/// The picture area: the video, or the loading/error state in its place.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.controller,
    required this.onRetry,
    required this.hasSource,
  });

  final VideoPlaybackController? controller;
  final VoidCallback onRetry;

  /// False when the item carries no playable URL at all.
  final bool hasSource;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final surface = controller?.buildSurface();
    final failed = controller?.errorMessage != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ColoredBox(
        color: colors.surfaceContainerHighest,
        child: AspectRatio(
          aspectRatio: controller?.aspectRatio ?? 16 / 9,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (surface != null && !failed) surface,
              if (failed)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: colors.error,
                        size: 36,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        l10n.videoPlaybackFailed,
                        key: const Key('player.error'),
                        textAlign: TextAlign.center,
                        style: context.text.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SecondaryButton(
                        key: const Key('player.retry'),
                        dense: true,
                        label: l10n.videoRetry,
                        icon: Icons.refresh_rounded,
                        onPressed: onRetry,
                      ),
                    ],
                  ),
                )
              else if (!hasSource)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    l10n.videoNotPlayableInApp,
                    key: const Key('player.noSource'),
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium,
                  ),
                )
              else if (surface == null || controller?.isBuffering == true)
                const CircularProgressIndicator(key: Key('player.loading')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Play/pause and elapsed time. Children must always be able to stop.
class _Controls extends StatelessWidget {
  const _Controls({required this.controller, required this.onTogglePlay});

  final VideoPlaybackController controller;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final playing = controller.isPlaying;
    final total = controller.duration;
    final progress = total.inMilliseconds <= 0
        ? 0.0
        : (controller.position.inMilliseconds / total.inMilliseconds).clamp(
            0.0,
            1.0,
          );

    return Row(
      children: [
        IconButton.filled(
          key: const Key('player.playPause'),
          // A 48dp target: the control a child uses most must be easy to hit.
          iconSize: 32,
          tooltip: playing ? l10n.videoPause : l10n.videoPlay,
          onPressed: onTogglePlay,
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  key: const Key('player.progress'),
                  value: progress,
                  minHeight: 8,
                  backgroundColor: colors.surfaceContainerHighest,
                  semanticsLabel: l10n.videoProgressLabel,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${formatPlaybackTime(controller.position)} / '
                '${formatPlaybackTime(total)}',
                key: const Key('player.time'),
                style: context.text.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
