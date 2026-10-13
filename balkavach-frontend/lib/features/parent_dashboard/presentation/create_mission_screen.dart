import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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

/// Parent creates a mission (`POST /api/v1/tasks`) or, when [mission] is
/// given, edits it (`PATCH /api/v1/tasks/{id}`) or removes it
/// (`DELETE /api/v1/tasks/{id}`, which only deactivates it).
///
/// Repeat rules exist in the API but are not part of any Stitch design.
class CreateMissionScreen extends ConsumerStatefulWidget {
  const CreateMissionScreen({this.mission, super.key});

  final Mission? mission;

  @override
  ConsumerState<CreateMissionScreen> createState() =>
      _CreateMissionScreenState();
}

class _CreateMissionScreenState extends ConsumerState<CreateMissionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.mission?.title);
  late final _description = TextEditingController(
    text: widget.mission?.description,
  );
  late final _stars = TextEditingController(
    text: '${widget.mission?.starReward ?? 10}',
  );
  late final _xp = TextEditingController(
    text: '${widget.mission?.xpReward ?? 20}',
  );
  late String? _categoryId = widget.mission?.categoryId;
  late String? _childId = widget.mission?.assignedChildId;
  late DateTime? _dueAt = widget.mission?.dueAt?.toLocal();
  bool _busy = false;
  bool _removing = false;

  bool get _editing => widget.mission != null;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _stars.dispose();
    _xp.dispose();
    super.dispose();
  }

  Future<void> _chooseIdea() async {
    final l10n = AppLocalizations.of(context);
    final presets = ref.read(missionPresetsProvider.future);
    final chosen = await showModalBottomSheet<MissionPreset>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FutureBuilder<List<MissionPreset>>(
        future: presets,
        builder: (context, snapshot) {
          final items = snapshot.data;
          return SafeArea(
            child: items == null
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        title: Text(
                          l10n.createMissionIdeasTitle,
                          style: context.text.titleLarge,
                        ),
                        subtitle: Text(l10n.createMissionIdeasHint),
                      ),
                      if (items.isEmpty)
                        ListTile(title: Text(l10n.createMissionIdeasEmpty)),
                      for (final preset in items)
                        ListTile(
                          key: Key('idea.${preset.id}'),
                          title: Text(preset.title),
                          subtitle: Text(
                            [
                              ?preset.categoryName,
                              '${preset.suggestedStars} ★ · ${preset.suggestedXp} XP',
                            ].join(' · '),
                          ),
                          onTap: () => Navigator.pop(context, preset),
                        ),
                    ],
                  ),
          );
        },
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _title.text = chosen.title;
      _description.text = chosen.description ?? '';
      _stars.text = '${chosen.suggestedStars}';
      _xp.text = '${chosen.suggestedXp}';
      _categoryId = chosen.categoryId;
    });
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    // A date, not a time: missions are due by the end of that day.
    if (picked != null) {
      setState(
        () => _dueAt = DateTime(picked.year, picked.month, picked.day, 23, 59),
      );
    }
  }

  Future<void> _submit() async {
    if (_busy || _removing) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      // Await rather than read `.value`: the family may still be loading.
      final family = await ref.read(currentFamilyProvider.future);
      if (family == null) {
        throw const NotFoundException(message: 'Family not found');
      }
      final input = NewMission(
        familyId: family.id,
        title: _title.text,
        description: _description.text,
        categoryId: _categoryId,
        assignedChildId: _childId,
        starReward: int.tryParse(_stars.text.trim()) ?? 0,
        xpReward: int.tryParse(_xp.text.trim()) ?? 0,
        dueAt: _dueAt,
      );
      final repository = ref.read(missionsRepositoryProvider);
      if (_editing) {
        await repository.updateMission(widget.mission!.id, input);
      } else {
        await repository.createMission(input);
      }
      ref
        ..invalidate(familyMissionsProvider(family.id))
        ..invalidate(childMissionsProvider);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _editing ? l10n.missionSaved : l10n.createMissionSuccess,
          ),
        ),
      );
      await Navigator.maybePop(context);
    } on ApiException catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final mission = widget.mission;
    if (mission == null || _busy || _removing) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text(l10n.removeMissionConfirmTitle),
        content: Text(l10n.removeMissionConfirmBody(mission.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('mission.remove.confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              foregroundColor: context.colors.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.removeMissionConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing = true);
    try {
      await ref.read(missionsRepositoryProvider).deactivateMission(mission.id);
      ref
        ..invalidate(familyMissionsProvider(mission.familyId))
        ..invalidate(childMissionsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.removeMissionDone)));
      await Navigator.maybePop(context);
    } on ApiException catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _removing = false);
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
    final locale = Localizations.localeOf(context).toLanguageTag();
    final busy = _busy || _removing;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? l10n.editMissionTitle : l10n.createMissionTitle),
      ),
      body: Form(
        key: _formKey,
        child: ScrollablePage(
          maxWidth: ContentWidth.form,
          spacing: AppSpacing.lg,
          children: [
            if (!_editing)
              SecondaryButton(
                key: const Key('mission.ideas'),
                label: l10n.createMissionIdeas,
                icon: Icons.lightbulb_outline_rounded,
                onPressed: busy ? null : _chooseIdea,
              ),
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
              // New key once the list loads, so the saved value shows.
              key: ValueKey('category-${categories.length}'),
              label: l10n.createMissionCategory,
              value: categories.any((c) => c.id == _categoryId)
                  ? _categoryId
                  : null,
              items: {
                null: l10n.createMissionNoCategory,
                for (final c in categories) c.id: c.name,
              },
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            _Dropdown<String?>(
              key: ValueKey('assignee-${children.length}'),
              label: l10n.createMissionAssign,
              value: children.any((c) => c.id == _childId) ? _childId : null,
              items: {
                null: l10n.missionForEveryone,
                for (final c in children) c.id: c.displayName,
              },
              onChanged: (v) => setState(() => _childId = v),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.sm,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.createMissionDue,
                        style: context.text.titleSmall,
                      ),
                    ),
                    Text(
                      l10n.optional,
                      style: context.text.labelMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SecondaryButton(
                      key: const Key('mission.due'),
                      icon: Icons.event_rounded,
                      label: _dueAt == null
                          ? l10n.createMissionDuePick
                          : DateFormat.yMMMd(locale).format(_dueAt!),
                      onPressed: busy ? null : _pickDue,
                    ),
                    if (_dueAt != null)
                      TextButton(
                        key: const Key('mission.due.clear'),
                        onPressed: busy
                            ? null
                            : () => setState(() => _dueAt = null),
                        child: Text(l10n.createMissionDueClear),
                      ),
                  ],
                ),
              ],
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
              label: _editing ? l10n.saveChanges : l10n.createMissionSubmit,
              icon: _editing ? Icons.check_rounded : Icons.add_task_rounded,
              loading: _busy,
              onPressed: family == null || _removing ? null : _submit,
            ),
            if (_editing)
              TextButton.icon(
                key: const Key('mission.remove'),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.error,
                  minimumSize: const Size.fromHeight(AppTouch.parentMin),
                ),
                onPressed: busy ? null : _remove,
                icon: _removing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded),
                label: Text(l10n.removeMissionButton),
              ),
          ],
        ),
      ),
    );
  }
}

