import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/platform/device_time_zone.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/brand_header.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/illustration.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../child_profile/domain/family_models.dart';
import '../../child_profile/presentation/family_providers.dart';
import '../../onboarding/presentation/onboarding_controller.dart';
import '../data/settings_repository.dart';
import 'settings_providers.dart';

const languageNames = {'en': 'English', 'gu': 'ગુજરાતી', 'hi': 'हिन्दी'};

/// Parent Settings & Security (Stitch `parent_settings_security`).
///
/// Shows only controls the backend supports: account and family details,
/// linked children, notification preferences (`/settings/me`), app language
/// and consent records. Parent PIN, screen-time / bedtime locks, data export
/// and family deletion have no API yet and are not shown.
class ParentSettingsScreen extends ConsumerWidget {
  const ParentSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final family = ref.watch(currentFamilyProvider).value;
    return Scaffold(
      appBar: AppBar(title: BrandTitle(title: l10n.settingsAppBar)),
      body: ScrollablePage(
        spacing: AppSpacing.lg,
        children: [
          _SectionTitle(
            title: l10n.settingsFamilyAccount,
            trailing: family == null
                ? null
                : Text(
                    family.familyName.toUpperCase(),
                    style: context.text.labelMedium?.copyWith(
                      color: context.colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          _AccountCard(family: family),
          _SectionTitle(
            title: l10n.settingsSafety,
            icon: Icons.lock_outline_rounded,
          ),
          AppCard(
            child: _InfoRow(
              icon: Icons.verified_user_rounded,
              tint: context.colors.secondaryContainer,
              iconColor: context.colors.onSecondaryContainer,
              title: l10n.settingsApprovalTitle,
              subtitle: l10n.settingsApprovalBody,
              trailing: Chip(label: Text(l10n.settingsAlwaysOn)),
            ),
          ),
          _SectionTitle(
            title: l10n.settingsPreferences,
            icon: Icons.tune_rounded,
          ),
          _PreferencesCard(familyId: family?.id),
          const _SafetyCard(),
          if (family != null) _PrivacyCard(familyId: family.id),
          SecondaryButton(
            key: const Key('settings.logout'),
            label: l10n.settingsLogOut,
            icon: Icons.logout_rounded,
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).signOut(),
          ),
          Text(
            l10n.settingsFooter,
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.icon, this.trailing});

  final String title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: context.text.headlineSmall),
            ),
          ),
          if (trailing != null) Flexible(child: trailing!),
          if (icon != null) Icon(icon, color: context.colors.primary),
        ],
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.family});

  final Family? family;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final user = ref.watch(sessionControllerProvider).value?.user;
    final family = this.family;
    final children = family == null
        ? null
        : ref.watch(familyChildrenProvider(family.id));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          if (user != null)
            Row(
              children: [
                ChildAvatar(name: user.fullName, size: 56),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName, style: context.text.titleLarge),
                      if (user.email != null)
                        Text(
                          user.email!,
                          style: context.text.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      if (family != null && family.createdBy == user.id)
                        Text(
                          l10n.settingsPrimaryAdmin,
                          style: context.text.labelSmall?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          if (family != null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.sm + 4,
                  children: [
                    SectionHeader(
                      title: l10n.settingsLinkedChildren,
                      trailing: TextButton.icon(
                        key: const Key('settings.addChild'),
                        onPressed: () => context.push(AppRoutes.parentNewChild),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        label: Text(l10n.childrenAdd),
                      ),
                    ),
                    switch (children) {
                      AsyncData(:final value) when value.isEmpty => Text(
                        l10n.childrenEmpty,
                        style: context.text.bodyMedium,
                      ),
                      AsyncData(:final value) => Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final child in value) _LinkedChild(child: child),
                        ],
                      ),
                      AsyncError(:final error) => Text(
                        describeError(l10n, error),
                        style: context.text.bodyMedium,
                      ),
                      _ => const LinearProgressIndicator(),
                    },
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LinkedChild extends ConsumerWidget {
  const _LinkedChild({required this.child});

  final ChildProfile child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final avatar = ref.watch(childAvatarProvider(child.id));
    final age = child.ageOn(ref.watch(clockProvider)());
    return Material(
      color: context.colors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () => context.push(AppRoutes.parentChild(child.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, AppSpacing.md, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChildAvatar(
                name: child.displayName,
                option: avatar,
                size: 40,
                ring: false,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(child.displayName, style: context.text.titleSmall),
                    if (age != null)
                      Text(
                        l10n.profileAge(age),
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.text.titleMedium),
        if (subtitle != null)
          Text(
            subtitle!,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
      ],
    );
    final leading = CircleAvatar(
      radius: 22,
      backgroundColor: tint,
      child: Icon(icon, color: iconColor),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrow screens and large text: the control drops under the text
        // instead of squeezing it.
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final stacked =
            trailing != null && constraints.maxWidth / textScale < 300;
        final header = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: AppSpacing.md),
            Expanded(child: text),
            if (trailing != null && !stacked) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ],
          ],
        );
        if (!stacked) return header;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.sm,
          children: [
            header,
            Align(alignment: AlignmentDirectional.centerEnd, child: trailing),
          ],
        );
      },
    );
  }
}

