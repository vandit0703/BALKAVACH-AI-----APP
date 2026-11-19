import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';

/// What the server said about one playback progress report.
enum PlaybackVerdict {
  /// Time remains (or one report failed but is not yet worth interrupting for).
  ok,

  /// The server says today's video time is used up. Stop and show the lock.
  exhausted,

  /// Reports keep failing. Playback is paused: unverified time is never free.
  offline,

  /// The session is no longer valid; the app's auth handling takes over.
  signedOut,
}

/// The low-time warning threshold. Same value as the server's
/// `LOW_TIME_THRESHOLD_SECONDS` (roadmap Phase 3: "≤2 min").
const kVideoLowTimeSeconds = 120;

class PlaybackReport {
  const PlaybackReport(
    this.verdict, {
    this.remainingSeconds,
    this.lowTime = false,
  });

  final PlaybackVerdict verdict;

  /// Server-reported remaining seconds, when the server answered.
  final int? remainingSeconds;

  /// This report is the one that took the remaining time down to
  /// [kVideoLowTimeSeconds] or less: show the "nearly done" warning once.
  final bool lowTime;
}

/// Interprets progress reports. It never measures or grants time itself: the
/// only authority is the backend's answer; this just decides when silence from
/// the backend means playback must stop.
class PlaybackGuard {
  PlaybackGuard({this.maxConsecutiveFailures = 2, this.onLowTime})
    : assert(maxConsecutiveFailures >= 1);

  /// Failed reports in a row before playback is paused. With reports every 10
  /// seconds this bounds unverified playback to roughly 20-30 seconds.
  final int maxConsecutiveFailures;

  /// Called once per crossing of [kVideoLowTimeSeconds], with the server's
  /// remaining seconds. Re-armed only when the server reports more than the
  /// threshold again (a new parent-approved grant, or a new day), so several
  /// videos, Shorts pages or background/resume cycles never repeat it.
  final void Function(int remainingSeconds)? onLowTime;

  int _failures = 0;
  bool _lowTimeWarned = false;

  int get consecutiveFailures => _failures;

  bool _checkLowTime(int? remaining) {
    if (remaining == null) return false;
    if (remaining > kVideoLowTimeSeconds) {
      _lowTimeWarned = false;
      return false;
    }
    if (remaining <= 0 || _lowTimeWarned) return false;
    _lowTimeWarned = true;
    onLowTime?.call(remaining);
    return true;
  }

  /// Sends one report through [send] and classifies the outcome.
  Future<PlaybackReport> report(
    Future<Map<String, dynamic>?> Function() send,
  ) async {
    try {
      final data = await send();
      _failures = 0;
      final remaining = data?['remaining_allowance_seconds'];
      final remainingSeconds = remaining is num ? remaining.toInt() : null;
      if (data != null && data['is_exhausted'] == true) {
        _lowTimeWarned = false; // only a new grant can follow: warn again then
        return const PlaybackReport(
          PlaybackVerdict.exhausted,
          remainingSeconds: 0,
        );
      }
      return PlaybackReport(
        PlaybackVerdict.ok,
        remainingSeconds: remainingSeconds,
        lowTime: _checkLowTime(remainingSeconds),
      );
    } on UnauthorizedException {
      return const PlaybackReport(PlaybackVerdict.signedOut);
    } on ForbiddenException {
      // The server refused the report: no time left, or the video is no
      // longer allowed for this child. Either way playback must stop.
      _failures = 0;
      _lowTimeWarned = false;
      return const PlaybackReport(
        PlaybackVerdict.exhausted,
        remainingSeconds: 0,
      );
    } on ApiException {
      // Network loss, timeout, or a server error: nothing was verified.
      _failures++;
      return PlaybackReport(
        _failures >= maxConsecutiveFailures
            ? PlaybackVerdict.offline
            : PlaybackVerdict.ok,
      );
    }
  }

  void reset() => _failures = 0;
}

/// One "nearly out of video time" moment, for the app-wide notice.
@immutable
class LowTimeNotice {
  const LowTimeNotice({required this.remainingSeconds, required this.serial});

  final int remainingSeconds;

  /// Distinguishes two notices with the same figure.
  final int serial;

  /// Whole minutes, rounded up (95 s is "about 2 minutes").
  int get minutes => (remainingSeconds / 60).ceil().clamp(1, 2);
}

class LowTimeNoticeController extends Notifier<LowTimeNotice?> {
  @override
  LowTimeNotice? build() => null;

  void show(int remainingSeconds) => state = LowTimeNotice(
    remainingSeconds: remainingSeconds,
    serial: (state?.serial ?? 0) + 1,
  );
}

/// The latest low-time notice. The app shell shows it, wherever the child is.
final lowTimeNoticeProvider =
    NotifierProvider<LowTimeNoticeController, LowTimeNotice?>(
      LowTimeNoticeController.new,
    );

/// One guard for the whole app session, so failures count across pages (a
/// child swiping through Shorts offline cannot dodge the limit by changing
/// page), and the low-time warning is shown once across videos.
final playbackGuardProvider = Provider<PlaybackGuard>(
  (ref) => PlaybackGuard(
    onLowTime: (seconds) =>
        ref.read(lowTimeNoticeProvider.notifier).show(seconds),
  ),
);
