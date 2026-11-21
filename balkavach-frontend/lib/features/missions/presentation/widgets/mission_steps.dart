import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';

/// A piece of a mission's instructions: running text, or numbered steps.
sealed class InstructionBlock {
  const InstructionBlock();
}

class ParagraphBlock extends InstructionBlock {
  const ParagraphBlock(this.text);
  final String text;
}

class StepsBlock extends InstructionBlock {
  const StepsBlock(this.steps);
  final List<String> steps;
}

final _stepLine = RegExp(r'^\s*\d{1,2}[.)]\s+(.+)$');

/// Splits a mission's text into paragraphs and numbered steps ("1. ...").
///
/// Only the layout changes: every line of the original text is kept, in
/// order, word for word (minus the "1." numbering, which the step layout
/// shows). Text with fewer than two numbered lines stays one paragraph.
List<InstructionBlock> parseInstructions(String text) {
  final lines = text.split('\n');
  if (lines.where(_stepLine.hasMatch).length < 2) {
    return [ParagraphBlock(text.trim())];
  }
  final blocks = <InstructionBlock>[];
  final paragraph = <String>[];
  final steps = <String>[];
  void flushParagraph() {
    final joined = paragraph.join('\n').trim();
    if (joined.isNotEmpty) blocks.add(ParagraphBlock(joined));
    paragraph.clear();
  }

  void flushSteps() {
    if (steps.isNotEmpty) blocks.add(StepsBlock(List.of(steps)));
    steps.clear();
  }

  for (final line in lines) {
    final step = _stepLine.firstMatch(line);
    if (step != null) {
      flushParagraph();
      steps.add(step.group(1)!.trim());
    } else if (line.trim().isEmpty) {
      flushSteps();
      flushParagraph();
    } else {
      flushSteps();
      paragraph.add(line);
    }
  }
  flushSteps();
  flushParagraph();
  return blocks;
}

/// Renders [parseInstructions] output.
class InstructionsView extends StatelessWidget {
  const InstructionsView({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final blocks = parseInstructions(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.md,
      children: [
        for (final block in blocks)
          switch (block) {
            ParagraphBlock(:final text) => Text(
              text,
              style: context.text.bodyLarge,
            ),
            StepsBlock(:final steps) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.sm + 4,
              children: [
                for (var i = 0; i < steps.length; i++)
                  MergeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          label: l10n.missionStepLabel(i + 1),
                          excludeSemantics: true,
                          child: Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: context.text.labelLarge?.copyWith(
                                color: colors.onPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              steps[i],
                              style: context.text.bodyLarge,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          },
      ],
    );
  }
}
