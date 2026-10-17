import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kSupportedLanguageCodes = ['en', 'hi', 'gu'];

/// Each language in its own script, so an administrator can always find theirs.
const kLanguageNames = {'en': 'English', 'hi': 'हिन्दी', 'gu': 'ગુજરાતી'};

const _languageKey = 'admin.language_code';

/// Loaded in `main()`; `null` (tests, or storage blocked) means the choice is
/// kept for this session only.
final languagePrefsProvider = Provider<SharedPreferences?>((ref) => null);

/// The panel language: the saved choice, else English. Only the language code
/// is stored in the browser; tokens never are.
class LocaleController extends Notifier<Locale> {
  @override
  Locale build() {
    final saved = ref.watch(languagePrefsProvider)?.getString(_languageKey);
    return Locale(kSupportedLanguageCodes.contains(saved) ? saved! : 'en');
  }

  Future<void> choose(String code) async {
    if (!kSupportedLanguageCodes.contains(code)) {
      throw ArgumentError.value(code, 'code', 'unsupported language');
    }
    state = Locale(code);
    await ref.read(languagePrefsProvider)?.setString(_languageKey, code);
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale>(
  LocaleController.new,
);
