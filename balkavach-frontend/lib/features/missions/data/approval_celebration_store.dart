import 'package:flutter/foundation.dart';

import '../../../core/storage/app_preferences.dart';
import '../domain/mission_models.dart';

/// A mission approval the child has not been celebrated for yet. Every field
/// comes from the server's record of the submission.
@immutable
class NewApproval {
  const NewApproval({
    required this.submissionId,
    required this.title,
    required this.stars,
    required this.xp,
  });

  final String submissionId;
  final String title;
  final int stars;
  final int xp;
}

/// What the device remembers, per child, about approvals it already handled.
///
/// The server decides what was approved and what was paid
/// (`GET /tasks/submissions/mine`, amounts read from the ledgers). The device
/// only remembers which submission ids it has already celebrated, so a
/// celebration plays at most once per approved submission, across screen
/// refreshes, app restarts and rebuilds. An id is recorded only AFTER the child
/// has dismissed its celebration: if the app is closed first, the celebration
/// is simply shown again next time and is never lost.
class ApprovalCelebrationStore {
  ApprovalCelebrationStore(this._prefs);

  final AppPreferences _prefs;

  /// More than the server will ever list (3 pages of 100), so an id never
  /// drops out while its submission can still be returned.
  static const maxRemembered = 600;

  Set<String> consumed(String childId) =>
      _prefs.celebratedSubmissionIds(childId).toSet();

  /// False until the first look at this child's list on this device.
  bool baselineDone(String childId) => _prefs.approvalBaselineDone(childId);

  Future<void> _write(String childId, Iterable<String> ids) {
    final list = ids.toList();
    final kept = list.length > maxRemembered
        ? list.sublist(list.length - maxRemembered)
        : list;
    return _prefs.setCelebratedSubmissionIds(childId, kept);
  }

  /// The first time a child's approvals are seen on a device, everything
  /// already approved is history, not news: remember it without celebrating,
  /// so installing this feature never replays old missions.
  Future<void> recordBaseline(
    String childId,
    List<TaskSubmission> submissions,
  ) async {
    final ids = [
      ..._prefs.celebratedSubmissionIds(childId),
      for (final s in submissions)
        if (s.status == 'approved') s.id,
    ];
    await _write(childId, {...ids});
    await _prefs.setApprovalBaselineDone(childId);
  }

  Future<void> markCelebrated(String childId, String submissionId) => _write(
    childId,
    {..._prefs.celebratedSubmissionIds(childId), submissionId},
  );

  /// Approvals that are new AND whose reward the server confirms, oldest
  /// first. Anything else is ignored:
  ///
  /// * not `approved` (pending, rejected, resubmission, cancelled),
  /// * already consumed (reopened mission, restart, duplicate rows),
  /// * approved but the server reports no Stars/XP for it (missing or zero
  ///   reward data). Those are left unconsumed, so they celebrate if and when
  ///   the server confirms a reward, and never before.
  List<NewApproval> pending(String childId, List<TaskSubmission> submissions) {
    final done = consumed(childId);
    final seen = <String>{};
    final approvals = <TaskSubmission>[];
    for (final s in submissions) {
      if (s.status != 'approved') continue;
      if (done.contains(s.id) || !seen.add(s.id)) continue;
      final stars = s.starsAwarded ?? 0;
      final xp = s.xpAwarded ?? 0;
      if (stars <= 0 && xp <= 0) continue;
      approvals.add(s);
    }
    approvals.sort((a, b) {
      final left = a.reviewedAt ?? a.submittedAt;
      final right = b.reviewedAt ?? b.submittedAt;
      return left.compareTo(right);
    });
    return [
      for (final s in approvals)
        NewApproval(
          submissionId: s.id,
          title: s.taskTitle ?? '',
          stars: s.starsAwarded ?? 0,
          xp: s.xpAwarded ?? 0,
        ),
    ];
  }
}
