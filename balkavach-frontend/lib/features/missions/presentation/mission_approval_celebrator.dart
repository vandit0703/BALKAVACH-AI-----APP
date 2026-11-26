import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_preferences.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/celebration/activity_completion.dart';
import '../../../shared/celebration/celebration_queue.dart';
import '../../../shared/celebration/panda_celebration.dart';
import '../../learning/data/video_feed_repository.dart'
    show videoAllowanceProvider;
import '../../progress/data/progress_repository.dart';
import '../../progress/presentation/progress_milestone_celebrator.dart';
import '../data/approval_celebration_store.dart';
import '../domain/mission_models.dart';
import 'mission_providers.dart';

final approvalCelebrationStoreProvider = Provider<ApprovalCelebrationStore>(
  (ref) => ApprovalCelebrationStore(ref.watch(appPreferencesProvider)),
);

/// Celebrates a mission the moment the child learns it was approved AND the
/// server confirms its Stars/XP. It reuses the shared [PandaCelebration] and
/// computes nothing: the amounts shown are the server's
/// (`stars_awarded` / `xp_awarded` on `GET /tasks/submissions/mine`).
///
/// It looks at the child's attempts when the child area opens, whenever that
/// list reloads, and when the app returns from the background (a parent may
/// have approved while the app was closed). Duplicate prevention is the
/// durable [ApprovalCelebrationStore]; the `_busy` flag below only stops two
/// celebrations from overlapping on screen.
class MissionApprovalCelebrator extends ConsumerStatefulWidget {
  const MissionApprovalCelebrator({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<MissionApprovalCelebrator> createState() =>
      _MissionApprovalCelebratorState();
}

class _MissionApprovalCelebratorState
    extends ConsumerState<MissionApprovalCelebrator>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _again = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_check());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Approved while the app was closed or in the background.
      ref.invalidate(mySubmissionsProvider);
    }
  }

  /// Handles the newest list from the server. Re-entrant calls (the list
  /// reloading while a celebration is open) are coalesced into one more pass.
  Future<void> _check() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _pass();
      } while (_again && mounted);
    } finally {
      _busy = false;
    }
  }

  Future<void> _pass() async {
    final childId = ref.read(activeChildIdProvider);
    if (childId == null) return;
    final List<TaskSubmission> submissions;
    try {
      submissions = await ref.read(mySubmissionsProvider.future);
    } on Object {
      return; // Offline or failed: nothing is known, so nothing is celebrated.
    }
    if (!mounted) return;
    final store = ref.read(approvalCelebrationStoreProvider);
    if (!store.baselineDone(childId)) {
      await store.recordBaseline(childId, submissions);
      return;
    }
    var celebrated = false;
    final approvals = store.pending(childId, submissions).toList();
    if (approvals.isNotEmpty) {
      // Each approval also unlocked video time on the server: reload the
      // balance now (not after the celebration), so Home and the players
      // stop showing a stale lock without a sign-out or a push.
      ref
        ..invalidate(childNotificationsProvider)
        ..invalidate(videoAllowanceProvider);
    }
    for (final approval in approvals) {
      if (!mounted) return;
      // One celebration at a time across the whole app (approvals, level-ups,
      // badges), in the order they were detected.
      await ref.read(celebrationQueueProvider).run(() async {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context);
        await showPandaCelebration(
          context,
          ActivityCompletion(
            kind: ActivityKind.mission,
            headline: l10n.celebrationMissionApproved,
            title: approval.title,
            stars: approval.stars,
            xp: approval.xp,
            note: l10n.celebrationMissionApprovedNote,
          ),
        );
        // Recorded only once the child has seen it. If the app was killed
        // before this line, the celebration is shown again next time.
        await store.markCelebrated(childId, approval.submissionId);
        celebrated = true;
      });
    }
    if (celebrated && mounted) {
      // An approval pays XP: look at the level and badges it may have moved.
      ref
        ..invalidate(childProgressProvider(childId))
        ..invalidate(achievementsProvider(childId));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(mySubmissionsProvider, (_, next) {
      if (next is AsyncData) unawaited(_check());
    });
    // Level-ups and badges are celebrated by the sibling watcher, through the
    // same queue, so mounting this once covers all child-area celebrations.
    return ProgressMilestoneCelebrator(child: widget.child);
  }
}
