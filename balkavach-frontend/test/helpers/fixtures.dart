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
  }) => {
    'access_token': accessToken,
    'token_type': 'bearer',
    'expires_at': expiresAt,
    'user': user ?? Fx.user(),
  };

  static Map<String, Object?> childToken() => token(
    accessToken: 'child.jwt.token',
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
  }) => {
    'id': id,
    'family_id': familyId,
    'category_id': categoryId,
    'created_by': parentUserId,
    'assigned_child_id': null,
    'title': title,
    'description': description,
    'star_reward': stars,
    'xp_reward': 20,
    'due_at': null,
    'is_active': true,
    'created_at': '2026-10-02T08:00:00Z',
  };

  static Map<String, Object?> submission({
    String id = submissionId,
    String taskId = Fx.taskId,
    String status = 'pending',
    String proofType = 'note',
    String? note = 'I read it!',
  }) => {
    'id': id,
    'task_id': taskId,
    'child_id': childId,
    'submission_number': 1,
    'proof_type': proofType,
    'proof_url': null,
    'proof_note': note,
    'status': status,
    'submitted_at': '2026-10-12T09:00:00Z',
    'reviewed_at': null,
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

  static Map<String, Object?> progress() => {
    'child_id': childId,
    'star_balance': 240,
    'total_xp': 420,
    'level_number': 4,
    'level_name': 'Explorer',
    'current_streak': 5,
    'longest_streak': 9,
    'activity_days': <Object?>[],
    'badges': <Object?>[],
  };

  static Session parentSession() => Session.fromTokenResponse(token());

  static Session childSession() =>
      Session.fromTokenResponse(childToken(), childId: childId);
}
