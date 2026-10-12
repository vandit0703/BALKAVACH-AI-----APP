import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/shield_logo.dart';

/// Shown while the stored session is restored; the router leaves it
/// automatically.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShieldLogo(size: 112, semanticLabel: l10n.appTitle),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.appTitle, style: context.text.headlineMedium),
            const SizedBox(height: AppSpacing.lg),
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}
