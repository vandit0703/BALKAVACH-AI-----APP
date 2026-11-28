import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/brand_header.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../child_profile/domain/family_models.dart';
import '../../child_profile/presentation/family_providers.dart';
import '../data/panda_chat_access_repository.dart';

class PandaChatAccessScreen extends ConsumerWidget {
  const PandaChatAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider).value;
    final family = ref.watch(currentFamilyProvider);
    return Scaffold(
      appBar: AppBar(title: BrandTitle(title: l10n.pandaChatAccessTitle)),
      body: switch ((session?.isParent ?? false, family)) {
        (false, _) => Center(child: EmptyView(message: l10n.pandaChatParentOnly)),
        (_, AsyncData(value: final f?)) => _Children(familyId: f.id),
        (_, AsyncData()) => Center(child: EmptyView(message: l10n.childrenEmpty)),
        (_, AsyncError(:final error)) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(currentFamilyProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _Children extends ConsumerWidget {
  const _Children({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final children = ref.watch(familyChildrenProvider(familyId));
    final statuses = ref.watch(familyPandaChatAccessProvider(familyId));
    final Widget content;
    if (children.hasError) {
      content = ErrorView(
        error: children.error!,
        onRetry: () => ref.invalidate(familyChildrenProvider(familyId)),
      );
    } else if (statuses.hasError) {
      content = ErrorView(
        error: statuses.error!,
        onRetry: () => ref.invalidate(familyPandaChatAccessProvider(familyId)),
      );
    } else if (children.isLoading || statuses.isLoading) {
      content = const LoadingView();
    } else if ((children.value ?? const <ChildProfile>[]).isEmpty) {
      content = EmptyView(message: l10n.childrenEmpty);
    } else {
      final childRows = children.value!;
      final accessRows = statuses.value ?? const <PandaChatAccessStatus>[];
      content = Column(
        spacing: AppSpacing.sm,
        children: [
          for (final child in childRows)
            _ChildAccessTile(
              familyId: familyId,
              child: child,
              status: accessRows.firstWhere(
                (item) => item.childId == child.id,
                orElse: () => PandaChatAccessStatus(
                  childId: child.id,
                  status: 'not_requested',
                ),
              ),
            ),
        ],
      );
    }
    return ListView(
      key: const Key('pandaChatAccess.list'),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        AppCard(
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline_rounded, color: context.colors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(l10n.pandaChatAccessIntro)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        content,
      ],
    );
  }
}

class _ChildAccessTile extends ConsumerStatefulWidget {
  const _ChildAccessTile({
    required this.familyId,
    required this.child,
    required this.status,
  });

  final String familyId;
  final ChildProfile child;
  final PandaChatAccessStatus status;

  @override
  ConsumerState<_ChildAccessTile> createState() => _ChildAccessTileState();
}

class _ChildAccessTileState extends ConsumerState<_ChildAccessTile> {
  bool _saving = false;

  Future<void> _decide(String action) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(pandaChatAccessRepositoryProvider).decide(
        familyId: widget.familyId,
        childId: widget.child.id,
        action: action,
      );
      ref.invalidate(familyPandaChatAccessProvider(widget.familyId));
    } on ApiException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pandaChatAccessSaveFailed)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = widget.status.status;
    final label = switch (status) {
      'pending' => l10n.pandaChatAccessPending,
      'approved' => l10n.pandaChatAccessApproved,
      'rejected' => l10n.pandaChatAccessRejected,
      'revoked' => l10n.pandaChatAccessRevoked,
      _ => l10n.pandaChatAccessNotRequested,
    };
    return AppCard(
      key: Key('pandaChatAccess.child.${widget.child.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.child.displayName, style: context.text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(label, key: Key('pandaChatAccess.status.$status')),
          if (status == 'pending') ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              children: [
                TextButton(
                  key: Key('pandaChatAccess.reject.${widget.child.id}'),
                  onPressed: _saving ? null : () => _decide('reject'),
                  child: Text(l10n.pandaChatAccessReject),
                ),
                FilledButton.icon(
                  key: Key('pandaChatAccess.approve.${widget.child.id}'),
                  onPressed: _saving ? null : () => _decide('approve'),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(l10n.pandaChatAccessApprove),
                ),
              ],
            ),
          ] else if (status == 'approved') ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: Key('pandaChatAccess.revoke.${widget.child.id}'),
                onPressed: _saving ? null : () => _decide('revoke'),
                icon: const Icon(Icons.block_rounded),
                label: Text(l10n.pandaChatAccessRevoke),
              ),
          ),
          ],
        ],
      ),
    );
  }
}
