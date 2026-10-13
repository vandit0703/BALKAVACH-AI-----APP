import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';

/// `UserSettingsPublic`.
@immutable
class UserSettings {
  const UserSettings({
    required this.languageCode,
    required this.pushEnabled,
    required this.emailNotificationsEnabled,
  });

  factory UserSettings.fromJson(Map<String, dynamic> json) => UserSettings(
    languageCode: json['language_code'] as String? ?? 'en',
    pushEnabled: json['push_enabled'] as bool? ?? true,
    emailNotificationsEnabled:
        json['email_notifications_enabled'] as bool? ?? true,
  );

  final String languageCode;
  final bool pushEnabled;
  final bool emailNotificationsEnabled;

  UserSettings copyWith({
    String? languageCode,
    bool? pushEnabled,
    bool? emailNotificationsEnabled,
  }) => UserSettings(
    languageCode: languageCode ?? this.languageCode,
    pushEnabled: pushEnabled ?? this.pushEnabled,
    emailNotificationsEnabled:
        emailNotificationsEnabled ?? this.emailNotificationsEnabled,
  );
}

/// `FamilySettingsPublic`. Only the time zone is used by the app; the other
/// JSON blocks are carried through untouched so saving never drops them.
@immutable
class FamilySettings {
  const FamilySettings({required this.missionSettings, this.timezone});

  factory FamilySettings.fromJson(Map<String, dynamic> json) {
    final mission = Map<String, dynamic>.from(
      json['mission_settings'] as Map<String, dynamic>? ?? const {},
    );
    return FamilySettings(
      missionSettings: mission,
      timezone: mission['timezone'] as String?,
    );
  }

  final Map<String, dynamic> missionSettings;

  /// IANA zone the family's days are cut in; `null` until one is saved (the
  /// server then uses UTC).
  final String? timezone;
}

/// Verified contract: `app/api/v1/settings.py` (`/settings/me`). Values sent
/// as `null` are rejected with 422, so only changed fields are sent.
class SettingsRepository {
  SettingsRepository(this._dio);

  final Dio _dio;

  Future<UserSettings> mySettings() => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/settings/me',
    );
    return UserSettings.fromJson(response.data!);
  });

  /// `GET /api/v1/settings/families/{id}` (parent).
  Future<FamilySettings> familySettings(String familyId) => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/settings/families/$familyId',
    );
    return FamilySettings.fromJson(response.data!);
  });

  /// `PATCH /api/v1/settings/families/{id}`. The server replaces the whole
  /// `mission_settings` object, so the existing keys are sent back with the
  /// new `timezone`. A zone the server does not know is a 422.
  Future<FamilySettings> saveTimezone(
    String familyId,
    FamilySettings current,
    String timezone,
  ) => guardApi(() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/v1/settings/families/$familyId',
      data: {
        'mission_settings': {...current.missionSettings, 'timezone': timezone},
      },
    );
    return FamilySettings.fromJson(response.data!);
  });

  Future<UserSettings> updateMySettings({
    String? languageCode,
    bool? pushEnabled,
    bool? emailNotificationsEnabled,
  }) => guardApi(() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/v1/settings/me',
      data: {
        'language_code': ?languageCode,
        'push_enabled': ?pushEnabled,
        'email_notifications_enabled': ?emailNotificationsEnabled,
      },
    );
    return UserSettings.fromJson(response.data!);
  });
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(apiDioProvider)),
);
