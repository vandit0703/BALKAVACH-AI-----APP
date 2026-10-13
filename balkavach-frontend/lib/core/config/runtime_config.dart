import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../network/interceptors.dart';
import '../storage/app_preferences.dart';

/// Non-sensitive settings the server controls (`GET /api/v1/app-config`),
/// managed from the admin panel.
@immutable
class RuntimeConfig {
  const RuntimeConfig({
    required this.consentVersions,
    required this.maintenanceEnabled,
    this.maintenanceMessage = '',
    this.consentFromAdmin = false,
  });

  factory RuntimeConfig.fromJson(Map<String, dynamic> json) {
    final versions = (json['consent_versions'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as String),
    );
    final maintenance =
        json['maintenance'] as Map<String, dynamic>? ?? const {};
    return RuntimeConfig(
      consentVersions: versions,
      consentFromAdmin: json['consent_source'] == 'admin',
      maintenanceEnabled: maintenance['enabled'] == true,
      maintenanceMessage: (maintenance['message'] as String? ?? '').trim(),
    );
  }

  /// Consent document type → current version.
  final Map<String, String> consentVersions;
  final bool consentFromAdmin;
  final bool maintenanceEnabled;
  final String maintenanceMessage;

  /// The version of the parent/guardian terms parents must accept.
  String? get parentTermsVersion => consentVersions['parent_guardian_terms'];
}

/// Fetches the server's runtime configuration once per app start.
///
/// Failure is not an error for the user: the last version this device saw (or
/// the built-in default) keeps working, so the app is usable offline.
final runtimeConfigProvider = FutureProvider<RuntimeConfig?>((ref) async {
  final dio = ref.watch(apiDioProvider);
  try {
    final response = await dio.get<Map<String, dynamic>>(
      '/api/v1/app-config',
      options: Options(extra: const {kAuthenticatedExtra: false}),
    );
    final config = RuntimeConfig.fromJson(response.data!);
    final version = config.parentTermsVersion;
    if (version != null) {
      await ref.read(appPreferencesProvider).setCurrentConsentVersion(version);
    }
    return config;
  } on Object {
    // Older server (404), no connection or an unexpected body: the cached or
    // built-in values keep the app usable.
    return null;
  }
});
