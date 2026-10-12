import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_preferences.dart';

/// Version of the parent consent text shown on the consent screen.
///
/// Recorded on the server as `document_version`. Legal must confirm the real
/// value before launch (docs/api-integration-matrix.md, B11).
const kConsentDocumentVersion = '2026-10-draft';
const kConsentType = 'parent_guardian_terms';

const kSupportedLanguageCodes = ['en', 'gu', 'hi'];

@immutable
class OnboardingState {
  const OnboardingState({this.languageCode, this.consentAcknowledged = false});

  final String? languageCode;
  final bool consentAcknowledged;

  bool get languageChosen => languageCode != null;

  @override
  bool operator ==(Object other) =>
      other is OnboardingState &&
      other.languageCode == languageCode &&
      other.consentAcknowledged == consentAcknowledged;

  @override
  int get hashCode => Object.hash(languageCode, consentAcknowledged);
}

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() {
    final prefs = ref.watch(appPreferencesProvider);
    final code = prefs.languageCode;
    return OnboardingState(
      languageCode: kSupportedLanguageCodes.contains(code) ? code : null,
      consentAcknowledged:
          prefs.acknowledgedConsentVersion == kConsentDocumentVersion,
    );
  }

  Future<void> chooseLanguage(String code) async {
    if (!kSupportedLanguageCodes.contains(code)) {
      throw ArgumentError.value(code, 'code', 'unsupported language');
    }
    await ref.read(appPreferencesProvider).setLanguageCode(code);
    state = OnboardingState(
      languageCode: code,
      consentAcknowledged: state.consentAcknowledged,
    );
  }

  Future<void> acknowledgeConsent() async {
    await ref
        .read(appPreferencesProvider)
        .setAcknowledgedConsentVersion(kConsentDocumentVersion);
    state = OnboardingState(
      languageCode: state.languageCode,
      consentAcknowledged: true,
    );
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );

/// App locale; `null` until a language is chosen (system locale is used).
final appLocaleProvider = Provider<Locale?>((ref) {
  final code = ref.watch(
    onboardingControllerProvider.select((s) => s.languageCode),
  );
  return code == null ? null : Locale(code);
});
