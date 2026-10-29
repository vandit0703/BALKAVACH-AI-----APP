import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/lazy_list_page.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/video_feed_repository.dart';
import 'video_player_screen.dart' show formatPlaybackTime;
import 'youtube_player_screen.dart';

/// Server-approved videos for the signed-in child, in two tabs: longer
/// learning videos and short ones. Only what `GET /videos/feed` and
/// `GET /videos/shorts` return is shown; the app adds nothing of its own.
class VideoFeedScreen extends StatelessWidget {
  const VideoFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.videoFeedTitle),
          bottom: TabBar(
            tabs: [
              Tab(
                key: const Key('videos.tab.learn'),
                text: l10n.videoFeedLearnTab,
              ),
              Tab(
                key: const Key('videos.tab.shorts'),
                text: l10n.videoFeedShortsTab,
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _FeedTab(kind: VideoFeedKind.learn),
            ShortsFeed(),
          ],
        ),
      ),
    );
  }
}

/// The approved child Shorts feed. Home and Learn & Watch share this widget so
/// there is one pager and one player lifecycle for the Shorts experience.
class ShortsFeed extends ConsumerStatefulWidget {
  const ShortsFeed({this.showMissionsAction = false, super.key});

  final bool showMissionsAction;

  @override
  ConsumerState<ShortsFeed> createState() => _ShortsFeedState();
}

class _ShortsFeedState extends ConsumerState<ShortsFeed> {
  late final VideoFeedPager _pager;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pager = VideoFeedPager(
      ref.read(videoFeedRepositoryProvider),
      VideoFeedKind.shorts,
      pageSize: 10,
    )..addListener(_changed);
    _pager.loadMore();
  }

  void _changed() => setState(() {});

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
    final embedBuilder = ref.watch(youtubeEmbedBuilderProvider);
    if (items.isEmpty) {
      if (_pager.status == PagerStatus.error) {
        return ErrorView(
          key: const Key('videos.shorts.error'),
          error: _pager.error!,
          onRetry: _pager.retry,
        );
      }
      if (_pager.status == PagerStatus.done) {
        return EmptyView(
          key: const Key('videos.shorts.empty'),
          message: AppLocalizations.of(context).videoFeedEmpty,
          image: AppImages.pandaDrawing,
          action: widget.showMissionsAction
              ? FilledButton.icon(
                  key: const Key('videos.shorts.toMissions'),
                  onPressed: () => context.go(AppRoutes.childMissions),
                  icon: const Icon(Icons.rocket_launch_rounded),
                  label: Text(AppLocalizations.of(context).watchMissionsOpen),
                )
              : null,
        );
      }
      return const LoadingView();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          key: const Key('videos.shorts.pager'),
          scrollDirection: Axis.vertical,
          itemCount: items.length,
          onPageChanged: (index) {
            setState(() => _currentPage = index);
            if (index >= items.length - 2) _pager.loadMore();
          },
          itemBuilder: (context, index) => _ShortsPage(
            key: ValueKey(items[index].youtubeVideoId ?? items[index].id),
            video: items[index],
            active: index == _currentPage,
            embedBuilder: embedBuilder,
          ),
        ),
        if (_pager.status == PagerStatus.loading)
          const Positioned(
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }
}

class _ShortsPage extends StatefulWidget {
  const _ShortsPage({
    super.key,
    required this.video,
    required this.active,
    required this.embedBuilder,
  });

  final FeedVideo video;
  final bool active;
  final YouTubeEmbedBuilder embedBuilder;

  @override
  State<_ShortsPage> createState() => _ShortsPageState();
}

class _ShortsPageState extends State<_ShortsPage> {
  bool _failed = false;
  int _attempt = 0;

