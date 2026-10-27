import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/json_utils.dart';
import '../../authentication/presentation/session_controller.dart';

/// `VideoCategoryPublic`.
@immutable
class LearningCategory {
  const LearningCategory({
    required this.id,
    required this.name,
    required this.slug,
  });

  factory LearningCategory.fromJson(Map<String, dynamic> json) =>
      LearningCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
      );

  final String id;
  final String name;
  final String slug;
}

/// `EducationalContentPublic`: something an administrator chose for children.
@immutable
class LearningItem {
  const LearningItem({
    required this.id,
    required this.title,
    required this.contentType,
    required this.requiresEntitlement,
    this.description,
    this.categoryId,
    this.contentUrl,
    this.thumbnailUrl,
    this.videoId,
    this.collectionId,
  });

  factory LearningItem.fromJson(Map<String, dynamic> json) => LearningItem(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    contentType: json['content_type'] as String,
    categoryId: json['category_id'] as String?,
    contentUrl: json['content_url'] as String?,
    thumbnailUrl: json['thumbnail_url'] as String?,
    videoId: json['video_id'] as String?,
    collectionId: json['collection_id'] as String?,
    requiresEntitlement: json['requires_entitlement'] as bool? ?? false,
  );

  final String id;
  final String title;
  final String? description;

  /// `video`, `article`, `link`, `document` or `activity`.
  final String contentType;
  final String? categoryId;
  final String? contentUrl;
  final String? thumbnailUrl;
  final String? videoId;
  final String? collectionId;
  final bool requiresEntitlement;

  /// The link the child may open: only `https`, and only when the server sent
  /// one (hosted videos and reward-gated items never carry a link here).
  Uri? get openableUri {
    final raw = contentUrl;
    if (raw == null) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }

  bool get isHosted => videoId != null || collectionId != null;

  bool get isYouTubeLink {
    final host = openableUri?.host.toLowerCase();
    if (host == null) return false;
    return host == 'youtu.be' ||
        host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtube-nocookie.com' ||
        host.endsWith('.youtube-nocookie.com');
  }

  /// Whether this item can be played by the in-app player.
  ///
  /// Only an admin-curated direct link qualifies. Hosted and entitlement-gated
  /// videos deliberately arrive without a URL: they must go through the
  /// authorised playback-session API, which needs a configured provider, so
  /// they are never played here.
  bool get isPlayableInApp =>
      contentType == 'video' &&
      !requiresEntitlement &&
      !isHosted &&
      openableUri != null &&
      !isYouTubeLink;
}

/// Verified contracts: `app/api/v1/educational_content.py` and
/// `GET /videos/categories` (both child-only).
class LearningRepository {
  LearningRepository(this._dio);

  final Dio _dio;

  Future<List<LearningItem>> list({int limit = 30, int offset = 0}) =>
      guardApi(() async {
        final response = await _dio.get<List<dynamic>>(
          '/api/v1/educational-content',
          queryParameters: {'limit': limit, 'offset': offset},
        );
        return parseJsonList(response.data, LearningItem.fromJson);
      });

  Future<List<LearningCategory>> categories() => guardApi(() async {
    final response = await _dio.get<List<dynamic>>('/api/v1/videos/categories');
    return parseJsonList(response.data, LearningCategory.fromJson);
  });
}

final learningRepositoryProvider = Provider<LearningRepository>(
  (ref) => LearningRepository(ref.watch(apiDioProvider)),
);

/// First page (up to 30 items) for the signed-in child.
final learningItemsProvider = FutureProvider<List<LearningItem>>((ref) {
  ref.watch(sessionUserIdProvider);
  return ref.watch(learningRepositoryProvider).list();
});

/// Categories are decoration: if they fail to load the list still works.
final learningCategoriesProvider = FutureProvider<List<LearningCategory>>((
  ref,
) async {
  ref.watch(sessionUserIdProvider);
  try {
    return await ref.watch(learningRepositoryProvider).categories();
  } on ApiException {
    return const [];
  }
});
