import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/presentation/session_controller.dart';
import '../domain/family_models.dart';

/// Confirms, then swaps the parent session for [child]'s session. The router
/// moves to the child area once the new session is adopted.
///
/// [onBusy] is called with `true` only while the session request is running
/// (not while the dialog is open), so callers can show a spinner.
///
/// Returns normally when cancelled or after showing an error.
Future<void> confirmAndStartChildMode(
  BuildContext context,
  WidgetRef ref,
  ChildProfile child, {
  ValueChanged<bool>? onBusy,
}) async {
  final l10n = AppLocalizations.of(context);
  final name = child.displayName;
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
  if (confirmed != true || !context.mounted) return;
  onBusy?.call(true);
  try {
    await ref.read(sessionControllerProvider.notifier).startChildMode(child.id);
  } on ApiException catch (error) {
    if (context.mounted) showErrorSnackBar(context, error);
  } finally {
    onBusy?.call(false);
  }
}
