/// Every route path in one place.
abstract final class AppRoutes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const consent = '/consent';
  static const role = '/role';
  static const childStart = '/child-start';
  static const childLogin = '/child-login';
  static const parentAuth = '/parent-auth';

  static const parentHome = '/parent';
  static const parentNewChild = '/parent/children/new';
  static const parentNewMission = '/parent/missions/new';
  static String parentEditMission(String taskId) =>
      '/parent/missions/$taskId/edit';
  static const parentApprovals = '/parent/approvals';
  static const parentReports = '/parent/reports';
  static String parentReportsFor(String childId) =>
      Uri(path: parentReports, queryParameters: {'child': childId}).toString();
  static const parentSettings = '/parent/settings';
  static const parentRewards = '/parent/rewards';
  static const parentNewReward = '/parent/rewards/new';
  static String parentEditReward(String rewardId) =>
      '/parent/rewards/$rewardId/edit';
  static String parentChild(String childId) => '/parent/children/$childId';

  static const childHome = '/child';
  static const childMissions = '/child/missions';
  static const childRewards = '/child/rewards';
  static const childGarden = '/child/garden';
  static const childLearn = '/child/learn';
  static const childVideos = '/child/videos';
  static const childVideoPlay = '/child/videos/play';
  static const childProfile = '/child/profile';
  static String childLearnItem(String id) => '/child/learn/$id';
  static String childLearnPlay(String id) => '/child/learn/$id/play';
  static String childMission(String taskId) => '/child/missions/$taskId';
  static String childMissionSubmit(String taskId) =>
      '/child/missions/$taskId/submit';
  static String childMissionWaiting(String taskId) =>
      '/child/missions/$taskId/waiting';

  /// Reachable without a session once onboarding is complete.
  static const signedOut = {role, childStart, childLogin, parentAuth};
}
