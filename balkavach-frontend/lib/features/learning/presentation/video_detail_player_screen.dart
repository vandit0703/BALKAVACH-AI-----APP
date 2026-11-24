import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/celebration/activity_completion.dart';
import '../../../shared/celebration/panda_celebration.dart';
import '../../../shared/diag/video_diag.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/play_ticket_client.dart' show TicketStop;
import '../data/playable_video.dart';
import '../data/playback_guard.dart';
import '../data/ticketed_playback.dart';
import '../data/video_feed_repository.dart';
import '../data/video_playback_controller.dart';
import 'video_lock_screen.dart';
import 'video_player_screen.dart' show formatPlaybackTime;
import 'widgets/ticket_notice.dart';
import 'widgets/video_actions.dart';
import 'youtube_player_screen.dart';

/// The regular (non-Shorts) watching experience: a player, the video's
/// details and an "Up next" list.
///
/// A YouTube video plays in the official embed (YouTube's own controls,
/// branding, ads and fullscreen button). A direct stream plays in the native
/// player with play/pause, seek, buffering and a fullscreen toggle. Hosted
/// videos that need an approved reward are never played here. Feed-video
/// progress is persisted by the child-scoped watch-history endpoint.
class VideoDetailPlayerScreen extends ConsumerStatefulWidget {
  const VideoDetailPlayerScreen({required this.launch, super.key});

  final VideoLaunch launch;

  @override
  ConsumerState<VideoDetailPlayerScreen> createState() =>
      _VideoDetailPlayerScreenState();
}

