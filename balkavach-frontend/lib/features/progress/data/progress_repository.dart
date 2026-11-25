import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../authentication/presentation/session_controller.dart';

// ---------------------------------------------------------------------------
// StreakInfo — returned by GET /api/v1/progress/children/{id}/streak
// ---------------------------------------------------------------------------

@immutable
class StreakInfo {
  const StreakInfo({
    required this.childId,
    required this.currentStreak,
    required this.longestStreak,
    required this.streakState,
    this.graceDeadline,
    this.secondsUntilExpiry,
    this.lastActivityDate,
    this.lastActivityAt,
  });

  factory StreakInfo.fromJson(Map<String, dynamic> json) => StreakInfo(
    childId: json['child_id'] as String,
    currentStreak: json['current_streak'] as int? ?? 0,
    longestStreak: json['longest_streak'] as int? ?? 0,
    streakState: json['streak_state'] as String? ?? 'active',
    graceDeadline: json['grace_deadline'] == null
        ? null
        : DateTime.parse(json['grace_deadline'] as String).toUtc(),
    secondsUntilExpiry: json['seconds_until_grace_expires'] as int?,
    lastActivityDate: json['last_activity_date'] == null
        ? null
        : _utcCalendarDate(json['last_activity_date'] as String),
    lastActivityAt: json['last_activity_at'] == null
        ? null
        : DateTime.parse(json['last_activity_at'] as String).toUtc(),
  );

  final String childId;
  final int currentStreak;
  final int longestStreak;

  /// One of: "active" | "at_risk" | "broken" | "recovered"
  final String streakState;

  /// UTC deadline for the grace window; null when active or broken.
  final DateTime? graceDeadline;

  /// Seconds until the grace window closes, as of the last server response.
  final int? secondsUntilExpiry;
  final DateTime? lastActivityDate;
  final DateTime? lastActivityAt;
}

/// Parses a `YYYY-MM-DD` API date into midnight UTC, never shifting by the
/// device's offset.
DateTime _utcCalendarDate(String value) {
  final parsed = DateTime.parse(value);
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}

/// `ActivityDayPublic`: one UTC day of parent-approved missions.
@immutable
class ActivityDay {
  const ActivityDay({
    required this.date,
    required this.completedTasks,
    required this.starsEarned,
    required this.xpEarned,
  });

  factory ActivityDay.fromJson(Map<String, dynamic> json) => ActivityDay(
    date: _utcCalendarDate(json['activity_date'] as String),
    completedTasks: json['completed_tasks'] as int? ?? 0,
    starsEarned: json['stars_earned'] as int? ?? 0,
    xpEarned: json['xp_earned'] as int? ?? 0,
  );

  /// UTC calendar date (midnight UTC). The server derives it from
  /// `datetime.now(timezone.utc).date()` when a mission is approved, so it is
  /// NOT the family's local day.
  final DateTime date;
  final int completedTasks;
  final int starsEarned;
  final int xpEarned;
}

