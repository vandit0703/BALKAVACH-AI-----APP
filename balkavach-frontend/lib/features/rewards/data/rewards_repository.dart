import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/json_utils.dart';
import '../../authentication/presentation/session_controller.dart';

/// Reward kinds a parent can create in the app. `video_time` rewards unlock
/// hosted videos and are set up by an administrator, so they are not offered.
const kRewardTypes = [
  'custom',
  'gift',
  'book',
  'outdoor_activity',
  'screen_time',
];

/// `RewardPublic`.
@immutable
class Reward {
  const Reward({
    required this.id,
    required this.familyId,
    required this.name,
    required this.rewardType,
    required this.starCost,
    required this.isActive,
    this.description,
    this.maxUses,
  });

  factory Reward.fromJson(Map<String, dynamic> json) => Reward(
    id: json['id'] as String,
    familyId: json['family_id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    rewardType: json['reward_type'] as String,
    starCost: json['star_cost'] as int,
    maxUses: json['max_uses'] as int?,
    isActive: json['is_active'] as bool? ?? true,
  );

  final String id;
  final String familyId;
  final String name;
  final String? description;
  final String rewardType;
  final int starCost;
  final int? maxUses;
  final bool isActive;
}

/// `RedemptionPublic`, or `RedemptionDetailPublic` (adds the reward and child
/// names) when a parent lists a family's requests.
@immutable
class Redemption {
  const Redemption({
    required this.id,
    required this.rewardId,
    required this.starCost,
    required this.status,
    required this.requestedAt,
    this.reviewedAt,
    this.fulfilledAt,
    this.reviewNote,
    this.rewardName,
    this.childName,
    this.childId,
  });

  factory Redemption.fromJson(Map<String, dynamic> json) => Redemption(
    id: json['id'] as String,
    rewardId: json['reward_id'] as String,
    starCost: json['star_cost_at_request'] as int? ?? 0,
    status: json['status'] as String,
    requestedAt: DateTime.parse(json['requested_at'] as String),
    reviewedAt: json['reviewed_at'] == null
        ? null
        : DateTime.parse(json['reviewed_at'] as String),
    fulfilledAt: json['fulfilled_at'] == null
        ? null
        : DateTime.parse(json['fulfilled_at'] as String),
    reviewNote: json['review_note'] as String?,
    rewardName: json['reward_name'] as String?,
    childName: json['child_name'] as String?,
    childId: json['child_id'] as String?,
  );

  final String id;
  final String rewardId;
  final String? childId;
  final int starCost;

  /// `pending`, `approved`, `rejected`, `fulfilled` or `cancelled`.
  final String status;
  final DateTime requestedAt;
  final DateTime? reviewedAt;
  final DateTime? fulfilledAt;
  final String? reviewNote;
  final String? rewardName;
  final String? childName;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
}

/// Input for creating or editing a reward.
@immutable
class RewardInput {
  const RewardInput({
    required this.name,
    required this.rewardType,
    required this.starCost,
    this.description,
  });

  final String name;
  final String rewardType;
  final int starCost;
  final String? description;

  String? get _description {
    final trimmed = description?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Map<String, dynamic> toCreateJson(String familyId) => {
    'family_id': familyId,
    'name': name.trim(),
    'reward_type': rewardType,
    'star_cost': starCost,
    'description': ?_description,
  };

  /// Sends every editable field, with `null` to clear the description.
  Map<String, dynamic> toPatchJson() => {
    'name': name.trim(),
    'star_cost': starCost,
    'description': _description,
  };
}

/// A random key that identifies one *intent* to redeem. Re-sending the same
/// key (a retry after a lost response) returns the original request instead of
/// creating a second one.
String newIdempotencyKey([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return 'redeem-$hex';
}

/// Verified contract: `app/api/v1/rewards.py`.
class RewardsRepository {
  RewardsRepository(this._dio);

  final Dio _dio;

  // ---- child ----------------------------------------------------------------

  /// `GET /api/v1/rewards` as a child: the active rewards of the child's own
  /// family.
  Future<List<Reward>> childCatalog() => guardApi(() async {
    final response = await _dio.get<List<dynamic>>(
      '/api/v1/rewards',
      queryParameters: {'limit': 100},
    );
    return parseJsonList(response.data, Reward.fromJson);
  });

  /// `GET /api/v1/redemptions/mine` (child), newest first.
  Future<List<Redemption>> myRedemptions() => guardApi(() async {
    final response = await _dio.get<List<dynamic>>(
      '/api/v1/redemptions/mine',
      queryParameters: {'limit': 50},
    );
    return parseJsonList(response.data, Redemption.fromJson);
  });

  /// `POST /api/v1/redemptions` (child). 409 `insufficient_stars`,
  /// `redemption_pending`, `reward_unavailable`.
  Future<Redemption> requestReward(String rewardId, String idempotencyKey) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/v1/redemptions',
          data: {'reward_id': rewardId},
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return Redemption.fromJson(response.data!);
      });

