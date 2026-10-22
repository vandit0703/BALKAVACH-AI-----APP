import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../authentication/presentation/session_controller.dart';

/// Where the child is in today's learning workflow, as the server sees it.
enum LearningPhase {
  firstSession,
  missions,
  awaitingApproval,
  secondSession,
  complete,

  /// The daily video gate cannot be satisfied at all: no playback provider is
  /// configured on the server, or a parent switched video off for the family.
  videoUnavailable;

  static LearningPhase parse(String raw) => switch (raw) {
    'first_session' => LearningPhase.firstSession,
    'missions' => LearningPhase.missions,
    'awaiting_approval' => LearningPhase.awaitingApproval,
    'second_session' => LearningPhase.secondSession,
    'complete' => LearningPhase.complete,
    _ => LearningPhase.videoUnavailable,
  };
}

/// `LearningGatePublic` from `GET /api/v1/learning-gate/today`.
///
/// Every field is decided by the server. Nothing here may be computed, cached
/// past a refresh, or assumed by the app: an unlock the server did not grant is
/// not an unlock.
@immutable
class LearningGate {
  const LearningGate({
    required this.phase,
    required this.videoGateAvailable,
    required this.videoEnabled,
    required this.playbackConfigured,
    required this.firstSessionTargetSeconds,
    required this.secondSessionTargetSeconds,
    required this.dailyAllowanceSeconds,
    required this.watchedSecondsToday,
    required this.remainingAllowanceSeconds,
    required this.firstSessionComplete,
    required this.secondSessionComplete,
    required this.missionsUnlocked,
    required this.secondSessionUnlocked,
    required this.missionsAssigned,
    required this.missionsApproved,
    required this.missionsPendingApproval,
    required this.blockers,
  });

  factory LearningGate.fromJson(Map<String, dynamic> json) => LearningGate(
    phase: LearningPhase.parse(json['phase'] as String? ?? ''),
    videoGateAvailable: json['video_gate_available'] as bool? ?? false,
    videoEnabled: json['video_enabled'] as bool? ?? true,
    playbackConfigured: json['playback_configured'] as bool? ?? false,
    firstSessionTargetSeconds:
        json['first_session_target_seconds'] as int? ?? 0,
    secondSessionTargetSeconds:
        json['second_session_target_seconds'] as int? ?? 0,
    dailyAllowanceSeconds: json['daily_allowance_seconds'] as int? ?? 0,
    watchedSecondsToday: json['watched_seconds_today'] as int? ?? 0,
    remainingAllowanceSeconds: json['remaining_allowance_seconds'] as int? ?? 0,
    firstSessionComplete: json['first_session_complete'] as bool? ?? false,
    secondSessionComplete: json['second_session_complete'] as bool? ?? false,
    // Defaulting to *unlocked* is deliberate: a malformed or partial response
    // must never be the reason a child cannot reach their missions.
    missionsUnlocked: json['missions_unlocked'] as bool? ?? true,
    secondSessionUnlocked: json['second_session_unlocked'] as bool? ?? false,
    missionsAssigned: json['missions_assigned'] as int? ?? 0,
    missionsApproved: json['missions_approved'] as int? ?? 0,
    missionsPendingApproval: json['missions_pending_approval'] as int? ?? 0,
    blockers: [
      for (final blocker in (json['blockers'] as List<dynamic>? ?? const []))
        if (blocker is String) blocker,
    ],
  );

  final LearningPhase phase;
  final bool videoGateAvailable;
  final bool videoEnabled;
  final bool playbackConfigured;
  final int firstSessionTargetSeconds;
  final int secondSessionTargetSeconds;
  final int dailyAllowanceSeconds;
  final int watchedSecondsToday;
  final int remainingAllowanceSeconds;
  final bool firstSessionComplete;
  final bool secondSessionComplete;
  final bool missionsUnlocked;
  final bool secondSessionUnlocked;
  final int missionsAssigned;
  final int missionsApproved;
  final int missionsPendingApproval;
  final List<String> blockers;

  /// Progress towards the session the child is working on now, 0..1.
  ///
  /// Null while the gate is unavailable: there is no measured viewing time, and
  /// showing a bar that cannot move would misrepresent the child's progress.
  double? get sessionProgress {
    if (!videoGateAvailable) return null;
    final (done, target) = firstSessionComplete
        ? (
            watchedSecondsToday - firstSessionTargetSeconds,
            secondSessionTargetSeconds,
          )
        : (watchedSecondsToday, firstSessionTargetSeconds);
    if (target <= 0) return null;
    return (done / target).clamp(0.0, 1.0);
  }

  /// Seconds still needed in the session now in progress, never negative.
  int get secondsRemainingInSession {
    if (!videoGateAvailable) return 0;
    final target = firstSessionComplete
        ? firstSessionTargetSeconds + secondSessionTargetSeconds
        : firstSessionTargetSeconds;
    return (target - watchedSecondsToday).clamp(0, target);
  }
}

/// Verified contract: `app/api/v1/learning_gate.py` (child-only; the child is
/// taken from the validated session, never sent by the app).
class LearningGateRepository {
  LearningGateRepository(this._dio);

  final Dio _dio;

  Future<LearningGate> today() => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/learning-gate/today',
    );
    return LearningGate.fromJson(response.data ?? const {});
  });
}

final learningGateRepositoryProvider = Provider<LearningGateRepository>(
  (ref) => LearningGateRepository(ref.watch(apiDioProvider)),
);

/// Today's authoritative state. Re-read whenever the signed-in child changes so
/// a switched account never inherits the previous child's day.
final learningGateProvider = FutureProvider<LearningGate>((ref) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(learningGateRepositoryProvider).today();
});
