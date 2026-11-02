import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/playable_video.dart';
import '../data/video_playback_controller.dart';
import 'video_player_screen.dart' show formatPlaybackTime;
import 'widgets/video_actions.dart';
import 'youtube_player_screen.dart';

/// The regular (non-Shorts) watching experience: a player, the video's
/// details and an "Up next" list.
///
/// A YouTube video plays in the official embed (YouTube's own controls,
/// branding, ads and fullscreen button). A direct stream plays in the native
/// player with play/pause, seek, buffering and a fullscreen toggle. Hosted
/// videos that need an approved reward are never played here. Nothing on
/// this screen measures or reports viewing time.
class VideoDetailPlayerScreen extends ConsumerStatefulWidget {
  const VideoDetailPlayerScreen({required this.launch, super.key});

  final VideoLaunch launch;

  @override
  ConsumerState<VideoDetailPlayerScreen> createState() =>
      _VideoDetailPlayerScreenState();
}

class _VideoDetailPlayerScreenState
    extends ConsumerState<VideoDetailPlayerScreen>
    with WidgetsBindingObserver {
  late PlayableVideo _video = widget.launch.video;
  VideoPlaybackController? _controller;
  bool _failed = false;
  bool _blocked = false;
  bool _fullscreen = false;
  bool _muted = false;

  /// Bumped on retry or on a new video so players are built afresh.
  int _attempt = 0;
  final _scroll = ScrollController();

  List<PlayableVideo> get _upNext => [
    for (final video in widget.launch.related)
      if (video.key != _video.key) video,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    final source = _video.source;
    if (source is! DirectStreamSource) return;
    final controller = ref.read(videoPlaybackControllerFactoryProvider)(
      source.uri,
    );
    _controller = controller;
    controller.listenable.addListener(_onPlayer);
    unawaited(_initialise(controller));
  }

  Future<void> _initialise(VideoPlaybackController controller) async {
    await controller.initialise();
    if (!mounted || _controller != controller) return;
    if (controller.errorMessage != null) {
      setState(() => _failed = true);
      return;
    }
    await controller.setVolume(_muted ? 0 : 1);
    await controller.play();
  }

  void _onPlayer() {
    final failed = _controller?.errorMessage != null;
    if (mounted && failed && !_failed) setState(() => _failed = true);
  }

  void _release() {
    final controller = _controller;
    _controller = null;
    controller?.listenable.removeListener(_onPlayer);
    unawaited(controller?.dispose());
  }

  void _retry() => setState(() {
    _release();
    _failed = false;
    _blocked = false;
    _attempt++;
    _start();
  });

  void _open(PlayableVideo next) {
    setState(() {
      _release();
      _video = next;
      _failed = false;
      _blocked = false;
      _attempt++;
      _start();
    });
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.isInitialised) return;
    await (controller.isPlaying ? controller.pause() : controller.play());
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _controller?.setVolume(_muted ? 0 : 1);
  }

  Future<void> _setFullscreen(bool value) async {
    if (value == _fullscreen) return;
    setState(() => _fullscreen = value);
    if (value) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await _restoreSystemUi();
    }
  }

  static Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const []);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Nothing plays behind another app. The YouTube embed pauses itself.
    if (state != AppLifecycleState.resumed) unawaited(_controller?.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release();
    _scroll.dispose();
    if (_fullscreen) unawaited(_restoreSystemUi());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stage = KeyedSubtree(
      key: ValueKey(('detail.stage', _video.key, _attempt)),
      child: _stage(context),
    );

    if (_fullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_setFullscreen(false));
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Column(
              children: [
                Expanded(child: Center(child: stage)),
                if (_controller != null)
                  _StreamControls(
                    controller: _controller!,
                    fullscreen: true,
                    muted: _muted,
                    onTogglePlay: _togglePlay,
                    onToggleMute: _toggleMute,
                    onToggleFullscreen: () => _setFullscreen(false),
                    dark: true,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final upNext = _upNext;
    final description = _video.description;
    final channel = _video.channelName;
    final reportId = _video.reportVideoId;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
        title: Text(l10n.watchTitle),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // In landscape the player may use most of the height, so the
            // details never push it off screen.
            final maxStageHeight = constraints.maxHeight * 0.8;
            return ListView(
              key: const Key('detail.list'),
              controller: _scroll,
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxStageHeight),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: ColoredBox(
                      color: Colors.black,
                      child: AspectRatio(
                        aspectRatio:
                            _controller?.isInitialised == true && !_failed
                            ? _controller!.aspectRatio
                            : 16 / 9,
                        child: stage,
                      ),
                    ),
                  ),
                ),
                if (_controller != null && !_failed) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _StreamControls(
                    controller: _controller!,
                    fullscreen: false,
                    muted: _muted,
                    onTogglePlay: _togglePlay,
                    onToggleMute: _toggleMute,
                    onToggleFullscreen: () => _setFullscreen(true),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Text(
                  _video.title,
                  key: const Key('detail.title'),
                  style: context.text.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (channel != null)
                      EyebrowPill(
                        icon: Icons.person_pin_rounded,
                        label: channel,
                      ),
                    if (_video.duration != null)
                      EyebrowPill(
                        icon: Icons.schedule_rounded,
                        label: formatPlaybackTime(_video.duration!),
                      ),
                    if (_video.isYouTube)
                      EyebrowPill(
                        icon: Icons.smart_display_rounded,
                        label: l10n.videoBadgeYouTube,
                      ),
                  ],
                ),
                if (description != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    description,
                    key: const Key('detail.description'),
                    style: context.text.bodyLarge,
                  ),
                ],
                if (_video.isYouTube) ...[
                  const SizedBox(height: AppSpacing.md),
                  InlineNotice(
                    icon: Icons.info_outline_rounded,
                    message: l10n.videoFeedAdsNotice,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (upNext.isNotEmpty)
                      PrimaryButton(
                        key: const Key('detail.next'),
                        label: l10n.videoPlayNext,
                        icon: Icons.skip_next_rounded,
                        childSized: true,
                        onPressed: () => _open(upNext.first),
                      ),
                    if (_video.shareUri != null)
                      SecondaryButton(
                        key: const Key('detail.share'),
                        label: l10n.videoShare,
                        icon: Icons.share_rounded,
                        dense: true,
                        onPressed: () =>
                            confirmAndShareVideo(context, ref, _video),
                      ),
                    if (reportId != null)
                      SecondaryButton(
                        key: const Key('detail.report'),
                        label: l10n.videoReport,
                        icon: Icons.flag_outlined,
                        dense: true,
                        onPressed: () => reportVideo(context, reportId),
                      ),
                  ],
                ),
                if (upNext.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(l10n.videoUpNext, style: context.text.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  for (final video in upNext)
                    _UpNextTile(video: video, onTap: () => _open(video)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _stage(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final video = _video;
    final still = VideoThumbnail(
      url: video.thumbnailUrl,
      placeholderColor: Colors.black,
      iconColor: AppPalette.onPrimary,
    );
    switch (video.source) {
      case UnavailableSource(:final reason):
        return _StageNotice(
          key: const Key('detail.unavailable'),
          background: still,
          icon: Icons.lock_rounded,
          message: reason == VideoUnavailableReason.needsGrownUp
              ? l10n.videoNeedsGrownUp
              : l10n.learnNotReady,
        );
      case YouTubeVideoSource(:final videoId):
        if (_blocked) {
          return _StageNotice(
            key: const Key('detail.blocked'),
            background: still,
            icon: Icons.block_rounded,
            message: l10n.videoNotEmbeddable,
          );
        }
        if (_failed) {
          return _StageNotice(
            key: const Key('detail.error'),
            background: still,
            icon: Icons.wifi_off_rounded,
            message: l10n.youtubePlayerError,
            onRetry: _retry,
          );
        }
        final embed = ref.watch(youtubeEmbedBuilderProvider);
        return embed(
          YouTubeEmbedConfig(
            videoId: videoId,
            autoplay: true,
            onLeaveRequested: (uri) => askGrownUpThenOpen(context, ref, uri),
            onForeignVideo: () {
              ScaffoldMessenger.maybeOf(context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text(l10n.youtubeOtherVideoBlocked)),
                );
            },
            onError: () {
              if (mounted && !_failed) setState(() => _failed = true);
            },
            onBlocked: () {
              if (mounted && !_blocked) setState(() => _blocked = true);
            },
          ),
        );
      case DirectStreamSource():
        if (_failed) {
          return _StageNotice(
            key: const Key('detail.error'),
            background: still,
            icon: Icons.wifi_off_rounded,
            message: l10n.videoPlaybackFailed,
            onRetry: _retry,
          );
        }
        final controller = _controller!;
        return ListenableBuilder(
          listenable: controller.listenable,
          builder: (context, _) {
            final surface = controller.buildSurface();
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlay,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (surface == null)
                    still
                  else
                    Center(
                      child: AspectRatio(
                        aspectRatio: controller.aspectRatio,
                        child: surface,
                      ),
                    ),
                  if (surface == null || controller.isBuffering)
                    Center(
                      child: CircularProgressIndicator(
                        key: const Key('detail.loading'),
                        color: AppPalette.onPrimary,
                        semanticsLabel: l10n.videoLoading,
                      ),
                    ),
                ],
              ),
            );
          },
        );
    }
  }
}

