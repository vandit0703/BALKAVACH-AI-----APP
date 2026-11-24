import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/gamification.dart';
import '../data/quiz_repository.dart';

String quizDifficultyName(AppLocalizations l10n, String difficulty) =>
    switch (difficulty) {
      'medium' => l10n.quizDifficultyMedium,
      'hard' => l10n.quizDifficultyHard,
      _ => l10n.quizDifficultyEasy,
    };

String quizStatusName(AppLocalizations l10n, QuizStatus status) =>
    switch (status) {
      QuizStatus.inProgress => l10n.quizStatusInProgress,
      QuizStatus.attempted => l10n.quizStatusAttempted,
      QuizStatus.passed => l10n.quizStatusPassed,
      QuizStatus.pending => l10n.quizStatusPending,
    };

/// "First pass earns 10 Stars + 15 XP", or null when nothing can be earned.
String? quizRewardText(AppLocalizations l10n, QuizSummary quiz) {
  if (!quiz.hasOpenReward) return null;
  final parts = [
    if (quiz.starReward > 0) l10n.quizRewardStars(quiz.starReward),
    if (quiz.xpReward > 0) l10n.quizRewardXp(quiz.xpReward),
  ];
  return '${l10n.quizRewardPrefix} ${parts.join(' + ')}';
}

/// Subject, difficulty, length and completion status of a quiz.
class QuizChips extends StatelessWidget {
  const QuizChips({required this.quiz, super.key});

  final QuizSummary quiz;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final passed = quiz.status == QuizStatus.passed;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        EyebrowPill(label: quiz.subject),
        EyebrowPill(label: quizDifficultyName(l10n, quiz.difficulty)),
        EyebrowPill(label: l10n.quizQuestionCount(quiz.questionCount)),
        StatusChip(
          label: quizStatusName(l10n, quiz.status),
          icon: passed
              ? Icons.check_circle_rounded
              : quiz.status.isDone
              ? Icons.refresh_rounded
              : Icons.radio_button_unchecked_rounded,
          background: passed ? colors.primaryFixed : colors.surfaceContainer,
          foreground: passed ? colors.primary : colors.onSurfaceVariant,
        ),
      ],
    );
  }
}
