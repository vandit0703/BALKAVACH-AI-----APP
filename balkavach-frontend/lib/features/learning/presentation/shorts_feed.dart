import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/playable_video.dart';
import '../data/video_feed_repository.dart';
import '../data/video_playback_controller.dart';
import 'video_player_screen.dart' show formatPlaybackTime;
import 'widgets/video_actions.dart';
import 'youtube_player_screen.dart';

/// Colours of the full-bleed Shorts surface: a black video stage, brand
/// navy behind stills and empty states, white type and the star accent.
abstract final class _ShortsColors {
  static const background = AppPalette.navy;
  static const stage = Colors.black;
  static const onDark = AppPalette.onPrimary;
  static const chip = Color(0x33FFFFFF);
  static const accent = AppPalette.star;
}

/// Full-screen Shorts: one approved video per page, swiped vertically.
///
/// Opened from the Shorts row on Home. Covers the bottom navigation, like any
/// player, and Android back returns to where the child was.
class ShortsFeedScreen extends StatelessWidget {
  const ShortsFeedScreen({this.launch = const ShortsLaunch(), super.key});

  final ShortsLaunch launch;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _ShortsColors.stage,
    // Edge to edge: the video runs under the status and navigation bars;
    // each page pads its own controls with the system insets.
    body: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ShortsFeed(
        launch: launch,
        showMissionsAction: true,
        onBack: () => Navigator.of(context).maybePop(),
      ),
    ),
  );
}

/// The approved child Shorts feed from `GET /videos/shorts`: paging, the top
/// bar and the loading, empty and error states. Playback itself is
/// [ShortsPlayerPager]'s job.
class ShortsFeed extends ConsumerStatefulWidget {
  const ShortsFeed({
    this.launch = const ShortsLaunch(),
    this.showMissionsAction = false,
    this.onBack,
    super.key,
  });

  final ShortsLaunch launch;
  final bool showMissionsAction;

  /// Shows a back button in the top bar when set.
  final VoidCallback? onBack;

  @override
  ConsumerState<ShortsFeed> createState() => _ShortsFeedState();
}

class _ShortsFeedState extends ConsumerState<ShortsFeed> {
  late final VideoFeedPager _pager;
  late final int _start;
  int _current = 0;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    final launch = widget.launch;
    _pager = VideoFeedPager(
      ref.read(videoFeedRepositoryProvider),
      VideoFeedKind.shorts,
      pageSize: 10,
      initialItems: launch.initialVideos,
      initialOffset: launch.nextOffset,
      initialDone: launch.exhausted,
    )..addListener(_changed);
    _start = _current = launch.initialVideos.isEmpty
        ? 0
        : launch.initialIndex.clamp(0, launch.initialVideos.length - 1);
    if (_pager.items.isEmpty) {
      unawaited(_pager.loadMore());
    } else {
      _maybeLoadMore();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _maybeLoadMore() {
    if (_current >= _pager.items.length - 3 &&
        _pager.status == PagerStatus.idle) {
      unawaited(_pager.loadMore());
    }
  }

  @override
  void dispose() {
    _pager
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _pager.items;
    final ended =
        _pager.status == PagerStatus.done || _pager.status == PagerStatus.error;
    if (items.isEmpty) {
      return ColoredBox(
        color: _ShortsColors.background,
        child: Column(
          children: [
            _ShortsTopBar(onBack: widget.onBack, loadingMore: false),
            Expanded(child: _emptyBody(context)),
          ],
        ),
      );
    }
    return ShortsPlayerPager(
      videos: [for (final video in items) PlayableVideo.fromFeed(video)],
      initialIndex: _start,
      muted: _muted,
      onToggleMute: () => setState(() => _muted = !_muted),
      onBack: widget.onBack,
      loadingMore: _pager.status == PagerStatus.loading,
      trailing: ended ? _endPage(context) : null,
      onPageChanged: (index) {
        _current = index;
        _maybeLoadMore();
      },
    );
  }

  Widget _emptyBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final Widget child;
    if (_pager.status == PagerStatus.error) {
      child = ErrorView(
        key: const Key('videos.shorts.error'),
        error: _pager.error!,
        onRetry: _pager.retry,
      );
    } else if (_pager.status == PagerStatus.done) {
      child = EmptyView(
        key: const Key('videos.shorts.empty'),
        message: l10n.videoFeedEmpty,
        image: AppImages.pandaDrawing,
        action: widget.showMissionsAction
            ? FilledButton.icon(
                key: const Key('videos.shorts.toMissions'),
                onPressed: () => context.go(AppRoutes.childMissions),
                icon: const Icon(Icons.rocket_launch_rounded),
                label: Text(l10n.watchMissionsOpen),
              )
            : null,
      );
    } else {
      return const Center(
        child: CircularProgressIndicator(color: _ShortsColors.onDark),
      );
    }
    // The shared state views are designed for light surfaces.
    return ColoredBox(
      color: context.colors.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: child,
        ),
      ),
    );
  }

  Widget _endPage(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_pager.status == PagerStatus.error) {
      return ColoredBox(
        color: context.colors.surface,
        child: SafeArea(
          child: ErrorView(
            key: const Key('videos.shorts.pageError'),
            error: _pager.error!,
            onRetry: _pager.retry,
          ),
        ),
      );
    }
    final end = Center(
      key: const Key('videos.shorts.end'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.celebration_rounded,
              size: 56,
              color: _ShortsColors.accent,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.shortsEnd,
              textAlign: TextAlign.center,
              style: context.text.titleLarge?.copyWith(
                color: _ShortsColors.onDark,
              ),
            ),
            if (widget.showMissionsAction) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                key: const Key('videos.shorts.endToMissions'),
                onPressed: () => context.go(AppRoutes.childMissions),
                icon: const Icon(Icons.rocket_launch_rounded),
                label: Text(l10n.watchMissionsOpen),
              ),
            ],
          ],
        ),
      ),
    );
    return ColoredBox(
      color: _ShortsColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          end,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _ShortsTopBar(onBack: widget.onBack, loadingMore: false),
          ),
        ],
      ),
    );
  }
}

