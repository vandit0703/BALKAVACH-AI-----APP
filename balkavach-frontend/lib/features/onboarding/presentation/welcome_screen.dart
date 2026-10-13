import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/app_assets.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/brand_header.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/illustration.dart';
import 'onboarding_controller.dart';

/// Language rows exactly as written in the Stitch export. Native names and
/// subtitles stay in their own script regardless of the app language.
class _LanguageOption {
  const _LanguageOption(this.code, this.glyph, this.name, this.subtitle);

  final String code;
  final String glyph;
  final String name;
  final String subtitle;
}

const _languages = [
  _LanguageOption('en', 'A', 'English', 'Default • Primary Mode'),
  _LanguageOption('gu', 'ગુ', 'ગુજરાતી', 'Gujarati • સહજ બાળ શિક્ષણ'),
  _LanguageOption('hi', 'अ', 'हिन्दी', 'Hindi • सुरक्षित एवं ज्ञानवर्धक'),
];

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected =
        ref.watch(onboardingControllerProvider).languageCode ??
        Localizations.localeOf(context).languageCode;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: ResponsiveContent(
            maxWidth: ContentWidth.form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BrandWordmark(),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.welcomeTagline,
                  textAlign: TextAlign.center,
                  style: context.text.titleMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _MascotCard(bubble: l10n.welcomeBubble),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Icon(
                      Icons.translate_rounded,
                      color: context.colors.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        l10n.welcomeSelectLanguage,
                        style: context.text.titleMedium,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        l10n.welcomeChangeAnytime,
                        textAlign: TextAlign.end,
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm + 4),
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (code) {
                    if (code != null) {
                      ref
                          .read(onboardingControllerProvider.notifier)
                          .chooseLanguage(code);
                    }
                  },
                  child: Column(
                    spacing: AppSpacing.sm + 4,
                    children: [
                      for (final option in _languages)
                        _LanguageTile(
                          option: option,
                          selected: option.code == selected,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  key: const Key('welcome.getStarted'),
                  label: l10n.welcomeGetStarted,
                  trailingIcon: Icons.arrow_forward_rounded,
                  gradient: true,
                  childSized: true,
                  onPressed: () async {
                    await ref
                        .read(onboardingControllerProvider.notifier)
                        .chooseLanguage(selected);
                    if (context.mounted) context.go(AppRoutes.consent);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: context.colors.secondary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        l10n.welcomeFooter,
                        textAlign: TextAlign.center,
                        style: context.text.labelMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MascotCard extends StatelessWidget {
  const _MascotCard({required this.bubble});

  final String bubble;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      radius: AppRadius.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              EyebrowPill(
                label: l10n.welcomeMascotLabel,
                icon: Icons.auto_awesome_rounded,
                background: context.colors.secondaryContainer,
                foreground: context.colors.onSecondaryContainer,
              ),
              EyebrowPill(
                label: l10n.welcomeBuddyLabel,
                icon: Icons.star_rounded,
                background: context.colors.tertiaryFixed,
                foreground: context.colors.onTertiaryFixed,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Stack(
            children: [
              const Illustration(
                asset: AppImages.pandaWelcome,
                aspectRatio: 4 / 3,
                borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
              ),
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: AppShadows.tier2,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      child: Text(
                        '👋  $bubble',
                        textAlign: TextAlign.center,
                        style: context.text.titleSmall,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({required this.option, required this.selected});

  final _LanguageOption option;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.onPrimary : colors.onSurface;
    void select() =>
        RadioGroup.maybeOf<String>(context)?.onChanged(option.code);
    // One labelled, checkable node per language: a screen reader announces
    // "ગુજરાતી, Gujarati, selected" instead of an unnamed radio button.
    return Semantics(
      container: true,
      excludeSemantics: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: '${option.name}. ${option.subtitle}',
      onTap: select,
      child: _tile(context, colors, foreground, select),
    );
  }

  Widget _tile(
    BuildContext context,
    ColorScheme colors,
    Color foreground,
    VoidCallback select,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected
            ? colors.primaryContainer
            : colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.tier1,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: select,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 14,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: selected
                      ? Colors.white.withValues(alpha: 0.2)
                      : colors.surfaceContainerHigh,
                  child: Text(
                    option.glyph,
                    style: context.text.titleLarge?.copyWith(
                      color: selected ? colors.onPrimary : colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.name,
                        style: context.text.headlineSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        option.subtitle,
                        style: context.text.bodyMedium?.copyWith(
                          color: selected
                              ? colors.onPrimary.withValues(alpha: 0.9)
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Radio<String>(
                  value: option.code,
                  fillColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? colors.onPrimary
                        : colors.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
