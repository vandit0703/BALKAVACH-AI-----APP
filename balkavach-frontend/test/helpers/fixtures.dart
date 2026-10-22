import 'package:balkavach_app/features/authentication/domain/session.dart';

/// JSON shaped exactly like the backend Pydantic schemas.
abstract final class Fx {
  static const parentUserId = '11111111-1111-4111-8111-111111111111';
  static const childUserId = '22222222-2222-4222-8222-222222222222';
  static const childId = '33333333-3333-4333-8333-333333333333';
  static const familyId = '44444444-4444-4444-8444-444444444444';
  static const taskId = '55555555-5555-4555-8555-555555555555';
  static const task2Id = '55555555-5555-4555-8555-555555555556';
  static const categoryId = '66666666-6666-4666-8666-666666666666';
  static const submissionId = '77777777-7777-4777-8777-777777777777';

  static Map<String, Object?> user({
    String id = parentUserId,
    String role = 'parent',
    String name = 'Priya Sharma',
    String? email = 'priya@example.com',
  }) => {
    'id': id,
    'full_name': name,
    'email': email,
    'role': role,
    'preferred_language': 'en',
  };

  static Map<String, Object?> token({
    Map<String, Object?>? user,
    String accessToken = 'parent.jwt.token',
    String expiresAt = '2100-01-01T00:00:00Z',
    String? childId,
    String? refreshToken,
    String? refreshExpiresAt,
  }) => {
    'access_token': accessToken,
    'token_type': 'bearer',
    'expires_at': expiresAt,
    'child_id': ?childId,
    'refresh_token': ?refreshToken,
    'refresh_expires_at': ?(refreshToken == null
        ? null
        : (refreshExpiresAt ?? '2100-01-01T00:00:00Z')),
    'user': user ?? Fx.user(),
  };

  static Map<String, Object?> childToken() => token(
    accessToken: 'child.jwt.token',
    childId: childId,
    user: user(id: childUserId, role: 'child', name: 'Aarav', email: null),
  );

  static Map<String, Object?> family() => {
    'id': familyId,
    'family_name': 'Sharma Family',
    'created_by': parentUserId,
    'created_at': '2026-10-01T10:00:00Z',
  };

  static Map<String, Object?> child({String name = 'Aarav'}) => {
    'id': childId,
    'user_id': childUserId,
    'family_id': familyId,
    'display_name': name,
    'date_of_birth': '2019-05-04',
    'avatar_url': null,
    'is_active': true,
    'created_at': '2026-10-01T10:05:00Z',
  };

  static Map<String, Object?> category({String name = 'Learn'}) => {
    'id': categoryId,
    'name': name,
    'description': 'Reading and puzzles',
    'icon_name': 'menu_book',
    'is_default': true,
  };

  static Map<String, Object?> task({
    String id = taskId,
    String title = 'Read a Storybook',
    String? description = 'Read one story and tell us your favourite part.',
    int stars = 10,
    String? categoryId = Fx.categoryId,
    String? dueAt,
    String? assignedChildId,
  }) => {
    'id': id,
    'family_id': familyId,
    'category_id': categoryId,
    'created_by': parentUserId,
    'assigned_child_id': assignedChildId,
    'title': title,
    'description': description,
    'star_reward': stars,
    'xp_reward': 20,
    'due_at': dueAt,
    'is_active': true,
    'created_at': '2026-10-02T08:00:00Z',
  };

  static Map<String, Object?> submission({
    String id = submissionId,
    String taskId = Fx.taskId,
    String status = 'pending',
    String proofType = 'note',
    String? note = 'I read it!',
    int number = 1,
    String? proofUrl,
    String? taskTitle,
    String? reviewNote,
    String submittedAt = '2026-10-12T09:00:00Z',
  }) => {
    'id': id,
    'task_id': taskId,
    'child_id': childId,
    'submission_number': number,
    'proof_type': proofType,
    'proof_url': proofUrl,
    'proof_note': note,
    'status': status,
    'submitted_at': submittedAt,
    'reviewed_at': null,
    'task_title': ?taskTitle,
    'review_note': ?reviewNote,
  };

  static Map<String, Object?> notification({
    required String type,
    String id = '88888888-8888-4888-8888-888888888888',
    String? taskId = Fx.taskId,
    String? submissionId = Fx.submissionId,
    String createdAt = '2026-10-12T10:00:00Z',
  }) => {
    'id': id,
    'notification_type': type,
    'title': 'Task reviewed',
    'message': 'Your task was approved.',
    'related_task_id': taskId,
    'related_submission_id': submissionId,
    'related_redemption_id': null,
    'is_read': false,
    'read_at': null,
    'created_at': createdAt,
  };

  /// "Today" for every test that uses the harness (see [Harness]).
  static final now = DateTime(2026, 10, 12, 12);