  /// `POST /api/v1/redemptions/{id}/cancel/mine` (child, pending only).
  Future<Redemption> cancelMine(String redemptionId) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/redemptions/$redemptionId/cancel/mine',
    );
    return Redemption.fromJson(response.data!);
  });

  // ---- parent ---------------------------------------------------------------

  /// `GET /api/v1/rewards?family_id=` (parent).
  Future<List<Reward>> familyRewards(String familyId) => guardApi(() async {
    final response = await _dio.get<List<dynamic>>(
      '/api/v1/rewards',
      queryParameters: {'family_id': familyId, 'limit': 100},
    );
    return parseJsonList(response.data, Reward.fromJson);
  });

  /// `POST /api/v1/rewards` (parent).
  Future<Reward> createReward(String familyId, RewardInput input) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/v1/rewards',
          data: input.toCreateJson(familyId),
        );
        return Reward.fromJson(response.data!);
      });

  /// `PATCH /api/v1/rewards/{id}` (parent).
  Future<Reward> updateReward(String rewardId, RewardInput input) =>
      guardApi(() async {
        final response = await _dio.patch<Map<String, dynamic>>(
          '/api/v1/rewards/$rewardId',
          data: input.toPatchJson(),
        );
        return Reward.fromJson(response.data!);
      });

  /// `DELETE /api/v1/rewards/{id}` (parent): hides it from children; past
  /// requests keep their record.
  Future<void> removeReward(String rewardId) => guardApi(() async {
    await _dio.delete<void>('/api/v1/rewards/$rewardId');
  });

  /// `GET /api/v1/redemptions?family_id=&status=` (parent), newest first.
  Future<List<Redemption>> familyRedemptions(
    String familyId, {
    String? status,
  }) => guardApi(() async {
    final response = await _dio.get<List<dynamic>>(
      '/api/v1/redemptions',
      queryParameters: {'family_id': familyId, 'status': ?status, 'limit': 100},
    );
    return parseJsonList(response.data, Redemption.fromJson);
  });

  /// `POST /api/v1/redemptions/{id}/approve` (parent): deducts the stars.
  Future<Redemption> approve(String redemptionId, {String? note}) =>
      _review(redemptionId, 'approve', note);

  /// `POST /api/v1/redemptions/{id}/reject` (parent): stars are untouched.
  Future<Redemption> reject(String redemptionId, {String? note}) =>
      _review(redemptionId, 'reject', note);

  Future<Redemption> _review(String id, String action, String? note) =>
      guardApi(() async {
        final trimmed = note?.trim();
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/v1/redemptions/$id/$action',
          data: {
            if (trimmed != null && trimmed.isNotEmpty) 'review_note': trimmed,
          },
        );
        return Redemption.fromJson(response.data!);
      });

  /// `POST /api/v1/redemptions/{id}/fulfill` (parent, approved only).
  Future<Redemption> fulfill(String redemptionId) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/redemptions/$redemptionId/fulfill',
    );
    return Redemption.fromJson(response.data!);
  });

  /// `POST /api/v1/redemptions/{id}/cancel` (parent): an approved request
  /// refunds its stars once.
  Future<Redemption> cancelAsParent(String redemptionId) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/redemptions/$redemptionId/cancel',
    );
    return Redemption.fromJson(response.data!);
  });
}

final rewardsRepositoryProvider = Provider<RewardsRepository>(
  (ref) => RewardsRepository(ref.watch(apiDioProvider)),
);

final myRedemptionsProvider = FutureProvider<List<Redemption>>((ref) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(rewardsRepositoryProvider).myRedemptions();
});

/// What the signed-in child can ask for.
final childCatalogProvider = FutureProvider<List<Reward>>((ref) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(rewardsRepositoryProvider).childCatalog();
});

final familyRewardsProvider = FutureProvider.family<List<Reward>, String>((
  ref,
  familyId,
) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(rewardsRepositoryProvider).familyRewards(familyId);
});

/// Requests still waiting for, or awaiting hand-over by, this parent.
final familyRedemptionsProvider =
    FutureProvider.family<List<Redemption>, String>((ref, familyId) async {
      ref.watch(sessionUserIdProvider);
      final repository = ref.watch(rewardsRepositoryProvider);
      final results = await Future.wait([
        repository.familyRedemptions(familyId, status: 'pending'),
        repository.familyRedemptions(familyId, status: 'approved'),
      ]);
      // A request approved between the two calls would otherwise appear
      // twice; keep one entry per id, preferring the later (approved) state.
      final byId = <String, Redemption>{};
      for (final redemption in [...results[0], ...results[1]]) {
        byId[redemption.id] = redemption;
      }
      return byId.values.toList();
    });

/// Number of requests waiting for a decision, or `null` while unknown.
final pendingRedemptionCountProvider = Provider.family<int?, String>((
  ref,
  familyId,
) {
  final redemptions = ref.watch(familyRedemptionsProvider(familyId)).value;
  return redemptions?.where((r) => r.isPending).length;
});
