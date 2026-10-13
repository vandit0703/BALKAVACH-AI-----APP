import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/media/photo_picker.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/validation/validators.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gamification.dart';
import '../../../shared/widgets/state_views.dart';
import '../domain/mission_models.dart';
import 'mission_providers.dart';

/// Complete Your Mission (Stitch `complete_your_mission`). The child can add
/// a real photo (uploaded to the server, then attached to the submission), a
/// note, both, or neither.
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
  PickedPhoto? _photo;
  bool _pickFailed = false;

  Future<void> _pick(PhotoSource source) async {
    try {
      final photo = await ref.read(photoPickerProvider).pick(source);
      if (!mounted) return;
      setState(() {
        _pickFailed = false;
        if (photo != null) _photo = photo;
      });
    } on PhotoPickException {
      if (mounted) setState(() => _pickFailed = true);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final submission = await ref
        .read(missionSubmitControllerProvider.notifier)
        .submit(widget.taskId, note: _note.text, photo: _photo);
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
                    _PhotoSection(
                      photo: _photo,
                      busy: busy,
                      failed: _pickFailed,
                      onPick: _pick,
                      onRemove: () => setState(() => _photo = null),
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

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.photo,
    required this.busy,
    required this.failed,
    required this.onPick,
    required this.onRemove,
  });

  final PickedPhoto? photo;
  final bool busy;
  final bool failed;
  final Future<void> Function(PhotoSource source) onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chosen = photo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        if (chosen == null)
          Text(
            l10n.submitPhotoHelp,
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          )
        else ...[
          Semantics(
            image: true,
            label: l10n.submitPhotoPreview,
            child: ClipRRect(
              borderRadius: AppRadius.card,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: Image.memory(
                  chosen.bytes,
                  key: const Key('submit.photo.preview'),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  excludeFromSemantics: true,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
          Text(
            l10n.submitPhotoReady,
            style: context.text.labelLarge?.copyWith(
              color: context.colors.primary,
            ),
          ),
        ],
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            SecondaryButton(
              key: const Key('submit.photo.camera'),
              label: chosen == null
                  ? l10n.submitTakePhoto
                  : l10n.submitAddPhoto,
              icon: Icons.photo_camera_outlined,
              onPressed: busy ? null : () => onPick(PhotoSource.camera),
            ),
            SecondaryButton(
              key: const Key('submit.photo.gallery'),
              label: l10n.submitChoosePhoto,
              icon: Icons.photo_library_outlined,
              onPressed: busy ? null : () => onPick(PhotoSource.gallery),
            ),
            if (chosen != null)
              TextButton.icon(
                key: const Key('submit.photo.remove'),
                onPressed: busy ? null : onRemove,
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(l10n.submitRemovePhoto),
              ),
          ],
        ),
        if (failed)
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.submitPhotoPickFailed,
              key: const Key('submit.photo.error'),
              style: context.text.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ),
        if (busy && chosen != null)
          Text(l10n.submitUploading, style: context.text.bodySmall),
      ],
    );
  }
}
