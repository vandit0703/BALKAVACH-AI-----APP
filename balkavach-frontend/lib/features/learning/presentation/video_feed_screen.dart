import 'dart:async';

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
import 'shorts_feed.dart';
import 'video_lock_screen.dart';
import 'video_player_screen.dart' show formatPlaybackTime;

export 'shorts_feed.dart' show ShortsFeed, ShortsFeedScreen;

/// Server-approved videos for the signed-in child, in two tabs: longer
/// learning videos and short ones. Only what `GET /videos/feed` and
/// `GET /videos/shorts` return is shown; the app adds nothing of its own.
class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.videoFeedTitle),
        bottom: TabBar(
          controller: _tabs,
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
      body: TabBarView(
        controller: _tabs,
        children: const [
          VideoFeedList(kind: VideoFeedKind.learn),
          _KeepAlive(child: ShortsFeed()),
        ],
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class VideoFeedList extends ConsumerStatefulWidget {
  const VideoFeedList({required this.kind, this.header = const [], super.key});

  final VideoFeedKind kind;

  /// Shown above the videos (the Learning Hub puts curated picks here).
  final List<Widget> header;

  @override
  ConsumerState<VideoFeedList> createState() => _VideoFeedListState();
}

class _VideoFeedListState extends ConsumerState<VideoFeedList>
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
              ...widget.header,
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
        header: widget.header,
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

class _VideoCard extends ConsumerWidget {
  const _VideoCard({required this.video});

  final FeedVideo video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          ? () async {
              if (!await ensureVideoAllowance(context, ref) ||
                  !context.mounted) {
                return;
              }
              unawaited(context.push(AppRoutes.childVideoPlay, extra: video));
            }
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
