import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/async/refresh_quietly.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/validation/validators.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/brand_header.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gamification.dart';
import '../../../shared/widgets/illustration.dart';
import '../../../shared/widgets/nav_tile.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/data/auth_repository.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../progress/data/progress_repository.dart';
import '../data/family_repository.dart';
import '../domain/family_models.dart';
import 'child_mode_launcher.dart';
import 'create_child_screen.dart';
import 'family_providers.dart';

/// Child profile & family management (Stitch
/// `child_profile_family_management`).
///
/// Interests, daily mission target and reward multiplier from the design are
/// not stored by the backend (B8) and are not shown. "Delete" deactivates the
/// profile (`DELETE /families/{id}/children/{child_id}` is a soft delete).
class ChildProfileScreen extends ConsumerWidget {
  const ChildProfileScreen({required this.childId, super.key});

  final String childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final family = ref.watch(currentFamilyProvider);
    return Scaffold(
      appBar: AppBar(title: BrandTitle(title: l10n.familyManageAppBar)),
      body: switch (family) {
        AsyncData(value: final f?) => _Body(familyId: f.id, childId: childId),
        AsyncData() => EmptyView(message: l10n.familyMissing),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(currentFamilyProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.familyId, required this.childId});

  final String familyId;
  final String childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final children = ref.watch(familyChildrenProvider(familyId));
    return switch (children) {
      AsyncData(:final value) => switch (value
          .where((c) => c.id == childId)
          .firstOrNull) {
        final ChildProfile child => _Profile(
          familyId: familyId,
          child: child,
          siblings: value.where((c) => c.id != childId).toList(),
        ),
        null => EmptyView(
          message: l10n.childProfileMissing,
          action: SecondaryButton(
            label: l10n.backToParentHub,
            icon: Icons.arrow_back_rounded,
            onPressed: () => context.go(AppRoutes.parentHome),
          ),
        ),
      },
      AsyncError(:final error) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(familyChildrenProvider(familyId)),
      ),
      _ => const LoadingView(),
    };
  }
}

class _Profile extends ConsumerWidget {
  const _Profile({
    required this.familyId,
    required this.child,
    required this.siblings,
  });

