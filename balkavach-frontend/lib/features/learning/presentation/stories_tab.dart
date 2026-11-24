import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/async/refresh_quietly.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/lazy_list_page.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/learning_repository.dart';

/// Whether a curated item is a story: an administrator-written `article`.
bool isStory(LearningItem item) => item.contentType == 'article';

/// Minutes to read [text] at roughly 120 words a minute (never below one).
int storyReadingMinutes(String text) {
  final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return (words.length / 120).ceil().clamp(1, 999);
}

/// The Stories tab of the Learning Hub: the admin-published `article` items
/// for the child's language. A story's text lives in its description.
class StoriesTab extends ConsumerWidget {
  const StoriesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    Future<void> refresh() async {
      ref.invalidate(learningItemsProvider);
      await refreshQuietly(ref.read(learningItemsProvider.future));
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: switch (ref.watch(learningItemsProvider)) {
        AsyncData(:final value) => _list(context, l10n, [
          for (final item in value)
            if (isStory(item)) item,
        ]),
        AsyncError(:final error) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ErrorView(
              key: const Key('stories.error'),
              error: error,
              onRetry: () => ref.invalidate(learningItemsProvider),
            ),
          ],
        ),
        _ => const LoadingView(),
      },
    );
  }

  Widget _list(
    BuildContext context,
    AppLocalizations l10n,
    List<LearningItem> stories,
  ) {
    if (stories.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyView(
            key: const Key('stories.empty'),
            message: l10n.storiesEmpty,
            image: AppImages.pandaDrawing,
          ),
        ],
      );
    }
    return LazyListPage(
      key: const Key('stories.list'),
      header: const [],
      itemCount: stories.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: _StoryCard(story: stories[index]),
      ),
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.story});

  final LearningItem story;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final text = story.description;
    final cover = story.thumbnailUrl;
    return AppCard(
      key: Key('story.${story.id}'),
      onTap: () =>
          context.push(AppRoutes.childLearnItem(story.id), extra: story),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              width: 72,
              height: 72,
              child: cover == null
                  ? _CoverFallback(color: colors.primaryFixed)
                  : Image.network(
                      cover,
                      fit: BoxFit.cover,
                      // A missing or slow cover never blocks reading.
                      errorBuilder: (_, _, _) =>
                          _CoverFallback(color: colors.primaryFixed),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.xs,
              children: [
                Text(story.title, style: context.text.titleMedium),
                if (text != null && text.trim().isNotEmpty)
                  EyebrowPill(
                    label: l10n.storyReadingTime(storyReadingMinutes(text)),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Icon(Icons.auto_stories_rounded, color: context.colors.primary),
  );
}
