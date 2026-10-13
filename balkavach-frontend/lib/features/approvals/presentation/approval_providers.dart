import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../child_profile/presentation/family_providers.dart';
import '../../missions/data/missions_repository.dart';
import '../../missions/domain/mission_models.dart';
import '../../missions/presentation/mission_providers.dart';
import '../../progress/data/progress_repository.dart';
import '../data/approvals_repository.dart';
import '../domain/review_models.dart';

/// Most tasks whose submissions are fetched for one inbox load. Bounds the
/// fan-out that blocker B4 forces on the app.
const kMaxInboxTasks = 25;

/// Requests in flight at once while loading the inbox.
const _inboxConcurrency = 5;

/// The parent's notifications (newest 100). One request feeds both the Parent
/// Hub badge and the inbox.
final parentNotificationsProvider = FutureProvider<List<AppNotification>>((
  ref,
) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(missionsRepositoryProvider).listNotifications();
});

/// Number of submissions waiting for this parent, or `null` until known (or
/// if notifications could not be loaded; the badge then simply stays hidden).
final unreviewedCountProvider = Provider<int?>((ref) {
  final notifications = ref.watch(parentNotificationsProvider).value;
  return notifications == null
      ? null
      : unreviewedSubmissionCount(notifications);
});

/// The parent's approval inbox for one family.
///
/// Submissions are fetched per task (there is no family-wide endpoint, B4).
/// A task whose request fails is skipped and counted in
/// [ApprovalInbox.failedCount]; the inbox only fails as a whole when every
/// request failed, or the session ended (401).
final approvalInboxProvider = FutureProvider.family<ApprovalInbox, String>((
  ref,
  familyId,
) async {
  ref.watch(sessionUserIdProvider);
  final repository = ref.watch(approvalsRepositoryProvider);
  try {
    // Three bounded requests, whatever the number of missions.
    final results = await Future.wait([
      repository.listFamilySubmissions(familyId, statuses: ['pending']),
      repository.listFamilySubmissions(
        familyId,
        statuses: ['approved'],
        limit: 50,
      ),
      repository.listFamilySubmissions(
        familyId,
        statuses: ['rejected', 'resubmission_requested'],
        limit: 50,
      ),
    ]);
    final missions = await ref.watch(familyMissionsProvider(familyId).future);
    final children = await ref.watch(familyChildrenProvider(familyId).future);
    return ApprovalInbox.from(
      submissions: results.expand((list) => list),
      missions: missions,
      children: children,
      truncated: results.any((list) => list.length >= 100),
    );
  } on NotFoundException {
    // A server that predates the family-wide endpoint: use the per-task path.
    return _legacyApprovalInbox(ref, familyId);
  }
});

/// The inbox for servers without `GET /reviews/submissions`: submissions are
/// fetched per task named by the parent's `task_submitted` notifications.
Future<ApprovalInbox> _legacyApprovalInbox(Ref ref, String familyId) async {
  final notifications = await ref.watch(parentNotificationsProvider.future);
  final taskIds = submittedTaskIds(notifications);
  final missions = await ref.watch(familyMissionsProvider(familyId).future);
  final children = await ref.watch(familyChildrenProvider(familyId).future);

  final repository = ref.watch(approvalsRepositoryProvider);
  final wanted = taskIds.take(kMaxInboxTasks).toList();
  final submissions = <TaskSubmission>[];
  var failed = 0;
  ApiException? firstError;

  Future<List<TaskSubmission>> fetch(String taskId) async {
    try {
      return await repository.listSubmissions(taskId);
    } on UnauthorizedException {
      rethrow;
    } on NotFoundException {
      // The task was removed or belongs to another family: nothing to review.
      return const [];
    } on ApiException catch (error) {
      failed++;
      firstError ??= error;
      return const [];
    }
  }

  for (var i = 0; i < wanted.length; i += _inboxConcurrency) {
    final batch = wanted.skip(i).take(_inboxConcurrency);
    final results = await Future.wait(batch.map(fetch));
    for (final list in results) {
      submissions.addAll(list);
    }
  }
  if (wanted.isNotEmpty && failed == wanted.length) throw firstError!;

  return ApprovalInbox.from(
    submissions: submissions,
    missions: missions,
    children: children,
    truncated:
        taskIds.length > kMaxInboxTasks ||
        notifications.length >= kNotificationPageSize,
    failedCount: failed,
  );
}

/// A stored proof photo (needs the signed-in parent's token, so it is
/// fetched through the API client and cached per URL).
final proofImageProvider = FutureProvider.family<Uint8List, String>((
  ref,
  proofUrl,
) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(missionsRepositoryProvider).downloadProof(proofUrl);
});

/// Reviews one submission and refreshes everything the decision changes.
///
/// Rethrows [ApiException] so the screen can show it. A 409
/// `submission_already_reviewed` still refreshes the inbox, because another
/// parent got there first.
Future<void> reviewSubmission(
  WidgetRef ref, {
  required String familyId,
  required ReviewItem item,
  required ReviewDecision decision,
  String? note,
}) async {
  try {
    await ref
        .read(approvalsRepositoryProvider)
        .review(item.submission.id, decision, note: note);
  } on ConflictException {
    await _markSubmittedNotificationsRead(ref, item.submission.id);
    ref.invalidate(approvalInboxProvider(familyId));
    rethrow;
  }
  await _markSubmittedNotificationsRead(ref, item.submission.id);
  ref
    ..invalidate(approvalInboxProvider(familyId))
    ..invalidate(childProgressProvider(item.submission.childId));
}

/// Marks the `task_submitted` notification(s) for [submissionId] as read so
/// the Parent Hub count drops. Best effort: a failure only leaves the count
/// stale until the next refresh, and must not undo a successful review.
Future<void> _markSubmittedNotificationsRead(
  WidgetRef ref,
  String submissionId,
) async {
  final notifications = ref.read(parentNotificationsProvider).value ?? const [];
  final repository = ref.read(missionsRepositoryProvider);
  for (final n in notifications) {
    if (n.type == 'task_submitted' &&
        !n.isRead &&
        n.relatedSubmissionId == submissionId) {
      try {
        await repository.markNotificationRead(n.id);
      } on ApiException {
        // Best effort.
      }
    }
  }
  ref.invalidate(parentNotificationsProvider);
}
