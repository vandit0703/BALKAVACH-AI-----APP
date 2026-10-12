import '../../l10n/app_localizations.dart';

/// Form validators mirroring the backend Pydantic constraints so users see
/// problems before a round trip. The server stays the source of truth.
class Validators {
  const Validators(this._l10n);

  final AppLocalizations _l10n;

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// `RegistrationRequest.full_name`: 2–160 chars.
  String? fullName(String? value) => _name(value, min: 2, max: 160);

  /// `FamilyCreate.family_name`: 2–160 chars.
  String? familyName(String? value) => _name(value, min: 2, max: 160);

  /// `ChildCreate.display_name`: 1–100 chars.
  String? childName(String? value) => _name(value, min: 1, max: 100);

  /// `TaskCreate.title`: 2–180 chars.
  String? missionTitle(String? value) => _name(value, min: 2, max: 180);

  String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty || !_email.hasMatch(v)) return _l10n.validationEmailInvalid;
    return null;
  }

  /// Login accepts any non-empty password (max 128).
  String? loginPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return _l10n.validationPasswordRequired;
    if (v.length > 128) return _l10n.validationTooLong(128);
    return null;
  }

  /// `RegistrationRequest.password`: 12–128 chars.
  String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return _l10n.validationPasswordRequired;
    if (v.length < 12) return _l10n.validationPasswordTooShort;
    if (v.length > 128) return _l10n.validationTooLong(128);
    return null;
  }

  String? maxLength(String? value, int max) =>
      (value?.trim().length ?? 0) > max ? _l10n.validationTooLong(max) : null;

  /// Whole number within [min]..[max]; empty counts as [min].
  String? intRange(String? value, {required int min, required int max}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final parsed = int.tryParse(v);
    if (parsed == null || parsed < min || parsed > max) {
      return _l10n.validationNumberRange(min, max);
    }
    return null;
  }

  String? _name(String? value, {required int min, required int max}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return _l10n.validationNameRequired;
    if (v.length < min) return _l10n.validationNameTooShort;
    if (v.length > max) return _l10n.validationTooLong(max);
    return null;
  }
}
