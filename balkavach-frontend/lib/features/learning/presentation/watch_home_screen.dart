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
import '../../../shared/widgets/state_views.dart';
import '../data/learning_repository.dart';
import '../data/playable_video.dart';
import '../data/video_feed_repository.dart';
import 'learning_screen.dart' show learningCategoryName;
import 'video_player_screen.dart' show formatPlaybackTime;
import 'widgets/video_actions.dart';

/// Home: Watch & Learn. A row of Shorts that opens the full-screen vertical
/// feed, topic filters, the regular video list and grown-up picks.
///
/// Everything shown comes from the server for the signed-in child
/// (`/videos/shorts`, `/videos/feed`, `/videos/categories`,
/// `/educational-content`). No player is created on this page; players only
/// exist on the Shorts and video screens it opens.
///
/// There is deliberately no "Continue watching" row: the app has no
/// trustworthy, server-side record of what a child watched, and inventing one
/// on the device would be fake progress.
class WatchHomeScreen extends ConsumerStatefulWidget {
  const WatchHomeScreen({super.key});

  @override
  ConsumerState<WatchHomeScreen> createState() => _WatchHomeScreenState();
}

class _WatchHomeScreenState extends ConsumerState<WatchHomeScreen> {
  late VideoFeedPager _shorts;
  late VideoFeedPager _videos;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    final repository = ref.read(videoFeedRepositoryProvider);
    _shorts = VideoFeedPager(repository, VideoFeedKind.shorts, pageSize: 10)
      ..addListener(_changed);
    _videos = _videoPager(repository, null);
    unawaited(_shorts.loadMore());
    unawaited(_videos.loadMore());
  }

  VideoFeedPager _videoPager(
    VideoFeedRepository repository,
    String? category,
  ) =>
      VideoFeedPager(repository, VideoFeedKind.learn, categoryId: category)
        ..addListener(_changed);

  void _changed() {
    if (mounted) setState(() {});
  }

  void _selectCategory(String? categoryId) {
    if (categoryId == _categoryId) return;
    final previous = _videos;
    setState(() {
      _categoryId = categoryId;
      _videos = _videoPager(ref.read(videoFeedRepositoryProvider), categoryId);
    });
    previous
      ..removeListener(_changed)
      ..dispose();
    unawaited(_videos.loadMore());
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(learningItemsProvider)
      ..invalidate(learningCategoriesProvider);
    await Future.wait([_shorts.refresh(), _videos.refresh()]);
  }

  @override
  void dispose() {
    for (final pager in [_shorts, _videos]) {
      pager
        ..removeListener(_changed)
        ..dispose();
    }
    super.dispose();
  }

  void _openShort(int index) {
    unawaited(
      context.push(
        AppRoutes.childShorts,
        extra: ShortsLaunch(
          initialVideos: _shorts.items,
          initialIndex: index,
          nextOffset: _shorts.nextOffset,
          exhausted: !_shorts.hasMore,
        ),
      ),
    );
  }

  void _openVideo(PlayableVideo video, List<PlayableVideo> from) {
    // "Up next" prefers the same topic, then the rest of the list.
    final related = [
      ...from.where(
        (v) => v.key != video.key && v.categoryId == video.categoryId,
      ),
      ...from.where(
        (v) => v.key != video.key && v.categoryId != video.categoryId,
      ),
    ].take(20).toList();
    unawaited(
      context.push(
        AppRoutes.childWatch,
        extra: VideoLaunch(video: video, related: related),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(learningCategoriesProvider).value ?? const [];
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
        videos.isEmpty &&
        _videos.status == PagerStatus.done &&
        _categoryId == null;
    final nothingAtAll =
        shortsSettledEmpty && videosSettledEmpty && picked.isEmpty;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        key: const Key('watch.scroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            sliver: SliverToBoxAdapter(child: _Greeting(l10n: l10n)),
          ),
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
            if (categories.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.explore_rounded,
                title: l10n.watchTopicsSection,
              ),
              SliverToBoxAdapter(
                child: _TopicChips(
                  categories: categories,
                  selected: _categoryId,
                  onSelected: _selectCategory,
                ),
              ),
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
        itemBuilder: (context, index) => _ShortCard(
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

class _Greeting extends StatelessWidget {
  const _Greeting({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        ClipOval(
          child: Image.asset(
            AppImages.pandaDrawing,
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            cacheWidth: (64 * dpr).round(),
            excludeFromSemantics: true,
          ),
        ),
      ],
    );
  }
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

class _TopicChips extends StatelessWidget {
  const _TopicChips({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<LearningCategory> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        spacing: AppSpacing.sm,
        children: [
          ChoiceChip(
            key: const Key('watch.topic.all'),
            label: Text(l10n.learnAll),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final category in categories)
            ChoiceChip(
              key: Key('watch.topic.${category.slug}'),
              label: Text(learningCategoryName(l10n, category)),
              selected: selected == category.id,
              onSelected: (_) => onSelected(category.id),
            ),
        ],
      ),
    );
  }
}

/// A portrait card: Shorts look different from regular videos at a glance.
class _ShortCard extends StatelessWidget {
  const _ShortCard({required this.video, required this.onTap});

  final PlayableVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: 132,
      child: Material(
        color: AppPalette.navy,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('watch.short.${video.key}'),
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
