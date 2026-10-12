import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../authentication/presentation/session_controller.dart';

/// `ProgressPublic` (badges and activity days are kept as counts for now).
@immutable
class ChildProgress {
  const ChildProgress({
    required this.childId,
    required this.starBalance,
    required this.totalXp,
    required this.currentStreak,
    required this.longestStreak,
    required this.badgeCount,
    this.levelNumber,
    this.levelName,
  });

  factory ChildProgress.fromJson(Map<String, dynamic> json) => ChildProgress(
    childId: json['child_id'] as String,
    starBalance: json['star_balance'] as int? ?? 0,
    totalXp: json['total_xp'] as int? ?? 0,
    levelNumber: json['level_number'] as int?,
    levelName: json['level_name'] as String?,
    currentStreak: json['current_streak'] as int? ?? 0,
    longestStreak: json['longest_streak'] as int? ?? 0,
    badgeCount: (json['badges'] as List<dynamic>? ?? const []).length,
  );

  final String childId;
  final int starBalance;
  final int totalXp;
  final int? levelNumber;
  final String? levelName;
  final int currentStreak;
  final int longestStreak;
  final int badgeCount;
}

/// Verified contract: `app/api/v1/progress.py`. Callable by the child itself
/// or a parent in the same family.
class ProgressRepository {
  ProgressRepository(this._dio);

  final Dio _dio;

  Future<ChildProgress> childProgress(String childId) => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/progress/children/$childId',
    );
    return ChildProgress.fromJson(response.data!);
  });
}

final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) => ProgressRepository(ref.watch(apiDioProvider)),
);

final childProgressProvider = FutureProvider.family<ChildProgress, String>((
  ref,
  childId,
) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(progressRepositoryProvider).childProgress(childId);
});
