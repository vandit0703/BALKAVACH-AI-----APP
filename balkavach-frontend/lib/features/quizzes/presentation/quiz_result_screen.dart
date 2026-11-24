import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/celebration/activity_completion.dart';
import '../../../shared/celebration/panda_celebration.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gamification.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/quiz_repository.dart';

/// The outcome of a graded attempt. [result] is passed along right after
/// submitting; opening one from the history loads it by id instead. Either way
/// every number comes from the server, and viewing never pays anything.
class QuizResultScreen extends ConsumerStatefulWidget {
  const QuizResultScreen({required this.attemptId, this.result, super.key});

  final String attemptId;
  final QuizResult? result;

  @override
  ConsumerState<QuizResultScreen> createState() => _QuizResultScreenState();
}

class _QuizResultScreenState extends ConsumerState<QuizResultScreen> {
  @override
  void initState() {
    super.initState();
    // Only the result handed over by a fresh submit is celebrated. A result
    // reopened from the history is loaded by id and never is, and a failed
    // attempt gets the encouraging result page instead.
    final fresh = widget.result;
    if (fresh != null && fresh.passed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_celebrate(fresh));
      });
    }
  }

  Future<void> _celebrate(QuizResult result) async {
    final action = await showPandaCelebration(
      context,
      ActivityCompletion(
        kind: ActivityKind.quiz,
        title: result.quizTitle,
        // What the server paid for this attempt: zero on a retake.
        stars: result.starsAwarded,
        xp: result.xpAwarded,
        offerHome: true,
      ),
    );
    if (mounted && action == CelebrationAction.home) {
      context.go(AppRoutes.childHome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loaded = widget.result;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.hubTabQuizzes),
        automaticallyImplyLeading: false,
        leading: BackButton(onPressed: () => _leave(context)),
      ),
      body: SafeArea(
        child: loaded != null
            ? _Body(result: loaded)
            : switch (ref.watch(quizResultProvider(widget.attemptId))) {
                AsyncData(:final value) => _Body(result: value),
                AsyncError(:final error) => ErrorView(
                  error: error,
                  onRetry: () =>
                      ref.invalidate(quizResultProvider(widget.attemptId)),
                ),
                _ => const LoadingView(),
              },
      ),
    );
  }
}

void _leave(BuildContext context) => context.canPop()
    ? context.pop()
    : context.go(AppRoutes.childLearnTab('quizzes'));

class _Body extends StatelessWidget {
  const _Body({required this.result});

  final QuizResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final earned = result.starsAwarded > 0 || result.xpAwarded > 0;
    final review = result.review;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (result.passed)
          ClipRRect(
            borderRadius: AppRadius.card,
            child: Image.asset(
              AppImages.pandaCheering,
              key: const Key('quiz.result.panda'),
              height: 180,
              fit: BoxFit.cover,
              semanticLabel: l10n.quizResultPassed,
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Text(
          result.passed ? l10n.quizResultPassed : l10n.quizResultTryAgain,
          key: const Key('quiz.result.title'),
          textAlign: TextAlign.center,
          style: context.text.headlineMedium,
        ),
        Text(
          result.quizTitle,
          textAlign: TextAlign.center,
          style: context.text.bodyLarge?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          '${result.scorePercent}%',
          key: const Key('quiz.result.percent'),
          textAlign: TextAlign.center,
          style: context.text.displayMedium?.copyWith(color: colors.primary),
        ),
        Text(
          l10n.quizScoreLine(result.correctCount, result.totalQuestions),
          key: const Key('quiz.result.line'),
          textAlign: TextAlign.center,
          style: context.text.titleMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          spacing: AppSpacing.sm,
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.check_circle_rounded,
                iconColor: colors.primary,
                label: l10n.quizCorrectLabel,
                value: '${result.correctCount}',
              ),
            ),
            Expanded(
              child: StatTile(
                icon: Icons.cancel_rounded,
                iconColor: colors.error,
                label: l10n.quizIncorrectLabel,
                value: '${result.incorrectCount}',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (earned)
          InlineNotice(
            key: const Key('quiz.result.earned'),
            icon: Icons.stars_rounded,
            message: l10n.quizEarned(result.starsAwarded, result.xpAwarded),
          )
        else if (result.passed)
          Text(
            l10n.quizRewardOnce,
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          )
        else
          Text(
            l10n.quizNeedMore(result.passPercent),
            key: const Key('quiz.result.needMore'),
            textAlign: TextAlign.center,
            style: context.text.bodyMedium,
          ),
        const SizedBox(height: AppSpacing.lg),
        if (result.canRetry)
          PrimaryButton(
            key: const Key('quiz.result.retry'),
            label: l10n.quizTryAgain,
            icon: Icons.refresh_rounded,
            childSized: true,
            onPressed: () =>
                context.pushReplacement(AppRoutes.childQuizTake(result.quizId)),
          ),
        const SizedBox(height: AppSpacing.sm),
        SecondaryButton(
          key: const Key('quiz.result.learn'),
          label: l10n.quizBackToLearn,
          icon: Icons.menu_book_rounded,
          onPressed: () => context.go(AppRoutes.childLearnTab('quizzes')),
        ),
        const SizedBox(height: AppSpacing.sm),
        SecondaryButton(
          key: const Key('quiz.result.home'),
          label: l10n.quizHome,
          icon: Icons.home_rounded,
          onPressed: () => context.go(AppRoutes.childHome),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.quizReviewTitle, style: context.text.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        if (review == null)
          Text(
            l10n.quizReviewUnavailable,
            key: const Key('quiz.review.unavailable'),
            style: context.text.bodyMedium,
          )
        else
          for (final item in review) _ReviewCard(item: item),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.item});

  final ReviewItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    String names(Iterable<ReviewOption> options) =>
        options.map((o) => o.text).join(', ');
    final yours = names(
      item.options.where((o) => item.selectedOptionIds.contains(o.id)),
    );
    final right = names(item.options.where((o) => o.isCorrect));
    final explanation = item.explanation?.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        key: Key('quiz.review.${item.questionId}'),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.xs,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  item.isCorrect
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: item.isCorrect ? colors.primary : colors.error,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(item.prompt, style: context.text.titleMedium),
                ),
              ],
            ),
            Text(
              '${l10n.quizYourAnswer}: ${yours.isEmpty ? '—' : yours}',
              style: context.text.bodyMedium,
            ),
            if (!item.isCorrect)
              Text(
                '${l10n.quizRightAnswer}: $right',
                style: context.text.bodyMedium?.copyWith(color: colors.primary),
              ),
            if (explanation != null && explanation.isNotEmpty)
              Text(
                explanation,
                style: context.text.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
