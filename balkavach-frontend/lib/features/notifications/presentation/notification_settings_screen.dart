import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/brand_header.dart';
import '../../../shared/widgets/state_views.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../child_profile/presentation/family_providers.dart';
import '../domain/notification_preferences.dart';
import 'notification_preferences_controller.dart';
import 'push_registration.dart';

/// Parent-only: which alerts reach the family's phones, and quiet hours.
///
/// Preferences decide *push* alerts. Every notification still appears in the
/// in-app notification centre, so nothing is lost by switching one off.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider).value;
    final family = ref.watch(currentFamilyProvider);
    return Scaffold(
      appBar: AppBar(title: BrandTitle(title: l10n.notifPrefsTitle)),
      body: switch ((session?.isParent ?? false, family)) {
        // The router never sends a child here; this is a second lock.
        (false, _) => Center(
          child: EmptyView(message: l10n.notifPrefsParentOnly),
        ),
        (_, AsyncData(value: final f?)) => _Preferences(familyId: f.id),
        (_, AsyncData()) => Center(
          child: EmptyView(message: l10n.childrenEmpty),
        ),
        (_, AsyncError(:final error)) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(currentFamilyProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _Preferences extends ConsumerWidget {
  const _Preferences({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = notificationPreferencesProvider(familyId);
    final async = ref.watch(provider);
    final push = ref.watch(pushRegistrationProvider);

    Future<void> guard(Future<void> Function() change) async {
      try {
        await change();
      } on ApiException catch (error) {
        if (context.mounted) showErrorSnackBar(context, error);
      }
    }

    return switch (async) {
      AsyncData(:final value) => ScrollablePage(
        spacing: AppSpacing.lg,
        children: [
          Text(l10n.notifPrefsIntro, style: context.text.bodyLarge),
          if (_pushNotice(l10n, push) case final notice?)
            InlineNotice(
              key: const Key('notifPrefs.pushNotice'),
              icon: Icons.notifications_off_outlined,
              message: notice,
            ),
          for (final (title, icon, categories) in [
            (
              l10n.notifPrefsGroupMissions,
              Icons.flag_rounded,
              const [
                PreferenceCategory.newMissions,
                PreferenceCategory.missionReviews,
              ],
            ),
            (
              l10n.notifPrefsGroupStreaks,
              Icons.local_fire_department_rounded,
              const [PreferenceCategory.streaks],
            ),
            (
              l10n.notifPrefsGroupVideos,
              Icons.play_circle_rounded,
              const [
                PreferenceCategory.videoAllowance,
                PreferenceCategory.videoTimeUp,
              ],
            ),
            (
              l10n.notifPrefsGroupRewards,
              Icons.card_giftcard_rounded,
              const [PreferenceCategory.rewards],
            ),
            (
              l10n.notifPrefsGroupSafety,
              Icons.shield_rounded,
              const [PreferenceCategory.safety],
            ),
          ])
            _Group(
              title: title,
              icon: icon,
              children: [
                for (final c in categories)
                  _CategoryTile(
                    category: c,
                    preferences: value,
                    onChanged: (on) => guard(
                      () => ref.read(provider.notifier).setCategory(c, on),
                    ),
                  ),
              ],
            ),
          _Group(
            title: l10n.notifPrefsQuietTitle,
            icon: Icons.bedtime_rounded,
            children: [
              _QuietHoursEditor(
                preferences: value,
                onChanged: (q) =>
                    guard(() => ref.read(provider.notifier).setQuietHours(q)),
              ),
            ],
          ),
        ],
      ),
      AsyncError(:final error) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(provider),
      ),
      _ => const LoadingView(),
    };
  }

  String? _pushNotice(AppLocalizations l10n, PushStatus status) =>
      switch (status) {
        PushStatus.off => l10n.notifPrefsPushOff,
        PushStatus.permissionDenied => l10n.notifPrefsPushDenied,
        PushStatus.notConfigured => l10n.notifPrefsPushUnavailable,
        _ => null,
      };
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        Row(
          children: [
            Icon(icon, color: context.colors.primary, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: context.text.titleLarge),
              ),
            ),
          ],
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.sm,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.preferences,
    required this.onChanged,
  });

  final PreferenceCategory category;
  final NotificationPreferences preferences;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locked = preferences.isLocked(category);
    final (title, body) = switch (category) {
      PreferenceCategory.newMissions => (
        l10n.notifPrefsNewMissions,
        l10n.notifPrefsNewMissionsBody,
      ),
      PreferenceCategory.missionReviews => (
        l10n.notifPrefsMissionReviews,
        l10n.notifPrefsMissionReviewsBody,
      ),
      PreferenceCategory.streaks => (
        l10n.notifPrefsStreaks,
        l10n.notifPrefsStreaksBody,
      ),
      PreferenceCategory.videoAllowance => (
        l10n.notifPrefsVideoAllowance,
        l10n.notifPrefsVideoAllowanceBody,
      ),
      PreferenceCategory.videoTimeUp => (
        l10n.notifPrefsVideoTimeUp,
        l10n.notifPrefsVideoTimeUpBody,
      ),
      PreferenceCategory.rewards => (
        l10n.notifPrefsRewards,
        l10n.notifPrefsRewardsBody,
      ),
      PreferenceCategory.safety => (
        l10n.notifPrefsSafety,
        l10n.notifPrefsSafetyBody,
      ),
    };
    return SwitchListTile(
      key: Key('notifPrefs.category.${category.key}'),
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: context.text.titleMedium),
      subtitle: Text(
        locked ? '$body ${l10n.notifPrefsAlwaysOnNote}' : body,
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
      value: preferences.isOn(category),
      // A locked switch reads as "on" but cannot be changed.
      onChanged: locked ? null : onChanged,
    );
  }
}

