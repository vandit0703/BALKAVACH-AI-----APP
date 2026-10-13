import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/validation/validators.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/server_status.dart';
import '../../../shared/widgets/state_views.dart';
import 'session_controller.dart';

enum _AuthMode { signIn, register }

/// Parent Login / Register. The Stitch design shows phone OTP and Google; the
/// backend supports only email + password (blocker B1), so that is what this
/// form does.
class ParentAuthScreen extends ConsumerStatefulWidget {
  const ParentAuthScreen({super.key});

  @override
  ConsumerState<ParentAuthScreen> createState() => _ParentAuthScreenState();
}

class _ParentAuthScreenState extends ConsumerState<ParentAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;
  bool _busy = false;
  String? _formError;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _formError = null;
      _fieldErrors = const {};
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final controller = ref.read(sessionControllerProvider.notifier);
    try {
      if (_mode == _AuthMode.signIn) {
        await controller.signIn(email: _email.text, password: _password.text);
      } else {
        await controller.register(
          fullName: _name.text,
          email: _email.text,
          password: _password.text,
        );
      }
      // The router redirects to the parent home on success.
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _formError = switch (error) {
          UnauthorizedException(code: 'invalid_credentials') =>
            l10n.authInvalidCredentials,
          ConflictException() => l10n.authEmailInUse,
          ValidationException() => null,
          _ => describeError(l10n, error),
        };
        if (error is ValidationException) {
          _fieldErrors = {
            for (final e in error.fieldErrors) e.field: e.message,
          };
          _formError = _fieldErrors.isEmpty ? l10n.errorGeneric : null;
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
    final registering = _mode == _AuthMode.register;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(AppRoutes.role)),
      ),
      body: ScrollablePage(
        maxWidth: ContentWidth.form,
        children: [
          _Hero(eyebrow: l10n.authHeroEyebrow, caption: l10n.authHeroCaption),
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.authTitle, style: context.text.displaySmall),
          Text(
            l10n.authSubtitle,
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
                    SegmentedButton<_AuthMode>(
                      segments: [
                        ButtonSegment(
                          value: _AuthMode.signIn,
                          label: Text(l10n.authTabSignIn),
                        ),
                        ButtonSegment(
                          value: _AuthMode.register,
                          label: Text(l10n.authTabRegister),
                        ),
                      ],
                      selected: {_mode},
                      showSelectedIcon: false,
                      onSelectionChanged: _busy
                          ? null
                          : (selection) => setState(() {
                              _mode = selection.first;
                              _formError = null;
                              _fieldErrors = const {};
                            }),
                    ),
                    if (registering)
                      AppTextField(
                        fieldKey: const Key('auth.name'),
                        label: l10n.authFullName,
                        controller: _name,
                        validator: validators.fullName,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        maxLength: 160,
                        errorText: _fieldErrors['full_name'],
                      ),
                    AppTextField(
                      fieldKey: const Key('auth.email'),
                      label: l10n.authEmail,
                      controller: _email,
                      validator: validators.email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      errorText: _fieldErrors['email'],
                    ),
                    AppTextField(
                      fieldKey: const Key('auth.password'),
                      label: l10n.authPassword,
                      controller: _password,
                      helper: registering ? l10n.authPasswordHint : null,
                      validator: registering
                          ? validators.newPassword
                          : validators.loginPassword,
                      obscure: true,
                      showObscureToggle: true,
                      showPasswordLabel: l10n.authShowPassword,
                      hidePasswordLabel: l10n.authHidePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: [
                        registering
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      maxLength: 128,
                      onFieldSubmitted: (_) => _submit(),
                      errorText: _fieldErrors['password'],
                    ),
                    if (_formError != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _formError!,
                          key: const Key('auth.error'),
                          style: context.text.bodyMedium?.copyWith(
                            color: context.colors.error,
                          ),
                        ),
                      ),
                    PrimaryButton(
                      key: const Key('auth.submit'),
                      label: registering
                          ? l10n.authRegisterButton
                          : l10n.authSignInButton,
                      trailingIcon: Icons.arrow_forward_rounded,
                      loading: _busy,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
          InlineNotice(message: l10n.authUnavailableMethods),
          const ServerStatusBadge(),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.eyebrow, required this.caption});

  final String eyebrow;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.hero,
      child: AspectRatio(
        aspectRatio: 21 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              AppImages.parentAuthHero,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00041B3C),
                    Color(0xD9041B3C),
                    Color(0xF2041B3C),
                  ],
                  stops: [0.1, 0.55, 1],
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.md,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: context.colors.secondaryContainer,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          eyebrow,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelLarge?.copyWith(
                            color: context.colors.secondaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