class _PreferencesCard extends ConsumerWidget {
  const _PreferencesCard({required this.familyId});

  final String? familyId;

  Future<void> _update(
    BuildContext context,
    WidgetRef ref, {
    bool? push,
    bool? email,
  }) async {
    try {
      await ref
          .read(userSettingsProvider.notifier)
          .save(pushEnabled: push, emailNotificationsEnabled: email);
    } on ApiException catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> _chooseLanguage(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final current = ref.read(onboardingControllerProvider).languageCode;
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: RadioGroup<String>(
          groupValue: current,
          onChanged: (value) => Navigator.pop(context, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  l10n.settingsLanguage,
                  style: context.text.titleLarge,
                ),
              ),
              for (final MapEntry(key: code, value: name)
                  in languageNames.entries)
                RadioListTile<String>(
                  key: Key('settings.language.$code'),
                  value: code,
                  title: Text(name),
                ),
            ],
          ),
        ),
      ),
    );
    if (code == null || code == current) return;
    await ref.read(onboardingControllerProvider.notifier).chooseLanguage(code);
    // The app language changes immediately on this device; saving it to the
    // account is best effort.
    try {
      await ref.read(userSettingsProvider.notifier).save(languageCode: code);
    } on ApiException catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final settings = ref.watch(userSettingsProvider);
    final saving = ref.watch(settingsSavingProvider);
    final language =
        languageNames[ref.watch(onboardingControllerProvider).languageCode] ??
        languageNames['en']!;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          _InfoRow(
            icon: Icons.translate_rounded,
            tint: colors.surfaceContainerHigh,
            iconColor: colors.primary,
            title: l10n.settingsLanguage,
            subtitle: language,
            trailing: SecondaryButton(
              key: const Key('settings.language'),
              dense: true,
              label: l10n.settingsChange,
              onPressed: saving ? null : () => _chooseLanguage(context, ref),
            ),
          ),
          if (familyId != null) ...[
            const Divider(height: 1),
            _TimezoneRow(familyId: familyId!, saving: saving),
          ],
          const Divider(height: 1),
          switch (settings) {
            AsyncData(:final value) => Column(
              children: [
                SwitchListTile(
                  key: const Key('settings.push'),
                  contentPadding: EdgeInsets.zero,
                  secondary: CircleAvatar(
                    radius: 22,
                    backgroundColor: colors.surfaceContainerHigh,
                    child: Icon(
                      Icons.notifications_active_rounded,
                      color: colors.primary,
                    ),
                  ),
                  title: Text(l10n.settingsPush),
                  subtitle: Text(l10n.settingsPushBody),
                  value: value.pushEnabled,
                  onChanged: saving
                      ? null
                      : (v) => _update(context, ref, push: v),
                ),
                const SizedBox(height: AppSpacing.sm),
                _InfoRow(
                  key: const Key('settings.email'),
                  icon: Icons.mail_outline_rounded,
                  tint: colors.surfaceContainerHigh,
                  iconColor: colors.onSurfaceVariant,
                  title: l10n.settingsEmail,
                  subtitle: l10n.settingsEmailBody,
                ),
              ],
            ),
            AsyncError(:final error) => ErrorView(
              error: error,
              onRetry: () => ref.invalidate(userSettingsProvider),
            ),
            _ => const LoadingView(),
          },
        ],
      ),
    );
  }
}

