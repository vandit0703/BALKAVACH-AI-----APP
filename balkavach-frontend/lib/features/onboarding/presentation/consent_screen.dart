import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/shield_logo.dart';
import 'onboarding_controller.dart';

/// Parent Safety First. The acknowledgement is stored on the device here and
/// recorded on the server once the parent has a family (`consentSyncProvider`).
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _confirmed = false;
  bool _showRequired = false;

  Future<void> _continue() async {
    if (!_confirmed) {
      setState(() => _showRequired = true);
      return;
    }
    await ref.read(onboardingControllerProvider.notifier).acknowledgeConsent();
    if (mounted) context.go(AppRoutes.role);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final points = [
      (
        Icons.fingerprint_rounded,
        colors.surfaceContainerHigh,
        colors.primary,
        l10n.consentApprovalTitle,
        l10n.consentApprovalBody,
      ),
      (
        Icons.block_rounded,
        colors.secondaryContainer,
        colors.onSecondaryContainer,
        l10n.consentAdsTitle,
        l10n.consentAdsBody,
      ),
      (
        Icons.shield_rounded,
        colors.surfaceContainerHigh,
        colors.primary,
        l10n.consentPrivateTitle,
        l10n.consentPrivateBody,
      ),
      (
        Icons.task_alt_rounded,
        colors.tertiaryFixed,
        colors.tertiary,
        l10n.consentGoalsTitle,
        l10n.consentGoalsBody,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(AppRoutes.welcome)),
      ),
      body: ScrollablePage(
        maxWidth: ContentWidth.form,
        children: [
          Center(child: ShieldLogo(size: 104, semanticLabel: l10n.appTitle)),
          Center(
            child: EyebrowPill(
              label: l10n.consentEyebrow,
              icon: Icons.verified_user_outlined,
            ),
          ),
          Text(
            l10n.consentTitle,
            textAlign: TextAlign.center,
            style: context.text.displaySmall,
          ),
          Text(
            l10n.consentSubtitle,
            textAlign: TextAlign.center,
            style: context.text.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          for (final (icon, tint, iconColor, title, body) in points)
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: tint,
                    child: Icon(icon, color: iconColor, size: 28),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: context.text.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          body,
                          style: context.text.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.check_circle_outline_rounded,
                    color: colors.secondary,
                  ),
                ],
              ),
            ),
          AppCard(
            color: colors.surfaceContainerLow,
            elevated: false,
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: CheckboxListTile(
              key: const Key('consent.checkbox'),
              value: _confirmed,
              onChanged: (value) => setState(() {
                _confirmed = value ?? false;
                if (_confirmed) _showRequired = false;
              }),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
              ),
              title: Text(l10n.consentCheckbox, style: context.text.bodyMedium),
              subtitle: _showRequired
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.consentCheckboxRequired,
                        style: context.text.bodySmall?.copyWith(
                          color: colors.error,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
          PrimaryButton(
            key: const Key('consent.continue'),
            label: l10n.consentContinue,
            trailingIcon: Icons.arrow_forward_rounded,
            backgroundColor: colors.primaryContainer,
            onPressed: _continue,
          ),
        ],
      ),
    );
  }
}
