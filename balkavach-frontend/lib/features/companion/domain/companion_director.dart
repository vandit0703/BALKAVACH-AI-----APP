import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';

/// Moments Panda can comment on. Chosen by the app from real state (missions,
/// allowance); Panda never invents one and never calls a server per line.
enum CompanionEvent {
  greeting,
  greetingNamed,
  missionIntro,
  rewardExplain,
  missionsReady,
  missionSubmitted,
  missionApproved,
  videoUnlocked,
  videoLow,
  videoUp,
}

/// Authored lines per event, in every language. Two variants each for now so
/// the same line is not repeated back to back.
const kCompanionVariants = 2;

/// How Panda looks while saying a line. Drives the animation only.
enum PandaMood { talking, celebrating, sleepy }

/// The mood that fits [event]: cheering for good news, drowsy when the video
/// time is over, otherwise just chatting.
PandaMood pandaMoodFor(CompanionEvent event) => switch (event) {
  CompanionEvent.missionApproved ||
  CompanionEvent.videoUnlocked => PandaMood.celebrating,
  CompanionEvent.videoUp => PandaMood.sleepy,
  _ => PandaMood.talking,
};

/// The text of one authored line. [minutes] fills the video-unlocked line,
/// [name] the personal greeting, [missionTitle] the mission introduction and
/// [stars] the reward explanation. The name only ever stays on the device.
String pandaLine(
  AppLocalizations l10n,
  CompanionEvent event,
  int variant, {
  int minutes = 15,
  String name = '',
  String missionTitle = '',
  int stars = 1,
}) {
  final first = variant % kCompanionVariants == 0;
  return switch (event) {
    CompanionEvent.greeting =>
      first ? l10n.pandaGreeting1 : l10n.pandaGreeting2,
    CompanionEvent.greetingNamed =>
      first ? l10n.pandaGreetingNamed1(name) : l10n.pandaGreetingNamed2(name),
    CompanionEvent.missionIntro =>
      first
          ? l10n.pandaMissionIntro1(missionTitle)
          : l10n.pandaMissionIntro2(missionTitle),
    CompanionEvent.rewardExplain =>
      first
          ? l10n.pandaRewardExplain1(stars)
          : l10n.pandaRewardExplain2(stars),
    CompanionEvent.missionsReady =>
      first ? l10n.pandaMissionsReady1 : l10n.pandaMissionsReady2,
    CompanionEvent.missionSubmitted =>
      first ? l10n.pandaMissionSubmitted1 : l10n.pandaMissionSubmitted2,
    CompanionEvent.missionApproved =>
      first ? l10n.pandaMissionApproved1 : l10n.pandaMissionApproved2,
    CompanionEvent.videoUnlocked =>
      first
          ? l10n.pandaVideoUnlocked1(minutes)
          : l10n.pandaVideoUnlocked2(minutes),
    CompanionEvent.videoLow =>
      first ? l10n.pandaVideoLow1 : l10n.pandaVideoLow2,
    CompanionEvent.videoUp => first ? l10n.pandaVideoUp1 : l10n.pandaVideoUp2,
  };
}

/// Decides which authored line to show, deterministically and without
/// nagging: never the same variant twice in a row for an event, and an event
/// that spoke recently stays quiet for [cooldown].
///
/// Pure Dart: the clock and the random source are injected, so it is fully
/// testable. Nothing here touches the network or personal data.
class CompanionDirector {
  CompanionDirector({
    DateTime Function()? now,
    Random? random,
    this.cooldown = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random();

  final DateTime Function() _now;
  final Random _random;

  /// How long an event stays quiet after speaking. [CompanionEvent.videoUp]
  /// and [CompanionEvent.videoUnlocked] are never throttled: they report a
  /// state change the child must see.
  final Duration cooldown;

  final _lastVariant = <CompanionEvent, int>{};
  final _lastSpoke = <CompanionEvent, DateTime>{};

  static const _alwaysSpeak = {
    CompanionEvent.videoUp,
    CompanionEvent.videoUnlocked,
  };

  /// The variant to show for [event], or `null` when it spoke too recently.
  int? next(CompanionEvent event) {
    final now = _now();
    final before = _lastSpoke[event];
    if (!_alwaysSpeak.contains(event) &&
        before != null &&
        now.difference(before) < cooldown) {
      return null;
    }
    final last = _lastVariant[event];
    var variant = _random.nextInt(kCompanionVariants);
    if (last != null && variant == last) {
      variant = (variant + 1) % kCompanionVariants;
    }
    _lastVariant[event] = variant;
    _lastSpoke[event] = now;
    return variant;
  }
}

/// One director for the whole app session.
final companionDirectorProvider = Provider<CompanionDirector>(
  (ref) => CompanionDirector(),
);
