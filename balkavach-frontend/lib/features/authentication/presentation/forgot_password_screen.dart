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

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({required this.initialEmail, super.key});

  final String initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).requestPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = describeError(l10n, error));
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
        leading: BackButton(onPressed: () => context.go(AppRoutes.parentAuth)),
        title: Text(l10n.authForgotPassword),
      ),
      body: ScrollablePage(
        maxWidth: ContentWidth.form,
        children: [
          Text(l10n.authForgotPassword, style: context.text.displaySmall),
          if (_sent)
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.authResetSent,
                key: const Key('forgot.done'),
                style: context.text.bodyLarge,
              ),
            )
          else ...[
            Text(
              l10n.forgotPasswordBody,
              style: context.text.bodyLarge?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            AppCard(
              radius: AppRadius.hero,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.md,
                  children: [
                    AppTextField(
                      fieldKey: const Key('forgot.email'),
                      label: l10n.authEmail,
                      controller: _email,
                      validator: validators.email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      enabled: !_busy,
                    ),
                    if (_error != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          key: const Key('forgot.error'),
                          style: context.text.bodyMedium?.copyWith(
                            color: context.colors.error,
                          ),
                        ),
                      ),
                    PrimaryButton(
                      key: const Key('forgot.submit'),
                      label: l10n.forgotPasswordSend,
                      loading: _busy,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ],
          SecondaryButton(
            key: const Key('forgot.toSignIn'),
            label: l10n.resetPasswordToSignIn,
            icon: Icons.arrow_back_rounded,
            onPressed: () => context.go(AppRoutes.parentAuth),
          ),
        ],
      ),
    );
  }
}