class _VideoDetailPlayerScreenState
    extends ConsumerState<VideoDetailPlayerScreen>
    with WidgetsBindingObserver {
  late PlayableVideo _video = widget.launch.video;
  VideoPlaybackController? _controller;
  bool _failed = false;
  bool _blocked = false;
  bool _allowanceExhausted = false;
  MissionVideoWatch? _missionWatch;
  int _missionSequence = 0;
  bool _missionHeartbeatInFlight = false;
  bool _missionWatchStarting = false;
  String _missionClientSessionId = _newMissionClientSessionId();

  /// Reports kept failing: playback is stopped until the server answers.
  bool _offline = false;

  /// The server requires play tickets and this build does not use them
  /// (409 `play_ticket_required`). Set together with [_offline] so every
  /// "stop playback" check applies; there is no retry, only an app update.
  bool _updateRequired = false;
  PlaybackGuard get _guard => ref.read(playbackGuardProvider);
  bool _fullscreen = false;

  /// The video reached its end: the overlay offers what to watch next.
  bool _ended = false;

  /// The mission-video celebration is shown once per opening of this screen.
  bool _celebratedMissionVideo = false;
  bool _leaving = false;
  bool _muted = false;
  DateTime _lastProgressSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastPosition = Duration.zero;

  /// Bumped on retry or on a new video so players are built afresh.
  int _attempt = 0;
  final _scroll = ScrollController();

  /// The list this screen was opened with (never the server's choice).
  List<PlayableVideo> get _relatedFallback => [
    for (final video in widget.launch.related)
      if (video.key != _video.key) video,
  ];

  /// Server-ranked suggestions for this video, when it has a server row.
  AsyncValue<List<FeedVideo>>? get _serverNext {
    final id = _video.reportVideoId;
    return id == null ? null : ref.watch(nextVideosProvider(id));
  }

  /// What to show under and after the video. The server's ranked list wins;
  /// the opening list fills in when the server has nothing or cannot be reached.
  List<PlayableVideo> get _upNext {
    final server = _serverNext?.value;
    if (server != null && server.isNotEmpty) {
      return [
        for (final item in server.map(PlayableVideo.fromFeed))
          if (item.key != _video.key) item,
      ];
    }
    return _relatedFallback;
  }

  /// Play tickets (D6) for the current video, when the build enables them.
  late TicketedPlayback _tickets = _newTickets();

  TicketedPlayback _newTickets() => ticketedPlaybackFor(
    ref,
    metered:
        widget.launch.missionTaskId == null && _video.reportVideoId != null,
    onChanged: _onTicketChanged,
  );

  void _startTicket() {
    final id = _video.reportVideoId;
    if (mounted &&
        widget.launch.missionTaskId == null &&
        id != null &&
        _tickets.handles) {
      unawaited(_tickets.begin(id));
    }
  }

  static String _newMissionClientSessionId() => List.generate(
    32,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();

  Future<void> _startMissionWatch() async {
    final taskId = widget.launch.missionTaskId;
    final videoId = _video.reportVideoId;
    if (taskId == null || videoId == null || _missionWatchStarting) return;
    _missionWatchStarting = true;
    try {
      final watch = await ref
          .read(videoFeedRepositoryProvider)
          .startMissionVideoWatch(taskId, videoId, _missionClientSessionId);
      if (!mounted) return;
      setState(() {
        _missionWatch = watch;
        _missionSequence = 0;
        _offline = false;
        _lastProgressSentAt = DateTime.now();
      });
      final controller = _controller;
      if (controller != null && controller.isInitialised) {
        await controller.play();
      }
    } on Object {
      if (mounted) setState(() => _offline = true);
    } finally {
      _missionWatchStarting = false;
    }
  }

  void _onTicketChanged() {
    if (!mounted) return;
    if (_tickets.stopReason == TicketStop.exhausted) {
      _stopForExhaustedAllowance();
      return;
    }
    final controller = _controller;
    if (controller != null && controller.isInitialised) {
      if (_tickets.phase == TicketPhase.granted && !controller.isPlaying) {
        unawaited(controller.play());
      } else if (!_tickets.mayPlay && controller.isPlaying) {
        unawaited(controller.pause());
      }
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    vdiag(
      'detail.initState',
      screen: 'detail',
      id: identityHashCode(this),
      extra: 'mission=${widget.launch.missionTaskId != null}',
    );
    WidgetsBinding.instance.addObserver(this);
    _start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.launch.missionTaskId == null) {
        _startTicket();
      } else {
        unawaited(_startMissionWatch());
      }
    });
  }

  void _start() {
    final source = _video.source;
    if (source is! DirectStreamSource) return;
    final controller = ref.read(videoPlaybackControllerFactoryProvider)(
      source.uri,
    );
    _controller = controller;
    controller.listenable.addListener(_onPlayer);
    unawaited(_initialise(controller));
  }

  Future<void> _initialise(VideoPlaybackController controller) async {
    await controller.initialise();
    if (!mounted || _controller != controller) return;
    if (controller.errorMessage != null) {
      setState(() => _failed = true);
      return;
    }
    final resumeAt = _video.resumePositionSeconds;
    if (resumeAt > 0 && resumeAt < controller.duration.inSeconds) {
      await controller.seekTo(Duration(seconds: resumeAt));
    }
    await controller.setVolume(_muted ? 0 : 1);
    // Ticketed and mission playback wait for server authorization.
    if (_tickets.mayPlay ||
        (widget.launch.missionTaskId != null &&
            _missionWatch?.status == 'active')) {
      await controller.play();
    }
  }

  void _onPlayer() {
    final controller = _controller;
    if (controller == null) return;
    _lastPosition = controller.position;
    _recordWatchProgress(
      _lastPosition,
      controller.duration,
      isPlaying: controller.isPlaying && !controller.isBuffering,
    );
    final failed = _controller?.errorMessage != null;
    if (mounted && failed && !_failed) setState(() => _failed = true);
    final total = controller.duration;
    if (mounted &&
        !_ended &&
        controller.isInitialised &&
        total > Duration.zero &&
        !controller.isPlaying &&
        controller.position >= total - const Duration(milliseconds: 500)) {
      setState(() => _ended = true);
      if (widget.launch.missionTaskId != null) unawaited(_finishMissionWatch());
    }
  }

  void _release() {
    final controller = _controller;
    _controller = null;
    controller?.listenable.removeListener(_onPlayer);
    unawaited(controller?.dispose());
  }

  void _retry() {
    unawaited(_retryPlayer());
  }

  Future<void> _retryPlayer() async {
    if (widget.launch.missionTaskId != null) {
      await _finishMissionWatch();
      _missionClientSessionId = _newMissionClientSessionId();
    }
    setState(() {
      _release();
      _failed = false;
      _blocked = false;
      _ended = false;
      _attempt++;
      _start();
      if (widget.launch.missionTaskId != null) _missionWatch = null;
    });
    if (widget.launch.missionTaskId != null) await _startMissionWatch();
  }

  Future<void> _open(PlayableVideo next) async {
    if (widget.launch.missionTaskId != null) return;
    // The server confirms time remains before the next video starts.
    if (!await ensureVideoAllowance(context, ref) || !mounted) return;
    if (_tickets.handles) {
      // One ticket per video: end this one, then ask for the next.
      final old = _tickets;
      await old.finish(_controller?.position ?? _lastPosition);
      old.dispose();
      if (!mounted) return;
      _video = next;
      _tickets = _newTickets();
    } else {
      _recordWatchProgress(
        _controller?.position ?? _lastPosition,
        _controller?.duration ?? Duration.zero,
        force: true,
        isPlaying: false,
      );
    }
    setState(() {
      _release();
      _video = next;
      _failed = false;
      _blocked = false;
      _ended = false;
      _attempt++;
      _start();
    });
    _startTicket();
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.isInitialised) return;
    await (controller.isPlaying ? controller.pause() : controller.play());
    _recordWatchProgress(
      controller.position,
      controller.duration,
      force: true,
      isPlaying: controller.isPlaying && !controller.isBuffering,
    );
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _controller?.setVolume(_muted ? 0 : 1);
  }

  void _recordWatchProgress(
    Duration position,
    Duration duration, {
    bool force = false,
    bool isPlaying = true,
  }) {
    _lastPosition = position;
    if (widget.launch.missionTaskId != null) {
      _reportMissionWatch(position, force: force, isPlaying: isPlaying);
      return;
    }
    final videoId = _video.reportVideoId;
    if (videoId != null && _tickets.handles) {
      // Ticket mode: heartbeats meter this playback, record_progress never.
      _tickets.report(position, isPlaying: isPlaying);
      return;
    }
    final now = DateTime.now();
    if (videoId == null ||
        (!force &&
            now.difference(_lastProgressSentAt) <
                const Duration(seconds: 10))) {
      return;
    }
    _lastProgressSentAt = now;
    unawaited(
      _guard
          .report(
            () => ref
                .read(videoFeedRepositoryProvider)
                .recordProgress(
                  videoId,
                  position.inSeconds,
                  isPlaying: isPlaying,
                ),
          )
          .then(_apply),
    );
  }

  void _reportMissionWatch(
    Duration position, {
    required bool force,
    required bool isPlaying,
  }) {
    final watch = _missionWatch;
    if (watch == null ||
        watch.status != 'active' ||
        _missionHeartbeatInFlight) {
      return;
    }
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastProgressSentAt) < const Duration(seconds: 10)) {
      return;
    }
    _lastProgressSentAt = now;
    _missionHeartbeatInFlight = true;
    unawaited(() async {
      try {
        final updated = await ref
            .read(videoFeedRepositoryProvider)
            .reportMissionVideoWatch(
              sessionId: watch.sessionId,
              sequence: _missionSequence++,
              positionSeconds: position.inSeconds,
              isPlaying: isPlaying,
            );
        if (!mounted) return;
        setState(() => _missionWatch = updated);
        if (updated.progress.isComplete) {
          unawaited(_controller?.pause());
        }
      } on Object {
        if (mounted) {
          unawaited(_controller?.pause());
          setState(() => _offline = true);
        }
      } finally {
        _missionHeartbeatInFlight = false;
      }
    }());
  }

  Future<void> _finishMissionWatch() async {
    final watch = _missionWatch;
    if (watch == null || watch.status != 'active') return;
    try {
      final finalReport = await ref
          .read(videoFeedRepositoryProvider)
          .reportMissionVideoWatch(
            sessionId: watch.sessionId,
            sequence: _missionSequence++,
            positionSeconds: (_controller?.position ?? _lastPosition).inSeconds,
            isPlaying: false,
          );
      final closed = finalReport.status == 'active'
          ? await ref
                .read(videoFeedRepositoryProvider)
                .interruptMissionVideoWatch(watch.sessionId)
          : finalReport;
      if (mounted) setState(() => _missionWatch = closed);
    } on Object {
      // An interrupted session preserves only previously accepted progress.
    }
  }

  void _apply(PlaybackReport report) {
    if (!mounted) return;
    switch (report.verdict) {
      case PlaybackVerdict.ok:
        break;
      case PlaybackVerdict.exhausted:
        _stopForExhaustedAllowance();
      case PlaybackVerdict.updateRequired:
        unawaited(_controller?.pause());
        setState(() => _offline = _updateRequired = true);
      case PlaybackVerdict.offline:
      case PlaybackVerdict.signedOut:
        if (_offline) break;
        unawaited(_controller?.pause());
        setState(() => _offline = true);
    }
  }

  void _retryTicket() {
    _tickets.reset();
    setState(() => _attempt++);
    _startTicket();
  }

  Future<void> _retryOnline() async {
    if (_tickets.handles) return _retryTicket();
    if (widget.launch.missionTaskId != null) {
      final current = _missionWatch;
      if (current == null || current.status != 'active') {
        _missionClientSessionId = _newMissionClientSessionId();
        if (current != null) setState(() => _missionWatch = null);
        await _startMissionWatch();
        return;
      }
      try {
        final updated = await ref
            .read(videoFeedRepositoryProvider)
            .reportMissionVideoWatch(
              sessionId: current.sessionId,
              sequence: _missionSequence++,
              positionSeconds: _lastPosition.inSeconds,
              isPlaying: false,
            );
        if (!mounted) return;
        if (updated.status == 'active' || updated.status == 'completed') {
          setState(() {
            _missionWatch = updated;
            _offline = false;
          });
        } else {
          await ref
              .read(videoFeedRepositoryProvider)
              .interruptMissionVideoWatch(current.sessionId);
          setState(() => _missionWatch = null);
          await _startMissionWatch();
        }
      } on Object {
        if (mounted) setState(() => _offline = true);
      }
      return;
    }
    final videoId = _video.reportVideoId;
    if (videoId == null) return;
    final report = await _guard.report(
      () => ref
          .read(videoFeedRepositoryProvider)
          .recordProgress(videoId, _lastPosition.inSeconds, isPlaying: false),
    );
    if (!mounted) return;
    if (report.verdict == PlaybackVerdict.ok) {
      setState(() {
        _offline = false;
        _attempt++;
      });
    } else {
      _apply(report);
    }
  }

  void _stopForExhaustedAllowance() {
    if (!mounted || _allowanceExhausted) return;
    unawaited(_controller?.pause());
    setState(() => _allowanceExhausted = true);
    // Leave fullscreen/landscape first so the lock page is readable.
    unawaited(_setFullscreen(false));
    unawaited(showVideoLockScreen(context));
  }

  Future<void> _leave() async {
    vdiag(
      'detail.leave.begin',
      screen: 'detail',
      id: identityHashCode(this),
      extra: 'alreadyLeaving=$_leaving',
    );
    if (_leaving) return;
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) return;
    setState(() => _leaving = true);
    final missionWatch = _missionWatch;
    if (widget.launch.missionTaskId != null && missionWatch != null) {
      await _finishMissionWatch();
      if (mounted) navigator.pop();
      return;
    }
    final videoId = _video.reportVideoId;
    if (videoId != null && _tickets.handles) {
      await _tickets.finish(_controller?.position ?? _lastPosition);
    } else if (videoId != null) {
      try {
        await ref
            .read(videoFeedRepositoryProvider)
            .recordProgress(
              videoId,
              (_controller?.position ?? _lastPosition).inSeconds,
              isPlaying: false,
            );
      } on Object {
        // The route should still close if the final heartbeat cannot be sent.
      }
    }
    if (mounted) navigator.pop();
  }

  Future<void> _setFullscreen(bool value) async {
    if (value == _fullscreen) return;
    setState(() => _fullscreen = value);
    if (value) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await _restoreSystemUi();
    }
  }

  static Future<void> _restoreSystemUi() async {
    vdiag('systemUi.restore.begin', screen: 'detail');
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const []);
    vdiag('systemUi.restore.end', screen: 'detail');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    vdiag(
      'detail.appLifecycle',
      screen: 'detail',
      id: identityHashCode(this),
      extra: 'state=${state.name}',
    );
    // Nothing plays behind another app. The YouTube embed pauses itself.
    if (state != AppLifecycleState.resumed) {
      unawaited(_controller?.pause());
      if (widget.launch.missionTaskId != null) {
        _recordWatchProgress(
          _controller?.position ?? _lastPosition,
          _controller?.duration ?? Duration.zero,
          force: true,
          isPlaying: false,
        );
        return;
      }
      if (_tickets.handles) {
        _tickets.report(
          _controller?.position ?? _lastPosition,
          isPlaying: false,
        );
      }
    } else if (_tickets.handles) {
      // Ticket mode: playing again resumes the heartbeats.
    } else if (!_allowanceExhausted) {
      // Ask the server again (a paused report is free) so a lock that
      // happened meanwhile shows, instead of trusting what was on screen.
      _recordWatchProgress(
        _controller?.position ?? _lastPosition,
        Duration.zero,
        force: true,
        isPlaying: false,
      );
    }
  }

  @override
  void dispose() {
    vdiag(
      'detail.dispose.begin',
      screen: 'detail',
      id: identityHashCode(this),
      extra: 'fullscreen=$_fullscreen leaving=$_leaving',
    );
    WidgetsBinding.instance.removeObserver(this);
    _tickets.dispose();
    _release();
    _scroll.dispose();
    if (_fullscreen) unawaited(_restoreSystemUi());
    vdiag('detail.dispose.end', screen: 'detail', id: identityHashCode(this));
    super.dispose();
  }

  /// The server marked the mission's required watch time complete. Mission
  /// Stars and XP come from the parent's later approval, so none are shown.
  void _celebrateMissionVideoOnce() {
    if (_celebratedMissionVideo) return;
    _celebratedMissionVideo = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        showPandaCelebration(
          context,
          ActivityCompletion(
            kind: ActivityKind.video,
            title: widget.launch.video.title,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final upNext = _upNext;
    final stage = KeyedSubtree(
      key: ValueKey(('detail.stage', _video.key, _attempt)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _stage(context),
          if (_ended && !_allowanceExhausted)
            _EndOverlay(
              suggestions: widget.launch.missionTaskId == null
                  ? upNext.take(3).toList()
                  : const [],
              onPlay: _open,
              onReplay: _retry,
            ),
        ],
      ),
    );

    if (_fullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_setFullscreen(false));
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Column(
              children: [
                Expanded(child: Center(child: stage)),
                if (_controller != null)
                  _StreamControls(
                    controller: _controller!,
                    fullscreen: true,
                    muted: _muted,
                    onTogglePlay: _togglePlay,
                    onToggleMute: _toggleMute,
                    onToggleFullscreen: () => _setFullscreen(false),
                    dark: true,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final description = _video.description;
    final channel = _video.channelName;
    final reportId = _video.reportVideoId;

    return PopScope(
      canPop: _video.reportVideoId == null || _leaving,
      onPopInvokedWithResult: (didPop, _) {
        vdiag(
          'detail.popInvoked',
          screen: 'detail',
          id: identityHashCode(this),
          extra: 'didPop=$didPop',
        );
        if (!didPop && _video.reportVideoId != null) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(l10n.watchTitle),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // In landscape the player may use most of the height, so the
              // details never push it off screen.
              final maxStageHeight = constraints.maxHeight * 0.8;
              return ListView(
                key: const Key('detail.list'),
                controller: _scroll,
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxStageHeight),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: ColoredBox(
                        color: Colors.black,
                        child: AspectRatio(
                          aspectRatio:
                              _controller?.isInitialised == true && !_failed
                              ? _controller!.aspectRatio
                              : 16 / 9,
                          child: stage,
                        ),
                      ),
                    ),
                  ),
                  if (_controller != null && !_failed) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _StreamControls(
                      controller: _controller!,
                      fullscreen: false,
                      muted: _muted,
                      onTogglePlay: _togglePlay,
                      onToggleMute: _toggleMute,
                      onToggleFullscreen: () => _setFullscreen(true),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _video.title,
                    key: const Key('detail.title'),
                    style: context.text.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (channel != null)
                        EyebrowPill(
                          icon: Icons.person_pin_rounded,
                          label: channel,
                        ),
                      if (_video.duration != null)
                        EyebrowPill(
                          icon: Icons.schedule_rounded,
                          label: formatPlaybackTime(_video.duration!),
                        ),
                      if (_video.isYouTube)
                        EyebrowPill(
                          icon: Icons.smart_display_rounded,
                          label: l10n.videoBadgeYouTube,
                        ),
                    ],
                  ),
                  if (description != null && description.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    // Hidden until the child taps "more", like YouTube.
                    _DescriptionPanel(
                      key: ValueKey(('detail.descriptionPanel', _video.key)),
                      text: description,
                    ),
                  ],
                  if (_missionWatch != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.missionVideoProgress(
                        (_missionWatch!.progress.verifiedSeconds + 59) ~/ 60,
                        (_missionWatch!.progress.requiredSeconds + 59) ~/ 60,
                      ),
                      key: const Key('detail.mission.progress'),
                    ),
                    LinearProgressIndicator(
                      value:
                          (_missionWatch!.progress.verifiedSeconds /
                                  _missionWatch!.progress.requiredSeconds)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                    ),
                  ],
                  if (_video.isYouTube) ...[
                    const SizedBox(height: AppSpacing.md),
                    InlineNotice(
                      icon: Icons.info_outline_rounded,
                      message: l10n.videoFeedAdsNotice,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (upNext.isNotEmpty &&
                          widget.launch.missionTaskId == null)
                        PrimaryButton(
                          key: const Key('detail.next'),
                          label: l10n.videoPlayNext,
                          icon: Icons.skip_next_rounded,
                          childSized: true,
                          onPressed: () => _open(upNext.first),
                        ),
                      if (_video.shareUri != null)
                        SecondaryButton(
                          key: const Key('detail.share'),
                          label: l10n.videoShare,
                          icon: Icons.share_rounded,
                          dense: true,
                          onPressed: () =>
                              confirmAndShareVideo(context, ref, _video),
                        ),
                      if (reportId != null)
                        SecondaryButton(
                          key: const Key('detail.report'),
                          label: l10n.videoReport,
                          icon: Icons.flag_outlined,
                          dense: true,
                          onPressed: () => reportVideo(context, reportId),
                        ),
                    ],
                  ),
                  if (widget.launch.missionTaskId == null)
                    ..._upNextSection(context, upNext),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// "Up next" under the video, with its loading, error and empty states.
  List<Widget> _upNextSection(
    BuildContext context,
    List<PlayableVideo> upNext,
  ) {
    final l10n = AppLocalizations.of(context);
    final server = _serverNext;
    final header = [
      const SizedBox(height: AppSpacing.lg),
      Text(l10n.videoUpNext, style: context.text.titleLarge),
      const SizedBox(height: AppSpacing.sm),
    ];
    if (upNext.isNotEmpty) {
      return [
        ...header,
        for (final video in upNext)
          _UpNextTile(video: video, onTap: () => _open(video)),
      ];
    }
    if (server == null) return const [];
    if (server.isLoading) {
      return [
        ...header,
        const Center(
          key: Key('detail.upNext.loading'),
          child: CircularProgressIndicator(),
        ),
      ];
    }
    if (server.hasError) {
      return [
        ...header,
        InlineNotice(
          key: const Key('detail.upNext.error'),
          icon: Icons.wifi_off_rounded,
          message: l10n.videoUpNextFailed,
        ),
        const SizedBox(height: AppSpacing.sm),
        SecondaryButton(
          key: const Key('detail.upNext.retry'),
          label: l10n.videoRetry,
          icon: Icons.refresh_rounded,
          dense: true,
          onPressed: () =>
              ref.invalidate(nextVideosProvider(_video.reportVideoId!)),
        ),
      ];
    }
    return [
      ...header,
      Text(l10n.videoUpNextEmpty, key: const Key('detail.upNext.empty')),
    ];
  }

  Widget _stage(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final video = _video;
    final still = VideoThumbnail(
      url: video.thumbnailUrl,
      placeholderColor: Colors.black,
      iconColor: AppPalette.onPrimary,
    );
    final missionWatch = _missionWatch;
    if (widget.launch.missionTaskId != null && missionWatch == null) {
      return _StageNotice(
        key: const Key('detail.mission.initialising'),
        background: still,
        icon: _offline ? Icons.wifi_off_rounded : Icons.hourglass_top_rounded,
        message: _offline ? l10n.videoOfflinePaused : l10n.videoLoading,
        onRetry: _offline ? _startMissionWatch : null,
      );
    }
    if (widget.launch.missionTaskId != null &&
        missionWatch!.status != 'active') {
      final completed = missionWatch.status == 'completed';
      if (completed) _celebrateMissionVideoOnce();
      return _StageNotice(
        key: const Key('detail.mission.ended'),
        background: still,
        icon: completed ? Icons.verified_rounded : Icons.pause_circle_rounded,
        message: completed
            ? l10n.missionVideoComplete
            : l10n.missionVideoInterrupted,
        onRetry: completed ? null : _retry,
      );
    }
    final ticketMessage = ticketNotice(l10n, _tickets);
    if (ticketMessage != null &&
        !_allowanceExhausted &&
        video.source is! UnavailableSource) {
      return _StageNotice(
        key: const Key('detail.ticket'),
        background: still,
        icon: _tickets.stopReason == TicketStop.superseded
            ? Icons.devices_rounded
            : Icons.hourglass_top_rounded,
        message: ticketMessage,
        onRetry: ticketRetryable(_tickets) ? _retryTicket : null,
      );
    }
    switch (video.source) {
      case UnavailableSource(:final reason):
        return _StageNotice(
          key: const Key('detail.unavailable'),
          background: still,
          icon: Icons.lock_rounded,
          message: switch (reason) {
            VideoUnavailableReason.needsGrownUp => l10n.videoNeedsGrownUp,
            VideoUnavailableReason.timeUp => l10n.videoTimeExhaustedBody,
            VideoUnavailableReason.noSource => l10n.learnNotReady,
          },
        );
      case YouTubeVideoSource(:final videoId):
        if (_updateRequired) {
          return _StageNotice(
            key: const Key('detail.updateRequired'),
            background: still,
            icon: Icons.system_update_rounded,
            message: l10n.videoUpdateRequired,
          );
        }
        if (_offline && !_allowanceExhausted) {
          return _StageNotice(
            key: const Key('detail.offline'),
            background: still,
            icon: Icons.wifi_off_rounded,
            message: l10n.videoOfflinePaused,
            onRetry: _retryOnline,
          );
        }
        if (_allowanceExhausted) {
          return _StageNotice(
            key: const Key('detail.allowanceExhausted'),
            background: still,
            icon: Icons.lock_clock_rounded,
            message: l10n.videoAllowanceLocked,
          );
        }
        if (_blocked) {
          return _StageNotice(
            key: const Key('detail.blocked'),
            background: still,
            icon: Icons.block_rounded,
            message: l10n.videoNotEmbeddable,
          );
        }
        if (_failed) {
          return _StageNotice(
            key: const Key('detail.error'),
            background: still,
            icon: Icons.wifi_off_rounded,
            message: l10n.youtubePlayerError,
            onRetry: _retry,
          );
        }
        final embed = ref.watch(youtubeEmbedBuilderProvider);
        return embed(
          YouTubeEmbedConfig(
            videoId: videoId,
            autoplay: true,
            autoFullScreen: true,
            onLeaveRequested: (uri) => askGrownUpThenOpen(context, ref, uri),
            onForeignVideo: () {
              ScaffoldMessenger.maybeOf(context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text(l10n.youtubeOtherVideoBlocked)),
                );
            },
            onError: () {
              if (mounted && !_failed) setState(() => _failed = true);
            },
            onBlocked: () {
              if (mounted && !_blocked) setState(() => _blocked = true);
            },
            onProgress: _recordWatchProgress,
            onPlayingChanged: (isPlaying) => _recordWatchProgress(
              _lastPosition,
              video.duration ?? Duration.zero,
              force: true,
              isPlaying: isPlaying,
            ),
            onEnded: (duration) {
              if (widget.launch.missionTaskId != null) {
                _lastPosition = duration;
                unawaited(_finishMissionWatch());
              } else if (_tickets.handles) {
                _lastPosition = duration;
                unawaited(_tickets.finish(duration));
              } else {
                _recordWatchProgress(
                  duration,
                  duration,
                  force: true,
                  isPlaying: false,
                );
              }
              if (mounted && !_ended) setState(() => _ended = true);
            },
            startAtSeconds: video.resumePositionSeconds,
          ),
        );
      case DirectStreamSource():
        if (_failed) {
          return _StageNotice(
            key: const Key('detail.error'),
            background: still,
            icon: Icons.wifi_off_rounded,
            message: l10n.videoPlaybackFailed,
            onRetry: _retry,
          );
        }
        final controller = _controller!;
        return ListenableBuilder(
          listenable: controller.listenable,
          builder: (context, _) {
            final surface = controller.buildSurface();
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlay,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (surface == null)
                    still
                  else
                    Center(
                      child: AspectRatio(
                        aspectRatio: controller.aspectRatio,
                        child: surface,
                      ),
                    ),
                  if (surface == null || controller.isBuffering)
                    Center(
                      child: CircularProgressIndicator(
                        key: const Key('detail.loading'),
                        color: AppPalette.onPrimary,
                        semanticsLabel: l10n.videoLoading,
                      ),
                    ),
                ],
              ),
            );
          },
        );
    }
  }
}

