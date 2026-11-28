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
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/auth_repository.dart';
import 'session_controller.dart';

class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({required this.email, super.key});

  final String email;

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otp = TextEditingController();
  Timer? _timer;
  int _secondsRemaining = 60;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otp.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsRemaining = 60);
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

  Future<void> _verify() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // The session (if any) is stored by the controller before we navigate.
      final signedIn = await ref
          .read(sessionControllerProvider.notifier)
          .verifyRegistrationEmail(email: widget.email, otp: _otp.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            signedIn
                ? l10n.emailVerificationSignedIn
                : l10n.emailVerificationSuccess,
          ),
        ),
      );
      // Parent home: the router still applies consent requirements.
      context.go(signedIn ? AppRoutes.parentHome : AppRoutes.parentAuth);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          'expired_verification_code' => l10n.emailVerificationExpired,
          'verification_attempts_exceeded' =>
            l10n.emailVerificationAttemptsExceeded,
          'invalid_verification_code' => l10n.emailVerificationInvalid,
          'email_unavailable' => l10n.emailUnavailable,
          _ => describeError(l10n, error),
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await ref.read(authRepositoryProvider).resendVerification(widget.email);
      if (mounted) _startCountdown();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.code == 'email_unavailable'
            ? l10n.emailUnavailable
            : describeError(l10n, error),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final missingEmail = widget.email.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(AppRoutes.parentAuth)),
        title: Text(l10n.emailVerificationTitle),
      ),
      body: ScrollablePage(
        maxWidth: ContentWidth.form,
        children: [
          Icon(
            Icons.mark_email_read_outlined,
            size: 44,
            color: context.colors.primary,
          ),
          Text(l10n.emailVerificationTitle, style: context.text.displaySmall),
          Text(
            l10n.emailVerificationBody(widget.email),
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
                  TextFormField(
                    key: const Key('verify.otp'),
                    controller: _otp,
                    enabled: !_busy && !missingEmail,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    validator: (value) => value != null && value.length == 6
                        ? null
                        : l10n.emailVerificationInvalid,
                    onFieldSubmitted: (_) => _busy ? null : _verify(),
                    decoration: InputDecoration(
                      labelText: l10n.emailVerificationCode,
                      counterText: '',
                    ),
                    style: context.text.headlineMedium,
                  ),
                  if (_error != null || missingEmail)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error ?? l10n.emailVerificationInvalid,
                        key: const Key('verify.error'),
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.error,
                        ),
                      ),
                    ),
                  PrimaryButton(
                    key: const Key('verify.submit'),
                    label: l10n.emailVerificationVerify,
                    loading: _busy,
                    onPressed: missingEmail ? null : _verify,
                  ),
                  if (_secondsRemaining > 0)
                    Text(
                      l10n.emailVerificationCountdown(_secondsRemaining),
                      key: const Key('verify.timer'),
                      textAlign: TextAlign.center,
                    )
                  else
                    TextButton.icon(
                      key: const Key('verify.resend'),
                      onPressed: _busy || missingEmail ? null : _resend,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(l10n.emailVerificationResend),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
