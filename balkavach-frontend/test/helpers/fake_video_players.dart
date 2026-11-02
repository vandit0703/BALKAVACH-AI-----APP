import 'package:balkavach_app/features/learning/data/video_playback_controller.dart';
import 'package:balkavach_app/features/learning/presentation/youtube_player_screen.dart';
import 'package:balkavach_app/shared/platform/link_opener.dart';
import 'package:balkavach_app/shared/platform/text_sharer.dart';
import 'package:flutter/material.dart';

/// PLAYER MOCKS. These stand in for `video_player` (which needs a platform
/// decoder) and the YouTube web view (which needs a platform view). They prove
/// how SCREENS drive players: which player exists, when it plays, pauses and
/// is disposed. They are never evidence that real video decoded, buffered or
/// played on a device, and never evidence that a child watched anything.

class RecordingPlaybackController implements VideoPlaybackController {
  RecordingPlaybackController(
    this.uri, {
    this.failOnInitialise = false,
    this.aspect = 9 / 16,
  });

  /// The picture's shape as the decoder would report it.
  final double aspect;

  final Uri uri;
  bool failOnInitialise;
  final ChangeNotifier _notifier = ChangeNotifier();

  int initialiseCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  bool disposed = false;
  double volume = 1;
  final seeks = <Duration>[];
  bool _initialised = false;
  bool _playing = false;
  bool _buffering = false;
  String? _error;

  void notify() => _notifier.notifyListeners();

  /// Simulates the decoder reporting a failure mid-playback.
  void failNow() {
    _error = 'network dropped';
    _playing = false;
    notify();
  }

  set buffering(bool value) {
    _buffering = value;
    notify();
  }

  @override
  Listenable get listenable => _notifier;
  @override
  bool get isInitialised => _initialised;
  @override
  bool get isPlaying => _playing && !disposed;
  @override
  bool get isBuffering => _buffering;
  @override
  String? get errorMessage => _error;
  @override
  Duration get position => const Duration(seconds: 15);
  @override
  Duration get duration => const Duration(seconds: 60);
  @override
  double get aspectRatio => aspect;

  @override
  Future<void> initialise() async {
    initialiseCount++;
    if (failOnInitialise) {
      _error = 'decoder failed';
    } else {
      _error = null;
      _initialised = true;
    }
    notify();
  }

  @override
  Future<void> play() async {
    if (disposed) throw StateError('play() after dispose()');
    playCount++;
    _playing = true;
    notify();
  }

  @override
  Future<void> pause() async {
    if (disposed) throw StateError('pause() after dispose()');
    pauseCount++;
    _playing = false;
    notify();
  }

  @override
  Future<void> seekTo(Duration position) async => seeks.add(position);

  @override
  Future<void> setVolume(double value) async => volume = value;

  @override
  Future<void> dispose() async {
    disposed = true;
    _playing = false;
  }

  @override
  Widget? buildSurface() => _initialised
      ? ColoredBox(key: Key('fake.surface.$uri'), color: Colors.black)
      : null;
}

/// Hands out [RecordingPlaybackController]s and remembers every one.
class PlaybackRegistry {
  final created = <RecordingPlaybackController>[];

  /// Streams whose URL contains this text fail to initialise.
  String? failUrlsContaining;

  /// Shape reported by every new controller (portrait by default).
  double aspect = 9 / 16;

  VideoPlaybackController create(Uri uri) {
    final fail =
        failUrlsContaining != null &&
        uri.toString().contains(failUrlsContaining!);
    final controller = RecordingPlaybackController(
      uri,
      failOnInitialise: fail,
      aspect: aspect,
    );
    created.add(controller);
    return controller;
  }

  List<RecordingPlaybackController> get live => [
    for (final c in created)
      if (!c.disposed) c,
  ];

  List<RecordingPlaybackController> get playing => [
    for (final c in created)
      if (c.isPlaying) c,
  ];

  List<RecordingPlaybackController> forUrl(String url) => [
    for (final c in created)
      if (c.uri.toString() == url) c,
  ];
}

/// Stands in for the official YouTube embed and records what it was asked
/// to show. A mounted fake embed counts as "playing" when autoplay is on.
class EmbedRecorder {
  /// Every config an embed was ever built with, in order.
  final history = <YouTubeEmbedConfig>[];

  /// Embeds currently on screen, by video id.
  final mounted = <String, YouTubeEmbedConfig>{};

  Widget build(YouTubeEmbedConfig config) =>
      _FakeEmbed(config: config, recorder: this);

  YouTubeEmbedConfig only() {
    if (mounted.length != 1) {
      throw StateError('expected one embed, found ${mounted.keys.toList()}');
    }
    return mounted.values.single;
  }
}

class _FakeEmbed extends StatefulWidget {
  const _FakeEmbed({required this.config, required this.recorder});

  final YouTubeEmbedConfig config;
  final EmbedRecorder recorder;

  @override
  State<_FakeEmbed> createState() => _FakeEmbedState();
}

class _FakeEmbedState extends State<_FakeEmbed> {
  @override
  void initState() {
    super.initState();
    widget.recorder.history.add(widget.config);
    widget.recorder.mounted[widget.config.videoId] = widget.config;
  }

  @override
  void didUpdateWidget(_FakeEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.recorder.mounted[widget.config.videoId] = widget.config;
  }

  @override
  void dispose() {
    widget.recorder.mounted.remove(widget.config.videoId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: Key('test.youtubeEmbed.${widget.config.videoId}'),
    color: Colors.black,
    // The real embed draws the overlay in its controls layer, above the
    // web view, sized to the player box. The fake does the same in-tree.
    child: AspectRatio(
      aspectRatio: widget.config.aspectRatio ?? 16 / 9,
      child: Stack(fit: StackFit.expand, children: [?widget.config.overlay]),
    ),
  );
}

class RecordingLinkOpener implements LinkOpener {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

class RecordingSharer implements TextSharer {
  final shared = <String>[];

  @override
  Future<bool> share(String text, {String? subject}) async {
    shared.add(text);
    return true;
  }
}
