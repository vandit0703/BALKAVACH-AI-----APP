import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gamification.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/quiz_repository.dart';

/// One question at a time. The attempt comes from the server (which sends no
/// answers); only chosen option ids go back, and the server grades them.
class QuizTakeScreen extends ConsumerStatefulWidget {
  const QuizTakeScreen({required this.quizId, super.key});

  final String quizId;

  @override
  ConsumerState<QuizTakeScreen> createState() => _QuizTakeScreenState();
}

class _QuizTakeScreenState extends ConsumerState<QuizTakeScreen> {
  QuizAttempt? _attempt;
  Object? _loadError;
  int _index = 0;
  final Map<String, Set<String>> _chosen = {};
  bool _submitting = false;
  Object? _submitError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _submitError = null;
      _attempt = null;
      _index = 0;
      _chosen.clear();
    });
    try {
      final attempt = await ref
          .read(quizRepositoryProvider)
          .start(widget.quizId);
      if (mounted) setState(() => _attempt = attempt);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _toggle(QuizQuestion question, QuizOption option) {
    setState(() {
      final selected = _chosen.putIfAbsent(question.id, () => <String>{});
      if (question.isMultiple) {
        selected.contains(option.id)
            ? selected.remove(option.id)
            : selected.add(option.id);
      } else {
        selected
          ..clear()
          ..add(option.id);
      }
    });
  }

  Future<void> _submit() async {
    final attempt = _attempt!;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final result = await ref.read(quizRepositoryProvider).submit(attempt.id, {
        for (final question in attempt.questions)
          question.id: (_chosen[question.id] ?? const <String>{}).toList(),
      });
      if (!mounted) return;
      ref
        ..invalidate(quizzesProvider)
        ..invalidate(quizProvider(widget.quizId))
        ..invalidate(quizHistoryProvider);
      context.pushReplacement(
        AppRoutes.childQuizResult(result.attemptId),
        extra: result,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError = error;
        });
      }
    }
  }

  Future<bool> _confirmLeave() async {
    final l10n = AppLocalizations.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.quizLeaveTitle),
        content: Text(l10n.quizLeaveBody),
        actions: [
          TextButton(
            key: const Key('quiz.leave.stay'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.quizLeaveStay),
          ),
          TextButton(
            key: const Key('quiz.leave.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.quizLeaveConfirm),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final attempt = _attempt;
    // Android Back asks first once there is something to lose.
    final hasAnswers = _chosen.values.any((s) => s.isNotEmpty);
    return PopScope(
      canPop: !hasAnswers || _submitting,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave() && mounted) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(attempt?.title ?? l10n.hubTabQuizzes)),
        body: SafeArea(
          child: _loadError != null
              ? ErrorView(error: _loadError!, onRetry: _load)
              : attempt == null
              ? const LoadingView()
              : _question(context, l10n, attempt),
        ),
      ),
    );
  }

  Widget _question(
    BuildContext context,
    AppLocalizations l10n,
    QuizAttempt attempt,
  ) {
    final colors = context.colors;
    final question = attempt.questions[_index];
    final selected = _chosen[question.id] ?? const <String>{};
    final last = _index == attempt.questions.length - 1;
    final changed =
        _submitError is ApiException &&
        {
          'quiz_changed',
          'quiz_unavailable',
        }.contains((_submitError! as ApiException).code);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                l10n.quizQuestionOf(_index + 1, attempt.questions.length),
                key: const Key('quiz.progress'),
                style: context.text.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              PillProgressBar(
                value: (_index + 1) / attempt.questions.length,
                semanticsLabel: l10n.quizQuestionOf(
                  _index + 1,
                  attempt.questions.length,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                question.prompt,
                key: const Key('quiz.prompt'),
                style: context.text.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                question.isMultiple ? l10n.quizPickMany : l10n.quizPickOne,
                style: context.text.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final option in question.options)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _OptionTile(
                    key: Key('quiz.option.${option.id}'),
                    text: option.text,
                    selected: selected.contains(option.id),
                    multiple: question.isMultiple,
                    onTap: _submitting ? null : () => _toggle(question, option),
                  ),
                ),
              if (_submitError != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: InlineNotice(
                    key: const Key('quiz.submitError'),
                    icon: Icons.error_outline_rounded,
                    message: changed
                        ? l10n.quizChanged
                        : describeError(l10n, _submitError!),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            spacing: AppSpacing.md,
            children: [
              if (_index > 0)
                Expanded(
                  child: SecondaryButton(
                    key: const Key('quiz.previous'),
                    label: l10n.quizPrevious,
                    icon: Icons.arrow_back_rounded,
                    onPressed: _submitting
                        ? null
                        : () => setState(() => _index--),
                  ),
                ),
              Expanded(
                flex: 2,
                child: changed
                    ? PrimaryButton(
                        key: const Key('quiz.restart'),
                        label: l10n.quizStart,
                        childSized: true,
                        onPressed: _load,
                      )
                    : PrimaryButton(
                        key: Key(last ? 'quiz.submit' : 'quiz.next'),
                        label: last ? l10n.quizSubmit : l10n.quizNext,
                        trailingIcon: last
                            ? Icons.check_rounded
                            : Icons.arrow_forward_rounded,
                        loading: _submitting,
                        childSized: true,
                        // An answer is needed before moving on.
                        onPressed: selected.isEmpty || _submitting
                            ? null
                            : last
                            ? _submit
                            : () => setState(() => _index++),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.text,
    required this.selected,
    required this.multiple,
    required this.onTap,
    super.key,
  });

  final String text;
  final bool selected;
  final bool multiple;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final icon = multiple
        ? (selected
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded)
        : (selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: !multiple,
      child: AppCard(
        onTap: onTap,
        color: selected ? colors.primaryFixed : null,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Row(
            children: [
              Icon(icon, color: selected ? colors.primary : null),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(text, style: context.text.titleMedium)),
            ],
          ),
        ),
      ),
    );
  }
}
