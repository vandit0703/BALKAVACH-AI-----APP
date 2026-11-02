import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/learning_repository.dart';
import '../data/video_feed_repository.dart';
import '../data/youtube_embed_policy.dart';
import 'widgets/video_actions.dart' show askGrownUpThenOpen;

/// What the embed needs from the screen hosting it.
@immutable
class YouTubeEmbedConfig {
  const YouTubeEmbedConfig({
    required this.videoId,
    required this.onLeaveRequested,
    required this.onForeignVideo,
    required this.onError,
    this.autoplay = false,
    this.muted = false,
    this.onBlocked,
    this.onProgress,
    this.onVerticalSwipe,
    this.aspectRatio,
    this.overlay,
  });

  /// The approved video; nothing else may play in this embed.
  final String videoId;

  /// A link in the player wants to leave the app (title, logo, related video,
  /// end screen, ad). The screen asks a grown-up first.
  final ValueChanged<Uri> onLeaveRequested;

  /// The player loaded a different video than [videoId] and was reset.
  final VoidCallback onForeignVideo;

  /// A load or playback failure that a retry may fix (offline, hiccup).
  final VoidCallback onError;
  final bool autoplay;

  /// Starts (and stays) muted while true. Changing it mutes or unmutes.
  final bool muted;

  /// YouTube refuses this video for good: the owner disabled embedding, or it
  /// was removed or made private. Retrying will not help. When null, these
  /// are reported through [onError] instead.
  final VoidCallback? onBlocked;

  /// Position and length as the player reports them, for a progress bar.
  /// This is display only and is never sent anywhere as viewing time.
  final void Function(Duration position, Duration duration)? onProgress;

  /// When set, a vertical fling on the video is handed to the host (the
  /// Shorts feed uses it to change videos) instead of toggling fullscreen.
  /// Taps still reach YouTube's own controls.
  final ValueChanged<double>? onVerticalSwipe;

  /// Shape of the player box. Null keeps YouTube's 16:9. The Shorts feed
  /// passes the screen's own shape so the player fills it; YouTube then fits
  /// the video inside (a portrait Short fills it, a landscape one is
  /// letterboxed by YouTube itself, never cropped).
  final double? aspectRatio;

  /// Drawn above the video. On phones the web view sits in an overlay above
  /// the page, so this is the only way to place widgets on top of it. Empty
  /// areas of the overlay let taps through to YouTube's own controls.
  final Widget? overlay;
}

typedef YouTubeEmbedBuilder = Widget Function(YouTubeEmbedConfig config);

/// Seam so widget tests can replace the web view with a stand-in.
final youtubeEmbedBuilderProvider = Provider<YouTubeEmbedBuilder>(
  (ref) =>
      (config) => OfficialYouTubeEmbed(config: config),
);

/// The official YouTube IFrame player, unmodified: YouTube's controls,
/// branding, links and ads are all left in place.
///
/// Two things are added around it. Navigation leaving the player is routed to
/// [YouTubeEmbedConfig.onLeaveRequested] instead of the package default, which
/// would play a tapped related video inside the app. And if the player ever
/// reports a video other than the approved one, it is reset to the approved
/// one. There is no playlist and looping is off, so nothing plays next on its
/// own.
class OfficialYouTubeEmbed extends StatefulWidget {
  const OfficialYouTubeEmbed({required this.config, super.key});

  final YouTubeEmbedConfig config;

  @override
  State<OfficialYouTubeEmbed> createState() => _OfficialYouTubeEmbedState();
}

