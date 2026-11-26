import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart' show appRouteObserver;
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/diag/video_diag.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/state_views.dart';
import '../../missions/presentation/mission_providers.dart'
    show childNotificationsProvider;
import '../data/learning_repository.dart';
import '../data/playable_video.dart';
import '../data/video_feed_repository.dart';
import 'video_lock_screen.dart';
import 'video_player_screen.dart' show formatPlaybackTime;
import 'widgets/learn_hub_entry.dart';
import 'widgets/short_card.dart';
import 'widgets/video_actions.dart';
import 'widgets/video_allowance_card.dart';

/// Home: Watch & Learn. A unified, personalized discovery feed of Shorts,
/// regular videos, Continue Watching, and grown-up picks.
///
/// Everything shown comes from the server for the signed-in child
/// (`/videos/shorts`, `/videos/feed`, `/educational-content`). No player is
/// created on this page; players only exist on the Shorts and video screens it
/// opens.
///
/// Continue Watching is populated only from the child's backend watch history.
class WatchHomeScreen extends ConsumerStatefulWidget {
  const WatchHomeScreen({super.key});

  @override
  ConsumerState<WatchHomeScreen> createState() => _WatchHomeScreenState();
}

class _WatchHomeScreenState extends ConsumerState<WatchHomeScreen>
    with WidgetsBindingObserver, RouteAware {
  /// Returning from the background refreshes the allowance at most this often.
  static const _resumeRefreshGap = Duration(seconds: 15);
  static const _returnRefreshDebounce = Duration(seconds: 1);
  DateTime? _lastResumeRefresh;
  DateTime? _lastReturnRefresh;
  bool _isBackgroundRefreshing = false;
  PageRoute<dynamic>? _observedRoute;

  late final VideoFeedPager _shorts;
  late final VideoFeedPager _videos;

  @override
  void initState() {
    super.initState();
    vdiag('home.initState', screen: 'home', id: identityHashCode(this));
    WidgetsBinding.instance.addObserver(this);
    final repository = ref.read(videoFeedRepositoryProvider);
    _shorts = VideoFeedPager(repository, VideoFeedKind.shorts, pageSize: 10)
      ..addListener(_changed);
    _videos = VideoFeedPager(repository, VideoFeedKind.learn)
      ..addListener(_changed);
    unawaited(_shorts.loadMore());
    unawaited(_videos.loadMore());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _observedRoute) {
      appRouteObserver.unsubscribe(this);
      _observedRoute = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    unawaited(_refreshOnReturn());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(learningItemsProvider)
      ..invalidate(continueWatchingProvider)
      ..invalidate(videoAllowanceProvider);
    await Future.wait([_shorts.refresh(), _videos.refresh()]);
  }

  Future<void> _refreshOnReturn() async {
    if (!mounted || _isBackgroundRefreshing) return;
    final now = DateTime.now();
    final last = _lastReturnRefresh;
    if (last != null && now.difference(last) < _returnRefreshDebounce) return;
    _lastReturnRefresh = now;
    setState(() => _isBackgroundRefreshing = true);
    vdiag(
      'home.returnRefresh.begin',
      screen: 'home',
      id: identityHashCode(this),
      extra: 'mounted=$mounted',
    );
    try {
      ref
        ..invalidate(learningItemsProvider)
        ..invalidate(continueWatchingProvider)
        ..invalidate(videoAllowanceProvider);
      await Future.wait([_shorts.refresh(), _videos.refresh()]);
    } finally {
      if (mounted) {
        setState(() => _isBackgroundRefreshing = false);
      }
      vdiag(
        'home.returnRefresh.end',
        screen: 'home',
        id: identityHashCode(this),
        extra:
            'mounted=$mounted shorts=${_shorts.items.length} videos=${_videos.items.length}',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    final last = _lastResumeRefresh;
    if (last != null && now.difference(last) < _resumeRefreshGap) return;
    _lastResumeRefresh = now;
    // A parent may have approved a mission while the app was away: reload
    // the notifications (they drive the allowance) and refresh the feed.
    ref
      ..invalidate(childNotificationsProvider)
      ..invalidate(videoAllowanceProvider);
    unawaited(_refreshOnReturn());
  }

  @override
  void dispose() {
    vdiag('home.dispose', screen: 'home', id: identityHashCode(this));
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    for (final pager in [_shorts, _videos]) {
      pager
        ..removeListener(_changed)
        ..dispose();
    }
    super.dispose();
  }

  /// Continue-watching cards are 280 wide: a 16:9 thumbnail, then padding, a
  /// two-line title and the channel row. The text part grows with the font
  /// scale, so a fixed height would overflow at larger sizes and in Hindi or
  /// Gujarati.
  static double _continueRowHeight(BuildContext context) {
    const thumbnail = 280 * 9 / 16;
    const body = 124.0;
    return thumbnail + body * MediaQuery.textScalerOf(context).scale(1);
  }

  Future<void> _openShort(int index) async {
    // The server confirms time remains before anything opens.
    if (!await ensureVideoAllowance(context, ref) || !mounted) return;
    var start = index;
    if (_shorts.items.any((v) => v.playbackLocked)) {
      // Time was earned since this list was loaded: reload it so the Shorts
      // carry their playable ids, then open the one the child tapped.
      await _shorts.refresh();
      if (!mounted || _shorts.items.isEmpty) return;
      start = index.clamp(0, _shorts.items.length - 1);
    }
    unawaited(
      context
          .push(
            AppRoutes.childShorts,
            extra: ShortsLaunch(
              initialVideos: _shorts.items,
              initialIndex: start,
              nextOffset: _shorts.nextOffset,
              exhausted: !_shorts.hasMore,
            ),
          )
          .then((_) {
            vdiag(
              'home.push.completed',
              screen: 'home',
              extra: 'route=shorts mounted=$mounted',
            );
            return _refreshOnReturn();
          }),
    );
  }

  Future<void> _openVideo(PlayableVideo video, List<PlayableVideo> from) async {
    if (!await ensureVideoAllowance(context, ref) || !mounted) return;
    if (video.isTimeLocked) {
      // Time was earned since this card was loaded: reload so it becomes
      // playable. The child taps again; nothing plays from a stale card.
      await _refreshOnReturn();
      return;
    }
    // "Up next" prefers the same topic, then the rest of the list.
    final related = [
      ...from.where(
        (v) => v.key != video.key && v.categoryId == video.categoryId,
      ),
      ...from.where(
        (v) => v.key != video.key && v.categoryId != video.categoryId,
      ),
    ].take(20).toList();
    vdiag(
      'home.push.watch',
      screen: 'home',
      extra: 'source=${video.source.runtimeType}',
    );
    unawaited(
      context
          .push(
            AppRoutes.childWatch,
            extra: VideoLaunch(video: video, related: related),
          )
          .then((_) {
            vdiag(
              'home.push.completed',
              screen: 'home',
              extra: 'route=watch mounted=$mounted',
            );
            return _refreshOnReturn();
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final continueVideos =
        ref.watch(continueWatchingProvider).value ?? const [];
    vdiag(
      'home.build',
      screen: 'home',
      id: identityHashCode(this),
      extra:
          'continue=${continueVideos.length} shorts=${_shorts.items.length} videos=${_videos.items.length}',
    );
    final picked = [
      for (final item
          in ref.watch(learningItemsProvider).value ?? const <LearningItem>[])
        if (item.contentType == 'video' && item.playsInApp)
          PlayableVideo.fromLearning(item),
    ];
    final shorts = _shorts.items;
    final videos = [for (final v in _videos.items) PlayableVideo.fromFeed(v)];

    final shortsSettledEmpty =
        shorts.isEmpty && _shorts.status == PagerStatus.done;
    final videosSettledEmpty =
        videos.isEmpty && _videos.status == PagerStatus.done;
    // The server lists the catalogue even at zero allowance (cards are then
    // locked and the allowance card explains why), so an empty feed really
    // means nothing is eligible right now.
    final nothingAtAll =
        shortsSettledEmpty && videosSettledEmpty && picked.isEmpty;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        key: const Key('watch.scroll'),
        slivers: [
          if (_isBackgroundRefreshing)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(
                key: Key('watch.refreshing'),
                minHeight: 2,
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.md,
            ),
            sliver: SliverToBoxAdapter(child: _Heading(l10n: l10n)),
          ),
          const SliverToBoxAdapter(child: VideoAllowanceCard()),
          const SliverToBoxAdapter(child: LearnHubEntry()),
          if (continueVideos.isNotEmpty) ...[
            // _SectionHeader is itself a sliver, so it sits beside the row
            // in the scroll view, never inside a box widget like a Column.
            _SectionHeader(
              icon: Icons.play_circle_outline_rounded,
              title: l10n.watchContinue,
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  height: _continueRowHeight(context),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: continueVideos.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (context, index) {
                      final video = PlayableVideo.fromFeed(
                        continueVideos[index],
                      );
                      return SizedBox(
                        width: 280,
                        child: _VideoCard(
                          video: video,
                          onTap: () => _openVideo(video, [video]),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
          if (nothingAtAll)
            SliverToBoxAdapter(
              child: EmptyView(
                key: const Key('watch.empty'),
                message: l10n.watchNothingYet,
                image: AppImages.pandaDrawing,
                action: FilledButton.icon(
                  key: const Key('watch.toMissions'),
                  onPressed: () => context.go(AppRoutes.childMissions),
                  icon: const Icon(Icons.rocket_launch_rounded),
                  label: Text(l10n.watchMissionsOpen),
                ),
              ),
            )
          else ...[
            if (!shortsSettledEmpty) ...[
              _SectionHeader(
                key: const Key('watch.shorts.header'),
                icon: Icons.bolt_rounded,
                title: l10n.watchShortsSection,
                action: shorts.isEmpty
                    ? null
                    : TextButton(
                        key: const Key('watch.shorts.seeAll'),
                        onPressed: () => _openShort(0),
                        child: Text(l10n.shortsSeeAll),
                      ),
              ),
              SliverToBoxAdapter(child: _shortsRow(context, shorts)),
            ],
            if (!videosSettledEmpty) ...[
              _SectionHeader(
                key: const Key('watch.videos.header'),
                icon: Icons.smart_display_rounded,
                title: l10n.watchVideosSection,
              ),
              ..._videoList(context, videos),
            ],
            if (picked.isNotEmpty) ...[
              _SectionHeader(
                key: const Key('watch.picked.header'),
                icon: Icons.favorite_rounded,
                title: l10n.watchPickedSection,
                action: TextButton(
                  key: const Key('watch.openLearn'),
                  onPressed: () => context.push(AppRoutes.childLearn),
                  child: Text(l10n.learnOpenLearn),
                ),
              ),
              _videoGrid(
                picked,
                (video) => _openVideo(video, picked),
                keyPrefix: 'watch.picked',
              ),
            ],
          ],
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        ],
      ),
    );
  }

  Widget _shortsRow(BuildContext context, List<FeedVideo> shorts) {
    const height = 236.0;
    if (shorts.isEmpty) {
      if (_shorts.status == PagerStatus.error) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: ErrorView(
            key: const Key('watch.shorts.error'),
            error: _shorts.error!,
            onRetry: _shorts.retry,
          ),
        );
      }
      return const SizedBox(
        height: height,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SizedBox(
      height: height,
      child: ListView.separated(
        key: const Key('watch.shorts.row'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: shorts.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) => ShortCard(
          video: PlayableVideo.fromFeed(shorts[index]),
          onTap: () => _openShort(index),
        ),
      ),
    );
  }

  List<Widget> _videoList(BuildContext context, List<PlayableVideo> videos) {
    final l10n = AppLocalizations.of(context);
    if (videos.isEmpty) {
      final Widget child = switch (_videos.status) {
        PagerStatus.error => ErrorView(
          key: const Key('watch.videos.error'),
          error: _videos.error!,
          onRetry: _videos.retry,
        ),
        PagerStatus.done => EmptyView(
          key: const Key('watch.videos.empty'),
          message: l10n.watchNoVideos,
          image: AppImages.pandaDrawing,
        ),
        _ => const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      };
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          sliver: SliverToBoxAdapter(child: child),
        ),
      ];
    }
    return [
      _videoGrid(
        videos,
        (video) {
          _openVideo(video, videos);
        },
        keyPrefix: 'watch.video',
        onNearEnd: _loadMoreVideos,
      ),
      SliverToBoxAdapter(
        child: switch (_videos.status) {
          PagerStatus.loading => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          ),
          PagerStatus.error => Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: ErrorView(
              key: const Key('watch.videos.pageError'),
              error: _videos.error!,
              onRetry: _videos.retry,
            ),
          ),
          _ => const SizedBox.shrink(),
        },
      ),
    ];
  }

  void _loadMoreVideos() {
    if (_videos.status != PagerStatus.idle) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_videos.loadMore());
    });
  }

  /// One column on phones, more on tablets: cards stay a readable width.
  Widget _videoGrid(
    List<PlayableVideo> videos,
    ValueChanged<PlayableVideo> onTap, {
    required String keyPrefix,
    VoidCallback? onNearEnd,
  }) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    sliver: SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = (width / 420).floor().clamp(1, 3);
        if (columns == 1) {
          return SliverList.builder(
            itemCount: videos.length,
            itemBuilder: (context, index) {
              if (index >= videos.length - 3) onNearEnd?.call();
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _VideoCard(
                  key: Key('$keyPrefix.${videos[index].key}'),
                  video: videos[index],
                  onTap: () => onTap(videos[index]),
                ),
              );
            },
          );
        }
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            // Thumbnail (16:9) plus two lines of title and a meta row.
            mainAxisExtent:
                (width - (columns - 1) * AppSpacing.md) / columns * 9 / 16 +
                110 * MediaQuery.textScalerOf(context).scale(1),
          ),
          itemCount: videos.length,
          itemBuilder: (context, index) {
            if (index >= videos.length - 3) onNearEnd?.call();
            return _VideoCard(
              key: Key('$keyPrefix.${videos[index].key}'),
              video: videos[index],
              onTap: () => onTap(videos[index]),
            );
          },
        );
      },
    ),
  );
}

