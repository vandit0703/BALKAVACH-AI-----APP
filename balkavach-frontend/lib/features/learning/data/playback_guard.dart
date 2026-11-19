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

class PlaybackReport {
  const PlaybackReport(this.verdict, {this.remainingSeconds});

  final PlaybackVerdict verdict;

  /// Server-reported remaining seconds, when the server answered.
  final int? remainingSeconds;
}

/// Interprets progress reports. It never measures or grants time itself: the
/// only authority is the backend's answer; this just decides when silence from
/// the backend means playback must stop.
class PlaybackGuard {
  PlaybackGuard({this.maxConsecutiveFailures = 2})
    : assert(maxConsecutiveFailures >= 1);

  /// Failed reports in a row before playback is paused. With reports every 10
  /// seconds this bounds unverified playback to roughly 20-30 seconds.
  final int maxConsecutiveFailures;

  int _failures = 0;

  int get consecutiveFailures => _failures;

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
        return const PlaybackReport(
          PlaybackVerdict.exhausted,
          remainingSeconds: 0,
        );
      }
      return PlaybackReport(
        PlaybackVerdict.ok,
        remainingSeconds: remainingSeconds,
      );
    } on UnauthorizedException {
      return const PlaybackReport(PlaybackVerdict.signedOut);
    } on ForbiddenException {
      // The server refused the report: no time left, or the video is no
      // longer allowed for this child. Either way playback must stop.
      _failures = 0;
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

/// One guard for the whole app session, so failures count across pages (a
/// child swiping through Shorts offline cannot dodge the limit by changing
/// page).
final playbackGuardProvider = Provider<PlaybackGuard>((ref) => PlaybackGuard());
