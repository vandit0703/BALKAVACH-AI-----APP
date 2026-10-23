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
            _FeedTab(kind: VideoFeedKind.shorts),
          ],
        ),
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