class _QuietHoursEditor extends StatelessWidget {
  const _QuietHoursEditor({required this.preferences, required this.onChanged});

  final NotificationPreferences preferences;
  final ValueChanged<QuietHours> onChanged;

  Future<void> _pick(BuildContext context, {required bool start}) async {
    final quiet = preferences.quietHours;
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? quiet.start : quiet.end,
      helpText: start
          ? AppLocalizations.of(context).notifPrefsQuietStart
          : AppLocalizations.of(context).notifPrefsQuietEnd,
    );
    if (picked == null || !context.mounted) return;
    final next = start
        ? quiet.copyWith(start: picked)
        : quiet.copyWith(end: picked);
    if (next == quiet) return;
    if (next.enabled && next.start == next.end) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).notifPrefsQuietSame),
          ),
        );
      return;
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quiet = preferences.quietHours;
    final material = MaterialLocalizations.of(context);
    final exemptSafety = preferences.quietHoursExempt.contains(
      PreferenceCategory.safety.key,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.xs,
      children: [
        SwitchListTile(
          key: const Key('notifPrefs.quiet.enabled'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.notifPrefsQuietSwitch,
            style: context.text.titleMedium,
          ),
          subtitle: Text(
            l10n.notifPrefsQuietBody,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          value: quiet.enabled,
          onChanged: (on) {
            if (on && quiet.start == quiet.end) {
              onChanged(QuietHours.defaults.copyWith(enabled: true));
            } else {
              onChanged(quiet.copyWith(enabled: on));
            }
          },
        ),
        for (final (isStart, label, value) in [
          (true, l10n.notifPrefsQuietStart, quiet.start),
          (false, l10n.notifPrefsQuietEnd, quiet.end),
        ])
          ListTile(
            key: Key('notifPrefs.quiet.${isStart ? 'start' : 'end'}'),
            contentPadding: EdgeInsets.zero,
            enabled: quiet.enabled,
            leading: Icon(
              isStart ? Icons.nightlight_round : Icons.wb_sunny_outlined,
            ),
            title: Text(label),
            trailing: Text(
              material.formatTimeOfDay(value),
              style: context.text.titleMedium?.copyWith(
                color: quiet.enabled
                    ? context.colors.primary
                    : context.colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            onTap: () => _pick(context, start: isStart),
          ),
        if (quiet.enabled && quiet.overnight)
          Text(
            l10n.notifPrefsQuietOvernight(
              material.formatTimeOfDay(quiet.start),
              material.formatTimeOfDay(quiet.end),
            ),
            key: const Key('notifPrefs.quiet.overnight'),
            style: context.text.bodySmall,
          ),
        Text(
          l10n.notifPrefsQuietZone(preferences.timezone),
          key: const Key('notifPrefs.quiet.zone'),
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        if (preferences.timezoneIsDefault)
          InlineNotice(
            key: const Key('notifPrefs.quiet.zoneDefault'),
            icon: Icons.public_rounded,
            message: l10n.notifPrefsQuietZoneDefault,
          ),
        if (exemptSafety)
          Text(
            l10n.notifPrefsQuietSafetyNote,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
