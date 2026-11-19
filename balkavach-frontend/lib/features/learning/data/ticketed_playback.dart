import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'play_ticket_client.dart';

/// Whether players use play tickets. Off unless the build passes
/// `--dart-define=VIDEO_PLAY_TICKETS=true`; tests override it.
final playTicketModeProvider = Provider<bool>((ref) => kPlayTicketsEnabled);

enum TicketPhase {
  /// Tickets are off (or the server has none): the existing
  /// `record_progress` path meters this playback.
  legacy,

  /// Ticket mode, no ticket yet: nothing may play.
  idle,

  /// Asking the server for a ticket: nothing may play.
  requesting,

  /// A ticket is held: playback is allowed, heartbeats meter it.
  granted,

  /// The server refused or the network failed: playback must stay stopped.
  stopped,
}

/// The play-ticket side of one player, shared by the regular player, the
/// detail player and each Shorts page so the lifecycle lives in one place.
///
/// Rules:
/// * With tickets off this stays [TicketPhase.legacy] forever and the player
///   keeps its existing `record_progress` behaviour.
/// * `play_tickets_unavailable` **before the first ticket** falls back to
///   legacy. Once a ticket has been issued, nothing ever falls back: any later
///   refusal or failure stops playback ([TicketPhase.stopped]).
/// * While [handles] is true the player must not call `record_progress`, so
///   the two charging paths can never run together.
class TicketedPlayback {
  TicketedPlayback({
    required bool enabled,
    required this.api,
    required this.onChanged,
    this.onRemaining,
  }) : _phase = enabled ? TicketPhase.idle : TicketPhase.legacy;

  /// Resolves the API client when a ticket is requested.
  final PlayTicketApi Function() api;

  /// The phase or stop reason changed: rebuild.
  final VoidCallback onChanged;
  final void Function(int remainingSeconds)? onRemaining;

  TicketPhase _phase;
  TicketStop? _stopReason;
  PlayTicketSession? _session;
  bool _everIssued = false;
  bool _disposed = false;
  bool _finishRequested = false;
  Duration _position = Duration.zero;

  TicketPhase get phase => _phase;
  TicketStop? get stopReason => _stopReason;

  /// True when tickets meter this playback (or would, once granted): the
  /// player must then not use `record_progress`.
  bool get handles => _phase != TicketPhase.legacy;

  /// True while playback must wait for a ticket.
  bool get waiting =>
      _phase == TicketPhase.idle || _phase == TicketPhase.requesting;

  /// Playback may run (legacy, or a ticket is held).
  bool get mayPlay =>
      _phase == TicketPhase.legacy || _phase == TicketPhase.granted;

  void _set(TicketPhase phase, [TicketStop? reason]) {
    _phase = phase;
    _stopReason = reason;
    if (!_disposed) onChanged();
  }

  /// Asks for a ticket for [videoId]. Repeated calls while one is pending or
  /// held do nothing.
  Future<void> begin(String videoId) async {
    if (_disposed ||
        _phase == TicketPhase.legacy ||
        _phase == TicketPhase.requesting ||
        _phase == TicketPhase.granted) {
      return;
    }
    _finishRequested = false;
    _set(TicketPhase.requesting);
    final session = PlayTicketSession(
      api: api(),
      onStop: _onStop,
      onRemaining: onRemaining,
    );
    final start = await session.start(videoId);
    if (_disposed) {
      if (start is TicketGranted) unawaited(session.end(_position.inSeconds));
      session.dispose();
      return;
    }
    switch (start) {
      case TicketGranted():
        _everIssued = true;
        _session = session;
        _set(TicketPhase.granted);
        if (_finishRequested) await finish(_position);
      case TicketsUnavailable():
        session.dispose();
        // Safe only before anything was issued: the server meters through
        // record_progress then. Afterwards, stopping is the only safe answer.
        _everIssued
            ? _set(TicketPhase.stopped, TicketStop.offline)
            : _set(TicketPhase.legacy);
      case TicketRefused(:final reason):
        session.dispose();
        _set(TicketPhase.stopped, reason);
    }
  }

  void _onStop(TicketStop reason) {
    _session?.dispose();
    _session = null;
    _set(TicketPhase.stopped, reason);
  }

  /// The player's existing progress callback, in ticket mode. Playing starts
  /// (or keeps) heartbeats; not playing sends one pause heartbeat and stops
  /// them. Ignored while no ticket is held.
  void report(Duration position, {required bool isPlaying}) {
    _position = position;
    final session = _session;
    if (_phase != TicketPhase.granted || session == null) return;
    isPlaying
        ? session.onPlaying(position.inSeconds)
        : session.onPaused(position.inSeconds);
    session.onPosition(position.inSeconds);
  }

  /// Ends the held ticket once (finished, left, swiped away). Afterwards the
  /// player may [begin] again for another playback.
  Future<void> finish(Duration position) async {
    _position = position;
    if (_phase == TicketPhase.requesting) {
      _finishRequested = true;
      return;
    }
    final session = _session;
    if (session == null) return;
    _session = null;
    await session.end(position.inSeconds);
    session.dispose();
    if (_phase == TicketPhase.granted) _set(TicketPhase.idle);
  }

  /// Back to waiting after a stop, so Retry can ask for a fresh ticket.
  void reset() {
    if (_phase == TicketPhase.stopped) _set(TicketPhase.idle);
  }

  /// Player gone: end a held ticket (best effort) and stop all timers.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final session = _session;
    _session = null;
    if (session != null) {
      unawaited(session.end(_position.inSeconds));
      session.dispose();
    }
  }
}

/// A [TicketedPlayback] wired to the app's providers. [metered] is false for
/// playback the server does not meter at all (curated Learn & Watch links
/// without a video row): those never wait for a ticket.
TicketedPlayback ticketedPlaybackFor(
  WidgetRef ref, {
  required bool metered,
  required VoidCallback onChanged,
  void Function(int remainingSeconds)? onRemaining,
}) => TicketedPlayback(
  enabled: metered && ref.read(playTicketModeProvider),
  api: () => ref.read(playTicketApiProvider),
  onChanged: onChanged,
  onRemaining: onRemaining,
);
