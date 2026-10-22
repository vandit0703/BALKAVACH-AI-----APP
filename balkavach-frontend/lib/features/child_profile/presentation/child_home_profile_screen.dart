import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../missions/presentation/child_home_screen.dart';
import '../../onboarding/presentation/onboarding_controller.dart';

/// Child Profile: the dashboard that used to be Home.
///
/// Home is now the curated video experience, so the greeting, stats, mascot and
/// mission summary moved here unchanged — they are the same widgets, reused
/// rather than reimplemented, so nothing was lost in the move. Language choice
/// is added because this is now the child's own settings surface.
class ChildHomeProfileScreen extends ConsumerWidget {
  const ChildHomeProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ChildDashboard(
      key: Key('profile.dashboard'),
      trailing: [_LanguageCard()],
    );
  }
}

/// Language choice for the child, using the same stored preference the
/// onboarding screen writes, so switching here persists across restarts.
class _LanguageCard extends ConsumerWidget {
  const _LanguageCard();

  static const _languages = [
    ('en', 'English'),
    ('hi', 'हिन्दी'),
    ('gu', 'ગુજરાતી'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(
      onboardingControllerProvider.select((s) => s.languageCode ?? 'en'),
    );

    return AppCard(
      key: const Key('profile.language'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          SectionHeader(title: l10n.settingsLanguage),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (code, label) in _languages)
                ChoiceChip(
                  key: Key('profile.language.$code'),
                  label: Text(label),
                  selected: current == code,
                  onSelected: (selected) {
                    if (!selected) return;
                    ref
                        .read(onboardingControllerProvider.notifier)
                        .chooseLanguage(code);
                  },
                ),
            ],
          ),
          Text(
            l10n.profileLanguageHelp,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
