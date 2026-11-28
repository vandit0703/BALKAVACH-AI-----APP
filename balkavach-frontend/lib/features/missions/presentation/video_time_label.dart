import '../../../l10n/app_localizations.dart';

/// A video duration as a parent reads it: "15 min", "3 min 45 s" or "45 s".
///
/// Exact to the second, because the standard mission amount (225 s) is not a
/// whole number of minutes.
String videoTimeLabel(AppLocalizations l10n, int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = safe ~/ 60;
  final rest = safe % 60;
  if (minutes == 0) return l10n.videoDurationSeconds(rest);
  if (rest == 0) return l10n.videoDurationMinutes(minutes);
  return l10n.videoDurationMinutesSeconds(minutes, rest);
}