/// Vertical, one-video-per-page player for any mix of YouTube and direct
/// stream videos.
///
/// Playback rules, all enforced here rather than per player:
/// * only the settled, visible page plays; every other page shows a still;
/// * a direct stream for the next page may be prepared (never played), and
///   any controller further away is disposed;
/// * a fast fling through several pages starts no player for the pages it
///   passes, because a page only becomes playable once scrolling settles;
/// * nothing plays while the app is in the background, and the settled page
///   resumes when the app returns;
/// * leaving disposes every controller and web view.
///
/// Nothing here measures or reports viewing time.
class ShortsPlayerPager extends StatefulWidget {
  const ShortsPlayerPager({
    required this.videos,
    this.initialIndex = 0,
    this.muted = false,
    this.onToggleMute,
    this.onBack,
    this.loadingMore = false,
    this.trailing,
    this.onPageChanged,
    super.key,
  });

  final List<PlayableVideo> videos;
  final int initialIndex;
  final bool muted;
  final VoidCallback? onToggleMute;
  final VoidCallback? onBack;

  /// Shows a small spinner in the top bar while the next page loads.
  final bool loadingMore;

  /// An extra last page (end of feed, or a paging error).
  final Widget? trailing;
  final ValueChanged<int>? onPageChanged;

  @override
  State<ShortsPlayerPager> createState() => _ShortsPlayerPagerState();
}