  final String familyId;
  final ChildProfile child;
  final List<ChildProfile> siblings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final progress = ref.watch(childProgressProvider(child.id));
    final approved90 = progress.value?.activityDays.fold<int>(
      0,
      (sum, d) => sum + d.completedTasks,
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(familyChildrenProvider(familyId))
          ..invalidate(childProgressProvider(child.id));
        await refreshQuietly(ref.read(childProgressProvider(child.id).future));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ResponsiveContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.md,
              children: [
                Text(
                  l10n.familyManageSubtitle,
                  style: context.text.bodyLarge?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                AppCard(
                  radius: AppRadius.hero,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.md,
                    children: [
                      _ProfileHeader(familyId: familyId, child: child),
                      switch (progress) {
                        AsyncData(:final value) => Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            if (value.levelNumber != null)
                              EyebrowPill(
                                icon: Icons.military_tech_rounded,
                                label: l10n.reportsLevel(
                                  value.levelNumber!,
                                  value.levelName ?? '',
                                ),
                              ),
                            StarPill(
                              count: value.starBalance,
                              label: l10n.availableStars(value.starBalance),
                            ),
                          ],
                        ),
                        AsyncError(:final error) => InlineNotice(
                          icon: Icons.cloud_off_rounded,
                          message: describeError(l10n, error),
                        ),
                        _ => const LinearProgressIndicator(),
                      },
                      NavTile(
                        key: const Key('profile.activity'),
                        tonal: true,
                        icon: Icons.insights_rounded,
                        tint: context.colors.tertiaryFixed,
                        iconColor: context.colors.onTertiaryFixed,
                        title: l10n.viewActivityHistory,
                        subtitle: approved90 == null
                            ? null
                            : l10n.missionsApprovedRecently(approved90),
                        onTap: () =>
                            context.push(AppRoutes.parentReportsFor(child.id)),
                      ),
                      NavTile(
                        key: const Key('profile.childMode'),
                        tonal: true,
                        icon: Icons.rocket_launch_rounded,
                        tint: context.colors.secondaryContainer,
                        iconColor: context.colors.onSecondaryContainer,
                        title: l10n.childStartMode,
                        subtitle: l10n.childModeHint(child.displayName),
                        onTap: () =>
                            confirmAndStartChildMode(context, ref, child),
                      ),
                    ],
                  ),
                ),
                for (final sibling in siblings) _SiblingCard(child: sibling),
                AppCard(
                  key: const Key('profile.addChild'),
                  color: context.colors.surfaceContainer,
                  elevated: false,
                  radius: AppRadius.hero,
                  onTap: () => context.push(AppRoutes.parentNewChild),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        backgroundColor: context.colors.surfaceContainerHighest,
                        child: Icon(
                          Icons.person_add_alt_1_rounded,
                          color: context.colors.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(
                        child: Text(
                          l10n.addAnotherChild,
                          style: context.text.titleMedium?.copyWith(
                            color: context.colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _DevicesCard(child: child),
                const SizedBox(height: AppSpacing.sm),
                _RemoveCard(familyId: familyId, child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.familyId, required this.child});

  final String familyId;
  final ChildProfile child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final avatar = ref.watch(childAvatarProvider(child.id));
    final age = child.ageOn(ref.watch(clockProvider)());

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.xs,
      children: [
        Text(child.displayName, style: context.text.headlineSmall),
        StatusChip(
          label: l10n.profileActive,
          icon: Icons.check_circle_rounded,
          background: colors.surfaceContainerHigh,
          foreground: colors.primary,
        ),
        if (age != null)
          Text(
            l10n.profileAge(age),
            style: context.text.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
      ],
    );

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChildAvatar(name: child.displayName, option: avatar, size: 88),
            const SizedBox(width: AppSpacing.md),
            Flexible(child: details),
          ],
        ),
        SecondaryButton(
          key: const Key('profile.edit'),
          dense: true,
          label: l10n.edit,
          icon: Icons.edit_rounded,
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (_) => _EditSheet(familyId: familyId, child: child),
          ),
        ),
      ],
    );
  }
}

class _SiblingCard extends ConsumerWidget {
  const _SiblingCard({required this.child});

  final ChildProfile child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final avatar = ref.watch(childAvatarProvider(child.id));
    final age = child.ageOn(ref.watch(clockProvider)());
    return AppCard(
      radius: AppRadius.hero,
      semanticLabel: l10n.childOpenProfile(child.displayName),
      onTap: () => context.pushReplacement(AppRoutes.parentChild(child.id)),
      child: Row(
        children: [
          ChildAvatar(name: child.displayName, option: avatar, size: 64),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(child.displayName, style: context.text.titleLarge),
                if (age != null)
                  Text(
                    l10n.profileAge(age),
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: context.colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// Ends this child's sign-in on every device (a lost or shared tablet).
class _DevicesCard extends ConsumerStatefulWidget {
  const _DevicesCard({required this.child});

  final ChildProfile child;

  @override
  ConsumerState<_DevicesCard> createState() => _DevicesCardState();
}

class _DevicesCardState extends ConsumerState<_DevicesCard> {
  bool _busy = false;

  Future<void> _signOut() async {
    final l10n = AppLocalizations.of(context);
    final name = widget.child.displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.childSignOutDevices),
        content: Text(l10n.childSignOutDevicesBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('profile.devices.confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.childSignOutDevicesConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).endChildSessions(widget.child.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.childSignOutDevicesDone)));
    } on ApiException catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      elevated: false,
      color: context.colors.surfaceContainerLow,
      radius: AppRadius.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          Text(
            l10n.childSignOutDevicesBody(widget.child.displayName),
            style: context.text.bodyMedium,
          ),
          SecondaryButton(
            key: const Key('profile.devices'),
            label: l10n.childSignOutDevices,
            icon: Icons.devices_other_rounded,
            onPressed: _busy ? null : _signOut,
          ),
        ],
      ),
    );
  }
}

class _RemoveCard extends ConsumerStatefulWidget {
  const _RemoveCard({required this.familyId, required this.child});

  final String familyId;
  final ChildProfile child;

  @override
  ConsumerState<_RemoveCard> createState() => _RemoveCardState();
}

class _RemoveCardState extends ConsumerState<_RemoveCard> {
  bool _busy = false;

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    final name = widget.child.displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text(l10n.removeChildConfirmTitle(name)),
        content: Text(l10n.removeChildConfirmBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('profile.remove.confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              foregroundColor: context.colors.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.removeChildConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(familyRepositoryProvider)
          .deactivateChild(widget.familyId, widget.child.id);
      ref.invalidate(familyChildrenProvider(widget.familyId));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.removeChildDone(name))));
      context.go(AppRoutes.parentHome);
    } on ApiException catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final name = widget.child.displayName;
    return AppCard(
      color: colors.errorContainer.withValues(alpha: 0.45),
      elevated: false,
      radius: AppRadius.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.errorContainer,
                child: Icon(
                  Icons.person_off_rounded,
                  color: colors.onErrorContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.xs,
                  children: [
                    Text(
                      l10n.removeChildTitle,
                      style: context.text.titleMedium?.copyWith(
                        color: colors.error,
                      ),
                    ),
                    Text(
                      l10n.removeChildBody(name),
                      style: context.text.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: PrimaryButton(
              key: const Key('profile.remove'),
              label: l10n.removeChildButton(name),
              icon: Icons.delete_outline_rounded,
              backgroundColor: colors.error,
              loading: _busy,
              onPressed: _remove,
            ),
          ),
        ],
      ),
    );
  }
}

