import 'package:flutter/foundation.dart';

import 'mission_models.dart';

/// What the child sees on a mission card.
enum MissionStatus {
  notStarted,
  pending,
  approved,
  rejected,
  resubmissionRequested;

  /// Maps a backend review notification type (`task_<decision>`).
  static MissionStatus? fromReviewNotification(String type) => switch (type) {
    'task_approved' => MissionStatus.approved,
    'task_rejected' => MissionStatus.rejected,
    'task_resubmission_requested' => MissionStatus.resubmissionRequested,
    _ => null,
  };

  bool get isReviewed =>
      this == approved || this == rejected || this == resubmissionRequested;
}

/// A submission this device sent. The child token cannot list submissions
/// (blocker B3), so the app remembers what it sent.
@immutable
class LocalSubmissionRecord {
  const LocalSubmissionRecord({
    required this.taskId,
    required this.submissionId,
    required this.submittedAt,
  });

  factory LocalSubmissionRecord.fromJson(Map<String, dynamic> json) =>
      LocalSubmissionRecord(
        taskId: json['task_id'] as String,
        submissionId: json['submission_id'] as String,
        submittedAt: DateTime.parse(json['submitted_at'] as String),
      );

  factory LocalSubmissionRecord.fromSubmission(TaskSubmission submission) =>
      LocalSubmissionRecord(
        taskId: submission.taskId,
        submissionId: submission.id,
        submittedAt: submission.submittedAt,
      );

  final String taskId;
  final String submissionId;
  final DateTime submittedAt;

  Map<String, dynamic> toJson() => {
    'task_id': taskId,
    'submission_id': submissionId,
    'submitted_at': submittedAt.toUtc().toIso8601String(),
  };
}

/// Derives each task's status from local submissions and the child's review
/// notifications (`task_approved`, `task_rejected`,
/// `task_resubmission_requested`, each with `related_submission_id`).
///
/// For each task the newest event wins: a newer local submission makes the
/// task pending again; a review for that exact submission resolves it.
/// Reviews of submissions made on another device still apply by task id.
Map<String, MissionStatus> resolveMissionStatuses({
  required List<LocalSubmissionRecord> submissions,
  required List<AppNotification> notifications,
}) {
  final reviewsBySubmission = <String, AppNotification>{};
  final latestReviewByTask = <String, AppNotification>{};
  for (final notification in notifications) {
    if (MissionStatus.fromReviewNotification(notification.type) == null) {
      continue;
    }
    final submissionId = notification.relatedSubmissionId;
    if (submissionId != null) {
      final existing = reviewsBySubmission[submissionId];
      if (existing == null ||
          notification.createdAt.isAfter(existing.createdAt)) {
        reviewsBySubmission[submissionId] = notification;
      }
    }
    final taskId = notification.relatedTaskId;
    if (taskId != null) {
      final existing = latestReviewByTask[taskId];
      if (existing == null ||
          notification.createdAt.isAfter(existing.createdAt)) {
        latestReviewByTask[taskId] = notification;
      }
    }
  }

  final latestLocalByTask = <String, LocalSubmissionRecord>{};
  for (final record in submissions) {
    final existing = latestLocalByTask[record.taskId];
    if (existing == null || record.submittedAt.isAfter(existing.submittedAt)) {
      latestLocalByTask[record.taskId] = record;
    }
  }

  final statuses = <String, MissionStatus>{};
  for (final MapEntry(key: taskId, value: review)
      in latestReviewByTask.entries) {
    statuses[taskId] = MissionStatus.fromReviewNotification(review.type)!;
  }
  for (final MapEntry(key: taskId, value: record)
      in latestLocalByTask.entries) {
    final review = reviewsBySubmission[record.submissionId];
    if (review != null) {
      statuses[taskId] = MissionStatus.fromReviewNotification(review.type)!;
      continue;
    }
    final taskReview = latestReviewByTask[taskId];
    final reviewIsNewer =
        taskReview != null && taskReview.createdAt.isAfter(record.submittedAt);
    if (!reviewIsNewer) statuses[taskId] = MissionStatus.pending;
  }
  return statuses;
}