/// Play/pause, seek bar, time, sound and fullscreen for a direct stream.
class _StreamControls extends StatefulWidget {
  const _StreamControls({
    required this.controller,
    required this.fullscreen,
    required this.muted,
    required this.onTogglePlay,
    required this.onToggleMute,
    required this.onToggleFullscreen,
    this.dark = false,
  });

  final VideoPlaybackController controller;
  final bool fullscreen;
  final bool muted;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleFullscreen;
  final bool dark;

  @override
  State<_StreamControls> createState() => _StreamControlsState();
}

class _StreamControlsState extends State<_StreamControls> {
  /// Thumb position while the child drags, so the bar does not jump back.
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = widget.controller;
    final foreground = widget.dark ? AppPalette.onPrimary : null;

    return ListenableBuilder(
      listenable: controller.listenable,
      builder: (context, _) {
        final ready = controller.isInitialised;
        final totalMs = controller.duration.inMilliseconds.toDouble();
        final positionMs =
            (_dragMs ?? controller.position.inMilliseconds.toDouble()).clamp(
              0.0,
              totalMs <= 0 ? 0.0 : totalMs,
            );
        final playing = controller.isPlaying;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.fullscreen ? AppSpacing.md : 0,
          ),
          child: Row(
            children: [
              IconButton.filled(
                key: const Key('detail.playPause'),
                iconSize: 32,
                tooltip: playing ? l10n.videoPause : l10n.videoPlay,
                onPressed: ready ? widget.onTogglePlay : null,
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              Expanded(
                child: Slider(
                  key: const Key('detail.seek'),
                  value: positionMs,
                  max: totalMs <= 0 ? 1 : totalMs,
                  semanticFormatterCallback: (_) =>
                      '${formatPlaybackTime(Duration(milliseconds: positionMs.round()))} / '
                      '${formatPlaybackTime(controller.duration)}',
                  onChanged: ready && totalMs > 0
                      ? (value) => setState(() => _dragMs = value)
                      : null,
                  onChangeEnd: ready && totalMs > 0
                      ? (value) async {
                          await controller.seekTo(
                            Duration(milliseconds: value.round()),
                          );
                          if (mounted) setState(() => _dragMs = null);
                        }
                      : null,
                ),
              ),
              Text(
                '${formatPlaybackTime(Duration(milliseconds: positionMs.round()))}'
                ' / ${formatPlaybackTime(controller.duration)}',
                key: const Key('detail.time'),
                style: context.text.bodySmall?.copyWith(color: foreground),
              ),
              IconButton(
                key: const Key('detail.mute'),
                color: foreground,
                tooltip: widget.muted ? l10n.videoUnmute : l10n.videoMute,
                onPressed: widget.onToggleMute,
                icon: Icon(
                  widget.muted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                ),
              ),
              IconButton(
                key: const Key('detail.fullscreen'),
                color: foreground,
                tooltip: widget.fullscreen
                    ? l10n.videoExitFullscreen
                    : l10n.videoFullscreen,
                onPressed: widget.onToggleFullscreen,
                icon: Icon(
                  widget.fullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StageNotice extends StatelessWidget {
  const _StageNotice({
    required this.background,
    required this.icon,
    required this.message,
    this.onRetry,
    super.key,
  });

  final Widget background;
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: 0.3, child: background),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 36, color: AppPalette.onPrimary),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(
                    color: AppPalette.onPrimary,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.icon(
                    key: const Key('detail.retry'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(l10n.videoRetry),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UpNextTile extends StatelessWidget {
  const _UpNextTile({required this.video, required this.onTap});

  final PlayableVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final duration = video.duration;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        key: Key('detail.upNext.${video.key}'),
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 128,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: VideoThumbnail(url: video.thumbnailUrl),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleMedium,
                    ),
                    if (duration != null || !video.isPlayable)
                      Row(
                        children: [
                          if (!video.isPlayable) ...[
                            Icon(
                              Icons.lock_rounded,
                              size: 14,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                          ],
                          if (duration != null)
                            Text(
                              formatPlaybackTime(duration),
                              style: context.text.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
