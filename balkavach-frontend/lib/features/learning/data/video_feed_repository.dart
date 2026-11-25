import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/json_utils.dart';
import '../../missions/presentation/mission_providers.dart'
    show childNotificationsProvider;

final _youtubeIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

@immutable
class VideoAllowance {
  const VideoAllowance({
    required this.childId,
    required this.localDate,
    required this.timezone,
    required this.totalEarnedTodaySeconds,
    required this.consumedTodaySeconds,
    required this.remainingSeconds,
    required this.dailyCapSeconds,
    required this.isExhausted,
    required this.activeEntitlementsCount,
    int? freeRemainingSeconds,
    this.missionRemainingSeconds = 0,
  }) : freeRemainingSeconds = freeRemainingSeconds ?? 0;

  factory VideoAllowance.fromJson(Map<String, dynamic> json) => VideoAllowance(
    childId: json['child_id'] as String,
    localDate: json['local_date'] as String,
    timezone: json['timezone'] as String? ?? 'UTC',
    totalEarnedTodaySeconds:
        (json['total_earned_today_seconds'] as num?)?.toInt() ?? 0,
    consumedTodaySeconds:
        (json['consumed_today_seconds'] as num?)?.toInt() ?? 0,
    remainingSeconds: (json['remaining_seconds'] as num?)?.toInt() ?? 0,
    dailyCapSeconds: (json['daily_cap_seconds'] as num?)?.toInt() ?? 3600,
    isExhausted: json['is_exhausted'] as bool? ?? false,
    activeEntitlementsCount:
        (json['active_entitlements_count'] as num?)?.toInt() ?? 0,
    freeRemainingSeconds:
        (json['free_remaining_seconds'] as num?)?.toInt() ?? 0,
    missionRemainingSeconds:
        (json['mission_remaining_seconds'] as num?)?.toInt() ?? 0,
  );

  final String childId;
  final String localDate;
  final String timezone;
  final int totalEarnedTodaySeconds;
  final int consumedTodaySeconds;
  final int remainingSeconds;
  final int dailyCapSeconds;
  final bool isExhausted;
  final int activeEntitlementsCount;
  final int freeRemainingSeconds;
  final int missionRemainingSeconds;

  int get remainingMinutes => (remainingSeconds / 60).ceil();
}

/// One approved mission that earned video time today (parent view).
@immutable
class MissionVideoReward {
  const MissionVideoReward({
    required this.taskTitle,
    required this.grantedSeconds,
    required this.consumedSeconds,
  });

  factory MissionVideoReward.fromJson(Map<String, dynamic> json) =>
      MissionVideoReward(
        taskTitle: json['task_title'] as String?,
        grantedSeconds: (json['granted_seconds'] as num?)?.toInt() ?? 0,
        consumedSeconds: (json['consumed_seconds'] as num?)?.toInt() ?? 0,
      );

  final String? taskTitle;
  final int grantedSeconds;
  final int consumedSeconds;
}

/// `GET /video-access/children/{id}/summary`: the parent's read-only view of
/// today's video time. Every figure comes from the server.
@immutable
class VideoAllowanceSummary {
  const VideoAllowanceSummary({
    required this.allowance,
    required this.freeAllowanceSeconds,
    required this.freeConsumedSeconds,
    required this.rewards,
  });

  factory VideoAllowanceSummary.fromJson(Map<String, dynamic> json) =>
      VideoAllowanceSummary(
        allowance: VideoAllowance.fromJson(json),
        freeAllowanceSeconds:
            (json['free_allowance_seconds'] as num?)?.toInt() ?? 0,
        freeConsumedSeconds:
            (json['free_consumed_seconds'] as num?)?.toInt() ?? 0,
        rewards: [
          for (final item in (json['mission_rewards'] as List? ?? const []))
            MissionVideoReward.fromJson(item as Map<String, dynamic>),
        ],
      );

  final VideoAllowance allowance;
  final int freeAllowanceSeconds;
  final int freeConsumedSeconds;
  final List<MissionVideoReward> rewards;
}

@immutable
class MissionVideoProgress {
  const MissionVideoProgress({
    required this.taskId,
    required this.requiredSeconds,
    required this.verifiedSeconds,
    required this.remainingSeconds,
    required this.isComplete,
  });

  factory MissionVideoProgress.fromJson(Map<String, dynamic> json) =>
      MissionVideoProgress(
        taskId: json['task_id'] as String,
        requiredSeconds: (json['required_video_seconds'] as num).toInt(),
        verifiedSeconds: (json['verified_video_seconds'] as num).toInt(),
        remainingSeconds: (json['remaining_video_seconds'] as num).toInt(),
        isComplete: json['is_complete'] as bool,
      );

