import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_preferences.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/celebration/activity_completion.dart';
import '../../../shared/celebration/celebration_queue.dart';
import '../../../shared/celebration/panda_celebration.dart';
import '../../missions/presentation/mission_providers.dart';
import '../data/milestone_store.dart';
import '../data/progress_repository.dart';

final milestoneStoreProvider = Provider<MilestoneStore>(
  (ref) => MilestoneStore(ref.watch(appPreferencesProvider)),
);

/// Celebrates a level-up and newly unlocked badges, reusing the shared
/// [PandaCelebration]. The level and the badges are the server's
/// (`GET /progress/children/{id}`); the durable [MilestoneStore] makes each
/// one play once. Celebrations go through the shared queue, so they never
/// overlap a mission-approval celebration.
class ProgressMilestoneCelebrator extends ConsumerStatefulWidget {
  const ProgressMilestoneCelebrator({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ProgressMilestoneCelebrator> createState() =>
      _ProgressMilestoneCelebratorState();
}

class _ProgressMilestoneCelebratorState
    extends ConsumerState<ProgressMilestoneCelebrator>
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
    final childId = ref.read(activeChildIdProvider);
    if (state == AppLifecycleState.resumed && childId != null) {
      ref.invalidate(childProgressProvider(childId));
    }
  }

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
    final ChildProgress progress;
    try {
      progress = await ref.read(childProgressProvider(childId).future);
    } on Object {
      return; // Unknown progress is never celebrated.
    }
    if (!mounted) return;
    final store = ref.read(milestoneStoreProvider);
    if (!store.baselineDone(childId)) {
      await store.recordBaseline(childId, progress);
      return;
    }
    await store.acknowledgeStartingLevel(childId, progress);
    for (final milestone in store.pending(childId, progress)) {
      if (!mounted) return;
      await ref.read(celebrationQueueProvider).run(() async {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context);
        final isLevel = milestone.kind == MilestoneKind.level;
        final level = milestone.levelNumber;
        await showPandaCelebration(
          context,
          ActivityCompletion(
            kind: ActivityKind.garden,
            headline: isLevel ? l10n.celebrationLevelUp : l10n.celebrationBadge,
            title: isLevel
                ? [
                    l10n.childLevel(level!),
                    if (milestone.title != null) milestone.title!,
                  ].join(' · ')
                : milestone.title ?? '',
          ),
        );
        // Recorded only after the child has seen it.
        if (isLevel) {
          await store.markLevelSeen(childId, level!);
        } else {
          await store.markBadgeSeen(childId, milestone.id);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final childId = ref.watch(activeChildIdProvider);
    if (childId != null) {
      ref.listen(childProgressProvider(childId), (_, next) {
        if (next is AsyncData) unawaited(_check());
      });
    }
    return widget.child;
  }
}
