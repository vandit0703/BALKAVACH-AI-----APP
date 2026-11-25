import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gamification.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/quiz_repository.dart';

/// A parent's read-only view of a child's submitted quiz attempts: title,
/// date, result, score and what the server paid. It never shows questions or
/// answers and cannot start, change or reward anything.
///
/// The newest [kQuizHistoryPageSize] are listed first; "Show more" fetches
/// the next older page until there is nothing left.
class ParentQuizHistorySection extends ConsumerStatefulWidget {
  const ParentQuizHistorySection({required this.childId, super.key});

  final String childId;

  @override
  ConsumerState<ParentQuizHistorySection> createState() =>
      _ParentQuizHistorySectionState();
}

class _ParentQuizHistorySectionState
    extends ConsumerState<ParentQuizHistorySection> {
  var _pageCount = 1;

  @override
  void didUpdateWidget(ParentQuizHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) _pageCount = 1;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = [
      for (var page = 0; page < _pageCount; page++)
        ref.watch(
          parentQuizHistoryProvider((childId: widget.childId, page: page)),
        ),
    ];
    // Keyed by id: an attempt added between two requests shifts the pages.
    final attempts = <String, QuizHistoryItem>{
      for (final page in pages)
        for (final item in page.value?.items ?? const <QuizHistoryItem>[])
          item.attemptId: item,
    };
    // A failure on any page is shown, not only on the newest requested one.
    final failed = pages.indexWhere((page) => page is AsyncError);
    final status = failed < 0 ? pages.last : pages[failed];
    return Column(
      key: const Key('parent.quizHistory'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        SectionHeader(
          title: l10n.parentQuizHistoryTitle,
          icon: Icons.quiz_rounded,
        ),
        for (final item in attempts.values) _AttemptRow(item: item),
        switch (status) {
          AsyncData(:final value) when value.hasMore => SecondaryButton(
            key: const Key('parent.quizHistory.more'),
            label: l10n.showMore,
            icon: Icons.expand_more_rounded,
            onPressed: () => setState(() => _pageCount++),
          ),
          AsyncData() when attempts.isEmpty => Text(
            l10n.parentQuizHistoryEmpty,
            key: const Key('parent.quizHistory.empty'),
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          AsyncData() => const SizedBox.shrink(),
          AsyncError(:final error) => ErrorView(
            key: const Key('parent.quizHistory.error'),
            error: error,
            onRetry: () => ref.invalidate(
              parentQuizHistoryProvider((
                childId: widget.childId,
                page: failed,
              )),
            ),
          ),
          _ => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ],
    );
  }
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({required this.item});

  final QuizHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final rewards = [
      if (item.starsAwarded > 0) l10n.quizRewardStars(item.starsAwarded),
      if (item.xpAwarded > 0) l10n.quizRewardXp(item.xpAwarded),
    ];
    return AppCard(
      key: Key('parent.quiz.${item.attemptId}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.xs,
        children: [
          Text(item.quizTitle, style: context.text.titleSmall),
          StatusChip(
            label: item.passed
                ? l10n.quizStatusPassed
                : l10n.parentQuizNotPassed,
            icon: item.passed
                ? Icons.check_circle_rounded
                : Icons.refresh_rounded,
            background: item.passed
                ? colors.primaryFixed
                : colors.surfaceContainer,
            foreground: item.passed ? colors.primary : colors.onSurfaceVariant,
          ),
          Text(
            '${l10n.parentQuizScoreLine(item.correctCount, item.totalQuestions)}'
            ' · ${item.scorePercent}%',
            style: context.text.bodyMedium,
          ),
          Text(
            DateFormat.yMMMd(
              Localizations.localeOf(context).toString(),
            ).format(item.submittedAt.toLocal()),
            style: context.text.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (rewards.isNotEmpty)
            Text(
              '+ ${rewards.join(' + ')}',
              key: Key('parent.quiz.rewards.${item.attemptId}'),
              style: context.text.labelLarge?.copyWith(color: colors.primary),
            ),
        ],
      ),
    );
  }
}
