/// Every route path in one place.
abstract final class AppRoutes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const consent = '/consent';
  static const role = '/role';
  static const childStart = '/child-start';
  static const childLogin = '/child-login';
  static const parentAuth = '/parent-auth';
    static const verifyEmail = '/verify-email';
    static const forgotPassword = '/forgot-password';

  /// Passwordless parent sign-in with an emailed code.
  static const loginCode = '/login-code';

  /// Password-reset landing (deep link `balkavach://app/reset-password?token=…`).
  static const resetPassword = '/reset-password';

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
  static const parentNotificationSettings = '/parent/settings/notifications';
  static const parentPandaVoiceConsent = '/parent/settings/panda-voice';
    static const parentPandaChatAccess = '/parent/settings/panda-chat';
  static const parentHelpSupport = '/parent/settings/help';
  static const parentRewards = '/parent/rewards';
  static const parentNewReward = '/parent/rewards/new';
  static String parentEditReward(String rewardId) =>
      '/parent/rewards/$rewardId/edit';
  static String parentChild(String childId) => '/parent/children/$childId';
  static String parentChildWatchHistory(String childId) =>
      '${parentChild(childId)}/watch-history';

  static const childHome = '/child';
  static const childMissions = '/child/missions';
  static const childRewards = '/child/rewards';
  static const childGarden = '/child/garden';
  static const childLearn = '/child/learn';

  /// The Learning Hub opened on one of its tabs: `videos`, `quizzes`, `stories`.
  static String childLearnTab(String tab) =>
      Uri(path: childLearn, queryParameters: {'tab': tab}).toString();
  static String childQuiz(String quizId) => '/child/quizzes/$quizId';
  static String childQuizTake(String quizId) => '/child/quizzes/$quizId/take';
  static String childQuizResult(String attemptId) =>
      '/child/quizzes/result/$attemptId';
  static const childVideos = '/child/videos';
  static const childVideoPlay = '/child/videos/play';
  static const childShorts = '/child/shorts';
  static const childWatch = '/child/watch';
  static const childProfile = '/child/profile';

  /// Parent sign-in used to leave child mode.
  static const childParentGate = '/child/parent-gate';
  static const streakScreen = '/streak';
  static String childLearnItem(String id) => '/child/learn/$id';
  static String childLearnPlay(String id) => '/child/learn/$id/play';
  static String childMission(String taskId) => '/child/missions/$taskId';
  static String childMissionSubmit(String taskId) =>
      '/child/missions/$taskId/submit';
  static String childMissionWaiting(String taskId) =>
      '/child/missions/$taskId/waiting';

  /// Reachable without a session once onboarding is complete.
    static const signedOut = {
        role,
        childStart,
        childLogin,
        parentAuth,
        verifyEmail,
        forgotPassword,
        loginCode,
    };
}
