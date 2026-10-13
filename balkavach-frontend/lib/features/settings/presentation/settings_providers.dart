import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../shared/platform/device_time_zone.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../child_profile/data/family_repository.dart';
import '../../child_profile/domain/family_models.dart';
import '../data/settings_repository.dart';

/// The signed-in user's server-side settings.
///
/// [save] applies the change optimistically and restores the previous value
/// if the server rejects it, rethrowing the error for the screen to show.
class UserSettingsController extends AsyncNotifier<UserSettings> {
  @override
  Future<UserSettings> build() {
    ref.watch(sessionUserIdProvider);
    return ref.read(settingsRepositoryProvider).mySettings();
  }

  Future<void> save({
    String? languageCode,
    bool? pushEnabled,
    bool? emailNotificationsEnabled,
  }) async {
    // One save at a time: a second change while one is in flight would race
    // the rollback. The screen disables its controls while [saving] is true.
    if (ref.read(settingsSavingProvider)) return;
    ref.read(settingsSavingProvider.notifier).begin();
    final previous = state.value;
    if (previous != null) {
      state = AsyncData(
        previous.copyWith(
          languageCode: languageCode,
          pushEnabled: pushEnabled,
          emailNotificationsEnabled: emailNotificationsEnabled,
        ),
      );
    }
    try {
      final saved = await ref
          .read(settingsRepositoryProvider)
          .updateMySettings(
            languageCode: languageCode,
            pushEnabled: pushEnabled,
            emailNotificationsEnabled: emailNotificationsEnabled,
          );
      if (ref.mounted) state = AsyncData(saved);
    } on Object {
      if (ref.mounted && previous != null) state = AsyncData(previous);
      rethrow;
    } finally {
      if (ref.mounted) ref.read(settingsSavingProvider.notifier).end();
    }
  }
}

/// True while a settings change is being saved.
class SettingsSaving extends Notifier<bool> {
  @override
  bool build() => false;

  void begin() => state = true;

  void end() => state = false;
}

final settingsSavingProvider = NotifierProvider<SettingsSaving, bool>(
  SettingsSaving.new,
);

final userSettingsProvider =
    AsyncNotifierProvider<UserSettingsController, UserSettings>(
      UserSettingsController.new,
    );

/// Consent records for a family, newest first.
final familyConsentsProvider =
    FutureProvider.family<List<ConsentRecord>, String>((ref, familyId) {
      ref.watch(sessionUserIdProvider);
      return ref.watch(familyRepositoryProvider).listConsents(familyId);
    });

final familySettingsProvider = FutureProvider.family<FamilySettings, String>((
  ref,
  familyId,
) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(settingsRepositoryProvider).familySettings(familyId);
});

/// Gives a family that has no time zone yet this phone's zone, once, so
/// reports and streaks cut days where the family lives instead of at UTC.
/// Never overwrites a zone a parent chose. Completes with the zone in force.
final familyTimezoneSyncProvider = FutureProvider.family<String?, String>((
  ref,
  familyId,
) async {
  final repository = ref.watch(settingsRepositoryProvider);
  final current = await ref.watch(familySettingsProvider(familyId).future);
  if (current.timezone != null) return current.timezone;
  final device = await ref.watch(deviceTimeZoneProvider).current();
  if (device == null) return null;
  try {
    final saved = await repository.saveTimezone(familyId, current, device);
    return saved.timezone;
  } on ApiException {
    return null; // The server did not accept it; UTC stays in force.
  }
});