  final String taskId;
  final int requiredSeconds;
  final int verifiedSeconds;
  final int remainingSeconds;
  final bool isComplete;
}

@immutable
class MissionVideoWatch {
  const MissionVideoWatch({
    required this.progress,
    required this.sessionId,
    required this.acceptedSeconds,
    required this.status,
  });

  factory MissionVideoWatch.fromJson(Map<String, dynamic> json) =>
      MissionVideoWatch(
        progress: MissionVideoProgress.fromJson(json),
        sessionId: json['session_id'] as String,
        acceptedSeconds: (json['accepted_seconds'] as num?)?.toInt() ?? 0,
        status: json['status'] as String,
      );

  final MissionVideoProgress progress;
  final String sessionId;
  final int acceptedSeconds;
  final String status;
}

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
    this.resumePositionSeconds = 0,
    this.format = VideoFormat.regular,
    this.playbackLocked = false,
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
    resumePositionSeconds:
        (json['last_position_seconds'] as num?)?.toInt() ?? 0,
    format: VideoFormat.parse(json['video_format']),
    playbackLocked: json['playback_locked'] as bool? ?? false,
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
  final int resumePositionSeconds;

  /// The server's classification (1-60 s is a short). The app never decides
  /// this itself; a missing duration arrives as `unknown`.
  final VideoFormat format;

  /// Today's video time is used up. The server still lists the video so the
  /// child can browse, but withholds its playable id until time is earned.
  final bool playbackLocked;

  /// Playable in the official YouTube embed: a YouTube item with a well-formed id.
  bool get isYouTube =>
      source == 'youtube' && _youtubeIdPattern.hasMatch(youtubeVideoId ?? '');
}

@immutable
class VideoWatchHistoryEntry {
  const VideoWatchHistoryEntry({
    required this.video,
    required this.lastWatchedAt,
    required this.completionPercentage,
    required this.isCompleted,
  });

  factory VideoWatchHistoryEntry.fromJson(Map<String, dynamic> json) =>
      VideoWatchHistoryEntry(
        video: FeedVideo.fromJson({...json, 'id': json['video_id']}),
        lastWatchedAt: DateTime.parse(json['last_watched_at'] as String),
        completionPercentage: (json['completion_percentage'] as num).toInt(),
        isCompleted: json['is_completed'] as bool,
      );

  final FeedVideo video;
  final DateTime lastWatchedAt;
  final int completionPercentage;
  final bool isCompleted;
}

/// Mirrors `video_format` in `app/schemas/video.py`.
enum VideoFormat {
  short,
  regular,
  unknown;

