import 'package:flutter/foundation.dart';

import '../../../core/storage/app_preferences.dart';
import 'progress_repository.dart';

enum MilestoneKind { level, badge }

/// A level-up or an unlocked badge the child has not been celebrated for.
@immutable
class Milestone {
  const Milestone.level({required int number, String? name})
    : kind = MilestoneKind.level,
      id = 'level:$number',
      levelNumber = number,
      title = name,
      unlockedAt = null;

  Milestone.badge(EarnedBadge badge)
    : kind = MilestoneKind.badge,
      id = badge.id,
      levelNumber = null,
      title = badge.name,
      unlockedAt = badge.unlockedAt;

  final MilestoneKind kind;
  final String id;
  final int? levelNumber;

  /// The level's name or the badge's name, as the server sent it.
  final String? title;
  final DateTime? unlockedAt;
}

/// What this device remembers, per child, about level-ups and badges it has
/// already shown. The server decides the level and which badges are earned
/// (`GET /progress/children/{id}`); the device only records what it showed.
///
/// Same rules as the mission-approval celebration: the first look at a child's
/// progress is a silent baseline (history is not news), an entry is recorded
/// only after the child dismissed its celebration (so an interrupted one comes
/// back), and a reopened screen or restart never replays a consumed one.
class MilestoneStore {
  MilestoneStore(this._prefs);

  final AppPreferences _prefs;

  static const maxBadgesRemembered = 300;

  bool baselineDone(String childId) => _prefs.levelSeen(childId) != null;

  Future<void> recordBaseline(String childId, ChildProgress progress) async {
    await _prefs.setBadgesSeen(childId, [
      for (final badge in progress.badges) badge.id,
    ]);
    await _prefs.setLevelSeen(childId, progress.levelNumber ?? 0);
  }

  Future<void> markLevelSeen(String childId, int level) async {
    final seen = _prefs.levelSeen(childId) ?? 0;
    if (level > seen) await _prefs.setLevelSeen(childId, level);
  }

  Future<void> markBadgeSeen(String childId, String badgeId) async {
    final ids = {..._prefs.badgesSeen(childId), badgeId}.toList();
    final kept = ids.length > maxBadgesRemembered
        ? ids.sublist(ids.length - maxBadgesRemembered)
        : ids;
    await _prefs.setBadgesSeen(childId, kept);
  }

  /// A level-up first (every child starts at Level 1, so reaching it is not
  /// one), then new badges oldest first.
  List<Milestone> pending(String childId, ChildProgress progress) {
    final result = <Milestone>[];
    final level = progress.levelNumber;
    final seen = _prefs.levelSeen(childId) ?? 0;
    if (level != null && level > seen && level > 1) {
      result.add(Milestone.level(number: level, name: progress.levelName));
    }
    final done = _prefs.badgesSeen(childId).toSet();
    final unseen = <String>{};
    final badges = [
      for (final badge in progress.badges)
        if (!done.contains(badge.id) && unseen.add(badge.id)) badge,
    ]..sort((a, b) => a.unlockedAt.compareTo(b.unlockedAt));
    result.addAll(badges.map(Milestone.badge));
    return result;
  }

  /// Level 1 is the starting level: remember it without a celebration so a
  /// child's first level-up is Level 2.
  Future<void> acknowledgeStartingLevel(
    String childId,
    ChildProgress progress,
  ) async {
    final level = progress.levelNumber;
    if (level != null && level <= 1) await markLevelSeen(childId, level);
  }
}