/// Play/pause, seek bar, time, sound and fullscreen for a direct stream.
class _StreamControls extends StatefulWidget {
  const _StreamControls({
    required this.controller,
    required this.fullscreen,
    required this.muted,
    required this.onTogglePlay,
    required this.onToggleMute,
    required this.onToggleFullscreen,
    this.dark = false,
  });

  final VideoPlaybackController controller;
  final bool fullscreen;
  final bool muted;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleFullscreen;
  final bool dark;

  @override
  State<_StreamControls> createState() => _StreamControlsState();
}

class _StreamControlsState extends State<_StreamControls> {
  /// Thumb position while the child drags, so the bar does not jump back.
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = widget.controller;
    final foreground = widget.dark ? AppPalette.onPrimary : null;

    return ListenableBuilder(
      listenable: controller.listenable,
      builder: (context, _) {
        final ready = controller.isInitialised;
        final totalMs = controller.duration.inMilliseconds.toDouble();
        final positionMs =
            (_dragMs ?? controller.position.inMilliseconds.toDouble()).clamp(
              0.0,
              totalMs <= 0 ? 0.0 : totalMs,
            );
        final playing = controller.isPlaying;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.fullscreen ? AppSpacing.md : 0,
          ),
          child: Row(
            children: [
              IconButton.filled(
                key: const Key('detail.playPause'),
                iconSize: 32,
                tooltip: playing ? l10n.videoPause : l10n.videoPlay,
                onPressed: ready ? widget.onTogglePlay : null,
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              Expanded(
                child: Slider(
                  key: const Key('detail.seek'),
                  value: positionMs,
                  max: totalMs <= 0 ? 1 : totalMs,
                  semanticFormatterCallback: (_) =>
                      '${formatPlaybackTime(Duration(milliseconds: positionMs.round()))} / '
                      '${formatPlaybackTime(controller.duration)}',
                  onChanged: ready && totalMs > 0
                      ? (value) => setState(() => _dragMs = value)
                      : null,
                  onChangeEnd: ready && totalMs > 0
                      ? (value) async {
                          await controller.seekTo(
                            Duration(milliseconds: value.round()),
                          );
                          if (mounted) setState(() => _dragMs = null);
                        }
                      : null,
                ),
              ),
              // Shrinks (never wraps or overflows) at large text sizes.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${formatPlaybackTime(Duration(milliseconds: positionMs.round()))}'
                    ' / ${formatPlaybackTime(controller.duration)}',
                    key: const Key('detail.time'),
                    style: context.text.bodySmall?.copyWith(color: foreground),
                  ),
                ),
              ),
              IconButton(
                key: const Key('detail.mute'),
                color: foreground,
                tooltip: widget.muted ? l10n.videoUnmute : l10n.videoMute,
                onPressed: widget.onToggleMute,
                icon: Icon(
                  widget.muted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                ),
              ),
              IconButton(
                key: const Key('detail.fullscreen'),
                color: foreground,
                tooltip: widget.fullscreen
                    ? l10n.videoExitFullscreen
                    : l10n.videoFullscreen,
                onPressed: widget.onToggleFullscreen,
                icon: Icon(
                  widget.fullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StageNotice extends StatelessWidget {
  const _StageNotice({
    required this.background,
    required this.icon,
    required this.message,
    this.onRetry,
    super.key,
  });

  final Widget background;
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: 0.3, child: background),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 36, color: AppPalette.onPrimary),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(
                    color: AppPalette.onPrimary,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.icon(
                    key: const Key('detail.retry'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(l10n.videoRetry),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UpNextTile extends StatelessWidget {
  const _UpNextTile({required this.video, required this.onTap});

  final PlayableVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final duration = video.duration;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        key: Key('detail.upNext.${video.key}'),
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 128,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: VideoThumbnail(url: video.thumbnailUrl),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleMedium,
                    ),
                    if (duration != null || !video.isPlayable)
                      Row(
                        children: [
                          if (!video.isPlayable) ...[
                            Icon(
                              Icons.lock_rounded,
                              size: 14,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                          ],
                          if (duration != null)
                            Text(
                              formatPlaybackTime(duration),
                              style: context.text.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The video's description, collapsed out of sight until the child taps
/// "more". Nothing of it shows while collapsed.
class _DescriptionPanel extends StatefulWidget {
  const _DescriptionPanel({required this.text, super.key});

  final String text;

  @override
  State<_DescriptionPanel> createState() => _DescriptionPanelState();
}

class _DescriptionPanelState extends State<_DescriptionPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          key: const Key('detail.descriptionToggle'),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 48),
            alignment: AlignmentDirectional.centerStart,
          ),
          onPressed: () => setState(() => _open = !_open),
          child: Text(_open ? l10n.shortsLess : l10n.shortsMore),
        ),
        if (_open)
          Text(
            widget.text,
            key: const Key('detail.description'),
            style: context.text.bodyLarge,
          ),
      ],
    );
  }
}

/// Shown over the video when it ends: a few things to watch next, or watch it
/// again. Starting one goes through the same allowance check as any other.
class _EndOverlay extends StatelessWidget {
  const _EndOverlay({
    required this.suggestions,
    required this.onPlay,
    required this.onReplay,
  });

  final List<PlayableVideo> suggestions;
  final ValueChanged<PlayableVideo> onPlay;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ColoredBox(
      key: const Key('detail.endOverlay'),
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.videoWatchNext,
                style: context.text.titleMedium?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final video in suggestions)
                    InkWell(
                      key: Key('detail.end.${video.key}'),
                      onTap: () => onPlay(video),
                      child: SizedBox(
                        width: 112,
                        child: Column(
                          children: [
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: VideoThumbnail(url: video.thumbnailUrl),
                            ),
                            Text(
                              video.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              TextButton.icon(
                key: const Key('detail.end.replay'),
                onPressed: onReplay,
                icon: const Icon(Icons.replay_rounded, color: Colors.white),
                label: Text(
                  l10n.videoWatchAgain,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
