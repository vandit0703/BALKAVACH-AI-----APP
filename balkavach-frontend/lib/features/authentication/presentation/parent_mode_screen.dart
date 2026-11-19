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
import 'forgot_password_dialog.dart';
import 'session_controller.dart';

/// Parent sign-in used to leave child mode.
///
/// It asks for the same email and password as the normal parent sign-in; the
/// server additionally checks that the request comes from this child's session
/// and that the parent belongs to the child's family. Nothing here decides
/// access: on success the session controller swaps in the parent session and
/// the router follows; on any failure the child session stays as it was.
class ParentModeScreen extends ConsumerStatefulWidget {
  const ParentModeScreen({super.key});

  @override
  ConsumerState<ParentModeScreen> createState() => _ParentModeScreenState();
}

class _ParentModeScreenState extends ConsumerState<ParentModeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _backToChild() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.childHome);
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .enterParentMode(email: _email.text, password: _password.text);
      // The router leaves this screen when the parent session is adopted.
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error) {
          LockedException(:final retryAfter) => l10n.parentGateLocked(
            (retryAfter.inSeconds / 60).ceil().clamp(1, 1440),
          ),
          ForbiddenException(code: 'parent_authentication_failed') =>
            switch (error.attemptsRemaining) {
              final int left when left > 0 =>
                '${l10n.authInvalidCredentials} ${l10n.parentGateAttemptsLeft(left)}',
              _ => l10n.authInvalidCredentials,
            },
          _ => describeError(l10n, error),
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final validators = Validators(l10n);

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            key: const Key('parentGate.back'),
            onPressed: _busy ? null : _backToChild,
          ),
          title: Text(l10n.parentGateScreenTitle),
        ),
        body: ScrollablePage(
          maxWidth: ContentWidth.form,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 48,
              color: context.colors.primary,
              semanticLabel: l10n.parentGate,
            ),
            Text(l10n.parentGateScreenTitle, style: context.text.displaySmall),
            Text(
              l10n.parentGateScreenBody,
              style: context.text.bodyLarge?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
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
                        fieldKey: const Key('parentGate.email'),
                        label: l10n.authEmail,
                        controller: _email,
                        validator: validators.email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        enabled: !_busy,
                      ),
                      AppTextField(
                        fieldKey: const Key('parentGate.password'),
                        label: l10n.authPassword,
                        controller: _password,
                        validator: validators.loginPassword,
                        obscure: true,
                        showObscureToggle: true,
                        showPasswordLabel: l10n.authShowPassword,
                        hidePasswordLabel: l10n.authHidePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        maxLength: 128,
                        enabled: !_busy,
                        onFieldSubmitted: (_) => _busy ? null : _submit(),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          key: const Key('parentGate.forgotPassword'),
                          onPressed: _busy
                              ? null
                              : () => showForgotPasswordDialog(
                                  context,
                                  ref,
                                  initialEmail: _email.text,
                                ),
                          child: Text(l10n.authForgotPassword),
                        ),
                      ),
                      if (_error != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            key: const Key('parentGate.error'),
                            style: context.text.bodyMedium?.copyWith(
                              color: context.colors.error,
                            ),
                          ),
                        ),
                      PrimaryButton(
                        key: const Key('parentGate.submit'),
                        label: l10n.parentGateContinue,
                        trailingIcon: Icons.arrow_forward_rounded,
                        loading: _busy,
                        onPressed: _submit,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SecondaryButton(
              key: const Key('parentGate.stay'),
              label: l10n.parentGateBackToChild,
              icon: Icons.child_care_rounded,
              onPressed: _busy ? null : _backToChild,
            ),
          ],
        ),
      ),
    );
  }
}
