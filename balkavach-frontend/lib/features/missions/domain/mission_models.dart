import 'package:flutter/foundation.dart';

DateTime? _parseDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

/// `TaskCategoryPublic`.
@immutable
class TaskCategory {
  const TaskCategory({
    required this.id,
    required this.name,
    this.description,
    this.iconName,
    this.isDefault = false,
  });

  factory TaskCategory.fromJson(Map<String, dynamic> json) => TaskCategory(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    iconName: json['icon_name'] as String?,
    isDefault: json['is_default'] as bool? ?? false,
  );

  final String id;
  final String name;
  final String? description;
  final String? iconName;
  final bool isDefault;

  @override
  bool operator ==(Object other) =>
      other is TaskCategory && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// `TaskPublic`, called a "mission" in the UI.
@immutable
class Mission {
  const Mission({
    required this.id,
    required this.familyId,
    required this.createdBy,
    required this.title,
    required this.starReward,
    required this.xpReward,
    required this.isActive,
    required this.createdAt,
    this.categoryId,
    this.assignedChildId,
    this.description,
    this.dueAt,
  });

  factory Mission.fromJson(Map<String, dynamic> json) => Mission(
    id: json['id'] as String,
    familyId: json['family_id'] as String,
    categoryId: json['category_id'] as String?,
    createdBy: json['created_by'] as String,
    assignedChildId: json['assigned_child_id'] as String?,
    title: json['title'] as String,
    description: json['description'] as String?,
    starReward: json['star_reward'] as int? ?? 0,
    xpReward: json['xp_reward'] as int? ?? 0,
    dueAt: _parseDate(json['due_at']),
    isActive: json['is_active'] as bool? ?? true,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String familyId;
  final String? categoryId;
  final String createdBy;
  final String? assignedChildId;
  final String title;
  final String? description;
  final int starReward;
  final int xpReward;
  final DateTime? dueAt;
  final bool isActive;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      other is Mission &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.starReward == starReward &&
      other.xpReward == xpReward &&
      other.categoryId == categoryId &&
      other.assignedChildId == assignedChildId &&
      other.dueAt == dueAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    starReward,
    xpReward,
    categoryId,
    assignedChildId,
    dueAt,
  );
}

/// Input for `POST /api/v1/tasks`.
@immutable
class NewMission {
  const NewMission({
    required this.familyId,
    required this.title,
    this.description,
    this.categoryId,
    this.assignedChildId,
    this.starReward = 0,
    this.xpReward = 0,
  });

  final String familyId;
  final String title;
  final String? description;
  final String? categoryId;
  final String? assignedChildId;
  final int starReward;
  final int xpReward;

  Map<String, dynamic> toJson() {
    final trimmedDescription = description?.trim();
    return {
      'family_id': familyId,
      'title': title.trim(),
      if (trimmedDescription != null && trimmedDescription.isNotEmpty)
        'description': trimmedDescription,
      'category_id': ?categoryId,
      'assigned_child_id': ?assignedChildId,
      'star_reward': starReward,
      'xp_reward': xpReward,
    };
  }
}

/// `TaskSubmissionPublic`.
@immutable
class TaskSubmission {
  const TaskSubmission({
    required this.id,
    required this.taskId,
    required this.childId,
    required this.submissionNumber,
    required this.proofType,
    required this.status,
    required this.submittedAt,
    this.proofUrl,
    this.proofNote,
    this.reviewedAt,
  });

  factory TaskSubmission.fromJson(Map<String, dynamic> json) => TaskSubmission(
    id: json['id'] as String,
    taskId: json['task_id'] as String,
    childId: json['child_id'] as String,
    submissionNumber: json['submission_number'] as int,
    proofType: json['proof_type'] as String,
    proofUrl: json['proof_url'] as String?,
    proofNote: json['proof_note'] as String?,
    status: json['status'] as String,
    submittedAt: DateTime.parse(json['submitted_at'] as String),
    reviewedAt: _parseDate(json['reviewed_at']),
  );

  final String id;
  final String taskId;
  final String childId;
  final int submissionNumber;
  final String proofType;
  final String? proofUrl;
  final String? proofNote;

  /// `pending`, `approved`, `rejected` or `resubmission_requested`.
  final String status;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
}

/// `NotificationPublic`.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.relatedTaskId,
    this.relatedSubmissionId,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        type: json['notification_type'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
        relatedTaskId: json['related_task_id'] as String?,
        relatedSubmissionId: json['related_submission_id'] as String?,
        isRead: json['is_read'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String type;
  final String title;
  final String message;
  final String? relatedTaskId;
  final String? relatedSubmissionId;
  final bool isRead;
  final DateTime createdAt;
}
