import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import 'shield_logo.dart';

/// "🛡 BAL KAVACH AI / `title`" header used across the child app.
class BrandTitle extends StatelessWidget {
  const BrandTitle({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.appTitle.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.labelSmall?.copyWith(
            color: context.colors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.titleLarge,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // The logo is decorative; give its space to the title when tight.
        if (constraints.maxWidth < 140) return text;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ShieldLogo(size: 36),
            const SizedBox(width: 8),
            Flexible(child: text),
          ],
        );
      },
    );
  }
}

/// Large wordmark used on the welcome screen: "Bal Kavach AI".
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        ShieldLogo(size: 56, semanticLabel: l10n.appTitle),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${l10n.brandName} '),
                    TextSpan(
                      text: l10n.brandSuffix,
                      style: TextStyle(color: context.colors.primaryContainer),
                    ),
                  ],
                ),
                style: context.text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                l10n.brandEyebrow,
                style: context.text.labelMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
