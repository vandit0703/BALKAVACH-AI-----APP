import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret, device-local settings. Tokens never go here.
class AppPreferences {
  AppPreferences(this._prefs);

  final SharedPreferences _prefs;

  static const _languageKey = 'app.language_code';
  static const _consentVersionKey = 'onboarding.consent_version';
  static const _currentConsentKey = 'config.consent_version';
  static const _consentSyncedPrefix = 'consent.synced.';
  static const _avatarPrefix = 'child.avatar.';
  static const _submissionsPrefix = 'child.submissions.';
  static const _celebratedPrefix = 'child.celebrated_approvals.';
  static const _approvalBaselinePrefix = 'child.approval_baseline.';

  String? get languageCode => _prefs.getString(_languageKey);

  Future<void> setLanguageCode(String code) =>
      _prefs.setString(_languageKey, code);

  /// Version of the parent consent text the user acknowledged on this device.
  String? get acknowledgedConsentVersion =>
      _prefs.getString(_consentVersionKey);

  Future<void> setAcknowledgedConsentVersion(String version) =>
      _prefs.setString(_consentVersionKey, version);

  /// The newest consent version the server announced, kept for offline use.
  String? get currentConsentVersion => _prefs.getString(_currentConsentKey);

  Future<void> setCurrentConsentVersion(String version) =>
      _prefs.setString(_currentConsentKey, version);

  /// Whether the consent for [version] was recorded on the server for
  /// [familyId].
  bool isConsentSynced(String familyId, String version) =>
      _prefs.getString('$_consentSyncedPrefix$familyId') == version;

  Future<void> markConsentSynced(String familyId, String version) =>
      _prefs.setString('$_consentSyncedPrefix$familyId', version);

  /// Avatar choice is device-local because the backend only accepts http URLs
  /// for `avatar_url` (see docs/api-integration-matrix.md, B7).
  String? childAvatarKey(String childId) =>
      _prefs.getString('$_avatarPrefix$childId');

  Future<void> setChildAvatarKey(String childId, String avatarKey) =>
      _prefs.setString('$_avatarPrefix$childId', avatarKey);

  /// Raw JSON list of submissions this device sent for [childId].
  List<Map<String, dynamic>> submissionRecords(String childId) {
    final raw = _prefs.getString('$_submissionsPrefix$childId');
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return const [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } on FormatException {
      return const [];
    }
  }

  /// Ids of approved submissions this device already celebrated for
  /// [childId], oldest first.
  List<String> celebratedSubmissionIds(String childId) =>
      _prefs.getStringList('$_celebratedPrefix$childId') ?? const [];

  Future<void> setCelebratedSubmissionIds(String childId, List<String> ids) =>
      _prefs.setStringList('$_celebratedPrefix$childId', ids);

  /// Whether this child's approvals were looked at once on this device (what
  /// was already approved then is history and is never celebrated).
  bool approvalBaselineDone(String childId) =>
      _prefs.getBool('$_approvalBaselinePrefix$childId') ?? false;

  Future<void> setApprovalBaselineDone(String childId) =>
      _prefs.setBool('$_approvalBaselinePrefix$childId', true);

  Future<void> setSubmissionRecords(
    String childId,
    List<Map<String, dynamic>> records,
  ) => _prefs.setString('$_submissionsPrefix$childId', jsonEncode(records));
}

/// Overridden in `bootstrap()` with a loaded instance.
final appPreferencesProvider = Provider<AppPreferences>(
  (ref) => throw UnimplementedError('appPreferencesProvider not initialised'),
);
