import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../quizzes/presentation/quizzes_tab.dart';
import '../data/learning_repository.dart';
import '../data/video_feed_repository.dart';
import 'learning_screen.dart' show LearningCard;
import 'shorts_tab.dart';
import 'video_feed_screen.dart' show VideoFeedList;

/// The Learning Hub: three working sections, each backed by its own server
/// data: Videos, Quizzes and Shorts. Switching tabs keeps each section's
/// scroll position and loaded pages, and a player or quiz opened from here
/// returns to the same tab. Stories (article items) stay readable from the
/// Videos tab's "More to explore" list.
class LearningHubScreen extends ConsumerStatefulWidget {
  const LearningHubScreen({this.initialTab = 'videos', super.key});

  /// `videos`, `quizzes` or `shorts`; anything else opens Videos.
  final String initialTab;

  static const tabNames = ['videos', 'quizzes', 'shorts'];

  @override
  ConsumerState<LearningHubScreen> createState() => _LearningHubScreenState();
}

class _LearningHubScreenState extends ConsumerState<LearningHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    final start = LearningHubScreen.tabNames.indexOf(widget.initialTab);
    _tabs = TabController(
      length: LearningHubScreen.tabNames.length,
      vsync: this,
      initialIndex: start < 0 ? 0 : start,
    );
  }

  @override
  void didUpdateWidget(LearningHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A link such as /child/learn?tab=quizzes moves an open hub to that tab.
    final next = LearningHubScreen.tabNames.indexOf(widget.initialTab);
    if (widget.initialTab != oldWidget.initialTab &&
        next >= 0 &&
        next != _tabs.index) {
      _tabs.animateTo(next);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Curated items (stories, videos, links, documents, activities) the
  /// administrator picked; they stay reachable from the Videos tab.
  List<Widget> _curatedPicks(AppLocalizations l10n) {
    final items =
        ref.watch(learningItemsProvider).value ?? const <LearningItem>[];
    if (items.isEmpty) return const [];
    final categories = ref.watch(learningCategoriesProvider).value ?? const [];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(l10n.hubMoreToExplore, style: context.text.titleMedium),
      ),
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: LearningCard(item: item, categories: categories),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: [
            Tab(key: const Key('hub.tab.videos'), text: l10n.hubTabVideos),
            Tab(key: const Key('hub.tab.quizzes'), text: l10n.hubTabQuizzes),
            Tab(key: const Key('hub.tab.shorts'), text: l10n.hubTabShorts),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              VideoFeedList(
                kind: VideoFeedKind.learn,
                header: _curatedPicks(l10n),
              ),
              const QuizzesTab(),
              const ShortsTab(),
            ],
          ),
        ),
      ],
    );
  }
}