class _ShortsPlayerPagerState extends State<ShortsPlayerPager>
    with WidgetsBindingObserver {
  late final PageController _pages;

  /// The page under the finger (updates mid-swipe).
  late int _current;

  /// The page that may play: only set once scrolling has settled.
  late int _active;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _current = _active = widget.videos.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.videos.length - 1);
    _pages = PageController(initialPage: _current);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground != _foreground) setState(() => _foreground = foreground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollEndNotification &&
        notification.depth == 0 &&
        _pages.hasClients) {
      final settled = (_pages.page ?? _current.toDouble()).round();
      if (settled != _active) setState(() => _active = settled);
    }
    return false;
  }

  void _onSwipe(double velocity) {
    if (!_pages.hasClients) return;
    const duration = Duration(milliseconds: 280);
    if (velocity < -250) {
      unawaited(_pages.nextPage(duration: duration, curve: Curves.easeOut));
    } else if (velocity > 250) {
      unawaited(_pages.previousPage(duration: duration, curve: Curves.easeOut));
    }
  }

  @override
  Widget build(BuildContext context) {
    final videos = widget.videos;
    final trailing = widget.trailing;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: PageView.builder(
        key: const Key('videos.shorts.pager'),
        controller: _pages,
        scrollDirection: Axis.vertical,
        // Keeps one neighbour built on each side, so the next page can
        // prepare its stream and thumbnail before it is shown.
        allowImplicitScrolling: true,
        itemCount: videos.length + (trailing == null ? 0 : 1),
        onPageChanged: (index) {
          setState(() => _current = index);
          widget.onPageChanged?.call(index);
        },
        itemBuilder: (context, index) {
          if (index >= videos.length) return trailing!;
          final video = videos[index];
          return _ShortsPage(
            key: ValueKey(video.key),
            video: video,
            active: index == _active && index == _current,
            foreground: _foreground,
            prepare: index == _active || index == _active + 1,
            muted: widget.muted,
            onToggleMute: widget.onToggleMute,
            onBack: widget.onBack,
            loadingMore: widget.loadingMore,
            showSwipeHint: index == 0 && videos.length > 1,
            onSwipe: _onSwipe,
          );
        },
      ),
    );
  }
}

/// One Short. Owns at most one player, and only while [prepare] is true.
class _ShortsPage extends ConsumerStatefulWidget {
  const _ShortsPage({
    required this.video,
    required this.active,
    required this.foreground,
    required this.prepare,
    required this.muted,
    required this.showSwipeHint,
    required this.onSwipe,
    this.onToggleMute,
    this.onBack,
    this.loadingMore = false,
    super.key,
  });

  final PlayableVideo video;
  final VoidCallback? onToggleMute;
  final VoidCallback? onBack;
  final bool loadingMore;

  /// Settled and visible: the only page that may play.
  final bool active;

  /// The app is in the foreground. A direct stream pauses while it is not;
  /// the YouTube embed pauses and resumes itself, keeping its position.
  final bool foreground;

  /// May hold a (paused) hosted-stream controller.
  final bool prepare;
  final bool muted;
  final bool showSwipeHint;
  final ValueChanged<double> onSwipe;

  @override
  ConsumerState<_ShortsPage> createState() => _ShortsPageState();
}