/// Edits the name and date of birth on the server and the avatar on this
/// device (B7).
class _EditSheet extends ConsumerStatefulWidget {
  const _EditSheet({required this.familyId, required this.child});

  final String familyId;
  final ChildProfile child;

  @override
  ConsumerState<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends ConsumerState<_EditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.child.displayName);
  late DateTime? _dob = widget.child.dateOfBirth;
  late ChildAvatarOption _avatar =
      ref.read(childAvatarProvider(widget.child.id)) ??
      ChildAvatarOption.explorer;
  bool _busy = false;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 7, now.month, now.day),
      firstDate: DateTime(now.year - 18, now.month, now.day + 1),
      lastDate: DateTime(now.year, now.month, now.day - 1),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    setState(() => _fieldErrors = const {});
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(familyRepositoryProvider)
          .updateChild(
            widget.familyId,
            widget.child.id,
            displayName: _name.text,
            dateOfBirth: _dob,
          );
      await ref
          .read(appPreferencesProvider)
          .setChildAvatarKey(widget.child.id, _avatar.name);
      ref
        ..invalidate(familyChildrenProvider(widget.familyId))
        ..invalidate(childAvatarProvider(widget.child.id));
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.profileSaved)));
    } on ValidationException catch (error) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = {for (final e in error.fieldErrors) e.field: e.message};
      });
      if (_fieldErrors.isEmpty) showErrorSnackBar(context, error);
    } on ApiException catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dobError = _fieldErrors['date_of_birth'] ?? _fieldErrors['body'];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: ResponsiveContent(
            maxWidth: ContentWidth.form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.md,
              children: [
                Text(l10n.editProfileTitle, style: context.text.headlineSmall),
                AppTextField(
                  fieldKey: const Key('edit.name'),
                  label: l10n.createChildName,
                  controller: _name,
                  validator: Validators(l10n).childName,
                  maxLength: 100,
                  textInputAction: TextInputAction.done,
                  errorText: _fieldErrors['display_name'],
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SecondaryButton(
                      icon: Icons.cake_outlined,
                      label: _dob == null
                          ? l10n.createChildDobPick
                          : DateFormat.yMMMd(locale).format(_dob!),
                      onPressed: _pickDob,
                    ),
                  ],
                ),
                if (dobError != null)
                  Text(
                    dobError,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.error,
                    ),
                  ),
                AvatarPicker(
                  selected: _avatar,
                  onSelected: (option) => setState(() => _avatar = option),
                ),
                PrimaryButton(
                  key: const Key('edit.save'),
                  label: l10n.saveChanges,
                  icon: Icons.check_rounded,
                  loading: _busy,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