class _PrivacyCard extends ConsumerWidget {
  const _PrivacyCard({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final consents = ref.watch(familyConsentsProvider(familyId));
    final locale = Localizations.localeOf(context).toLanguageTag();

    return AppCard(
      color: colors.surfaceContainerLow,
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm + 4,
        children: [
          _InfoRow(
            icon: Icons.shield_outlined,
            tint: colors.secondaryContainer,
            iconColor: colors.onSecondaryContainer,
            title: l10n.settingsPrivacyTitle,
            subtitle: l10n.settingsPrivacyBody,
          ),
          switch (consents) {
            AsyncData(:final value) when value.isEmpty => Text(
              l10n.settingsNoConsents,
              style: context.text.bodySmall,
            ),
            AsyncData(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.xs,
              children: [
                for (final consent in value)
                  Text(
                    l10n.settingsConsentRow(
                      consent.documentVersion,
                      consent.acceptedAt == null
                          ? '—'
                          : DateFormat.yMMMd(
                              locale,
                            ).format(consent.acceptedAt!.toLocal()),
                      consent.isActive
                          ? l10n.settingsConsentActive
                          : l10n.settingsConsentRevoked,
                    ),
                    style: context.text.bodySmall,
                  ),
              ],
            ),
            AsyncError(:final error) => Text(
              describeError(l10n, error),
              style: context.text.bodySmall,
            ),
            _ => const LinearProgressIndicator(),
          },
        ],
      ),
    );
  }
}

/// Zones offered in the picker, plus the phone's own zone when it differs.
const _commonTimezones = [
  'Asia/Kolkata',
  'Asia/Dubai',
  'Asia/Karachi',
  'Asia/Dhaka',
  'Asia/Kathmandu',
  'Asia/Singapore',
  'Europe/London',
  'Europe/Paris',
  'Africa/Nairobi',
  'America/New_York',
  'America/Chicago',
  'America/Los_Angeles',
  'Australia/Sydney',
  'UTC',
];

class _TimezoneRow extends ConsumerWidget {
  const _TimezoneRow({required this.familyId, required this.saving});

  final String familyId;
  final bool saving;

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    FamilySettings current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final device = await ref.read(deviceTimeZoneProvider).current();
    if (!context.mounted) return;
    final zone = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                l10n.settingsTimezone,
                style: context.text.titleLarge,
              ),
            ),
            if (device != null && device != current.timezone)
              ListTile(
                key: const Key('settings.timezone.device'),
                leading: const Icon(Icons.smartphone_rounded),
                title: Text(l10n.settingsTimezoneUseDevice(device)),
                onTap: () => Navigator.pop(context, device),
              ),
            for (final name in _commonTimezones)
              ListTile(
                key: Key('settings.timezone.$name'),
                title: Text(name),
                trailing: name == current.timezone
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, name),
              ),
          ],
        ),
      ),
    );
    if (zone == null || zone == current.timezone || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .saveTimezone(familyId, current, zone);
      ref.invalidate(familySettingsProvider(familyId));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.settingsTimezoneSaved)));
    } on ApiException catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final settings = ref.watch(familySettingsProvider(familyId));
    final current = settings.value;
    return _InfoRow(
      icon: Icons.public_rounded,
      tint: colors.surfaceContainerHigh,
      iconColor: colors.primary,
      title: l10n.settingsTimezone,
      subtitle: switch (settings) {
        AsyncData(:final value) => value.timezone ?? 'UTC',
        AsyncError() => l10n.errorGeneric,
        _ => l10n.loading,
      },
      trailing: SecondaryButton(
        key: const Key('settings.timezone'),
        dense: true,
        label: l10n.settingsChange,
        onPressed: saving || current == null
            ? null
            : () => _choose(context, ref, current),
      ),
    );
  }
}

/// Plain-language statements about privacy and safety. Each one describes
/// something the system actually enforces.
class _SafetyCard extends StatelessWidget {
  const _SafetyCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final points = [
      l10n.safetyPointFamilyOnly,
      l10n.safetyPointPhotos,
      l10n.safetyPointChildMode,
      l10n.safetyPointApprovals,
      l10n.safetyPointNotifications,
      l10n.safetyPointNoAds,
    ];
    return AppCard(
      key: const Key('settings.safety'),
      color: colors.surfaceContainerLow,
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm + 4,
        children: [
          _InfoRow(
            icon: Icons.health_and_safety_outlined,
            tint: colors.secondaryContainer,
            iconColor: colors.onSecondaryContainer,
            title: l10n.settingsPrivacySafetyTitle,
          ),
          for (final point in points)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(point, style: context.text.bodyMedium)),
              ],
            ),
          const Divider(height: 1),
          Text(l10n.settingsSavedWhereTitle, style: context.text.titleSmall),
          Text(l10n.settingsSavedAccount, style: context.text.bodySmall),
          Text(l10n.settingsSavedDevice, style: context.text.bodySmall),
        ],
      ),
    );
  }
}