class _OfficialYouTubeEmbedState extends State<OfficialYouTubeEmbed>
    with WidgetsBindingObserver {
  static const _params = YoutubePlayerParams(
    showFullscreenButton: true,
    strictRelatedVideos: true,
    playsInline: true,
  );

  late final YoutubePlayerController _controller;
  StreamSubscription<YoutubePlayerValue>? _values;
  StreamSubscription<YoutubeVideoState>? _positions;
  bool _pausedByLifecycle = false;
  bool _blockedReported = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = YoutubePlayerController(params: _params);
    if (!kIsWeb) {
      unawaited(
        _controller.webViewController.setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: _onNavigation,
            onWebResourceError: (error) {
              if (error.isForMainFrame ?? false) widget.config.onError();
            },
          ),
        ),
      );
    }
    _values = _controller.stream.listen(_onValue);
    if (widget.config.onProgress != null) {
      _positions = _controller.videoStateStream.listen(_onPosition);
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    final config = widget.config;
    if (config.muted) await _controller.mute();
    await (config.autoplay
        ? _controller.loadVideoById(videoId: config.videoId)
        : _controller.cueVideoById(videoId: config.videoId));
  }

  @override
  void didUpdateWidget(OfficialYouTubeEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.muted != widget.config.muted) {
      unawaited(
        widget.config.muted ? _controller.mute() : _controller.unMute(),
      );
    }
  }

  void _onPosition(YoutubeVideoState state) {
    final duration = _controller.value.metaData.duration;
    widget.config.onProgress?.call(state.position, duration);
  }

  NavigationDecision _onNavigation(NavigationRequest request) {
    final decision = decidePlayerNavigation(
      request.url,
      isMainFrame: request.isMainFrame,
      baseUrl: _params.origin ?? _params.host,
    );
    switch (decision) {
      case PlayerNavigation.allow:
        return NavigationDecision.navigate;
      case PlayerNavigation.openOutsideAfterGate:
        widget.config.onLeaveRequested(Uri.parse(request.url));
        return NavigationDecision.prevent;
      case PlayerNavigation.block:
        return NavigationDecision.prevent;
    }
  }

  void _onValue(YoutubePlayerValue value) {
    if (value.hasError) {
      final onBlocked = widget.config.onBlocked;
      if (onBlocked != null && isPermanentYouTubeError(value.error)) {
        if (!_blockedReported) onBlocked();
        _blockedReported = true;
      } else {
        widget.config.onError();
      }
    }
    final loaded = value.metaData.videoId;
    if (loaded.isNotEmpty && loaded != widget.config.videoId) {
      unawaited(_controller.cueVideoById(videoId: widget.config.videoId));
      widget.config.onForeignVideo();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Like the native player: nothing keeps playing behind another app.
    if (state == AppLifecycleState.resumed) {
      // An autoplaying player that was playing picks up where it paused; a
      // cued one (the classic player screen) waits for the child to press
      // play.
      if (_pausedByLifecycle && widget.config.autoplay) {
        unawaited(_controller.playVideo());
      }
      _pausedByLifecycle = false;
    } else if (!_pausedByLifecycle) {
      final playerState = _controller.value.playerState;
      _pausedByLifecycle =
          playerState == PlayerState.playing ||
          playerState == PlayerState.buffering;
      unawaited(_controller.pauseVideo());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_values?.cancel());
    unawaited(_positions?.cancel());
    unawaited(_controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final onSwipe = config.onVerticalSwipe;
    final overlay = config.overlay;
    final aspectRatio = config.aspectRatio ?? 16 / 9;
    if (onSwipe == null && overlay == null) {
      return YoutubePlayer(
        controller: _controller,
        autoFullScreen: false,
        aspectRatio: aspectRatio,
      );
    }
    // On phones the web view lives in an overlay above the page, so a swipe
    // on the video would never reach the feed, and page widgets would sit
    // underneath it. Both go in the player's own controls layer instead. The
    // swipe catcher is translucent and only claims vertical drags, so taps
    // still reach YouTube's controls, ads and links.
    return YoutubePlayer(
      controller: _controller,
      autoFullScreen: false,
      aspectRatio: aspectRatio,
      backgroundColor: Colors.black,
      enableFullScreenOnVerticalDrag: onSwipe == null,
      controlsBuilder: (context, isFullscreen) => isFullscreen
          ? const SizedBox.shrink()
          : Stack(
              fit: StackFit.expand,
              children: [
                if (onSwipe != null)
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragEnd: (details) =>
                        onSwipe(details.primaryVelocity ?? 0),
                  ),
                ?overlay,
              ],
            ),
    );
  }
}

/// YouTube errors no retry can fix: embedding disabled by the owner, or the
/// video removed or made private.
bool isPermanentYouTubeError(YoutubeError error) => switch (error) {
  YoutubeError.notEmbeddable ||
  YoutubeError.sameAsNotEmbeddable ||
  YoutubeError.sameAsNotEmbeddable2 ||
  YoutubeError.videoNotFound ||
  YoutubeError.cannotFindVideo => true,
  _ => false,
};

/// Plays one YouTube video in the official player: either one the server
/// approved for the video feed, or one an administrator curated for Learn &
/// Watch.
class YouTubePlayerScreen extends ConsumerStatefulWidget {
  /// A feed video. It has a server-side video row, so it can be reported.
  YouTubePlayerScreen({required FeedVideo video, super.key})
    : title = video.title,
      youtubeVideoId = video.isYouTube ? video.youtubeVideoId : null,
      reportVideoId = video.id;

  /// A curated Learn & Watch link. It has no video row behind it, so the
  /// report form (which needs one) is not offered.
  YouTubePlayerScreen.curated({required LearningItem item, super.key})
    : title = item.title,
      youtubeVideoId = item.isYouTubeEmbeddable ? item.youtubeVideoId : null,
      reportVideoId = null;

  final String title;

  /// Null when there is nothing the embed may play; the screen says so.
  final String? youtubeVideoId;

  /// The server's video id for the report form, when there is one.
  final String? reportVideoId;

  @override
  ConsumerState<YouTubePlayerScreen> createState() =>
      _YouTubePlayerScreenState();
}

class _YouTubePlayerScreenState extends ConsumerState<YouTubePlayerScreen> {
  bool _failed = false;

  /// Bumped on retry so the embed (and its web view) is built afresh.
  int _attempt = 0;

