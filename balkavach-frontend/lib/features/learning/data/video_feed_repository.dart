import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/json_utils.dart';

final _youtubeIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// `VideoFeedItem`: a video the server has already decided this child may see.
///
/// The app never decides eligibility. YouTube videos only appear here after an
/// administrator approved them and the server re-verified them with YouTube.
@immutable
class FeedVideo {
  const FeedVideo({
    required this.id,
    required this.title,
    required this.durationSeconds,
    required this.source,
    this.description,
    this.thumbnailUrl,
    this.categoryId,
    this.youtubeVideoId,
    this.channelName,
  });

  factory FeedVideo.fromJson(Map<String, dynamic> json) => FeedVideo(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    thumbnailUrl: json['thumbnail_url'] as String?,
    durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
    categoryId: json['category_id'] as String?,
    source: json['video_source'] as String? ?? 'hosted',
    youtubeVideoId: json['youtube_video_id'] as String?,
    channelName: json['channel_name'] as String?,
  );

  final String id;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final int durationSeconds;
  final String? categoryId;

  /// `hosted`, `youtube` or `external`.
  final String source;
  final String? youtubeVideoId;
  final String? channelName;

  /// Playable in the official YouTube embed: a YouTube item with a well-formed id.
  bool get isYouTube =>
      source == 'youtube' && _youtubeIdPattern.hasMatch(youtubeVideoId ?? '');
}

enum VideoFeedKind {
  learn('/api/v1/videos/feed'),
  shorts('/api/v1/videos/shorts');

  const VideoFeedKind(this.path);

  final String path;
}

/// Mirrors `ReportReason` in `app/schemas/video.py`.
enum VideoReportReason {
  inappropriate,
  scary,
  violent,
  misleading,
  advertising,
  other,
}

/// Verified contracts: `GET /videos/feed`, `GET /videos/shorts` (child-only)
/// and `POST /videos/report` (parent or child) in `app/api/v1/videos.py`.
class VideoFeedRepository {
  VideoFeedRepository(this._dio);

  final Dio _dio;

  Future<List<FeedVideo>> page(
    VideoFeedKind kind, {
    required int limit,
    required int offset,
  }) => guardApi(() async {
    final response = await _dio.get<List<dynamic>>(
      kind.path,
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return parseJsonList(response.data, FeedVideo.fromJson);
  });

  Future<void> report(
    String videoId,
    VideoReportReason reason, {
    String? details,
  }) => guardApi(() async {
    final trimmed = details?.trim();
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/videos/report',
      data: {
        'video_id': videoId,
        'reason': reason.name,
        if (trimmed != null && trimmed.isNotEmpty) 'details': trimmed,
      },
    );
  });
}

final videoFeedRepositoryProvider = Provider<VideoFeedRepository>(
  (ref) => VideoFeedRepository(ref.watch(apiDioProvider)),
);

enum PagerStatus { idle, loading, error, done }

/// Offset pagination for one feed, owned by the screen showing it.
///
/// Items are de-duplicated by YouTube ID when present, otherwise by the server
/// row ID. This prevents the same published video from appearing twice if
/// duplicate rows exist or a video shifts between pages.
class VideoFeedPager extends ChangeNotifier {
  VideoFeedPager(this._repository, this.kind, {this.pageSize = 20});

  final VideoFeedRepository _repository;
  final VideoFeedKind kind;
  final int pageSize;

  final List<FeedVideo> _items = [];
  final Set<String> _seen = {};
  int _offset = 0;
  PagerStatus _status = PagerStatus.idle;
  Object? _error;
  bool _disposed = false;

  List<FeedVideo> get items => List.unmodifiable(_items);
  PagerStatus get status => _status;
  Object? get error => _error;
  bool get hasMore => _status != PagerStatus.done;

  /// True before the first page has arrived.
  bool get isInitial => _items.isEmpty && _offset == 0;

  Future<void> loadMore() async {
    if (_status == PagerStatus.loading || _status == PagerStatus.done) return;
    _set(PagerStatus.loading);
    try {
      final page = await _repository.page(
        kind,
        limit: pageSize,
        offset: _offset,
      );
      if (_disposed) return;
      _offset += page.length;
      for (final video in page) {
        final deduplicationKey = video.youtubeVideoId ?? video.id;
        if (_seen.add(deduplicationKey)) _items.add(video);
      }
      _error = null;
      _set(page.length < pageSize ? PagerStatus.done : PagerStatus.idle);
    } on Object catch (error) {
      if (_disposed) return;
      _error = error;
      _set(PagerStatus.error);
    }
  }

  /// After an error, tries the same page again.
  Future<void> retry() {
    if (_status != PagerStatus.error) return Future.value();
    _status = PagerStatus.idle;
    return loadMore();
  }

  Future<void> refresh() {
    _items.clear();
    _seen.clear();
    _offset = 0;
    _error = null;
    _status = PagerStatus.idle;
    return loadMore();
  }

  void _set(PagerStatus status) {
    _status = status;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
