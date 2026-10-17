import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/runtime_config.dart';
import '../../../core/storage/app_preferences.dart';

/// Built-in fallback for the version of the parent consent text.
///
/// The live value comes from the server (`/app-config`, edited in the admin
/// panel) and is cached on the device; this default is only used before the
/// first successful fetch. Legal must confirm the real value before launch.
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

/// The consent version parents must have accepted right now: the server's
/// (once fetched), else the last one this device saw, else the built-in one.
final consentVersionProvider = Provider<String>((ref) {
  final fetched = ref.watch(runtimeConfigProvider).value?.parentTermsVersion;
  return fetched ??
      ref.watch(appPreferencesProvider).currentConsentVersion ??
      kConsentDocumentVersion;
});

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() {
    final prefs = ref.watch(appPreferencesProvider);
    final code = prefs.languageCode;
    return OnboardingState(
      languageCode: kSupportedLanguageCodes.contains(code) ? code : null,
      consentAcknowledged:
          prefs.acknowledgedConsentVersion == ref.watch(consentVersionProvider),
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
        .setAcknowledgedConsentVersion(ref.read(consentVersionProvider));
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

/// App locale: the saved choice, else English until one is chosen.
final appLocaleProvider = Provider<Locale>((ref) {
  final code = ref.watch(
    onboardingControllerProvider.select((s) => s.languageCode),
  );
  return Locale(code ?? 'en');
});
