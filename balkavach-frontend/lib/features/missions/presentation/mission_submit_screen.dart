import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/validation/validators.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gamification.dart';
import '../../../shared/widgets/state_views.dart';
import '../domain/mission_models.dart';
import 'mission_providers.dart';

/// Complete Your Mission (Stitch `complete_your_mission`). Sends a `note`
/// proof (or `none`). Photo evidence is shown as unavailable because the API
/// has no upload endpoint (B2).
class MissionSubmitScreen extends ConsumerStatefulWidget {
  const MissionSubmitScreen({required this.taskId, super.key});

  final String taskId;

  @override
  ConsumerState<MissionSubmitScreen> createState() =>
      _MissionSubmitScreenState();
}

class _MissionSubmitScreenState extends ConsumerState<MissionSubmitScreen> {
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final submission = await ref
        .read(missionSubmitControllerProvider.notifier)
        .submit(widget.taskId, note: _note.text);
    if (!mounted || submission == null) return;
    context.pushReplacement(AppRoutes.childMissionWaiting(widget.taskId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mission = ref.watch(childMissionProvider(widget.taskId));
    final submitState = ref.watch(missionSubmitControllerProvider);
    final busy = submitState.isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.submitTitle)),
      body: switch (mission) {
        AsyncData(value: final Mission m) => Form(
          key: _formKey,
          child: ScrollablePage(
            maxWidth: ContentWidth.form,
            children: [
              _MissionBanner(mission: m),
              AppCard(
                radius: AppRadius.hero,
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.md,
                  children: [
                    SectionHeader(
                      title: l10n.submitEvidenceTitle,
                      icon: Icons.add_photo_alternate_outlined,
                    ),
                    InlineNotice(
                      icon: Icons.no_photography_outlined,
                      message: l10n.submitPhotoUnavailable,
                    ),
                    AppTextField(
                      fieldKey: const Key('submit.note'),
                      label: l10n.submitNoteLabel,
                      trailingLabel: l10n.optional,
                      hint: l10n.submitNoteHint,
                      controller: _note,
                      maxLength: 2000,
                      maxLines: 4,
                      minLines: 3,
                      validator: (v) => Validators(l10n).maxLength(v, 2000),
                      enabled: !busy,
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: context.colors.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            l10n.submitPrivacy,
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              MascotBubble(
                image: AppImages.pandaCheering,
                title: l10n.submitPandaName,
                message: l10n.submitPandaMessage,
              ),
              if (submitState case AsyncError(:final error))
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error is ForbiddenException &&
                            error.code == 'task_not_assigned'
                        ? l10n.submitNotAssigned
                        : describeError(l10n, error),
                    key: const Key('submit.error'),
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.error,
                    ),
                  ),
                ),
              PrimaryButton(
                key: const Key('submit.button'),
                label: '${l10n.submitButton} 🚀',
                backgroundColor: context.colors.primaryContainer,
                childSized: true,
                loading: busy,
                onPressed: _submit,
              ),
              Text(
                l10n.submitFooter(m.starReward),
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        AsyncData() => Center(child: EmptyView(message: l10n.missionNotFound)),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(childMissionsProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _MissionBanner extends StatelessWidget {
  const _MissionBanner({required this.mission});

  final Mission mission;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: AppRadius.hero,
      gradient: LinearGradient(
        colors: [
          context.colors.surfaceContainerHigh,
          context.colors.surfaceContainer,
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.sm,
        children: [
          StarPill(count: mission.starReward, prefix: '+'),
          Text(mission.title, style: context.text.headlineMedium),
        ],
      ),
    );
  }
}