  void _retry() => setState(() {
    _failed = false;
    _attempt++;
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final video = widget.video;
    final videoId = video.isYouTube ? video.youtubeVideoId : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: colors.surfaceContainerHighest,
          child: videoId == null
              ? (video.thumbnailUrl == null
                    ? const Center(
                        child: Icon(Icons.video_library_outlined, size: 56),
                      )
                    : Image.network(video.thumbnailUrl!, fit: BoxFit.cover))
              : widget.active && !_failed
              ? KeyedSubtree(
                  key: ValueKey('${video.id}-$_attempt'),
                  child: widget.embedBuilder(
                    YouTubeEmbedConfig(
                      videoId: videoId,
                      onLeaveRequested: (_) {},
                      onForeignVideo: () {},
                      onError: () {
                        if (mounted) setState(() => _failed = true);
                      },
                      autoplay: true,
                    ),
                  ),
                )
              : _failed
              ? _ShortsError(onRetry: _retry)
              : const SizedBox.shrink(),
        ),
        Positioned(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: AppSpacing.lg,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.scrim.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleLarge?.copyWith(
                      color: colors.onPrimary,
                    ),
                  ),
                  if ((video.channelName ?? '').isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      video.channelName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        color: colors.onPrimary,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    formatPlaybackTime(
                      Duration(seconds: video.durationSeconds),
                    ),
                    style: context.text.bodySmall?.copyWith(
                      color: colors.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShortsError extends StatelessWidget {
  const _ShortsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: FilledButton.icon(
        key: const Key('videos.shorts.retry'),
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(l10n.videoRetry),
      ),
    );
  }
}

class _FeedTab extends ConsumerStatefulWidget {
  const _FeedTab({required this.kind});

  final VideoFeedKind kind;

  @override
  ConsumerState<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends ConsumerState<_FeedTab>
    with AutomaticKeepAliveClientMixin {
  late final VideoFeedPager _pager;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _pager = VideoFeedPager(ref.read(videoFeedRepositoryProvider), widget.kind)
      ..addListener(_changed);
    _pager.loadMore();
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _pager
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final items = _pager.items;

    if (items.isEmpty) {
      return switch (_pager.status) {
        PagerStatus.error => ErrorView(
          key: Key('videos.${widget.kind.name}.error'),
          error: _pager.error!,
          onRetry: _pager.retry,
        ),
        PagerStatus.done => RefreshIndicator(
          onRefresh: _pager.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              EmptyView(
                key: Key('videos.${widget.kind.name}.empty'),
                message: l10n.videoFeedEmpty,
                image: AppImages.pandaDrawing,
              ),
            ],
          ),
        ),
        _ => const LoadingView(),
      };
    }

    return RefreshIndicator(
      onRefresh: _pager.refresh,
      child: LazyListPage(
        key: Key('videos.${widget.kind.name}.list'),
        header: const [],
        itemCount: items.length,
        itemBuilder: (context, index) {
          // Ask for the next page a few rows before the end.
          if (index >= items.length - 3 && _pager.status == PagerStatus.idle) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _pager.loadMore(),
            );
          }
          return _VideoCard(video: items[index]);
        },
        footer: [
          switch (_pager.status) {
            PagerStatus.loading => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              ),
            ),
            PagerStatus.error => ErrorView(
              key: Key('videos.${widget.kind.name}.pageError'),
              error: _pager.error!,
              onRetry: _pager.retry,
            ),
            _ => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video});

  final FeedVideo video;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final url = video.thumbnailUrl;
    final placeholder = Icon(
      Icons.play_circle_rounded,
      size: 32,
      color: colors.primary,
    );

    return AppCard(
      key: Key('videos.item.${video.id}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      // Only YouTube items are playable here; hosted videos still require the
      // authorised playback-session API and are not opened from this list.
      onTap: video.isYouTube
          ? () => context.push(AppRoutes.childVideoPlay, extra: video)
          : null,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: ColoredBox(
              color: colors.primaryFixed,
              child: SizedBox(
                width: 112,
                height: 63,
                child: url == null || Uri.tryParse(url)?.scheme != 'https'
                    ? Center(child: placeholder)
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Center(child: placeholder),
                      ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
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
                Text(
                  formatPlaybackTime(Duration(seconds: video.durationSeconds)),
                  style: context.text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (video.isYouTube)
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }
}