  /// Older servers send no label; their items are shown as regular videos.
  static VideoFormat parse(Object? value) => switch (value) {
    'short' => VideoFormat.short,
    'unknown' => VideoFormat.unknown,
    _ => VideoFormat.regular,
  };
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
    String? categoryId,
    String? seed,
  }) => guardApi(() async {
    final response = await _dio.get<List<dynamic>>(
      kind.path,
      queryParameters: {
        'limit': limit,
        'offset': offset,
        'category_id': ?categoryId,
        'seed': ?seed,
      },
    );
    if (kDebugMode) {
      debugPrint(
        '[video-feed] GET ${kind.path} status=${response.statusCode} '
        'response_count=${response.data?.length ?? 0}',
      );
    }
    return parseJsonList(response.data, FeedVideo.fromJson);
  });

  /// `GET /videos/{id}/next`: what to offer after [videoId]. The server picks
  /// only from videos this child may already see, and returns nothing once
  /// today's video time is used up.
  Future<List<FeedVideo>> nextVideos(String videoId, {int limit = 6}) =>
      guardApi(() async {
        final response = await _dio.get<List<dynamic>>(
          '/api/v1/videos/$videoId/next',
          queryParameters: {'limit': limit},
        );
        return parseJsonList(response.data, FeedVideo.fromJson);
      });

  Future<List<FeedVideo>> continueWatching({int limit = 20}) =>
      guardApi(() async {
        final response = await _dio.get<List<dynamic>>(
          '/api/v1/videos/watch-history/continue-watching',
          queryParameters: {'limit': limit},
        );
        return parseJsonList(
          response.data,
          (json) => FeedVideo.fromJson({...json, 'id': json['video_id']}),
        );
      });

  Future<Map<String, dynamic>?> recordProgress(
    String videoId,
    int positionSeconds, {
    bool isPlaying = true,
  }) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/videos/watch-history/$videoId/progress',
      data: {'position_seconds': positionSeconds, 'is_playing': isPlaying},
    );
    return response.data;
  });

  Future<VideoAllowanceSummary> parentAllowanceSummary(String childId) =>
      guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/v1/video-access/children/$childId/summary',
        );
        return VideoAllowanceSummary.fromJson(response.data!);
      });

  Future<VideoAllowance> getAllowance() => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/video-access/allowance',
    );
    return VideoAllowance.fromJson(response.data!);
  });

  /// `GET /api/v1/videos/interests` (child).
  Future<Map<String, dynamic>> getMyInterests() => guardApi(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/videos/interests',
    );
    return response.data!;
  });

  /// `POST /api/v1/videos/interests/request` (child): submits pending
  /// interest requests without altering active parent-approved interests.
  Future<Map<String, dynamic>> requestInterests(List<String> interests) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/v1/videos/interests/request',
          data: {'interests': interests},
        );
        return response.data!;
      });

  Future<MissionVideoProgress> missionVideoProgress(String taskId) =>
      guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/v1/tasks/$taskId/video-watch',
        );
        return MissionVideoProgress.fromJson(response.data!);
      });

  Future<List<FeedVideo>> missionVideoCatalogue(String taskId) =>
      guardApi(() async {
        final response = await _dio.get<List<dynamic>>(
          '/api/v1/tasks/$taskId/video-catalogue',
        );
        return parseJsonList(response.data, FeedVideo.fromJson);
      });

  Future<MissionVideoWatch> startMissionVideoWatch(
    String taskId,
    String videoId,
    String clientSessionId,
  ) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/tasks/$taskId/video-watch/sessions',
      data: {'video_id': videoId, 'client_session_id': clientSessionId},
    );
    return MissionVideoWatch.fromJson(response.data!);
  });

  Future<MissionVideoWatch> reportMissionVideoWatch({
    required String sessionId,
    required int sequence,
    required int positionSeconds,
    required bool isPlaying,
  }) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/tasks/video-watch/sessions/$sessionId/heartbeats',
      data: {
        'sequence': sequence,
        'position_seconds': positionSeconds,
        'is_playing': isPlaying,
      },
    );
    return MissionVideoWatch.fromJson(response.data!);
  });

  Future<MissionVideoWatch> interruptMissionVideoWatch(String sessionId) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/v1/tasks/video-watch/sessions/$sessionId/interrupt',
        );
        return MissionVideoWatch.fromJson(response.data!);
      });

  Future<List<VideoWatchHistoryEntry>> parentHistory(String childId) =>
      guardApi(() async {
        final response = await _dio.get<List<dynamic>>(
          '/api/v1/videos/watch-history/children/$childId',
        );
        return parseJsonList(response.data, VideoWatchHistoryEntry.fromJson);
      });

  Future<void> authorizeReplay(String childId, String videoId) =>
      guardApi(() async {
        await _dio.post<void>(
          '/api/v1/videos/watch-history/children/$childId/$videoId/replay',
        );
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

final continueWatchingProvider = FutureProvider<List<FeedVideo>>(
  (ref) => ref.watch(videoFeedRepositoryProvider).continueWatching(),
);

final parentVideoHistoryProvider =
    FutureProvider.family<List<VideoWatchHistoryEntry>, String>(
      (ref, childId) =>
          ref.watch(videoFeedRepositoryProvider).parentHistory(childId),
    );

final parentVideoSummaryProvider = FutureProvider.autoDispose
    .family<VideoAllowanceSummary, String>(
      (ref, childId) => ref
          .watch(videoFeedRepositoryProvider)
          .parentAllowanceSummary(childId),
    );

final nextVideosProvider = FutureProvider.autoDispose
    .family<List<FeedVideo>, String>(
      (ref, videoId) =>
          ref.watch(videoFeedRepositoryProvider).nextVideos(videoId),
    );

/// How many "video time unlocked" notifications the child has. Parent
/// approval creates one per grant, so a change means new time was granted.
/// A [Provider] only notifies when the value changes, so unrelated
/// notification refreshes cause no extra allowance requests.
final videoTimeGrantCountProvider = Provider<int>(
  (ref) => (ref.watch(childNotificationsProvider).value ?? const [])
      .where((item) => item.type == 'mission_video_time_granted')
      .length,
);

/// Today's allowance, straight from the server. It reloads when a new grant
/// notification appears, whenever it is first shown, and when invalidated.
final videoAllowanceProvider = FutureProvider.autoDispose<VideoAllowance>((
  ref,
) {
  ref.watch(videoTimeGrantCountProvider);
  return ref.watch(videoFeedRepositoryProvider).getAllowance();
});

enum PagerStatus { idle, loading, error, done }

/// Offset pagination for one feed, owned by the screen showing it.
///
/// Items are de-duplicated by YouTube ID when present, otherwise by the server
/// row ID. This prevents the same published video from appearing twice if
/// duplicate rows exist or a video shifts between pages.
class VideoFeedPager extends ChangeNotifier {
  VideoFeedPager(
    this._repository,
    this.kind, {
    this.pageSize = 20,
    this.categoryId,
    String? seed,
    List<FeedVideo> initialItems = const [],
    int? initialOffset,
    bool initialDone = false,
  }) : _seed = seed ?? _newSeed() {
    // Seeded from a list the caller already loaded (Home's Shorts row), so
    // opening the full-screen feed does not fetch the same page again.
    for (final video in initialItems) {
      if (_seen.add(video.youtubeVideoId ?? video.id)) _items.add(video);
    }
    _offset = initialOffset ?? initialItems.length;
    if (initialItems.isNotEmpty && initialDone) _status = PagerStatus.done;
  }

  static final Random _seedRandom = Random();

  static String _newSeed() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_seedRandom.nextInt(1 << 32)}';

  final VideoFeedRepository _repository;
  final VideoFeedKind kind;
  final int pageSize;

  /// Server-side category filter (`category_id`); null for every category.
  final String? categoryId;

  String _seed;

  final List<FeedVideo> _items = [];
  final Set<String> _seen = {};
  int _offset = 0;
  int _generation = 0;
  PagerStatus _status = PagerStatus.idle;
  Object? _error;
  bool _retryRefresh = false;
  bool _disposed = false;

  List<FeedVideo> get items => List.unmodifiable(_items);
  PagerStatus get status => _status;
  Object? get error => _error;
  bool get hasMore => _status != PagerStatus.done;

  /// Server offset of the next page.
  int get nextOffset => _offset;

  /// Stable ordering seed for this feed session.
  String get seed => _seed;

  /// True before the first page has arrived.
  bool get isInitial => _items.isEmpty && _offset == 0;

  Future<void> loadMore() {
    if (_disposed ||
        _status == PagerStatus.loading ||
        _status == PagerStatus.done) {
      return Future.value();
    }
    return _requestPage(generation: _generation, replace: false);
  }

  Future<void> _requestPage({
    required int generation,
    required bool replace,
  }) async {
    final requestOffset = replace ? 0 : _offset;
    _trace(
      'request generation=$generation offset=$requestOffset '
      'replace=$replace visible_ids=${_ids(_items)}',
    );
    _set(PagerStatus.loading);
    try {
      final page = await _repository.page(
        kind,
        limit: pageSize,
        offset: requestOffset,
        categoryId: categoryId,
        seed: _seed,
      );
      if (_disposed || generation != _generation) {
        _trace('discard stale response generation=$generation');
        return;
      }
      final previousIds = _ids(_items);
      final incomingIds = _ids(page);
      if (replace) {
        _items.clear();
        _seen.clear();
      }
      for (final video in page) {
        final deduplicationKey = video.youtubeVideoId ?? video.id;
        if (_seen.add(deduplicationKey)) _items.add(video);
      }
      _offset = requestOffset + page.length;
      _error = null;
      _retryRefresh = false;
      _trace(
        'response generation=$generation received_ids=$incomingIds '
        'visible_ids_before=$previousIds visible_ids_after=${_ids(_items)}',
      );
      _set(page.length < pageSize ? PagerStatus.done : PagerStatus.idle);
    } on Object catch (error) {
      if (_disposed || generation != _generation) {
        _trace('discard stale error generation=$generation');
        return;
      }
      if (replace &&
          error is ApiException &&
          (error.statusCode == 401 || error.statusCode == 403)) {
        _items.clear();
        _seen.clear();
        _offset = 0;
      }
      _error = error;
      _retryRefresh = replace;
      _trace(
        'request_failed generation=$generation error=${error.runtimeType} '
        'visible_ids=${_ids(_items)}',
      );
      _set(PagerStatus.error);
    }
  }

  /// After an error, tries the same page again.
  Future<void> retry() {
    if (_status != PagerStatus.error) return Future.value();
    if (_retryRefresh) {
      return _requestPage(generation: _generation, replace: true);
    }
    _status = PagerStatus.idle;
    return loadMore();
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    final generation = ++_generation;
    _error = null;
    _retryRefresh = true;
    // New session seed on explicit refresh/open-style reload so users can see a
    // different rotation while each paginated sequence remains stable.
    _seed = _newSeed();
    _trace('refresh generation=$generation visible_ids=${_ids(_items)}');
    return _requestPage(generation: generation, replace: true);
  }

  void _set(PagerStatus status) {
    final previous = _status;
    _status = status;
    _trace(
      'state=$previous->$status item_count=${_items.length} offset=$_offset',
    );
    if (!_disposed) notifyListeners();
  }

  void _trace(String message) {
    if (kDebugMode) debugPrint('[video-feed ${kind.name}] $message');
  }

  List<String> _ids(Iterable<FeedVideo> videos) => [
    for (final video in videos) video.id,
  ];

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
