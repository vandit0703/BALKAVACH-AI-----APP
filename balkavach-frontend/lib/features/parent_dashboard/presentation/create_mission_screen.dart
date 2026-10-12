import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/validation/validators.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/state_views.dart';
import '../../child_profile/domain/family_models.dart';
import '../../child_profile/presentation/family_providers.dart';
import '../../missions/data/missions_repository.dart';
import '../../missions/domain/mission_models.dart';
import '../../missions/presentation/mission_providers.dart';

/// Parent creates a mission via `POST /api/v1/tasks`. Due dates and repeat
/// rules exist in the API but are left for the parent-dashboard slice.
class CreateMissionScreen extends ConsumerStatefulWidget {
  const CreateMissionScreen({super.key});

  @override
  ConsumerState<CreateMissionScreen> createState() =>
      _CreateMissionScreenState();
}

class _CreateMissionScreenState extends ConsumerState<CreateMissionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _stars = TextEditingController(text: '10');
  final _xp = TextEditingController(text: '20');
  String? _categoryId;
  String? _childId;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _stars.dispose();
    _xp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      // Await rather than read `.value`: the family may still be loading.
      final family = await ref.read(currentFamilyProvider.future);
      if (family == null) {
        throw const NotFoundException(message: 'Family not found');
      }
      await ref
          .read(missionsRepositoryProvider)
          .createMission(
            NewMission(
              familyId: family.id,
              title: _title.text,
              description: _description.text,
              categoryId: _categoryId,
              assignedChildId: _childId,
              starReward: int.tryParse(_stars.text.trim()) ?? 0,
              xpReward: int.tryParse(_xp.text.trim()) ?? 0,
            ),
          );
      ref.invalidate(familyMissionsProvider(family.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).createMissionSuccess),
        ),
      );
      await Navigator.maybePop(context);
    } on ApiException catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final validators = Validators(l10n);
    final family = ref.watch(currentFamilyProvider).value;
    final categories = ref.watch(taskCategoriesProvider).value ?? const [];
    final children = family == null
        ? const <ChildProfile>[]
        : ref.watch(familyChildrenProvider(family.id)).value ??
              const <ChildProfile>[];
    final digitsOnly = [FilteringTextInputFormatter.digitsOnly];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.createMissionTitle)),
      body: Form(
        key: _formKey,
        child: ScrollablePage(
          maxWidth: ContentWidth.form,
          spacing: AppSpacing.lg,
          children: [
            AppTextField(
              fieldKey: const Key('mission.title'),
              label: l10n.createMissionName,
              controller: _title,
              validator: validators.missionTitle,
              maxLength: 180,
              textInputAction: TextInputAction.next,
            ),
            AppTextField(
              fieldKey: const Key('mission.description'),
              label: l10n.createMissionDescription,
              trailingLabel: l10n.optional,
              controller: _description,
              validator: (v) => validators.maxLength(v, 5000),
              maxLength: 5000,
              maxLines: 5,
              minLines: 3,
            ),
            _Dropdown<String?>(
              label: l10n.createMissionCategory,
              value: _categoryId,
              items: {
                null: l10n.createMissionNoCategory,
                for (final c in categories) c.id: c.name,
              },
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            _Dropdown<String?>(
              label: l10n.createMissionAssign,
              value: _childId,
              items: {
                null: l10n.missionForEveryone,
                for (final c in children) c.id: c.displayName,
              },
              onChanged: (v) => setState(() => _childId = v),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.md,
              children: [
                Expanded(
                  child: AppTextField(
                    fieldKey: const Key('mission.stars'),
                    label: l10n.createMissionStars,
                    controller: _stars,
                    keyboardType: TextInputType.number,
                    inputFormatters: digitsOnly,
                    validator: (v) =>
                        validators.intRange(v, min: 0, max: 10000),
                  ),
                ),
                Expanded(
                  child: AppTextField(
                    fieldKey: const Key('mission.xp'),
                    label: l10n.createMissionXp,
                    controller: _xp,
                    keyboardType: TextInputType.number,
                    inputFormatters: digitsOnly,
                    validator: (v) =>
                        validators.intRange(v, min: 0, max: 100000),
                  ),
                ),
              ],
            ),
            PrimaryButton(
              key: const Key('mission.submit'),
              label: l10n.createMissionSubmit,
              icon: Icons.add_task_rounded,
              loading: _busy,
              onPressed: family == null ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        Text(label, style: context.text.titleSmall),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(AppRadius.md),
          items: [
            for (final MapEntry(:key, value: text) in items.entries)
              DropdownMenuItem<T>(
                value: key,
                child: Text(text, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
