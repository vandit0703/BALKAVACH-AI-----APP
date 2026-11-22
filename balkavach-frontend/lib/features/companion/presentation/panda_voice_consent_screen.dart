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
import '../data/panda_voice_consent_repository.dart';

/// Parent-only: which children may talk to Panda out loud.
///
/// The microphone stays off for a child until a parent agrees here, after
/// reading how speech recognition works. Withdrawing takes effect on the
/// child's next voice turn. Typing to Panda never needs this.
class PandaVoiceConsentScreen extends ConsumerWidget {
  const PandaVoiceConsentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider).value;
    final family = ref.watch(currentFamilyProvider);
    return Scaffold(
      appBar: AppBar(title: BrandTitle(title: l10n.pandaConsentTitle)),
      body: switch ((session?.isParent ?? false, family)) {
        // The router never sends a child here; this is a second lock.
        (false, _) => Center(
          child: EmptyView(message: l10n.pandaConsentParentOnly),
        ),
        (_, AsyncData(value: final f?)) => _Children(familyId: f.id),
        (_, AsyncData()) => Center(
          child: EmptyView(message: l10n.childrenEmpty),
        ),
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
    final colors = context.colors;
    final children = ref.watch(familyChildrenProvider(familyId));
    return ListView(
      key: const Key('pandaConsent.list'),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.sm,
            children: [
              Row(
                spacing: AppSpacing.sm,
                children: [
                  Icon(Icons.mic_rounded, color: colors.primary),
                  Expanded(
                    child: Text(
                      l10n.pandaConsentIntro,
                      style: context.text.titleMedium,
                    ),
                  ),
                ],
              ),
              Text(
                l10n.pandaConsentDisclosure,
                key: const Key('pandaConsent.disclosure'),
                style: context.text.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        switch (children) {
          AsyncData(:final value) when value.isEmpty => EmptyView(
            message: l10n.childrenEmpty,
          ),
          AsyncData(:final value) => Column(
            spacing: AppSpacing.sm,
            children: [
              for (final child in value)
                _ChildConsentTile(familyId: familyId, child: child),
            ],
          ),
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

class _ChildConsentTile extends ConsumerStatefulWidget {
  const _ChildConsentTile({required this.familyId, required this.child});

  final String familyId;
  final ChildProfile child;

  @override
  ConsumerState<_ChildConsentTile> createState() => _ChildConsentTileState();
}

class _ChildConsentTileState extends ConsumerState<_ChildConsentTile> {
  bool _saving = false;

  (String, String) get _key => (widget.familyId, widget.child.id);

  Future<void> _change(bool granted) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (granted && await _confirm() != true) return;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(pandaVoiceConsentRepositoryProvider)
          .set(widget.familyId, widget.child.id, granted: granted);
      ref.invalidate(pandaVoiceConsentProvider(_key));
      if (!granted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.pandaConsentWithdrawn(widget.child.displayName)),
          ),
        );
      }
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'consent_version_outdated'
                ? l10n.pandaConsentOutdated
                : l10n.pandaConsentSaveFailed,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool?> _confirm() {
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('pandaConsent.confirm'),
        icon: const Icon(Icons.mic_rounded),
        title: Text(l10n.pandaConsentDialogTitle(widget.child.displayName)),
        content: SingleChildScrollView(
          child: Text(l10n.pandaConsentDisclosure),
        ),
        actions: [
          TextButton(
            key: const Key('pandaConsent.cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.pandaConsentCancel),
          ),
          FilledButton(
            key: const Key('pandaConsent.agree'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.pandaConsentAgree),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final consent = ref.watch(pandaVoiceConsentProvider(_key));
    final name = widget.child.displayName;
    return AppCard(
      key: Key('pandaConsent.child.${widget.child.id}'),
      child: switch (consent) {
        AsyncData(:final value) => SwitchListTile(
          key: Key('pandaConsent.switch.${widget.child.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text(name),
          subtitle: Text(
            value.granted ? l10n.pandaConsentOn : l10n.pandaConsentOff,
          ),
          value: value.granted,
          onChanged: _saving ? null : _change,
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(pandaVoiceConsentProvider(_key)),
        ),
        _ => const LoadingView(),
      },
    );
  }
}