  void _retry() => setState(() {
    _failed = false;
    _attempt++;
  });

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // Several navigation events can arrive for one tap; the shared gate asks
  // once.
  Future<void> _leave(Uri uri) => askGrownUpThenOpen(context, ref, uri);

  void _onForeignVideo() {
    if (mounted) {
      _notify(AppLocalizations.of(context).youtubeOtherVideoBlocked);
    }
  }

  void _onError() {
    if (mounted && !_failed) setState(() => _failed = true);
  }

  Future<void> _report(String videoId) async {
    final sent = await showVideoReportDialog(context, videoId);
    if (!mounted || sent == null) return;
    final l10n = AppLocalizations.of(context);
    _notify(sent ? l10n.videoReportSent : l10n.videoReportFailed);
    // The reported video is now hidden from the feed; leave the player.
    if (sent) unawaited(Navigator.of(context).maybePop());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final videoId = widget.youtubeVideoId;
    final reportVideoId = widget.reportVideoId;
    final embed = ref.watch(youtubeEmbedBuilderProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          reportVideoId == null ? l10n.learnTitle : l10n.videoFeedTitle,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _failed || videoId == null
                    ? ColoredBox(
                        color: colors.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                l10n.youtubePlayerError,
                                key: const Key('youtube.error'),
                                textAlign: TextAlign.center,
                              ),
                              // Load failures (offline, embed hiccup) may
                              // pass; a missing id never will.
                              if (videoId != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                SecondaryButton(
                                  key: const Key('youtube.retry'),
                                  dense: true,
                                  label: l10n.videoRetry,
                                  icon: Icons.refresh_rounded,
                                  onPressed: _retry,
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : KeyedSubtree(
                        key: ValueKey(('youtube.embed', _attempt)),
                        child: embed(
                          YouTubeEmbedConfig(
                            videoId: videoId,
                            onLeaveRequested: _leave,
                            onForeignVideo: _onForeignVideo,
                            onError: _onError,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(widget.title, style: context.text.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            InlineNotice(
              icon: Icons.info_outline_rounded,
              message: l10n.videoFeedAdsNotice,
            ),
            if (reportVideoId != null) ...[
              const SizedBox(height: AppSpacing.lg),
              SecondaryButton(
                key: const Key('youtube.report'),
                label: l10n.videoReport,
                icon: Icons.flag_outlined,
                onPressed: () => _report(reportVideoId),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens the grown-up report form for a server video row. Resolves `true`
/// when the server accepted the report, `false` when it failed, and `null`
/// when cancelled.
Future<bool?> showVideoReportDialog(BuildContext context, String videoId) =>
    showDialog<bool>(
      context: context,
      builder: (_) => _ReportDialog(videoId: videoId),
    );

/// Grown-up report form. Pops `true` when the server accepted the report,
/// `false` when it failed, and `null` when cancelled.
class _ReportDialog extends ConsumerStatefulWidget {
  const _ReportDialog({required this.videoId});

  final String videoId;

  @override
  ConsumerState<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends ConsumerState<_ReportDialog> {
  VideoReportReason? _reason;
  final _details = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(videoFeedRepositoryProvider)
          .report(widget.videoId, reason, details: _details.text);
      if (mounted) Navigator.pop(context, true);
    } on ApiException {
      if (mounted) Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('youtube.reportDialog'),
      title: Text(l10n.videoReportTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.videoReportBody),
            const SizedBox(height: AppSpacing.sm),
            RadioGroup<VideoReportReason>(
              groupValue: _reason,
              onChanged: (value) => setState(() => _reason = value),
              child: Column(
                children: [
                  for (final reason in VideoReportReason.values)
                    RadioListTile<VideoReportReason>(
                      key: Key('youtube.reason.${reason.name}'),
                      value: reason,
                      contentPadding: EdgeInsets.zero,
                      title: Text(reportReasonName(l10n, reason)),
                    ),
                ],
              ),
            ),
            TextField(
              controller: _details,
              maxLength: 1000,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(labelText: l10n.videoReportDetails),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: Text(l10n.videoReportCancel),
        ),
        PrimaryButton(
          key: const Key('youtube.reportSend'),
          label: l10n.videoReportSend,
          childSized: true,
          loading: _sending,
          onPressed: _reason == null || _sending ? null : _send,
        ),
      ],
    );
  }
}

String reportReasonName(AppLocalizations l10n, VideoReportReason reason) =>
    switch (reason) {
      VideoReportReason.inappropriate => l10n.videoReportReasonInappropriate,
      VideoReportReason.scary => l10n.videoReportReasonScary,
      VideoReportReason.violent => l10n.videoReportReasonViolent,
      VideoReportReason.misleading => l10n.videoReportReasonMisleading,
      VideoReportReason.advertising => l10n.videoReportReasonAdvertising,
      VideoReportReason.other => l10n.videoReportReasonOther,
    };
