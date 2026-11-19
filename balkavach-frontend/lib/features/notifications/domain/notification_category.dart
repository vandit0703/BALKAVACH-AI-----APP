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
