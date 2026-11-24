import 'package:flutter/foundation.dart';

/// The kinds of activity the Panda celebrates.
enum ActivityKind { mission, quiz, video, story, garden }

/// What a finished activity looks like to the celebration: a plain description
/// of something that already happened.
///
/// This is presentation data only. [stars] and [xp] are what the *server*
/// already paid for this activity (zero when it paid nothing, such as a
/// retake, a mission still waiting for a parent, a video or a story). Showing
/// a celebration never grants anything, and no screen computes a reward to
/// put here.
@immutable
class ActivityCompletion {
  const ActivityCompletion({
    required this.kind,
    required this.title,
    this.stars = 0,
    this.xp = 0,
    this.note,
    this.headline,
    this.offerHome = false,
  }) : assert(stars >= 0 && xp >= 0, 'rewards are never negative');

  final ActivityKind kind;

  /// The activity's name: the quiz, mission, video or story title.
  final String title;
  final int stars;
  final int xp;

  /// A line that replaces the generic encouragement, already localised.
  final String? note;

  /// Replaces the kind's default headline (already localised).
  final String? headline;

  /// Adds a "Back to Home" action next to Continue.
  final bool offerHome;

  bool get hasRewards => stars > 0 || xp > 0;
}
