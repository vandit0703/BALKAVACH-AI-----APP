import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/async/refresh_quietly.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/lazy_list_page.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/quiz_repository.dart';
import 'quiz_widgets.dart';

/// The Quizzes tab of the Learning Hub: every quiz the server offers this
/// child, with its completion status.
class QuizzesTab extends ConsumerWidget {
  const QuizzesTab({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(quizzesProvider)
      ..invalidate(quizHistoryProvider);
    await refreshQuietly(ref.read(quizzesProvider.future));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: switch (ref.watch(quizzesProvider)) {
        AsyncData(:final value) when value.isEmpty => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            EmptyView(
              key: const Key('quizzes.empty'),
              message: l10n.quizzesEmpty,
              image: AppImages.pandaDrawing,
            ),
          ],
        ),
        AsyncData(:final value) => LazyListPage(
          key: const Key('quizzes.list'),
          header: const [],
          itemCount: value.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _QuizCard(quiz: value[index]),
          ),
        ),
        AsyncError(:final error) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ErrorView(
              key: const Key('quizzes.error'),
              error: error,
              // GET /quizzes never answers 404 itself: a 404 means the server
              // does not have the quiz feature yet, not that it is empty.
              message: error is NotFoundException
                  ? l10n.quizzesUnavailable
                  : null,
              onRetry: () => ref.invalidate(quizzesProvider),
            ),
          ],
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _QuizCard extends ConsumerWidget {
  const _QuizCard({required this.quiz});

  final QuizSummary quiz;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final reward = quizRewardText(l10n, quiz);
    return AppCard(
      key: Key('quiz.${quiz.id}'),
      onTap: () async {
        await context.push(AppRoutes.childQuiz(quiz.id));
        // Status, best score and reward state may have changed.
        ref
          ..invalidate(quizzesProvider)
          ..invalidate(quizHistoryProvider);
      },
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: colors.primaryFixed,
            child: Icon(Icons.quiz_rounded, color: colors.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.xs,
              children: [
                Text(quiz.title, style: context.text.titleMedium),
                QuizChips(quiz: quiz),
                if (quiz.bestScorePercent != null)
                  Text(
                    l10n.quizBestScore(quiz.bestScorePercent!),
                    style: context.text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                if (reward != null)
                  Text(
                    reward,
                    style: context.text.bodySmall?.copyWith(
                      color: colors.primary,
                    ),
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