/// Route target for `/parent/missions/:taskId/edit`: finds the mission among
/// the family's missions, then shows the form. A mission that no longer
/// exists (removed elsewhere) shows a message instead of an empty form.
class EditMissionScreen extends ConsumerWidget {
  const EditMissionScreen({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final family = ref.watch(currentFamilyProvider);
    Widget scaffold(Widget body) => Scaffold(
      appBar: AppBar(title: Text(l10n.editMissionTitle)),
      body: body,
    );

    return switch (family) {
      AsyncData(value: final f?) => switch (ref.watch(
        familyMissionsProvider(f.id),
      )) {
        AsyncData(:final value) => switch (value
            .where((m) => m.id == taskId)
            .firstOrNull) {
          final Mission mission => CreateMissionScreen(
            key: ValueKey(mission.id),
            mission: mission,
          ),
          null => scaffold(
            Center(child: EmptyView(message: l10n.missionNotFound)),
          ),
        },
        AsyncError(:final error) => scaffold(
          ErrorView(
            error: error,
            onRetry: () => ref.invalidate(familyMissionsProvider(f.id)),
          ),
        ),
        _ => scaffold(const LoadingView()),
      },
      AsyncData() => scaffold(EmptyView(message: l10n.familyMissing)),
      AsyncError(:final error) => scaffold(
        ErrorView(
          error: error,
          onRetry: () => ref.invalidate(currentFamilyProvider),
        ),
      ),
      _ => scaffold(const LoadingView()),
    };
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
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
