import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'session_controller.dart';

/// Passwordless parent sign-in: email → emailed 6-digit code → session.
///
/// The code lives only in this screen's text controller (never stored). The
/// app moves on only after the server returned a session and the session
/// controller stored it.
class LoginCodeScreen extends ConsumerStatefulWidget {
  const LoginCodeScreen({required this.initialEmail, super.key});

  final String initialEmail;

  @override
  ConsumerState<LoginCodeScreen> createState() => _LoginCodeScreenState();
}

class _LoginCodeScreenState extends ConsumerState<LoginCodeScreen> {
  static const _resendSeconds = 60;

  final _emailFormKey = GlobalKey<FormState>();
  final _codeFormKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  Timer? _timer;
  int _secondsRemaining = 0;
  bool _busy = false;

  /// The address the current code was requested for; `null` on the email step.
  String? _sentTo;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsRemaining = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  String _message(AppLocalizations l10n, ApiException error) =>
      switch (error.code) {
        'invalid_login_code' => l10n.loginCodeInvalid,
        'email_unavailable' ||
        'login_code_unavailable' => l10n.emailUnavailable,
        _ => describeError(l10n, error),
      };

  Future<void> _send({required bool resend}) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _error = null);
    if (!resend && !(_emailFormKey.currentState?.validate() ?? false)) return;
    if (_busy) return;
    final email = resend ? _sentTo! : _email.text.trim();
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).requestLoginCode(email);
      if (!mounted) return;
      _code.clear();
      setState(() => _sentTo = email);
      _startCountdown();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = _message(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _error = null);
    if (!(_codeFormKey.currentState?.validate() ?? false)) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .signInWithCode(email: _sentTo!, otp: _code.text);
      // Session stored: parent home (the router applies consent rules).
      if (mounted) context.go(AppRoutes.parentHome);
    } on ApiException catch (error) {
      if (!mounted) return;
      _code.clear();
      setState(() => _error = _message(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeEmail() {
    _timer?.cancel();
    _code.clear();
    setState(() {
      _sentTo = null;
      _secondsRemaining = 0;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sentTo = _sentTo;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(AppRoutes.parentAuth)),
        title: Text(l10n.loginCodeTitle),
      ),
      body: ScrollablePage(
        maxWidth: ContentWidth.form,
        children: [
          Icon(
            Icons.mark_email_unread_outlined,
            size: 44,
            color: context.colors.primary,
          ),
          Text(l10n.loginCodeTitle, style: context.text.displaySmall),
          Text(
            sentTo == null
                ? l10n.loginCodeBody
                : l10n.loginCodeSentBody(sentTo),
            key: const Key('loginCode.body'),
            style: context.text.bodyLarge?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          AppCard(
            radius: AppRadius.hero,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: sentTo == null ? _emailStep(l10n) : _codeStep(l10n),
          ),
          SecondaryButton(
            key: const Key('loginCode.usePassword'),
            label: l10n.loginCodeUsePassword,
            icon: Icons.password_rounded,
            onPressed: _busy ? null : () => context.go(AppRoutes.parentAuth),
          ),
        ],
      ),
    );
  }

  Widget _errorText() => Semantics(
    liveRegion: true,
    child: Text(
      _error!,
      key: const Key('loginCode.error'),
      style: context.text.bodyMedium?.copyWith(color: context.colors.error),
    ),
  );

  Widget _emailStep(AppLocalizations l10n) {
    final validators = Validators(l10n);
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          AppTextField(
            fieldKey: const Key('loginCode.email'),
            label: l10n.authEmail,
            controller: _email,
            validator: validators.email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            enabled: !_busy,
            onFieldSubmitted: (_) => _send(resend: false),
          ),
          if (_error != null) _errorText(),
          PrimaryButton(
            key: const Key('loginCode.send'),
            label: l10n.loginCodeSend,
            trailingIcon: Icons.arrow_forward_rounded,
            loading: _busy,
            onPressed: () => _send(resend: false),
          ),
        ],
      ),
    );
  }

  Widget _codeStep(AppLocalizations l10n) {
    return Form(
      key: _codeFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          TextFormField(
            key: const Key('loginCode.otp'),
            controller: _code,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            enableSuggestions: false,
            autocorrect: false,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            validator: (value) => value != null && value.length == 6
                ? null
                : l10n.emailVerificationInvalid,
            onFieldSubmitted: (_) => _verify(),
            decoration: InputDecoration(
              labelText: l10n.loginCodeLabel,
              counterText: '',
            ),
            style: context.text.headlineMedium,
          ),
          if (_error != null) _errorText(),
          PrimaryButton(
            key: const Key('loginCode.verify'),
            label: l10n.loginCodeVerify,
            trailingIcon: Icons.arrow_forward_rounded,
            loading: _busy,
            onPressed: _verify,
          ),
          if (_secondsRemaining > 0)
            Text(
              l10n.emailVerificationCountdown(_secondsRemaining),
              key: const Key('loginCode.timer'),
              textAlign: TextAlign.center,
            )
          else
            TextButton.icon(
              key: const Key('loginCode.resend'),
              onPressed: _busy ? null : () => _send(resend: true),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.emailVerificationResend),
            ),
          TextButton(
            key: const Key('loginCode.changeEmail'),
            onPressed: _busy ? null : _changeEmail,
            child: Text(l10n.loginCodeChangeEmail),
          ),
        ],
      ),
    );
  }
}
