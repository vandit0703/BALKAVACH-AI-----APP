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
import 'session_controller.dart';

class ChildLoginScreen extends ConsumerStatefulWidget {
  const ChildLoginScreen({super.key});

  @override
  ConsumerState<ChildLoginScreen> createState() => _ChildLoginScreenState();
}

class _ChildLoginScreenState extends ConsumerState<ChildLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _formError;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _formError = null;
      _fieldErrors = const {};
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .signIn(
            identifier: _username.text.trim().toLowerCase(),
            password: _password.text,
          );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error is ValidationException) {
          _fieldErrors = {
            for (final field in error.fieldErrors) field.field: field.message,
          };
          _formError = _fieldErrors.isEmpty
              ? describeError(AppLocalizations.of(context), error)
              : null;
        } else {
          _formError = switch (error) {
            UnauthorizedException(code: 'invalid_credentials') =>
              AppLocalizations.of(context).childLoginInvalidCredentials,
            _ => describeError(AppLocalizations.of(context), error),
          };
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
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(AppRoutes.role)),
      ),
      body: ScrollablePage(
        maxWidth: ContentWidth.form,
        spacing: AppSpacing.lg,
        children: [
          Text(l10n.childLoginTitle, style: context.text.headlineMedium),
          Text(
            l10n.childLoginSubtitle,
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
                      fieldKey: const Key('child.login.username'),
                      label: l10n.createChildUsername,
                      controller: _username,
                      validator: validators.childUsername,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      maxLength: 32,
                      errorText: _fieldErrors['username'],
                    ),
                    AppTextField(
                      fieldKey: const Key('child.login.password'),
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
                      onFieldSubmitted: (_) => _submit(),
                      errorText: _fieldErrors['password'],
                    ),
                    if (_formError != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _formError!,
                          key: const Key('child.login.error'),
                          style: context.text.bodyMedium?.copyWith(
                            color: context.colors.error,
                          ),
                        ),
                      ),
                    PrimaryButton(
                      key: const Key('child.login.submit'),
                      label: l10n.childLoginButton,
                      trailingIcon: Icons.arrow_forward_rounded,
                      loading: _busy,
                      onPressed: _submit,
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
