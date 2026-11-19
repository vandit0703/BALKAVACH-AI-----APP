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
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/auth_repository.dart';

/// Consumes the single-use token from the password-reset email
/// (`balkavach://app/reset-password?token=…`). The token is held only in this
/// widget, is never shown, and is forgotten after use.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({required this.token, super.key});

  final String? token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late String? _token = widget.token;
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final token = _token;
    if (token == null || token.isEmpty) {
      setState(() => _error = l10n.resetPasswordInvalid);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .resetPassword(token: token, password: _password.text);
      if (!mounted) return;
      setState(() {
        _done = true;
        _token = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.code == 'invalid_reset_token') {
          _token = null; // single use: a new link is required
          _error = l10n.resetPasswordInvalid;
        } else if (error is ValidationException) {
          _error = l10n.validationPasswordTooShort;
        } else {
          _error = describeError(l10n, error);
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final validators = Validators(l10n);
    final missing = !_done && (_token == null || _token!.isEmpty);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.resetPasswordTitle)),
      body: ScrollablePage(
        maxWidth: ContentWidth.form,
        children: [
          Text(l10n.resetPasswordTitle, style: context.text.displaySmall),
          Text(
            l10n.resetPasswordBody,
            style: context.text.bodyLarge?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (_done) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.resetPasswordDone,
                key: const Key('reset.done'),
                style: context.text.titleMedium,
              ),
            ),
            PrimaryButton(
              key: const Key('reset.toSignIn'),
              label: l10n.resetPasswordToSignIn,
              onPressed: () => context.go(AppRoutes.parentAuth),
            ),
          ] else
            AppCard(
              radius: AppRadius.hero,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.md,
                    children: [
                      AppTextField(
                        fieldKey: const Key('reset.password'),
                        label: l10n.resetPasswordNew,
                        controller: _password,
                        validator: validators.newPassword,
                        helper: l10n.authPasswordHint,
                        obscure: true,
                        showObscureToggle: true,
                        showPasswordLabel: l10n.authShowPassword,
                        hidePasswordLabel: l10n.authHidePassword,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
                        maxLength: 128,
                        enabled: !_busy && !missing,
                      ),
                      AppTextField(
                        fieldKey: const Key('reset.confirm'),
                        label: l10n.resetPasswordConfirm,
                        controller: _confirm,
                        validator: (value) => value == _password.text
                            ? null
                            : l10n.resetPasswordMismatch,
                        obscure: true,
                        showObscureToggle: true,
                        showPasswordLabel: l10n.authShowPassword,
                        hidePasswordLabel: l10n.authHidePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.newPassword],
                        maxLength: 128,
                        enabled: !_busy && !missing,
                        onFieldSubmitted: (_) =>
                            (_busy || missing) ? null : _submit(),
                      ),
                      if (missing || _error != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error ?? l10n.resetPasswordInvalid,
                            key: const Key('reset.error'),
                            style: context.text.bodyMedium?.copyWith(
                              color: context.colors.error,
                            ),
                          ),
                        ),
                      PrimaryButton(
                        key: const Key('reset.submit'),
                        label: l10n.resetPasswordSubmit,
                        loading: _busy,
                        onPressed: missing ? null : _submit,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
