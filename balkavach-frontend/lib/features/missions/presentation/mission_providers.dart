import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../shared/media/photo_picker.dart';
import '../../authentication/presentation/session_controller.dart';
import '../data/missions_repository.dart';
import '../domain/mission_models.dart';
import '../domain/mission_status.dart';

/// Child id for the active child-mode session.
final activeChildIdProvider = Provider<String?>((ref) {
  final session = ref.watch(sessionControllerProvider).value;
  return session != null && session.isChild ? session.childId : null;
});

final taskCategoriesProvider = FutureProvider<List<TaskCategory>>((ref) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(missionsRepositoryProvider).listCategories();
});

/// Missions visible to the signed-in child.
final childMissionsProvider = FutureProvider<List<Mission>>((ref) {
  // Recompute when a different child signs in on this device. Without a
  // child session there is nothing to fetch (and no token to send).
  final childId = ref.watch(activeChildIdProvider);
  if (childId == null) return const <Mission>[];
  return ref.watch(missionsRepositoryProvider).listMissions();
});

/// Missions for the parent's family.
final familyMissionsProvider = FutureProvider.family<List<Mission>, String>((
  ref,
  familyId,
) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(missionsRepositoryProvider).listMissions(familyId: familyId);
});

/// Device-local record of submissions (B3 workaround).
class SubmissionLog {
  SubmissionLog(this._prefs);

  final AppPreferences _prefs;

  List<LocalSubmissionRecord> read(String childId) => _prefs
      .submissionRecords(childId)
      .map(LocalSubmissionRecord.fromJson)
      .toList();

  Future<void> add(String childId, LocalSubmissionRecord record) async {
    final records = [...read(childId), record];
    // Keep the log small: the newest 200 submissions are plenty to resolve
    // statuses against the 100 newest notifications.
    records.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    await _prefs.setSubmissionRecords(
      childId,
      records.take(200).map((r) => r.toJson()).toList(),
    );
  }
}

final submissionLogProvider = Provider<SubmissionLog>(
  (ref) => SubmissionLog(ref.watch(appPreferencesProvider)),
);

final childNotificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  ref.watch(activeChildIdProvider);
  return ref.watch(missionsRepositoryProvider).listNotifications();
});

/// Statuses per task id. [reviewsAvailable] is false when notifications could
/// not be fetched, in which case only locally known submissions show (as
/// pending).
@immutable
class MissionStatusSnapshot {
  const MissionStatusSnapshot({
    required this.statuses,
    required this.reviewsAvailable,
  });

  final Map<String, MissionStatus> statuses;
  final bool reviewsAvailable;

  MissionStatus statusOf(String taskId) =>
      statuses[taskId] ?? MissionStatus.notStarted;
}

/// The child's own attempts as the server records them.
final mySubmissionsProvider = FutureProvider<List<TaskSubmission>>((ref) {
  final childId = ref.watch(activeChildIdProvider);
  if (childId == null) return const <TaskSubmission>[];
  ref.watch(submissionLogRevisionProvider);
  return ref.watch(missionsRepositoryProvider).listMySubmissions();
});

/// Attempts at one mission, newest first.
final missionAttemptsProvider =
    FutureProvider.family<List<TaskSubmission>, String>((ref, taskId) async {
      final all = await ref.watch(mySubmissionsProvider.future);
      return all.where((s) => s.taskId == taskId).toList()
        ..sort((a, b) => b.submissionNumber.compareTo(a.submissionNumber));
    });

final missionStatusesProvider = FutureProvider<MissionStatusSnapshot>((
  ref,
) async {
  final childId = ref.watch(activeChildIdProvider);
  if (childId == null) {
    return const MissionStatusSnapshot(statuses: {}, reviewsAvailable: true);
  }
  // Re-read whenever a submission is added (see MissionSubmitController).
  ref.watch(submissionLogRevisionProvider);
  try {
    final submissions = await ref.watch(mySubmissionsProvider.future);
    return MissionStatusSnapshot(
      statuses: resolveStatusesFromSubmissions(submissions),
      reviewsAvailable: true,
    );
  } on ApiException {
    // Older server without the endpoint, or offline: fall back to what this
    // device sent plus the child's review notifications.
  }
  final records = ref.watch(submissionLogProvider).read(childId);
  try {
    final notifications = await ref.watch(childNotificationsProvider.future);
    return MissionStatusSnapshot(
      statuses: resolveMissionStatuses(
        submissions: records,
        notifications: notifications,
      ),
      reviewsAvailable: true,
    );
  } on ApiException {
    return MissionStatusSnapshot(
      statuses: resolveMissionStatuses(
        submissions: records,
        notifications: const [],
      ),
      reviewsAvailable: false,
    );
  }
});

/// Bumped after each local submission so dependants re-read the log.
final submissionLogRevisionProvider = NotifierProvider<_Revision, int>(
  _Revision.new,
);

class _Revision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Submits one mission. State is the last successful submission, if any.
class MissionSubmitController extends AsyncNotifier<TaskSubmission?> {
  @override
  TaskSubmission? build() => null;

  /// An uploaded photo that has not been attached to a mission yet. Kept so a
  /// retry after a failed submit does not upload the same photo again.
  String? _uploadedPhotoId;
  PickedPhoto? _uploadedPhoto;

  Future<TaskSubmission?> submit(
    String taskId, {
    String? note,
    PickedPhoto? photo,
  }) async {
    // A second tap while the first request is in flight must not create a
    // second submission.
    if (state.isLoading) return null;
    final childId = ref.read(activeChildIdProvider);
    if (childId == null) {
      state = const AsyncError(
        ForbiddenException(message: 'Child session required'),
        StackTrace.empty,
      );
      return null;
    }
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final repository = ref.read(missionsRepositoryProvider);
      String? uploadId;
      if (photo != null) {
        if (!identical(photo, _uploadedPhoto) || _uploadedPhotoId == null) {
          _uploadedPhotoId = await repository.uploadProof(photo);
          _uploadedPhoto = photo;
        }
        uploadId = _uploadedPhotoId;
      }
      final submission = await repository.submitMission(
        taskId,
        note: note,
        uploadId: uploadId,
      );
      _uploadedPhotoId = null;
      _uploadedPhoto = null;
      return submission;
    });
    if (!ref.mounted) return result.value;
    final submission = result.value;
    if (submission != null) {
      await ref
          .read(submissionLogProvider)
          .add(childId, LocalSubmissionRecord.fromSubmission(submission));
      if (!ref.mounted) return submission;
      ref.read(submissionLogRevisionProvider.notifier).bump();
    }
    state = result;
    return submission;
  }
}

final missionSubmitControllerProvider =
    AsyncNotifierProvider.autoDispose<MissionSubmitController, TaskSubmission?>(
      MissionSubmitController.new,
    );

/// One of the child's missions, or `null` if it is no longer listed.
final childMissionProvider = FutureProvider.family<Mission?, String>((
  ref,
  taskId,
) async {
  final missions = await ref.watch(childMissionsProvider.future);
  return missions.where((m) => m.id == taskId).firstOrNull;
});

/// Mission ideas for the create-mission form. Failing to load them never
/// blocks creating a mission by hand.
final missionPresetsProvider = FutureProvider<List<MissionPreset>>((ref) async {
  ref.watch(sessionUserIdProvider);
  try {
    return await ref.watch(missionsRepositoryProvider).listPresets();
  } on ApiException {
    return const [];
  }
});
