import 'package:flutter/foundation.dart';

import 'learning_repository.dart';
import 'video_feed_repository.dart';

/// Why a video in a list cannot be played inside the app.
enum VideoUnavailableReason {
  /// A hosted (uploaded) video. The server never sends its media URL in a
  /// feed: playback needs an authorised session backed by a reward a parent
  /// approved, so it is not played from a feed.
  needsGrownUp,

  /// The item carries nothing this app can play (no URL, or a YouTube page
  /// that is not a single video).
  noSource,
}

/// Where a video's picture comes from. Exactly one player handles each case.
@immutable
sealed class VideoSource {
  const VideoSource();
}

/// An approved YouTube video, shown only in the official embedded player.
final class YouTubeVideoSource extends VideoSource {
  const YouTubeVideoSource(this.videoId);

  final String videoId;

  /// The public watch page, used only for sharing (behind a grown-up check).
  Uri get watchUri => Uri.https('www.youtube.com', '/watch', {'v': videoId});

  @override
  bool operator ==(Object other) =>
      other is YouTubeVideoSource && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;
}

/// A direct HTTPS media stream (for example an MP4) that the server handed to
/// the child. Played by `video_player`. Never a YouTube page.
final class DirectStreamSource extends VideoSource {
  const DirectStreamSource(this.uri);

  final Uri uri;

  @override
  bool operator ==(Object other) =>
      other is DirectStreamSource && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

/// Shown in lists, but not playable here.
final class UnavailableSource extends VideoSource {
  const UnavailableSource(this.reason);

  final VideoUnavailableReason reason;

  @override
  bool operator ==(Object other) =>
      other is UnavailableSource && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

/// One video as the Shorts feed and the regular player see it, whichever API
/// it came from. This is presentation only: eligibility, age, language and
/// entitlements were already decided by the server that returned the item.
@immutable
class PlayableVideo {
  const PlayableVideo({
    required this.key,
    required this.title,
    required this.source,
    this.description,
    this.thumbnailUrl,
    this.channelName,
    this.duration,
    this.categoryId,
    this.reportVideoId,
  });

  /// A video from `GET /videos/feed` or `GET /videos/shorts`.
  factory PlayableVideo.fromFeed(FeedVideo video) => PlayableVideo(
    key: 'feed:${video.id}',
    title: video.title,
    description: _clean(video.description),
    thumbnailUrl: _httpsOrNull(video.thumbnailUrl),
    channelName: _clean(video.channelName),
    duration: video.durationSeconds > 0
        ? Duration(seconds: video.durationSeconds)
        : null,
    categoryId: video.categoryId,
    // Every feed video has a server row a grown-up can report.
    reportVideoId: video.id,
    source: video.isYouTube
        ? YouTubeVideoSource(video.youtubeVideoId!)
        : video.source == 'youtube'
        ? const UnavailableSource(VideoUnavailableReason.noSource)
        : const UnavailableSource(VideoUnavailableReason.needsGrownUp),
  );

  /// An admin-curated Learn & Watch video from `GET /educational-content`.
  factory PlayableVideo.fromLearning(LearningItem item) => PlayableVideo(
    key: 'learn:${item.id}',
    title: item.title,
    description: _clean(item.description),
    thumbnailUrl: _httpsOrNull(item.thumbnailUrl),
    categoryId: item.categoryId,
    source: item.isYouTubeEmbeddable
        ? YouTubeVideoSource(item.youtubeVideoId!)
        // `isPlayableInApp` already excludes YouTube links, hosted rows and
        // reward-locked items, so only a real media link gets here.
        : item.isPlayableInApp
        ? DirectStreamSource(item.openableUri!)
        : item.isHosted || item.requiresEntitlement
        ? const UnavailableSource(VideoUnavailableReason.needsGrownUp)
        : const UnavailableSource(VideoUnavailableReason.noSource),
  );

  /// Stable identity across pages and rebuilds.
  final String key;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final String? channelName;
  final Duration? duration;
  final String? categoryId;
  final VideoSource source;

  /// The server's video id for the grown-up report form, when there is one.
  final String? reportVideoId;

  bool get isPlayable => source is! UnavailableSource;
  bool get isYouTube => source is YouTubeVideoSource;

  /// What the share sheet may offer. Hosted media is never shared.
  Uri? get shareUri => switch (source) {
    YouTubeVideoSource(:final watchUri) => watchUri,
    DirectStreamSource(:final uri) => uri,
    UnavailableSource() => null,
  };

  @override
  bool operator ==(Object other) =>
      other is PlayableVideo && other.key == key && other.source == source;

  @override
  int get hashCode => Object.hash(key, source);
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _httpsOrNull(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
      ? url
      : null;
}

/// Arguments for the full-screen Shorts route.
@immutable
class ShortsLaunch {
  const ShortsLaunch({
    this.initialVideos = const [],
    this.initialIndex = 0,
    this.nextOffset,
    this.exhausted = false,
  });

  /// Shorts the caller already loaded, so the feed opens without a spinner.
  final List<FeedVideo> initialVideos;
  final int initialIndex;

  /// Server offset after [initialVideos]; null means "start from zero".
  final int? nextOffset;

  /// The server has nothing after [initialVideos].
  final bool exhausted;
}

/// Arguments for the regular video player route.
@immutable
class VideoLaunch {
  const VideoLaunch({required this.video, this.related = const []});

  final PlayableVideo video;

  /// What "Up next" offers, from lists the child could already see.
  final List<PlayableVideo> related;
}