/// Midnight UTC of the UTC calendar day containing [value].
DateTime utcDay(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// One badge in the full catalogue, earned or locked. [threshold] and
/// [current] exist only for criteria the server can measure: the app shows the
/// server's numbers and never invents progress.
@immutable
class AchievementBadge {
  const AchievementBadge({
    required this.id,
    required this.name,
    required this.unlocked,
    this.description,
    this.unlockedAt,
    this.threshold,
    this.current,
  });

  factory AchievementBadge.fromJson(Map<String, dynamic> json) =>
      AchievementBadge(
        id: json['badge_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        unlocked: json['unlocked'] as bool? ?? false,
        unlockedAt: json['unlocked_at'] == null
            ? null
            : DateTime.parse(json['unlocked_at'] as String),
        threshold: (json['threshold'] as num?)?.toInt(),
        current: (json['current'] as num?)?.toInt(),
      );

  final String id;
  final String name;
  final String? description;
  final bool unlocked;
  final DateTime? unlockedAt;
  final int? threshold;
  final int? current;

  bool get hasProgress => threshold != null && current != null;

  /// 0..1 towards the badge; null when the server gave no measurable target.
  double? get fraction =>
      hasProgress ? (current! / threshold!).clamp(0.0, 1.0).toDouble() : null;
}

/// The child's level and the distance to the next one (`level` in
/// `GET /progress/children/{id}/achievements`).
@immutable
class LevelProgress {
  const LevelProgress({
    required this.totalXp,
    required this.minimumXp,
    this.levelNumber,
    this.name,
    this.nextLevelNumber,
    this.nextLevelName,
    this.nextMinimumXp,
  });

  factory LevelProgress.fromJson(Map<String, dynamic> json) => LevelProgress(
    levelNumber: (json['level_number'] as num?)?.toInt(),
    name: json['name'] as String?,
    minimumXp: (json['minimum_xp'] as num?)?.toInt() ?? 0,
    nextLevelNumber: (json['next_level_number'] as num?)?.toInt(),
    nextLevelName: json['next_level_name'] as String?,
    nextMinimumXp: (json['next_minimum_xp'] as num?)?.toInt(),
    totalXp: (json['total_xp'] as num?)?.toInt() ?? 0,
  );

  final int? levelNumber;
  final String? name;
  final int minimumXp;
  final int? nextLevelNumber;
  final String? nextLevelName;
  final int? nextMinimumXp;
  final int totalXp;

  bool get isTopLevel => nextMinimumXp == null;
  int? get xpToNext => nextMinimumXp == null
      ? null
      : (nextMinimumXp! - totalXp).clamp(0, 1 << 30);

  /// 0..1 through the current level; null at the top level.
  double? get fraction {
    final next = nextMinimumXp;
    if (next == null || next <= minimumXp) return null;
    return ((totalXp - minimumXp) / (next - minimumXp))
        .clamp(0.0, 1.0)
        .toDouble();
  }
}

/// `AchievementsPublic`.
@immutable
class Achievements {
  const Achievements({required this.level, required this.badges});

  factory Achievements.fromJson(Map<String, dynamic> json) => Achievements(
    level: LevelProgress.fromJson(json['level'] as Map<String, dynamic>),
    badges: [
      for (final badge in json['badges'] as List<dynamic>? ?? const [])
        AchievementBadge.fromJson(badge as Map<String, dynamic>),
    ],
  );

  final LevelProgress level;
  final List<AchievementBadge> badges;

  List<AchievementBadge> get locked => [
    for (final badge in badges)
      if (!badge.unlocked) badge,
  ];
}

/// `BadgePublic`.
@immutable
class EarnedBadge {
  const EarnedBadge({
    required this.id,
    required this.name,
    required this.unlockedAt,
    this.description,
    this.iconUrl,
  });

  factory EarnedBadge.fromJson(Map<String, dynamic> json) => EarnedBadge(
    id: json['badge_id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    iconUrl: json['icon_url'] as String?,
    unlockedAt: DateTime.parse(json['unlocked_at'] as String),
  );

  final String id;
  final String name;
  final String? description;
  final String? iconUrl;
  final DateTime unlockedAt;
}

/// One decoration of the garden; it unlocks with the matching badge.
@immutable
class GardenItem {
  const GardenItem({
    required this.key,
    required this.badge,
    required this.unlocked,
  });

  factory GardenItem.fromJson(Map<String, dynamic> json) => GardenItem(
    key: json['key'] as String,
    badge: json['badge'] as String,
    unlocked: json['unlocked'] as bool? ?? false,
  );

  final String key;
  final String badge;
  final bool unlocked;
}

/// The server's view of the garden: size from XP, decorations from badges.
@immutable
class Garden {
  const Garden({
    required this.stage,
    required this.stageKey,
    required this.items,
    this.xpToNextStage,
  });

  factory Garden.fromJson(Map<String, dynamic> json) => Garden(
    stage: json['stage'] as int? ?? 1,
    stageKey: json['stage_key'] as String? ?? 'seed',
    xpToNextStage: json['xp_to_next_stage'] as int?,
    items: [
      for (final item in json['items'] as List<dynamic>? ?? const [])
        GardenItem.fromJson(item as Map<String, dynamic>),
    ],
  );

  final int stage;
  final String stageKey;

  /// `null` at the largest size.
  final int? xpToNextStage;
  final List<GardenItem> items;

  int get unlockedCount => items.where((i) => i.unlocked).length;
}

/// `ProgressPublic`.
@immutable
class ChildProgress {
  const ChildProgress({
    required this.childId,
    required this.starBalance,
    required this.totalXp,
    required this.currentStreak,
    required this.longestStreak,
    this.activityDays = const [],
    this.badges = const [],
    this.levelNumber,
    this.levelName,
    this.garden,
    this.streakState = 'active',
    this.graceDeadline,
    this.secondsUntilExpiry,
  });

  factory ChildProgress.fromJson(Map<String, dynamic> json) => ChildProgress(
    childId: json['child_id'] as String,
    starBalance: json['star_balance'] as int? ?? 0,
    totalXp: json['total_xp'] as int? ?? 0,
    levelNumber: json['level_number'] as int?,
    levelName: json['level_name'] as String?,
    currentStreak: json['current_streak'] as int? ?? 0,
    longestStreak: json['longest_streak'] as int? ?? 0,
    streakState: json['streak_state'] as String? ?? 'active',
    graceDeadline: json['grace_deadline'] == null
        ? null
        : DateTime.parse(json['grace_deadline'] as String).toUtc(),
    secondsUntilExpiry: json['seconds_until_grace_expires'] as int?,
    activityDays: [
      for (final day in json['activity_days'] as List<dynamic>? ?? const [])
        ActivityDay.fromJson(day as Map<String, dynamic>),
    ],
    badges: [
      for (final badge in json['badges'] as List<dynamic>? ?? const [])
        EarnedBadge.fromJson(badge as Map<String, dynamic>),
    ],
    garden: json['garden'] is Map<String, dynamic>
        ? Garden.fromJson(json['garden'] as Map<String, dynamic>)
        : null,
  );

  final String childId;
  final int starBalance;
  final int totalXp;
  final int? levelNumber;
  final String? levelName;
  final int currentStreak;
  final int longestStreak;
  final String? streakState;
  final DateTime? graceDeadline;
  final int? secondsUntilExpiry;

  /// Newest first, at most 90 days (server limit).
  final List<ActivityDay> activityDays;

  /// Newest first.
  final List<EarnedBadge> badges;

  /// Server-derived garden; `null` from a server that predates it.
  final Garden? garden;

  int get badgeCount => badges.length;

  /// Activity for the seven UTC days ending on the UTC day of [today] (oldest
  /// first). Days with no approved missions are zero.
  ///
  /// The window is anchored on UTC because `activity_date` is a UTC calendar
  /// day. Anchoring on the device-local date would drop or mis-bucket
  /// approvals made between 00:00 and 05:30 IST.
  List<ActivityDay> week(DateTime today) {
    final end = utcDay(today);
    final byDate = {for (final day in activityDays) utcDay(day.date): day};
    return [
      for (var i = 6; i >= 0; i--)
        byDate[end.subtract(Duration(days: i))] ??
            ActivityDay(
              date: end.subtract(Duration(days: i)),
              completedTasks: 0,
              starsEarned: 0,
              xpEarned: 0,
            ),
    ];
  }
}

/// One category row of the weekly report.
@immutable
class ReportCategory {
  const ReportCategory({
    required this.name,
    required this.completedTasks,
    required this.starsEarned,
    required this.xpEarned,
    this.categoryId,
  });

  factory ReportCategory.fromJson(Map<String, dynamic> json) => ReportCategory(
    categoryId: json['category_id'] as String?,
    name: json['name'] as String,
    completedTasks: json['completed_tasks'] as int? ?? 0,
    starsEarned: json['stars_earned'] as int? ?? 0,
    xpEarned: json['xp_earned'] as int? ?? 0,
  );

  final String? categoryId;
  final String name;
  final int completedTasks;
  final int starsEarned;
  final int xpEarned;
}

/// `WeeklyReportPublic`: a Monday-to-Sunday report in the *family's* time
/// zone, computed on the server from approved reviews only.
@immutable
class WeeklyReport {
  const WeeklyReport({
    required this.childId,
    required this.timezone,
    required this.periodStart,
    required this.periodEnd,
    required this.completedTasks,
    required this.starsEarned,
    required this.xpEarned,
    required this.days,
    required this.categories,
    required this.pendingSubmissions,
    required this.rejectedSubmissions,
    required this.currentStreak,
    required this.longestStreak,
  });

  factory WeeklyReport.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'] as Map<String, dynamic>;
    return WeeklyReport(
      childId: json['child_id'] as String,
      timezone: json['timezone'] as String? ?? 'UTC',
      periodStart: _utcCalendarDate(json['period_start'] as String),
      periodEnd: _utcCalendarDate(json['period_end'] as String),
      completedTasks: totals['completed_tasks'] as int? ?? 0,
      starsEarned: totals['stars_earned'] as int? ?? 0,
      xpEarned: totals['xp_earned'] as int? ?? 0,
      days: [
        for (final day in json['days'] as List<dynamic>)
          ActivityDay(
            date: _utcCalendarDate(
              (day as Map<String, dynamic>)['date'] as String,
            ),
            completedTasks: day['completed_tasks'] as int? ?? 0,
            starsEarned: day['stars_earned'] as int? ?? 0,
            xpEarned: day['xp_earned'] as int? ?? 0,
          ),
      ],
      categories: [
        for (final row in json['categories'] as List<dynamic>? ?? const [])
          ReportCategory.fromJson(row as Map<String, dynamic>),
      ],
      pendingSubmissions: json['pending_submissions'] as int? ?? 0,
      rejectedSubmissions: json['rejected_submissions'] as int? ?? 0,
      currentStreak: json['current_streak'] as int? ?? 0,
      longestStreak: json['longest_streak'] as int? ?? 0,
    );
  }

  final String childId;

  /// IANA zone name the days are cut in (the family's setting, else UTC).
  final String timezone;

  /// Calendar dates (Monday and Sunday) in [timezone], as UTC midnights.
  final DateTime periodStart;
  final DateTime periodEnd;
  final int completedTasks;
  final int starsEarned;
  final int xpEarned;

  /// Seven days, Monday first.
  final List<ActivityDay> days;
  final List<ReportCategory> categories;
  final int pendingSubmissions;
  final int rejectedSubmissions;
  final int currentStreak;
  final int longestStreak;

  int get activeDays => days.where((d) => d.completedTasks > 0).length;
}

/// Arguments of [weeklyReportProvider].
@immutable
class ReportQuery {
  const ReportQuery(this.childId, this.weeksBack);

  final String childId;
  final int weeksBack;

  @override
  bool operator ==(Object other) =>
      other is ReportQuery &&
      other.childId == childId &&
      other.weeksBack == weeksBack;

  @override
  int get hashCode => Object.hash(childId, weeksBack);
}

/// Verified contract: `app/api/v1/progress.py`. Callable by the child itself
/// or a parent in the same family.
class ProgressRepository {
  ProgressRepository(this._dio);

  final Dio _dio;

  Future<ChildProgress> childProgress(String childId) => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/progress/children/$childId',
    );
    return ChildProgress.fromJson(response.data!);
  });

  /// `GET /api/v1/progress/children/{id}/achievements`: every active badge
  /// with the child's real progress, plus level progress.
  Future<Achievements> achievements(String childId) => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/progress/children/$childId/achievements',
    );
    return Achievements.fromJson(response.data!);
  });

  /// `GET /api/v1/progress/children/{id}/streak`
  Future<StreakInfo> streakInfo(String childId) => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/progress/children/$childId/streak',
    );
    return StreakInfo.fromJson(response.data!);
  });

  /// `GET /api/v1/progress/children/{id}/weekly?weeks_back=` (parent or the
  /// child). Returns `null` on a server that predates the endpoint (404).
  Future<WeeklyReport?> weeklyReport(String childId, {int weeksBack = 0}) =>
      guardApi(() async {
        try {
          final response = await _dio.get<Map<String, dynamic>>(
            '/api/v1/progress/children/$childId/weekly',
            queryParameters: {'weeks_back': weeksBack},
          );
          return WeeklyReport.fromJson(response.data!);
        } on DioException catch (error) {
          if (error.response?.statusCode == 404 &&
              error.response?.data is Map &&
              ((error.response!.data as Map)['error'] as Map?)?['code'] ==
                  'http_error' &&
              ((error.response!.data as Map)['error'] as Map?)?['message'] ==
                  'Not Found') {
            return null;
          }
          rethrow;
        }
      });
}

final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) => ProgressRepository(ref.watch(apiDioProvider)),
);

final childProgressProvider = FutureProvider.family<ChildProgress, String>((
  ref,
  childId,
) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(progressRepositoryProvider).childProgress(childId);
});

/// Disposed when no screen shows it, so reopening a profile asks the server
/// again (a parent's app cannot know the child just earned something).
final achievementsProvider = FutureProvider.autoDispose
    .family<Achievements, String>((ref, childId) {
      ref.watch(sessionUserIdProvider);
      return ref.watch(progressRepositoryProvider).achievements(childId);
    });

final streakInfoProvider = FutureProvider.family<StreakInfo, String>((
  ref,
  childId,
) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(progressRepositoryProvider).streakInfo(childId);
});

/// The week's report, or `null` when the server cannot produce one (older
/// backend); the screen then falls back to deriving a UTC week from progress.
final weeklyReportProvider = FutureProvider.family<WeeklyReport?, ReportQuery>((
  ref,
  query,
) {
  ref.watch(sessionUserIdProvider);
  return ref
      .watch(progressRepositoryProvider)
      .weeklyReport(query.childId, weeksBack: query.weeksBack);
});
