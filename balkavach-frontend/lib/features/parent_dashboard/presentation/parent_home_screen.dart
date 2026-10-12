import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/validation/validators.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/brand_header.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gamification.dart';
import '../../../shared/widgets/illustration.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../child_profile/domain/family_models.dart';
import '../../child_profile/presentation/family_providers.dart';
import '../../missions/domain/mission_models.dart';
import '../../missions/presentation/mission_providers.dart';

class ParentHomeScreen extends ConsumerWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider).value;
    final family = ref.watch(currentFamilyProvider);

    return Scaffold(
      appBar: AppBar(
        title: BrandTitle(title: l10n.parentHubTitle),
        actions: [
          IconButton(
            tooltip: l10n.parentSignOut,
            icon: const Icon(Icons.logout_rounded),
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).signOut(),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(currentFamilyProvider);
          await _settle(ref.read(currentFamilyProvider.future));
        },
        child: switch (family) {
          AsyncData(value: null) => _scroll([
            if (session != null)
              Text(
                l10n.parentGreeting(session.user.fullName),
                style: context.text.headlineMedium,
              ),
            const _CreateFamilyCard(),
          ]),
          AsyncData(value: final Family f) => _scroll([
            if (session != null)
              Text(
                l10n.parentGreeting(session.user.fullName),
                style: context.text.headlineMedium,
              ),
            _ConsentSyncNotice(familyId: f.id),
            _ChildrenSection(familyId: f.id),
            _MissionsSection(familyId: f.id),
          ]),
          AsyncError(:final error) => _scroll([
            ErrorView(
              error: error,
              onRetry: () => ref.invalidate(currentFamilyProvider),
            ),
          ]),
          _ => const LoadingView(),
        },
      ),
    );
  }

  Widget _scroll(List<Widget> children) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.lg,
          children: children,
        ),
      ),
    ],
  );
}

class _CreateFamilyCard extends ConsumerStatefulWidget {
  const _CreateFamilyCard();

  @override
  ConsumerState<_CreateFamilyCard> createState() => _CreateFamilyCardState();
}

class _CreateFamilyCardState extends ConsumerState<_CreateFamilyCard> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref.read(currentFamilyProvider.notifier).create(_name.text);
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.md,
          children: [
            Text(l10n.familyCreateTitle, style: context.text.headlineSmall),
            Text(
              l10n.familyCreateBody,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            AppTextField(
              fieldKey: const Key('family.name'),
              label: l10n.familyNameLabel,
              controller: _name,
              validator: Validators(l10n).familyName,
              maxLength: 160,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _create(),
            ),
            PrimaryButton(
              key: const Key('family.create'),
              label: l10n.familyCreateButton,
              loading: _busy,
              onPressed: _create,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentSyncNotice extends ConsumerWidget {
  const _ConsentSyncNotice({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(consentSyncProvider(familyId));
    if (!sync.hasError) return const SizedBox.shrink();
    return InlineNotice(
      icon: Icons.sync_problem_rounded,
      message: AppLocalizations.of(context).consentSyncFailed,
    );
  }
}

class _ChildrenSection extends ConsumerWidget {
  const _ChildrenSection({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final children = ref.watch(familyChildrenProvider(familyId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm + 4,
      children: [
        SectionHeader(
          title: l10n.childrenTitle,
          icon: Icons.family_restroom_rounded,
          trailing: SecondaryButton(
            key: const Key('children.add'),
            dense: true,
            label: l10n.childrenAdd,
            icon: Icons.person_add_alt_1_rounded,
            onPressed: () => context.push(AppRoutes.parentNewChild),
          ),
        ),
        switch (children) {
          AsyncData(:final value) when value.isEmpty => EmptyView(
            message: l10n.childrenEmpty,
          ),
          AsyncData(:final value) => _ChildGrid(children: value),
          AsyncError(:final error) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(familyChildrenProvider(familyId)),
          ),
          _ => const LoadingView(),
        },
      ],
    );
  }
}

class _ChildGrid extends StatelessWidget {
  const _ChildGrid({required this.children});

  final List<ChildProfile> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 2 : 1;
        final width =
            (constraints.maxWidth - AppSpacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final child in children)
              SizedBox(
                width: width,
                child: _ChildCard(child: child),
              ),
          ],
        );
      },
    );
  }
}

class _ChildCard extends ConsumerStatefulWidget {
  const _ChildCard({required this.child});

  final ChildProfile child;

  @override
  ConsumerState<_ChildCard> createState() => _ChildCardState();
}

class _ChildCardState extends ConsumerState<_ChildCard> {
  bool _busy = false;

  Future<void> _startChildMode() async {
    final l10n = AppLocalizations.of(context);
    final name = widget.child.displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.childModeConfirmTitle(name)),
        content: Text(l10n.childModeConfirmBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.childModeConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .startChildMode(widget.child.id);
    } on ApiException catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final avatar = ref.watch(childAvatarProvider(widget.child.id));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          Row(
            children: [
              ChildAvatar(
                name: widget.child.displayName,
                option: avatar,
                size: 56,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  widget.child.displayName,
                  style: context.text.titleLarge,
                ),
              ),
            ],
          ),
          PrimaryButton(
            key: Key('child.start.${widget.child.id}'),
            label: l10n.childStartMode,
            icon: Icons.rocket_launch_rounded,
            loading: _busy,
            onPressed: _startChildMode,
          ),
        ],
      ),
    );
  }
}

class _MissionsSection extends ConsumerWidget {
  const _MissionsSection({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final missions = ref.watch(familyMissionsProvider(familyId));
    final children =
        ref.watch(familyChildrenProvider(familyId)).value ?? const [];
    final names = {for (final c in children) c.id: c.displayName};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm + 4,
      children: [
        SectionHeader(
          title: l10n.parentMissionsTitle,
          icon: Icons.rocket_launch_outlined,
          trailing: SecondaryButton(
            key: const Key('missions.new'),
            dense: true,
            label: l10n.parentMissionsNew,
            icon: Icons.add_rounded,
            onPressed: () => context.push(AppRoutes.parentNewMission),
          ),
        ),
        switch (missions) {
          AsyncData(:final value) when value.isEmpty => EmptyView(
            message: l10n.parentMissionsEmpty,
          ),
          AsyncData(:final value) => Column(
            spacing: AppSpacing.sm + 4,
            children: [
              for (final mission in value)
                _ParentMissionTile(
                  mission: mission,
                  assignee: mission.assignedChildId == null
                      ? l10n.missionForEveryone
                      : l10n.missionAssignedTo(
                          names[mission.assignedChildId] ?? '…',
                        ),
                ),
            ],
          ),
          AsyncError(:final error) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(familyMissionsProvider(familyId)),
          ),
          _ => const LoadingView(),
        },
      ],
    );
  }
}

class _ParentMissionTile extends StatelessWidget {
  const _ParentMissionTile({required this.mission, required this.assignee});

  final Mission mission;
  final String assignee;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mission.title, style: context.text.titleMedium),
                const SizedBox(height: 2),
                Text(
                  assignee,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          StarPill(count: mission.starReward),
        ],
      ),
    );
  }
}

/// Waits for a refresh to finish. Failures are already shown by the
/// provider's error state, so they must not escape the RefreshIndicator.
Future<void> _settle(Future<Object?> refresh) async {
  try {
    await refresh;
  } on Object {
    // Rendered by the watching widget.
  }
}