class _ShortsPageState extends ConsumerState<_ShortsPage>
    with WidgetsBindingObserver {
  VideoPlaybackController? _controller;
  final _progress = ValueNotifier<double>(0);

  /// The child tapped to pause; cleared when the page stops being active.
  bool _userPaused = false;
  bool _failed = false;

  /// YouTube refused to embed this video: retrying will not help.
  bool _blocked = false;

  /// Bumped on retry so the player is built afresh.
  int _attempt = 0;

  // Last seen controller state, so player ticks only rebuild on real change.
  bool _wasPlaying = false;
  bool _wasBuffering = false;
  bool _wasReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncStream();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause right here, not through a rebuild: Flutter stops producing
    // frames in the background, so a rebuild might not happen until the app
    // returns, and the audio would keep going until then. Resuming goes
    // through the pager's rebuild once frames are back.
    final controller = _controller;
    if (state != AppLifecycleState.resumed &&
        controller != null &&
        controller.isPlaying) {
      unawaited(controller.pause());
    }
  }

  @override
  void didUpdateWidget(_ShortsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) _userPaused = false;
    _syncStream();
  }

  /// Creates, drives or releases the hosted-stream controller so it matches
  /// [_ShortsPage.prepare] and [_ShortsPage.active].
  void _syncStream() {
    final source = widget.video.source;
    if (source is! DirectStreamSource) return;
    if (widget.prepare && _controller == null && !_failed) {
      _create(source.uri);
    } else if (!widget.prepare && _controller != null) {
      _release();
    }
    // Controllers notify synchronously from play/pause; this runs during a
    // build, so drive them right after it instead.
    scheduleMicrotask(_applyPlayback);
  }

  void _create(Uri uri) {
    final controller = ref.read(videoPlaybackControllerFactoryProvider)(uri);
    _controller = controller;
    controller.listenable.addListener(_onPlayer);
    unawaited(_initialise(controller));
  }

  Future<void> _initialise(VideoPlaybackController controller) async {
    await Future<void>.value();
    if (!mounted || _controller != controller) return;
    await controller.initialise();
    // Released (scrolled away or disposed) while initialising.
    if (!mounted || _controller != controller) return;
    if (controller.errorMessage != null) {
      setState(() => _failed = true);
      return;
    }
    _applyPlayback();
    setState(() {});
  }

  void _applyPlayback() {
    final controller = _controller;
    if (!mounted || controller == null || !controller.isInitialised) return;
    unawaited(controller.setVolume(widget.muted ? 0 : 1));
    final shouldPlay = widget.active && widget.foreground && !_userPaused;
    if (shouldPlay && !controller.isPlaying) {
      unawaited(controller.play());
    } else if (!shouldPlay && controller.isPlaying) {
      unawaited(controller.pause());
    }
  }

  void _onPlayer() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final total = controller.duration.inMilliseconds;
    _progress.value = total <= 0
        ? 0
        : (controller.position.inMilliseconds / total).clamp(0.0, 1.0);
    final failed = controller.errorMessage != null;
    if (failed != _failed ||
        controller.isPlaying != _wasPlaying ||
        controller.isBuffering != _wasBuffering ||
        controller.isInitialised != _wasReady) {
      setState(() {
        _failed = _failed || failed;
        _wasPlaying = controller.isPlaying;
        _wasBuffering = controller.isBuffering;
        _wasReady = controller.isInitialised;
      });
    }
  }

  void _release() {
    final controller = _controller;
    _controller = null;
    _wasPlaying = _wasBuffering = _wasReady = false;
    if (controller == null) return;
    controller.listenable.removeListener(_onPlayer);
    // Disposal stops audio immediately; a leaked controller would keep
    // playing after the page is gone.
    unawaited(controller.dispose());
  }

  void _retry() => setState(() {
    _release();
    _failed = false;
    _blocked = false;
    _attempt++;
    _progress.value = 0;
    _syncStream();
  });

  void _togglePause() {
    if (_controller?.isInitialised != true) return;
    setState(() => _userPaused = !_userPaused);
    _applyPlayback();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release();
    _progress.dispose();
    super.dispose();
  }

  Widget _overlay({required double bottomReserve}) => _ShortsOverlay(
    video: widget.video,
    muted: widget.muted,
    onToggleMute: widget.onToggleMute,
    progress: _progress,
    showSwipeHint: widget.showSwipeHint,
    bottomReserve: bottomReserve,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final insets = MediaQuery.paddingOf(context);
      final source = widget.video.source;
      final topBar = Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: _ShortsTopBar(
          onBack: widget.onBack,
          loadingMore: widget.loadingMore,
        ),
      );

      if (source is YouTubeVideoSource &&
          widget.active &&
          !_failed &&
          !_blocked) {
        // The official player fills everything below the top bar. YouTube
        // draws its own title bar at the top of the player, so the player
        // starts below ours instead of under it.
        final top = insets.top + _topBarHeight;
        final height = constraints.maxHeight - top - insets.bottom;
        final aspect = height <= 0 ? 9 / 16 : constraints.maxWidth / height;
        return ColoredBox(
          color: _ShortsColors.stage,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: top,
                left: 0,
                right: 0,
                bottom: insets.bottom,
                child: _youTubePlayer(context, source.videoId, aspect),
              ),
              topBar,
            ],
          ),
        );
      }

      return ColoredBox(
        color: _ShortsColors.stage,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _stage(context, constraints.biggest),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(bottom: insets.bottom),
                child: _overlay(bottomReserve: 0),
              ),
            ),
            topBar,
          ],
        ),
      );
    },
  );

  Widget _youTubePlayer(BuildContext context, String videoId, double aspect) {
    final embed = ref.watch(youtubeEmbedBuilderProvider);
    return Center(
      child: KeyedSubtree(
        key: ValueKey(('shorts.embed', widget.video.key, _attempt)),
        child: embed(
          YouTubeEmbedConfig(
            videoId: videoId,
            autoplay: true,
            muted: widget.muted,
            aspectRatio: aspect,
            overlay: _overlay(bottomReserve: kYouTubeControlsReserve),
            onLeaveRequested: (uri) => askGrownUpThenOpen(context, ref, uri),
            onForeignVideo: () {},
            onError: () {
              if (mounted && !_failed) setState(() => _failed = true);
            },
            onBlocked: () {
              if (mounted && !_blocked) setState(() => _blocked = true);
            },
            onProgress: (position, duration) {
              final total = duration.inMilliseconds;
              _progress.value = total <= 0
                  ? 0
                  : (position.inMilliseconds / total).clamp(0.0, 1.0);
            },
            onVerticalSwipe: widget.onSwipe,
          ),
        ),
      ),
    );
  }

  /// The picture when no web view is on screen: a still, a message, or a
  /// direct stream fitted to the page.
  Widget _stage(BuildContext context, Size page) {
    final l10n = AppLocalizations.of(context);
    final video = widget.video;
    final still = _SafeFitStill(url: video.thumbnailUrl);

    switch (video.source) {
      case UnavailableSource(:final reason):
        return _StageMessage(
          key: const Key('videos.shorts.unavailable'),
          background: still,
          icon: Icons.lock_rounded,
          message: reason == VideoUnavailableReason.needsGrownUp
              ? l10n.videoNeedsGrownUp
              : l10n.learnNotReady,
        );
      case YouTubeVideoSource():
        if (_blocked) {
          return _StageMessage(
            key: const Key('videos.shorts.blocked'),
            background: still,
            icon: Icons.block_rounded,
            message: l10n.videoNotEmbeddable,
          );
        }
        if (_failed) {
          return _StageMessage(
            background: still,
            icon: Icons.wifi_off_rounded,
            message: l10n.youtubePlayerError,
            onRetry: _retry,
          );
        }
        return still;
      case DirectStreamSource():
        if (_failed) {
          return _StageMessage(
            background: still,
            icon: Icons.wifi_off_rounded,
            message: l10n.videoPlaybackFailed,
            onRetry: _retry,
          );
        }
        final controller = _controller;
        final surface = controller?.buildSurface();
        final loading = surface == null || (controller?.isBuffering ?? false);
        Widget picture = still;
        if (surface != null) {
          final videoAspect = controller!.aspectRatio;
          final fit = shortsFitFor(
            videoAspect: videoAspect,
            boxAspect: page.width / page.height,
          );
          picture = fit == BoxFit.cover
              ? SizedBox.expand(
                  key: const Key('videos.shorts.fit.cover'),
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: videoAspect * 1000,
                      height: 1000,
                      child: surface,
                    ),
                  ),
                )
              : Stack(
                  key: const Key('videos.shorts.fit.contain'),
                  fit: StackFit.expand,
                  children: [
                    still,
                    Center(
                      child: AspectRatio(
                        aspectRatio: videoAspect,
                        child: surface,
                      ),
                    ),
                  ],
                );
        }
        return GestureDetector(
          key: const Key('videos.shorts.tapToPause'),
          behavior: HitTestBehavior.opaque,
          onTap: _togglePause,
          child: Stack(
            fit: StackFit.expand,
            children: [
              picture,
              if (widget.active && loading)
                Center(
                  child: Semantics(
                    label: l10n.videoLoading,
                    child: const CircularProgressIndicator(
                      key: Key('videos.shorts.buffering'),
                      color: _ShortsColors.onDark,
                    ),
                  ),
                ),
              if (_userPaused && surface != null)
                Center(
                  child: Icon(
                    Icons.play_arrow_rounded,
                    key: const Key('videos.shorts.paused'),
                    size: 88,
                    color: _ShortsColors.onDark.withValues(alpha: 0.9),
                    semanticLabel: l10n.videoPlay,
                  ),
                ),
            ],
          ),
        );
    }
  }
}

