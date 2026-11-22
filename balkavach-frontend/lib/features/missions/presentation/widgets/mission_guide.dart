import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/daily_mission_models.dart';

/// What a child needs to do a daily mission, from the mission's own
/// structured content: what they will learn, what they need, how long it
/// takes, numbered step cards, what to observe, what to submit and safety.
///
/// Sections whose text the mission does not have are left out: nothing here
/// is filler. A mission without real steps shows an honest notice instead.
class MissionGuide extends StatelessWidget {
  const MissionGuide({required this.content, super.key});

  final DailyMissionContent content;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!content.instructionsReady) {
      return _Notice(
        key: const Key('mission.guide.incomplete'),
        icon: Icons.info_outline_rounded,
        title: l10n.missionGuideIncompleteTitle,
        body: l10n.missionGuideIncompleteBody,
      );
    }
    return Column(
      key: const Key('mission.guide'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.lg,
      children: [
        if (content.learningObjective != null)
          _Section(
            title: l10n.missionGuideLearn,
            child: Text(
              content.learningObjective!,
              style: context.text.bodyLarge,
            ),
          ),
        if (content.materials.isNotEmpty)
          _Section(
            title: l10n.missionGuideNeed,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.xs,
              children: [
                for (final item in content.materials)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.check_circle_outline_rounded,
                          size: 20,
                          color: context.colors.primary,
                          semanticLabel: '',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(item, style: context.text.bodyLarge),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        if (content.durationMinutes > 0)
          Row(
            key: const Key('mission.guide.time'),
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 22,
                color: context.colors.primary,
                semanticLabel: '',
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${l10n.missionGuideTime}: '
                  '${l10n.missionGuideTimeValue(content.durationMinutes)}',
                  style: context.text.bodyLarge,
                ),
              ),
            ],
          ),
        _Section(
          title: l10n.missionGuideSteps,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < content.steps.length; i++)
                _StepCard(number: i + 1, text: content.steps[i]),
            ],
          ),
        ),
        if (content.observationGuidance != null)
          _Section(
            title: l10n.missionGuideObserve,
            child: Text(
              content.observationGuidance!,
              style: context.text.bodyLarge,
            ),
          ),
        if (content.submissionRequirements != null)
          _Section(
            title: l10n.missionGuideSubmit,
            child: Text(
              content.submissionRequirements!,
              style: context.text.bodyLarge,
            ),
          ),
        if (content.safetyInstructions.trim().isNotEmpty)
          _Notice(
            key: const Key('mission.guide.safety'),
            icon: Icons.health_and_safety_outlined,
            title: l10n.missionGuideSafety,
            body: content.safetyInstructions.trim(),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: AppSpacing.sm,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: context.text.titleLarge),
      ),
      child,
    ],
  );
}

/// One numbered step. The badge grows with the text size instead of clipping
/// its number, and the step text wraps freely on narrow or foldable widths.
class _StepCard extends StatelessWidget {
  const _StepCard({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: l10n.missionStepLabel(number),
              excludeSemantics: true,
              child: Container(
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: const EdgeInsets.all(6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: context.text.titleMedium?.copyWith(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(text, style: context.text.bodyLarge),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.onSecondaryContainer, semanticLabel: ''),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.xs,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: context.text.titleMedium?.copyWith(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  body,
                  style: context.text.bodyLarge?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
