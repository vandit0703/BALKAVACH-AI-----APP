import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';

/// Version of the consent explanation this app shows parents
/// (`pandaConsentDisclosure` in the ARB files). It must equal the backend's
/// `PANDA_VOICE_CONSENT_VERSION`; change both together with the wording. A
/// grant sent with an older version is refused (409 `consent_version_outdated`).
const kPandaVoiceConsentVersion = 'panda-voice-2026-11-20';

/// One child's Talk to Panda microphone consent
/// (`GET/PUT /api/v1/settings/families/{family}/children/{child}/panda-voice-consent`).
@immutable
class PandaVoiceConsent {
  const PandaVoiceConsent({
    required this.childId,
    required this.granted,
    required this.documentVersion,
    this.grantedAt,
  });

  factory PandaVoiceConsent.fromJson(Map<String, dynamic> json) =>
      PandaVoiceConsent(
        childId: json['child_id'] as String,
        granted: json['granted'] as bool? ?? false,
        documentVersion: json['document_version'] as String? ?? '',
        grantedAt: DateTime.tryParse(json['granted_at'] as String? ?? ''),
      );

  final String childId;
  final bool granted;
  final String documentVersion;
  final DateTime? grantedAt;
}

/// Parent-only access to the microphone consent. Nothing here records or
/// uploads audio; it only stores the parent's yes or no.
class PandaVoiceConsentRepository {
  PandaVoiceConsentRepository(this._dio);

  final Dio _dio;

  String _path(String familyId, String childId) =>
      '/api/v1/settings/families/$familyId/children/$childId/panda-voice-consent';

  Future<PandaVoiceConsent> get(String familyId, String childId) =>
      guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          _path(familyId, childId),
        );
        return PandaVoiceConsent.fromJson(response.data!);
      });

  /// Grants (for the consent text this app shows) or withdraws consent.
  Future<PandaVoiceConsent> set(
    String familyId,
    String childId, {
    required bool granted,
  }) => guardApi(() async {
    final response = await _dio.put<Map<String, dynamic>>(
      _path(familyId, childId),
      data: {
        'granted': granted,
        if (granted) 'document_version': kPandaVoiceConsentVersion,
      },
    );
    return PandaVoiceConsent.fromJson(response.data!);
  });
}

final pandaVoiceConsentRepositoryProvider =
    Provider<PandaVoiceConsentRepository>(
      (ref) => PandaVoiceConsentRepository(ref.watch(apiDioProvider)),
    );

/// One child's consent, keyed by `(familyId, childId)`.
final pandaVoiceConsentProvider = FutureProvider.autoDispose
    .family<PandaVoiceConsent, (String, String)>(
      (ref, key) =>
          ref.read(pandaVoiceConsentRepositoryProvider).get(key.$1, key.$2),
    );