/// Height of the Shorts top bar below the status bar.
const double _topBarHeight = 56;

/// Space left free at the bottom of a YouTube player for YouTube's own
/// control bar, so our overlay never covers YouTube's controls or logo.
const double kYouTubeControlsReserve = 48;

/// How a video picture fills the Shorts page.
///
/// A portrait video close to the page's own shape fills it edge to edge
/// (`cover`), losing at most a sliver at the sides. Anything else (landscape,
/// square, or a very different shape) is shown whole (`contain`) over a
/// blurred copy of its thumbnail, so nothing important is cropped away.
BoxFit shortsFitFor({required double videoAspect, required double boxAspect}) {
  if (videoAspect <= 0 || boxAspect <= 0 || videoAspect >= 1) {
    return BoxFit.contain;
  }
  final ratio = videoAspect / boxAspect;
  return ratio >= 0.75 && ratio <= 1.34 ? BoxFit.cover : BoxFit.contain;
}

class _ShortsTopBar extends StatelessWidget {
  const _ShortsTopBar({required this.onBack, required this.loadingMore});

  final VoidCallback? onBack;
  final bool loadingMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x99000000), Color(0x00000000)],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.sm, top, AppSpacing.sm, 0),
        child: SizedBox(
          height: _topBarHeight,
          child: Row(
            children: [
              if (onBack != null) ...[
                _RoundButton(
                  key: const Key('videos.shorts.back'),
                  icon: Icons.arrow_back_rounded,
                  tooltip: l10n.videoBack,
                  onPressed: onBack!,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              const Icon(Icons.bolt_rounded, color: _ShortsColors.accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  l10n.shortsTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleLarge?.copyWith(
                    color: _ShortsColors.onDark,
                    shadows: _textShadows,
                  ),
                ),
              ),
              if (loadingMore)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _ShortsColors.onDark,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const _textShadows = [
  Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1)),
];

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: _ShortsColors.chip,
      foregroundColor: _ShortsColors.onDark,
      minimumSize: const Size.square(48),
    ),
    icon: Icon(icon),
  );
}

