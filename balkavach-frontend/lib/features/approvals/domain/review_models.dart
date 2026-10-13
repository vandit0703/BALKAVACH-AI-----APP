import 'package:flutter/foundation.dart';

import '../../child_profile/domain/family_models.dart';
import '../../missions/domain/mission_models.dart';

/// `TaskReviewCreate.decision`.
enum ReviewDecision {
  approved('approved'),
  rejected('rejected'),
  resubmissionRequested('resubmission_requested');

  const ReviewDecision(this.apiValue);

  final String apiValue;
}

/// One submission with the task and child it belongs to.
@immutable
class ReviewItem {
  const ReviewItem({required this.submission, this.mission, this.child});

  final TaskSubmission submission;

  /// `null` when the task was deactivated after it was submitted and the
  /// server did not describe it either.
  final Mission? mission;
  final ChildProfile? child;

  /// The child's name from the profile, else the server's review queue.
  String? get childName => child?.displayName ?? submission.childName;

  String get status => submission.status;
}

/// Submissions split into the Stitch tabs. "Retry" also holds rejected
/// submissions so nothing reviewed disappears.
@immutable
class ApprovalInbox {
  const ApprovalInbox({
    required this.pending,
    required this.approved,
    required this.retry,
    required this.truncated,
    this.failedCount = 0,
  });

  /// Builds the inbox from submissions of the family's children only (a
  /// parent can belong to several families).
  factory ApprovalInbox.from({
    required Iterable<TaskSubmission> submissions,
    required List<Mission> missions,
    required List<ChildProfile> children,
    bool truncated = false,
    int failedCount = 0,
  }) {
    final missionById = {for (final m in missions) m.id: m};
    final childById = {for (final c in children) c.id: c};
    final seen = <String>{};
    final items =
        <ReviewItem>[
          for (final s in submissions)
            if (childById.containsKey(s.childId) && seen.add(s.id))
              ReviewItem(
                submission: s,
                mission: missionById[s.taskId] ?? _missionFromQueue(s),
                child: childById[s.childId],
              ),
        ]..sort(
          (a, b) =>
              b.submission.submittedAt.compareTo(a.submission.submittedAt),
        );
    return ApprovalInbox(
      pending: [
        for (final i in items)
          if (i.status == 'pending') i,
      ],
      approved: [
        for (final i in items)
          if (i.status == 'approved') i,
      ],
      retry: [
        for (final i in items)
          if (i.status == 'resubmission_requested' || i.status == 'rejected') i,
      ],
      truncated: truncated,
      failedCount: failedCount,
    );
  }

  /// A mission rebuilt from the review queue's own task fields, so a task
  /// that was removed after submission still shows its real title and stars.
  static Mission? _missionFromQueue(TaskSubmission s) {
    final title = s.taskTitle;
    if (title == null) return null;
    return Mission(
      id: s.taskId,
      familyId: s.familyId ?? '',
      createdBy: '',
      title: title,
      starReward: s.starReward ?? 0,
      xpReward: s.xpReward ?? 0,
      isActive: false,
      createdAt: s.submittedAt,
    );
  }

  final List<ReviewItem> pending;
  final List<ReviewItem> approved;
  final List<ReviewItem> retry;

  /// True when more submitted tasks exist than the app loaded.
  final bool truncated;

  /// Tasks whose submissions could not be fetched (network or server error).
  /// The inbox is shown without them rather than failing as a whole.
  final int failedCount;
}

/// Unread `task_submitted` notifications: submissions the parent has not yet
/// reviewed in this app. Cheap (one request), unlike the inbox itself.
int unreviewedSubmissionCount(List<AppNotification> notifications) =>
    notifications.where((n) => n.type == 'task_submitted' && !n.isRead).length;

/// Task ids named by the parent's `task_submitted` notifications, newest
/// first and de-duplicated. There is no family-wide "pending submissions"
/// endpoint (blocker B4); these notifications are how the app finds which
/// tasks have submissions without fetching every task.
List<String> submittedTaskIds(List<AppNotification> notifications) {
  final ids = <String>{};
  for (final n in notifications) {
    final taskId = n.relatedTaskId;
    if (n.type == 'task_submitted' && taskId != null) ids.add(taskId);
  }
  return ids.toList();
}
