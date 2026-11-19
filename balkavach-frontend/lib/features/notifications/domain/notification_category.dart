import '../../../core/routing/app_routes.dart';

/// Who is reading the notification centre.
enum NotificationAudience { child, parent }

/// The groups the notification centre filters by. Derived on the device from
/// the existing `notification_type` strings; the server stores no category.
enum NotificationCategory { all, missions, rewards, videos, streaks, other }

/// Which group a notification type belongs to.
NotificationCategory categoryOf(String type) {
  if (type.startsWith('task_') ||
      type.startsWith('mission_') && !type.contains('video') ||
      type.startsWith('daily_')) {
    return NotificationCategory.missions;
  }
  if (type.startsWith('reward_') ||
      type.startsWith('redemption_') ||
      type == 'badge_unlocked') {
    return NotificationCategory.rewards;
  }
  if (type.startsWith('video_') || type == 'mission_video_time_granted') {
    return NotificationCategory.videos;
  }
  if (type.startsWith('streak_')) return NotificationCategory.streaks;
  return NotificationCategory.other;
}

/// Where tapping a notification of [type] should go for [audience].
///
/// Only real, existing screens are returned, and the roles never cross: a
/// child is never sent to a parent screen or the other way round.
String routeFor(String type, NotificationAudience audience) {
  final category = categoryOf(type);
  switch (audience) {
    case NotificationAudience.child:
      return switch (category) {
        NotificationCategory.missions ||
        NotificationCategory.streaks => AppRoutes.childMissions,
        NotificationCategory.rewards =>
          type == 'badge_unlocked'
              ? AppRoutes.childProfile
              : AppRoutes.childRewards,
        NotificationCategory.videos => AppRoutes.childWatch,
        _ => AppRoutes.childHome,
      };
    case NotificationAudience.parent:
      return switch (category) {
        NotificationCategory.missions => AppRoutes.parentApprovals,
        NotificationCategory.rewards => AppRoutes.parentRewards,
        _ => AppRoutes.parentHome,
      };
  }
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _type = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

/// True for a well-formed id (anything else from a push is ignored).
bool isValidId(String? value) => value != null && _uuid.hasMatch(value);

/// True for a plausible `notification_type` string.
bool isValidType(String? value) => value != null && _type.hasMatch(value);

/// The exact screen a notification opens, item included where one exists.
///
/// Builds on [routeFor] (the category screens) and adds:
/// * child mission reviews (approved / rejected / try again) open that
///   mission, when the id is well formed; a new mission opens the list;
/// * child streak notifications open the streak screen for that child;
/// * the parent security alert opens Parent settings.
///
/// Ids are validated; the router's role guard is still the final word, so a
/// child can never land on a parent screen even with a forged value.
String locationFor({
  required String type,
  required NotificationAudience audience,
  String? relatedTaskId,
  String? childId,
}) {
  if (!isValidType(type)) {
    return audience == NotificationAudience.child
        ? AppRoutes.childHome
        : AppRoutes.parentHome;
  }
  switch (audience) {
    case NotificationAudience.child:
      const reviews = {
        'task_approved',
        'task_rejected',
        'task_resubmission_requested',
      };
      if (reviews.contains(type) && isValidId(relatedTaskId)) {
        return AppRoutes.childMission(relatedTaskId!);
      }
      if (categoryOf(type) == NotificationCategory.streaks &&
          isValidId(childId)) {
        return Uri(
          path: AppRoutes.streakScreen,
          queryParameters: {'childId': childId},
        ).toString();
      }
      return routeFor(type, audience);
    case NotificationAudience.parent:
      if (type == 'parent_mode_locked') return AppRoutes.parentSettings;
      return routeFor(type, audience);
  }
}
