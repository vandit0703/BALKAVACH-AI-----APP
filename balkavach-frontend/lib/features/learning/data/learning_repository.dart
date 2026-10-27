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

  /// The 11-character video id in a YouTube link, or null when the link is not
  /// a single YouTube video (a channel, playlist or search page, for example).
  ///
  /// Accepts `youtube.com/watch?v=`, `youtu.be/<id>` and the `/embed/`,
  /// `/shorts/`, `/live/` and `/v/` paths, on www, m and nocookie hosts.
  String? get youtubeVideoId {
    final uri = openableUri;
    if (uri == null || !isYouTubeLink) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final String? candidate;
    if (uri.host.toLowerCase() == 'youtu.be') {
      candidate = segments.firstOrNull;
    } else if (segments.length == 1 && segments.first == 'watch') {
      candidate = uri.queryParameters['v'];
    } else if (segments.length >= 2 &&
        const {'embed', 'shorts', 'live', 'v'}.contains(segments.first)) {
      candidate = segments[1];
    } else {
      candidate = null;
    }
    return candidate != null && _youtubeIdPattern.hasMatch(candidate)
        ? candidate
        : null;
  }

  bool get _isFreeCuratedVideo =>
      contentType == 'video' && !requiresEntitlement && !isHosted;

  /// Whether this item can be played by the native in-app player.
  ///
  /// Only an admin-curated direct link qualifies. Hosted and entitlement-gated
  /// videos deliberately arrive without a URL: they must go through the
  /// authorised playback-session API, which needs a configured provider, so
  /// they are never played here. A YouTube link is a web page, not a media
  /// stream, so it never reaches the native player either.
  bool get isPlayableInApp =>
      _isFreeCuratedVideo && openableUri != null && !isYouTubeLink;

  /// Whether this item is a curated YouTube video the official embedded
  /// player can show inside the app.
  bool get isYouTubeEmbeddable => _isFreeCuratedVideo && youtubeVideoId != null;

  /// Whether tapping this item plays it inside the app, in either player.
  bool get playsInApp => isPlayableInApp || isYouTubeEmbeddable;
}

final _youtubeIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

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
