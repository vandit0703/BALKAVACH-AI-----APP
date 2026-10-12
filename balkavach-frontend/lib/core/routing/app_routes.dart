/// Every route path in one place.
abstract final class AppRoutes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const consent = '/consent';
  static const role = '/role';
  static const childStart = '/child-start';
  static const parentAuth = '/parent-auth';

  static const parentHome = '/parent';
  static const parentNewChild = '/parent/children/new';
  static const parentNewMission = '/parent/missions/new';

  static const childHome = '/child';
  static const childMissions = '/child/missions';
  static String childMission(String taskId) => '/child/missions/$taskId';
  static String childMissionSubmit(String taskId) =>
      '/child/missions/$taskId/submit';
  static String childMissionWaiting(String taskId) =>
      '/child/missions/$taskId/waiting';

  /// Reachable without a session once onboarding is complete.
  static const signedOut = {role, childStart, parentAuth};
}
