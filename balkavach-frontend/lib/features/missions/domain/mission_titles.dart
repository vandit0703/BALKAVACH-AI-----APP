/// A trailing age range such as "(4 to 6)", "(Ages 4-6)" or "[11 – 15]".
///
/// Only a bracketed pair of numbers counts, so "(and a dog)", "Level (2)" or
/// "Plan for 3 (kids)" are left alone. Mirrors `child_facing_title` in
/// `balkavach-backend/app/services/mission_titles.py`.
final _trailingAgeRange = RegExp(
  r'\s*[(\[]\s*(?:ages?\s+)?\d{1,2}\s*(?:to|-|–|—)\s*\d{1,2}\s*\+?\s*(?:years?(?:\s+old)?)?\s*[)\]]\s*$',
  caseSensitive: false,
);

/// A mission title as a child reads it: without the age band some titles end
/// with ("Saturday Rhythm Rockstar 2 (4 to 6)"). The age is eligibility data
/// the server keeps; it is only hidden here, never removed from the record.
String childFacingMissionTitle(String title) {
  final cleaned = title.replaceFirst(_trailingAgeRange, '').trim();
  return cleaned.isEmpty ? title.trim() : cleaned;
}