/// One action in the right-hand column: a round button with a short label.
class _ShortsAction extends StatelessWidget {
  const _ShortsAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundButton(icon: icon, tooltip: tooltip, onPressed: onPressed),
        const SizedBox(height: 2),
        SizedBox(
          width: 64,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.text.labelSmall?.copyWith(
              color: _ShortsColors.onDark,
              shadows: _textShadows,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Everything drawn on top of the video: a soft gradient, the details at the
/// bottom left, the actions on the right and a thin progress line.
///
/// For YouTube this is handed to the embed, which draws it above the web
/// view; [bottomReserve] then keeps YouTube's control bar uncovered.
class _ShortsOverlay extends ConsumerStatefulWidget {
  const _ShortsOverlay({
    required this.video,
    required this.muted,
    required this.onToggleMute,
    required this.progress,
    required this.showSwipeHint,
    this.bottomReserve = 0,
  });

  final PlayableVideo video;
  final bool muted;
  final VoidCallback? onToggleMute;
  final ValueListenable<double> progress;
  final bool showSwipeHint;
  final double bottomReserve;

  @override
  ConsumerState<_ShortsOverlay> createState() => _ShortsOverlayState();
}

class _ShortsOverlayState extends ConsumerState<_ShortsOverlay> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final video = widget.video;
    final reportId = video.reportVideoId;
    final bottom = widget.bottomReserve;
    final onToggleMute = widget.onToggleMute;

    return LayoutBuilder(
      key: const Key('videos.shorts.overlay'),
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          // Legibility only; never catches a tap.
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom,
            height: constraints.maxHeight * 0.45,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xB3000000)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            right: 84,
            bottom: bottom + AppSpacing.md,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: (constraints.maxHeight - bottom) * 0.5,
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: _details(context, l10n),
              ),
            ),
          ),
          Positioned(
            right: AppSpacing.sm,
            bottom: bottom + AppSpacing.md,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (constraints.maxHeight - bottom) * 0.6,
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onToggleMute != null)
                      _ShortsAction(
                        key: const Key('videos.shorts.mute'),
                        icon: widget.muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        label: l10n.shortsActionSound,
                        tooltip: widget.muted
                            ? l10n.videoUnmute
                            : l10n.videoMute,
                        onPressed: onToggleMute,
                      ),
                    if (video.shareUri != null)
                      _ShortsAction(
                        key: const Key('videos.shorts.share'),
                        icon: Icons.share_rounded,
                        label: l10n.videoShare,
                        tooltip: l10n.videoShare,
                        onPressed: () =>
                            confirmAndShareVideo(context, ref, video),
                      ),
                    if (reportId != null)
                      _ShortsAction(
                        key: const Key('videos.shorts.report'),
                        icon: Icons.flag_outlined,
                        label: l10n.shortsActionReport,
                        tooltip: l10n.videoReport,
                        onPressed: () => reportVideo(context, reportId),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom,
            child: ValueListenableBuilder<double>(
              valueListenable: widget.progress,
              builder: (context, value, _) => LinearProgressIndicator(
                key: const Key('videos.shorts.progress'),
                value: value,
                minHeight: 3,
                color: _ShortsColors.accent,
                backgroundColor: _ShortsColors.chip,
                semanticsLabel: l10n.videoProgressLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _details(BuildContext context, AppLocalizations l10n) {
    final video = widget.video;
    final channel = video.channelName;
    final description = video.descriptionWithoutHashtags;
    final hashtags = video.hashtags;
    final duration = video.duration;
    const onDark = _ShortsColors.onDark;
    final soft = onDark.withValues(alpha: 0.85);
    TextStyle? style(TextStyle? base, Color color) =>
        base?.copyWith(color: color, shadows: _textShadows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (channel != null || duration != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                if (channel != null) ...[
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _ShortsColors.accent,
                    child: Text(
                      channel.characters.first.toUpperCase(),
                      style: context.text.titleSmall?.copyWith(
                        color: AppPalette.navy,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      channel,
                      key: const Key('videos.shorts.channel'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style(context.text.titleSmall, onDark),
                    ),
                  ),
                ],
                if (duration != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _ShortsColors.chip,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      child: Text(
                        formatPlaybackTime(duration),
                        key: const Key('videos.shorts.duration'),
                        style: style(context.text.labelSmall, onDark),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        Text(
          video.title,
          key: const Key('videos.shorts.title'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style(context.text.titleMedium, onDark),
        ),
        if (description != null || video.isYouTube)
          GestureDetector(
            key: const Key('videos.shorts.more'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (description != null)
                    Text(
                      description,
                      key: const Key('videos.shorts.description'),
                      maxLines: _expanded ? 8 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: style(context.text.bodyMedium, soft),
                    ),
                  if (_expanded && video.isYouTube)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        l10n.videoFeedAdsNotice,
                        style: style(context.text.bodySmall, soft),
                      ),
                    ),
                  Text(
                    _expanded ? l10n.shortsLess : l10n.shortsMore,
                    style: style(context.text.labelLarge, onDark),
                  ),
                ],
              ),
            ),
          ),
        if (hashtags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              hashtags.join(' '),
              key: const Key('videos.shorts.hashtags'),
              maxLines: _expanded ? 4 : 1,
              overflow: TextOverflow.ellipsis,
              style: style(context.text.labelLarge, AppPalette.primaryFixedDim),
            ),
          ),
        if (widget.showSwipeHint)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.swipe_up_rounded, size: 18, color: soft),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    l10n.shortsSwipeHint,
                    style: style(context.text.bodySmall, soft),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A still frame shown safely: blurred and darkened to fill the page, with
/// the whole picture on top.
class _SafeFitStill extends StatelessWidget {
  const _SafeFitStill({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return const ColoredBox(
        color: _ShortsColors.background,
        child: Center(
          child: Icon(
            Icons.play_circle_rounded,
            size: 56,
            color: _ShortsColors.onDark,
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0x66000000),
                BlendMode.darken,
              ),
              child: VideoThumbnail(
                url: url,
                placeholderColor: _ShortsColors.background,
                iconColor: _ShortsColors.onDark,
              ),
            ),
          ),
        ),
        VideoThumbnail(
          url: url,
          fit: BoxFit.contain,
          placeholderColor: Colors.transparent,
          iconColor: _ShortsColors.onDark,
        ),
      ],
    );
  }
}

/// A still picture with a short message (and optional retry) over it.
class _StageMessage extends StatelessWidget {
  const _StageMessage({
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
        Opacity(opacity: 0.45, child: background),
        Align(
          alignment: const Alignment(0, -0.2),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 40, color: _ShortsColors.onDark),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: context.text.bodyLarge?.copyWith(
                    color: _ShortsColors.onDark,
                    shadows: _textShadows,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    key: const Key('videos.shorts.retry'),
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