  /// `LearningGatePublic`. The default mirrors a deployment with no video
  /// playback provider configured, which is the current real state: the gate
  /// is unavailable and missions stay reachable.
  static Map<String, Object?> learningGate({
    String phase = 'video_unavailable',
    bool videoGateAvailable = false,
    bool videoEnabled = true,
    bool playbackConfigured = false,
    int watchedSecondsToday = 0,
    bool firstSessionComplete = false,
    bool secondSessionComplete = false,
    bool missionsUnlocked = true,
    bool secondSessionUnlocked = false,
    int missionsAssigned = 2,
    int missionsApproved = 0,
    int missionsPendingApproval = 0,
    List<String> blockers = const ['playback_provider_not_configured'],
  }) => {
    'local_date': '2026-10-22',
    'timezone': 'UTC',
    'phase': phase,
    'video_gate_available': videoGateAvailable,
    'video_enabled': videoEnabled,
    'playback_configured': playbackConfigured,
    'first_session_target_seconds': 600,
    'second_session_target_seconds': 900,
    'daily_allowance_seconds': 1500,
    'watched_seconds_today': watchedSecondsToday,
    'remaining_allowance_seconds': 1500 - watchedSecondsToday,
    'first_session_complete': firstSessionComplete,
    'second_session_complete': secondSessionComplete,
    'missions_unlocked': missionsUnlocked,
    'second_session_unlocked': secondSessionUnlocked,
    'missions_assigned': missionsAssigned,
    'missions_approved': missionsApproved,
    'missions_pending_approval': missionsPendingApproval,
    'requires_parent_approval': true,
    'blockers': blockers,
    'generated_at': '2026-10-22T06:00:00Z',
  };

  static Map<String, Object?> progress({
    List<Map<String, Object?>> activityDays = const [],
    List<Map<String, Object?>> badges = const [],
    int currentStreak = 5,
    int longestStreak = 9,
    Map<String, Object?>? garden,
  }) => {
    'child_id': childId,
    'star_balance': 240,
    'total_xp': 420,
    'level_number': 4,
    'level_name': 'Explorer',
    'current_streak': currentStreak,
    'longest_streak': longestStreak,
    'activity_days': activityDays,
    'badges': badges,
    'garden': ?garden,
  };

  static Map<String, Object?> activityDay(
    String date, {
    int tasks = 1,
    int stars = 10,
    int xp = 20,
  }) => {
    'activity_date': date,
    'completed_tasks': tasks,
    'stars_earned': stars,
    'xp_earned': xp,
  };

  static Map<String, Object?> badge({
    String id = '99999999-9999-4999-8999-999999999999',
    String name = 'Bookworm',
    String? description = 'Read 15 bedtime stories',
  }) => {
    'badge_id': id,
    'name': name,
    'description': description,
    'icon_url': null,
    'unlocked_at': '2026-10-10T09:00:00Z',
  };

  static const rewardId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  static const redemptionId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

  static Map<String, Object?> redemption({
    String status = 'pending',
    int cost = 50,
    String id = redemptionId,
    String rewardId = Fx.rewardId,
    String? reviewNote,
    String? rewardName,
    String? childName,
  }) => {
    'id': id,
    'reward_id': rewardId,
    'child_id': childId,
    'star_cost_at_request': cost,
    'status': status,
    'review_note': reviewNote,
    'requested_at': '2026-10-11T09:00:00Z',
    'reviewed_at': null,
    'fulfilled_at': null,
    if (rewardName != null) 'family_id': familyId,
    'reward_name': ?rewardName,
    'child_name': ?childName,
  };

  static Map<String, Object?> reward({
    String id = rewardId,
    String name = 'Ice cream',
    int cost = 50,
    String? description = 'One scoop after dinner',
    String type = 'custom',
  }) => {
    'id': id,
    'family_id': familyId,
    'name': name,
    'description': description,
    'reward_type': type,
    'star_cost': cost,
    'image_url': null,
    'video_id': null,
    'video_collection_id': null,
    'access_duration_seconds': null,
    'access_validity_seconds': null,
    'max_uses': null,
    'is_active': true,
  };

  static Map<String, Object?> userSettings({
    bool push = true,
    bool email = true,
  }) => {
    'user_id': parentUserId,
    'language_code': 'en',
    'push_enabled': push,
    'email_notifications_enabled': email,
    'updated_at': null,
  };

  static Map<String, Object?> consent() => {
    'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'family_id': familyId,
    'child_id': null,
    'parent_user_id': parentUserId,
    'consent_type': 'parent_guardian_terms',
    'document_version': '2026-10-draft',
    'accepted': true,
    'accepted_at': '2026-10-12T09:00:00Z',
    'revoked_at': null,
    'created_at': '2026-10-12T09:00:00Z',
  };

  static Session parentSession() => Session.fromTokenResponse(token());

  static Session childSession() =>
      Session.fromTokenResponse(childToken(), childId: childId);
}
