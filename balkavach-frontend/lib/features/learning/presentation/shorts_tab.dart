import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/playable_video.dart';
import '../data/video_feed_repository.dart';
import 'video_lock_screen.dart' show ensureVideoAllowance;
import 'widgets/short_card.dart';

/// The Shorts tab of the Learning Hub: the child's approved Shorts from
/// `GET /videos/shorts` as a grid. Tapping one opens the existing full-screen
/// Shorts player at that Short; the server still decides whether time remains.
class ShortsTab extends ConsumerStatefulWidget {
  const ShortsTab({super.key});

  @override
  ConsumerState<ShortsTab> createState() => _ShortsTabState();
}

class _ShortsTabState extends ConsumerState<ShortsTab>
    with AutomaticKeepAliveClientMixin {
  late final VideoFeedPager _pager;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _pager = VideoFeedPager(
      ref.read(videoFeedRepositoryProvider),
      VideoFeedKind.shorts,
      pageSize: 12,
    )..addListener(_changed);
    unawaited(_pager.loadMore());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pager
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  Future<void> _open(int index) async {
    if (!await ensureVideoAllowance(context, ref) || !mounted) return;
    var start = index;
    if (_pager.items.any((v) => v.playbackLocked)) {
      // Time was earned since this list loaded: reload so the Shorts carry
      // their playable ids, then open the one the child tapped.
      await _pager.refresh();
      if (!mounted || _pager.items.isEmpty) return;
      start = index.clamp(0, _pager.items.length - 1);
    }
    await context.push(
      AppRoutes.childShorts,
      extra: ShortsLaunch(
        initialVideos: _pager.items,
        initialIndex: start,
        nextOffset: _pager.nextOffset,
        exhausted: !_pager.hasMore,
      ),
    );
    // Watching used time: refresh the lock state of every card.
    if (mounted) {
      ref.invalidate(videoAllowanceProvider);
      unawaited(_pager.refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final items = _pager.items;

    if (items.isEmpty) {
      return switch (_pager.status) {
        PagerStatus.error => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ErrorView(
              key: const Key('hub.shorts.error'),
              error: _pager.error!,
              onRetry: _pager.retry,
            ),
          ],
        ),
        PagerStatus.done => RefreshIndicator(
          onRefresh: _pager.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              EmptyView(
                key: const Key('hub.shorts.empty'),
                message: l10n.hubShortsEmpty,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // About 170 dp per column: 2 on phones, 4+ on tablets.
          final columns = (constraints.maxWidth / 170).floor().clamp(2, 6);
          return CustomScrollView(
            key: const Key('hub.shorts.grid'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.md),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 9 / 15,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    // Ask for the next page a few cards before the end.
                    if (index >= items.length - 4 &&
                        _pager.status == PagerStatus.idle) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _pager.loadMore(),
                      );
                    }
                    return ShortCard(
                      video: PlayableVideo.fromFeed(items[index]),
                      width: null,
                      keyPrefix: 'hub.short',
                      onTap: () => _open(index),
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: switch (_pager.status) {
                  PagerStatus.loading => const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  PagerStatus.error => ErrorView(
                    key: const Key('hub.shorts.pageError'),
                    error: _pager.error!,
                    onRetry: _pager.retry,
                  ),
                  _ => const SizedBox(height: AppSpacing.xl),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