/// The page heading. No Panda or greeting bubble here: Panda has its own
/// entry point in the app bar, and the allowance card below says how much
/// video time is left.
class _Heading extends StatelessWidget {
  const _Heading({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(l10n.watchGreeting, style: context.text.headlineSmall),
      const SizedBox(height: AppSpacing.xs),
      Text(
        l10n.watchGreetingBody,
        style: context.text.bodyMedium?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.sm,
    ),
    sliver: SliverToBoxAdapter(
      child: Row(
        children: [
          Icon(icon, color: context.colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(title, style: context.text.titleLarge)),
          if (action != null) Flexible(child: action!),
        ],
      ),
    ),
  );
}

/// A portrait card: Shorts look different from regular videos at a glance.
/// A landscape card for a regular video.
class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video, required this.onTap, super.key});

  final PlayableVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final duration = video.duration;
    final channel = video.channelName;
    return Material(
      color: colors.surfaceContainerLowest,
      borderRadius: AppRadius.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoThumbnail(url: video.thumbnailUrl),
                  if (!video.isPlayable)
                    const ColoredBox(
                      color: Color(0x66000000),
                      child: Center(
                        child: Icon(
                          Icons.lock_rounded,
                          key: Key('watch.video.locked'),
                          size: 40,
                          color: AppPalette.onPrimary,
                        ),
                      ),
                    ),
                  if (duration != null)
                    Positioned(
                      right: AppSpacing.sm,
                      bottom: AppSpacing.sm,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xCC000000),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            formatPlaybackTime(duration),
                            style: context.text.labelMedium?.copyWith(
                              color: AppPalette.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.xs,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleMedium,
                  ),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (video.isYouTube)
                        EyebrowPill(
                          icon: Icons.smart_display_rounded,
                          label: l10n.videoBadgeYouTube,
                        ),
                      if (channel != null)
                        Text(
                          channel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
    );
  }
}
