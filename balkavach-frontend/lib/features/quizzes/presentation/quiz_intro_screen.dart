import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/quiz_repository.dart';
import 'quiz_widgets.dart';

/// What a quiz is, what it pays and how the child did before, then Start.
class QuizIntroScreen extends ConsumerWidget {
  const QuizIntroScreen({required this.quizId, super.key});

  final String quizId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.hubTabQuizzes),
        leading: BackButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.childLearnTab('quizzes')),
        ),
      ),
      body: SafeArea(
        child: switch (ref.watch(quizProvider(quizId))) {
          AsyncData(:final value) => _Body(quiz: value),
          AsyncError(:final error) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(quizProvider(quizId)),
          ),
          _ => const LoadingView(),
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.quiz});

  final QuizSummary quiz;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final reward = quizRewardText(l10n, quiz);
    final history = ref.watch(quizHistoryProvider).value ?? const [];
    final mine = [
      for (final item in history)
        if (item.quizId == quiz.id) item,
    ];
    final description = quiz.description?.trim();
    final startLabel = switch (quiz.status) {
      QuizStatus.inProgress => l10n.quizResume,
      QuizStatus.attempted || QuizStatus.passed => l10n.quizTryAgain,
      QuizStatus.pending => l10n.quizStart,
    };
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(quiz.title, style: context.text.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        QuizChips(quiz: quiz),
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(description, style: context.text.bodyLarge),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.quizPassMark(quiz.passPercent),
          style: context.text.bodyMedium,
        ),
        if (reward != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            reward,
            key: const Key('quiz.reward'),
            style: context.text.bodyMedium?.copyWith(color: colors.primary),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (quiz.canStart)
          PrimaryButton(
            key: const Key('quiz.start'),
            label: startLabel,
            icon: Icons.play_arrow_rounded,
            childSized: true,
            onPressed: () async {
              await context.push(AppRoutes.childQuizTake(quiz.id));
              ref
                ..invalidate(quizProvider(quiz.id))
                ..invalidate(quizzesProvider)
                ..invalidate(quizHistoryProvider);
            },
          )
        else
          InlineNotice(
            key: const Key('quiz.once'),
            icon: Icons.lock_outline_rounded,
            message: l10n.quizOnlyOnce,
          ),
        if (mine.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.quizHistoryTitle, style: context.text.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final item in mine)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                key: Key('quiz.attempt.${item.attemptId}'),
                onTap: () =>
                    context.push(AppRoutes.childQuizResult(item.attemptId)),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      item.passed
                          ? Icons.check_circle_rounded
                          : Icons.refresh_rounded,
                      color: item.passed
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        l10n.quizScoreLine(
                          item.correctCount,
                          item.totalQuestions,
                        ),
                        style: context.text.bodyMedium,
                      ),
                    ),
                    Text(
                      '${item.scorePercent}%',
                      style: context.text.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
