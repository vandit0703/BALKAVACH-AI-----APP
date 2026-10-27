import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/async/refresh_quietly.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/platform/link_opener.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/lazy_list_page.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/learning_repository.dart';

/// Localised name for the categories the app ships with; any other category
/// an administrator adds shows the name the server sent.
String learningCategoryName(AppLocalizations l10n, LearningCategory category) =>
    switch (category.slug) {
      'learning' => l10n.learnCategoryLearning,
      'stories' => l10n.learnCategoryStories,
      'science' => l10n.learnCategoryScience,
      'creativity' => l10n.learnCategoryCreativity,
      'healthy-habits' => l10n.learnCategoryHealthyHabits,
      _ => category.name,
    };

String learningTypeName(AppLocalizations l10n, String type) => switch (type) {
  'video' => l10n.learnTypeVideo,
  'article' => l10n.learnTypeArticle,
  'document' => l10n.learnTypeDocument,
  'activity' => l10n.learnTypeActivity,
  _ => l10n.learnTypeLink,
};

IconData learningTypeIcon(String type) => switch (type) {
  'video' => Icons.play_circle_outline_rounded,
  'article' => Icons.menu_book_rounded,
  'document' => Icons.description_outlined,
  'activity' => Icons.extension_outlined,
  _ => Icons.link_rounded,
};

/// Learn & Watch: admin-curated content for the child's language.
class LearningScreen extends ConsumerStatefulWidget {
  const LearningScreen({super.key});

  @override
  ConsumerState<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends ConsumerState<LearningScreen> {
  String? _categoryId;

  Future<void> _refresh() async {
    ref
      ..invalidate(learningItemsProvider)
      ..invalidate(learningCategoriesProvider);
    await refreshQuietly(ref.read(learningItemsProvider.future));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(learningItemsProvider);
    final categories = ref.watch(learningCategoriesProvider).value ?? const [];

    return RefreshIndicator(
      onRefresh: _refresh,
      child: switch (items) {
        AsyncData(:final value) => _list(context, l10n, value, categories),
        AsyncError(:final error) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ErrorView(
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
    List<LearningItem> all,
    List<LearningCategory> categories,
  ) {
    final usedCategoryIds = {for (final i in all) ?i.categoryId};
    final filters = [
      for (final c in categories)
        if (usedCategoryIds.contains(c.id)) c,
    ];
    final visible = _categoryId == null
        ? all
        : all.where((i) => i.categoryId == _categoryId).toList();
    return LazyListPage(
      header: [
        if (filters.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              ChoiceChip(
                key: const Key('learn.filter.all'),
                label: Text(l10n.learnAll),
                selected: _categoryId == null,
                onSelected: (_) => setState(() => _categoryId = null),
              ),
              for (final c in filters)
                ChoiceChip(
                  key: Key('learn.filter.${c.slug}'),
                  label: Text(learningCategoryName(l10n, c)),
                  selected: _categoryId == c.id,
                  onSelected: (_) => setState(() => _categoryId = c.id),
                ),
            ],
          ),
        if (visible.isEmpty)
          EmptyView(message: l10n.learnEmpty, image: AppImages.pandaDrawing),
      ],
      itemCount: visible.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: _LearningCard(item: visible[index], categories: categories),
      ),
    );
  }
}

class _LearningCard extends StatelessWidget {
  const _LearningCard({required this.item, required this.categories});

  final LearningItem item;
  final List<LearningCategory> categories;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final category = categories
        .where((c) => c.id == item.categoryId)
        .firstOrNull;
    return AppCard(
      key: Key('learn.${item.id}'),
      onTap: () => context.push(AppRoutes.childLearnItem(item.id), extra: item),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: colors.primaryFixed,
            child: Icon(
              learningTypeIcon(item.contentType),
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.xs,
              children: [
                Text(item.title, style: context.text.titleMedium),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    EyebrowPill(
                      label: learningTypeName(l10n, item.contentType),
                    ),
                    if (category != null)
                      EyebrowPill(label: learningCategoryName(l10n, category)),
                  ],
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

/// Details for one item. The item is passed through navigation so the screen
/// works without another request; opening it is the only action.
class LearningDetailScreen extends ConsumerStatefulWidget {
  const LearningDetailScreen({required this.item, super.key});

  final LearningItem item;

  @override
  ConsumerState<LearningDetailScreen> createState() =>
      _LearningDetailScreenState();
}

class _LearningDetailScreenState extends ConsumerState<LearningDetailScreen> {
  bool _failed = false;

  Future<void> _open(Uri uri) async {
    final opened = await ref.read(linkOpenerProvider).open(uri);
    if (mounted) setState(() => _failed = !opened);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final item = widget.item;
    final uri = item.openableUri;
    final description = item.description?.trim();
    final blocker = item.requiresEntitlement
        ? l10n.learnLocked
        : (uri == null ? l10n.learnNotReady : null);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.learnTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.md,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: colors.primaryFixed,
                    child: Icon(
                      learningTypeIcon(item.contentType),
                      size: 32,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(item.title, style: context.text.headlineSmall),
                  ),
                ],
              ),
              EyebrowPill(label: learningTypeName(l10n, item.contentType)),
              if (description != null && description.isNotEmpty)
                Text(description, style: context.text.bodyLarge),
              if (blocker != null)
                InlineNotice(
                  key: const Key('learn.blocker'),
                  icon: Icons.lock_outline_rounded,
                  message: blocker,
                )
              else if (item.playsInApp) ...[
                // A curated video (direct link or YouTube) plays inside the
                // app; the external path is only for what cannot.
                PrimaryButton(
                  key: const Key('learn.play'),
                  label: l10n.videoWatchInApp,
                  icon: Icons.play_arrow_rounded,
                  childSized: true,
                  onPressed: () => context.push(
                    AppRoutes.childLearnPlay(item.id),
                    extra: item,
                  ),
                ),
              ] else ...[
                PrimaryButton(
                  key: const Key('learn.open'),
                  label: l10n.learnOpen,
                  icon: Icons.open_in_new_rounded,
                  childSized: true,
                  onPressed: () => _open(uri!),
                ),
                Text(
                  l10n.learnOpensOutside,
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (_failed)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.learnOpenFailed,
                    key: const Key('learn.failed'),
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(
                      color: colors.error,
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
