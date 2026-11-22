import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/auth_repository.dart';

/// Asks for the parent's email and requests a password-reset link. The server
/// answers identically whether or not the account exists, so the confirmation
/// never reveals it. Shared by the parent sign-in screen and the parent gate.
Future<void> showForgotPasswordDialog(
  BuildContext context,
  WidgetRef ref, {
  String initialEmail = '',
}) async {
  final l10n = AppLocalizations.of(context);
  final email = TextEditingController(text: initialEmail);
  try {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.authForgotPassword),
        content: TextField(
          key: const Key('forgot.email'),
          controller: email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(labelText: l10n.authEmail),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.parentGateStay),
          ),
          FilledButton(
            key: const Key('forgot.submit'),
            onPressed: () => Navigator.pop(context, email.text),
            child: Text(l10n.authForgotPassword),
          ),
        ],
      ),
    );
    if (value == null || value.trim().isEmpty || !context.mounted) return;
    await ref.read(authRepositoryProvider).requestPasswordReset(value);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.authResetSent)));
    }
  } on ApiException catch (error) {
    if (context.mounted) showErrorSnackBar(context, error);
  } finally {
    email.dispose();
  }
}
