import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;

/// The switchable groups, in the order the settings screen shows them.
///
/// The keys are the server's (`notification_preferences_service.CATEGORIES`);
/// a key the app does not know is kept and sent back untouched but not shown.
enum PreferenceCategory {
  newMissions('new_missions'),
  missionReviews('mission_reviews'),
  streaks('streaks'),
  videoAllowance('video_allowance'),
  videoTimeUp('video_time_up'),
  rewards('rewards'),
  safety('safety');

  const PreferenceCategory(this.key);

  final String key;

  static PreferenceCategory? fromKey(String key) {
    for (final c in values) {
      if (c.key == key) return c;
    }
    return null;
  }
}

/// `HH:MM` (24-hour) to a [TimeOfDay]; `null` for anything else.
TimeOfDay? parseHhMm(String? value) {
  final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value ?? '');
  if (match == null) return null;
  return TimeOfDay(
    hour: int.parse(match.group(1)!),
    minute: int.parse(match.group(2)!),
  );
}

String formatHhMm(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

@immutable
class QuietHours {
  const QuietHours({
    required this.enabled,
    required this.start,
    required this.end,
  });

  factory QuietHours.fromJson(Map<String, dynamic> json) => QuietHours(
    enabled: json['enabled'] as bool? ?? false,
    start: parseHhMm(json['start'] as String?) ?? defaults.start,
    end: parseHhMm(json['end'] as String?) ?? defaults.end,
  );

  static const defaults = QuietHours(
    enabled: false,
    start: TimeOfDay(hour: 21, minute: 0),
    end: TimeOfDay(hour: 7, minute: 0),
  );

  final bool enabled;
  final TimeOfDay start;
  final TimeOfDay end;

  /// True when the window runs past midnight (for example 21:00 to 07:00).
  bool get overnight =>
      start.hour * 60 + start.minute > end.hour * 60 + end.minute;

  QuietHours copyWith({bool? enabled, TimeOfDay? start, TimeOfDay? end}) =>
      QuietHours(
        enabled: enabled ?? this.enabled,
        start: start ?? this.start,
        end: end ?? this.end,
      );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'start': formatHhMm(start),
    'end': formatHhMm(end),
  };

  @override
  bool operator ==(Object other) =>
      other is QuietHours &&
      other.enabled == enabled &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(enabled, start, end);
}

/// `NotificationPreferencesPublic`: one family's push preferences.
@immutable
class NotificationPreferences {
  const NotificationPreferences({
    required this.familyId,
    required this.categories,
    required this.locked,
    required this.quietHours,
    required this.quietHoursExempt,
    required this.timezone,
    required this.timezoneIsDefault,
  });

  factory NotificationPreferences.fromJson(
    Map<String, dynamic> json,
  ) => NotificationPreferences(
    familyId: json['family_id'] as String,
    categories: {
      for (final MapEntry(:key, :value)
          in (json['categories'] as Map<String, dynamic>? ?? const {}).entries)
        if (value is bool) key: value,
    },
    locked: {
      for (final key in json['locked_categories'] as List? ?? const [])
        key as String,
    },
    quietHours: QuietHours.fromJson(
      json['quiet_hours'] as Map<String, dynamic>? ?? const {},
    ),
    quietHoursExempt: {
      for (final key
          in json['quiet_hours_exempt_categories'] as List? ?? const [])
        key as String,
    },
    timezone: json['timezone'] as String? ?? 'UTC',
    timezoneIsDefault: json['timezone_is_default'] as bool? ?? true,
  );

  final String familyId;
  final Map<String, bool> categories;
  final Set<String> locked;
  final QuietHours quietHours;
  final Set<String> quietHoursExempt;
  final String timezone;

  /// The server has no saved family zone and is using UTC.
  final bool timezoneIsDefault;

  bool isOn(PreferenceCategory c) => isLocked(c) || (categories[c.key] ?? true);

  bool isLocked(PreferenceCategory c) => locked.contains(c.key);

  NotificationPreferences copyWith({
    Map<String, bool>? categories,
    QuietHours? quietHours,
  }) => NotificationPreferences(
    familyId: familyId,
    categories: categories ?? this.categories,
    locked: locked,
    quietHours: quietHours ?? this.quietHours,
    quietHoursExempt: quietHoursExempt,
    timezone: timezone,
    timezoneIsDefault: timezoneIsDefault,
  );
}
