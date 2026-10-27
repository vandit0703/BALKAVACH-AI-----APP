import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

/// What the player screen needs from a video controller.
///
/// `video_player` cannot run in a widget test (it needs a platform decoder), so
/// the screen talks to this interface and tests supply a fake. A fake proves the
/// screen's own behaviour — loading, errors, pause/resume, disposal — and is
/// never evidence that a child watched anything: only server-accepted heartbeats
/// are that, and those come from the backend, not from here.
abstract class VideoPlaybackController {
  /// Fires on every playback state change.
  Listenable get listenable;

  bool get isInitialised;
  bool get isPlaying;
  bool get isBuffering;

  /// Non-null once playback has failed; the screen offers a retry.
  String? get errorMessage;

  Duration get position;
  Duration get duration;

  /// Natural aspect ratio, or a 16:9 fallback before that is known.
  double get aspectRatio;

  Future<void> initialise();
  Future<void> play();
  Future<void> pause();
  Future<void> dispose();

  /// The picture. Returns null until there is something to show.
  Widget? buildSurface();
}

/// Real playback, backed by `video_player` (ExoPlayer on Android).
class NetworkVideoPlaybackController
    with ChangeNotifier
    implements VideoPlaybackController {
  NetworkVideoPlaybackController(this.uri);

  static const initialiseTimeout = Duration(seconds: 30);

  final Uri uri;
  VideoPlayerController? _controller;
  String? _error;
  bool _disposed = false;

  @override
  Listenable get listenable => this;

  @override
  bool get isInitialised => _controller?.value.isInitialized ?? false;

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  @override
  bool get isBuffering => _controller?.value.isBuffering ?? false;

  @override
  String? get errorMessage => _error;

  @override
  Duration get position => _controller?.value.position ?? Duration.zero;

  @override
  Duration get duration => _controller?.value.duration ?? Duration.zero;

  @override
  double get aspectRatio {
    final ratio = _controller?.value.aspectRatio;
    // A not-yet-known or degenerate ratio would collapse the layout.
    return (ratio == null || ratio <= 0) ? 16 / 9 : ratio;
  }

  @override
  Future<void> initialise() async {
    if (_disposed) return;
    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    controller.addListener(_onPlayerChanged);
    try {
      // A source that never answers (or is not media at all) must end in the
      // retry state, not an endless spinner.
      await controller.initialize().timeout(initialiseTimeout);
      // Disposal can win the race while initialise() is awaited.
      if (_disposed) {
        await controller.dispose();
        return;
      }
      _error = null;
    } catch (error) {
      _error = error.toString();
    }
    if (!_disposed) notifyListeners();
  }

  void _onPlayerChanged() {
    if (_disposed) return;
    final value = _controller?.value;
    if (value != null && value.hasError) {
      _error = value.errorDescription ?? 'playback_failed';
    }
    notifyListeners();
  }

  @override
  Future<void> play() async {
    if (_disposed || !isInitialised) return;
    await _controller?.play();
  }

  @override
  Future<void> pause() async {
    if (_disposed || !isInitialised) return;
    await _controller?.pause();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onPlayerChanged);
    // Releasing the decoder matters: a leaked controller keeps audio playing
    // after the screen is gone.
    await controller?.dispose();
    super.dispose();
  }

  @override
  Widget? buildSurface() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    return VideoPlayer(controller);
  }
}

/// Builds the controller for a video. Overridden in tests with a fake.
typedef VideoPlaybackControllerFactory =
    VideoPlaybackController Function(Uri uri);

final videoPlaybackControllerFactoryProvider =
    Provider<VideoPlaybackControllerFactory>(
      (ref) => NetworkVideoPlaybackController.new,
    );
