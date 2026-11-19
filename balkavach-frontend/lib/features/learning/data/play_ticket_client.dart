import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';

/// D6 play tickets on the device. **Off by default** and not yet used by the
/// players: the server refuses tickets until its deferred `video_play_tickets`
/// table exists, and `record_progress` stays the metering path meanwhile.
/// Build with `--dart-define=VIDEO_PLAY_TICKETS=true` only together with a
/// server that has tickets active.
const kPlayTicketsEnabled = bool.fromEnvironment('VIDEO_PLAY_TICKETS');

/// `POST /api/v1/video-access/tickets` reply.
@immutable
class PlayTicket {
  const PlayTicket({
    required this.id,
    required this.token,
    required this.videoId,
    required this.youtubeVideoId,
    required this.heartbeatInterval,
    required this.remainingSeconds,
  });

  factory PlayTicket.fromJson(Map<String, dynamic> json) => PlayTicket(
    id: json['ticket_id'] as String,
    token: json['ticket_token'] as String,
    videoId: json['video_id'] as String,
    youtubeVideoId: json['youtube_video_id'] as String?,
    heartbeatInterval: Duration(
      seconds: (json['heartbeat_interval_seconds'] as num?)?.toInt() ?? 10,
    ),
    remainingSeconds: (json['remaining_seconds'] as num).toInt(),
  );

  final String id;

  /// Secret for this ticket only. Never logged.
  final String token;
  final String videoId;
  final String? youtubeVideoId;
  final Duration heartbeatInterval;
  final int remainingSeconds;

  @override
  String toString() => 'PlayTicket($id)';
}

@immutable
class TicketStatus {
  const TicketStatus({
    required this.state,
    required this.remainingSeconds,
    required this.isExhausted,
  });

  factory TicketStatus.fromJson(Map<String, dynamic> json) => TicketStatus(
    state: json['state'] as String,
    remainingSeconds: (json['remaining_seconds'] as num).toInt(),
    isExhausted: json['is_exhausted'] as bool? ?? false,
  );

  final String state;
  final int remainingSeconds;
  final bool isExhausted;

  bool get active => const {'issued', 'playing', 'paused'}.contains(state);
}

class PlayTicketApi {
  PlayTicketApi(this._dio);

  final Dio _dio;

  Future<PlayTicket> create(String videoId, String deviceSessionId) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/v1/video-access/tickets',
          data: {'video_id': videoId, 'device_session_id': deviceSessionId},
        );
        return PlayTicket.fromJson(response.data!);
      });

  Future<TicketStatus> heartbeat(
    PlayTicket ticket, {
    required int sequence,
    required bool isPlaying,
    required int positionSeconds,
  }) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/video-access/tickets/${ticket.id}/heartbeat',
      data: {
        'ticket_token': ticket.token,
        'sequence': sequence,
        'is_playing': isPlaying,
        'position_seconds': positionSeconds,
      },
    );
    return TicketStatus.fromJson(response.data!);
  });

  Future<TicketStatus> end(
    PlayTicket ticket, {
    required int sequence,
    required int positionSeconds,
  }) => guardApi(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/video-access/tickets/${ticket.id}/end',
      data: {
        'ticket_token': ticket.token,
        'sequence': sequence,
        'position_seconds': positionSeconds,
      },
    );
    return TicketStatus.fromJson(response.data!);
  });
}

final playTicketApiProvider = Provider<PlayTicketApi>(
  (ref) => PlayTicketApi(ref.watch(apiDioProvider)),
);

/// Why the app must stop the player.
enum TicketStop {
  /// The same child started a video on another device.
  superseded,

  /// The ticket lapsed (missed heartbeats, local midnight). Ask for a new one.
  expired,

  /// A parent/admin revoked it, or the video is no longer allowed.
  revoked,

  /// Today's video time is used up: show the lock page.
  exhausted,

  /// Heartbeats keep failing: unverified playback is never free.
  offline,

  /// The ticket was refused as invalid or unknown.
  invalid,
}

/// How a start attempt ended.
sealed class TicketStart {
  const TicketStart();
}

class TicketGranted extends TicketStart {
  const TicketGranted(this.ticket);
  final PlayTicket ticket;
}

class TicketRefused extends TicketStart {
  const TicketRefused(this.reason);
  final TicketStop reason;
}

/// The server has no tickets yet (503 `play_tickets_unavailable`): use the
/// existing `record_progress` path. Never a reason to play unmetered.
class TicketsUnavailable extends TicketStart {
  const TicketsUnavailable();
}

/// One ticket's life on the device: start → heartbeats while playing →
/// end. It never measures or grants time: the server charges, from its own
/// clock; this only reports and obeys.
///
/// * Heartbeats run only while the player reports playing, every
///   `heartbeatInterval`, plus one at each play/pause change.
/// * Sequence numbers only go up, including after failures, so a retried
///   heartbeat is never mistaken for an old one.
/// * Any refusal stops playback through [onStop]. Two failed heartbeats in a
///   row stop it too (`offline`).
class PlayTicketSession {
  PlayTicketSession({
    required this.api,
    required this.onStop,
    this.onRemaining,
    this.maxConsecutiveFailures = 2,
    String? deviceSessionId,
  }) : deviceSessionId = deviceSessionId ?? newDeviceSessionId();

  final PlayTicketApi api;
  final void Function(TicketStop reason) onStop;
  final void Function(int remainingSeconds)? onRemaining;
  final int maxConsecutiveFailures;
  final String deviceSessionId;

  PlayTicket? _ticket;
  Timer? _timer;
  int _sequence = -1;
  int _failures = 0;
  int _position = 0;
  bool _playing = false;
  bool _stopped = false;
  bool _inFlight = false;

  /// A play/pause change arrived while a heartbeat was in flight: send it as
  /// soon as that one returns, so a pause is never lost (a lost pause would
  /// let the server charge the paused time as playing).
  bool _pending = false;

  PlayTicket? get ticket => _ticket;
  bool get playing => _playing;
  bool get stopped => _stopped;
  int get lastSequence => _sequence;

  /// Asks the server for a ticket. Playback may start only on [TicketGranted].
  Future<TicketStart> start(String videoId) async {
    try {
      final ticket = await api.create(videoId, deviceSessionId);
      _ticket = ticket;
      _stopped = false;
      onRemaining?.call(ticket.remainingSeconds);
      return TicketGranted(ticket);
    } on ServerException catch (error) {
      if (error.code == 'play_tickets_unavailable') {
        return const TicketsUnavailable();
      }
      return const TicketRefused(TicketStop.offline);
    } on ApiException catch (error) {
      return TicketRefused(_reasonFor(error) ?? TicketStop.offline);
    }
  }

  /// The player started (or resumed) playing.
  void onPlaying(int positionSeconds) {
    if (_ticket == null || _stopped) return;
    _position = positionSeconds;
    if (_playing) return;
    _playing = true;
    unawaited(_beat());
    _timer?.cancel();
    _timer = Timer.periodic(_ticket!.heartbeatInterval, (_) => _beat());
  }

  /// Keeps the reported position current between heartbeats.
  void onPosition(int positionSeconds) => _position = positionSeconds;

  /// Paused, buffering, app in the background, screen locked.
  void onPaused(int positionSeconds) {
    if (_ticket == null || _stopped) return;
    _position = positionSeconds;
    _timer?.cancel();
    _timer = null;
    if (!_playing) return;
    _playing = false;
    unawaited(_beat());
  }

  /// Playback finished or the child left the player.
  Future<void> end(int positionSeconds) async {
    final ticket = _ticket;
    _timer?.cancel();
    _timer = null;
    _playing = false;
    if (ticket == null || _stopped) return;
    _stopped = true;
    try {
      await api.end(
        ticket,
        sequence: ++_sequence,
        positionSeconds: positionSeconds,
      );
    } on ApiException {
      // The server lapses an unended ticket by itself; nothing to grant here.
    }
  }

  Future<void> _beat() async {
    final ticket = _ticket;
    if (ticket == null || _stopped) return;
    if (_inFlight) {
      _pending = true;
      return;
    }
    _inFlight = true;
    final playingNow = _playing;
    try {
      final status = await api.heartbeat(
        ticket,
        sequence: ++_sequence,
        isPlaying: playingNow,
        positionSeconds: _position,
      );
      _failures = 0;
      onRemaining?.call(status.remainingSeconds);
      if (status.isExhausted || status.state == 'exhausted') {
        _stop(TicketStop.exhausted);
      } else if (!status.active) {
        _stop(
          status.state == 'revoked' ? TicketStop.revoked : TicketStop.expired,
        );
      }
    } on ApiException catch (error) {
      final reason = _reasonFor(error);
      if (reason != null) {
        _stop(reason);
      } else if (++_failures >= maxConsecutiveFailures) {
        _stop(TicketStop.offline);
      }
    } finally {
      _inFlight = false;
    }
    if (_pending && !_stopped) {
      _pending = false;
      await _beat();
    }
  }

  void _stop(TicketStop reason) {
    if (_stopped) return;
    _stopped = true;
    _playing = false;
    _timer?.cancel();
    _timer = null;
    onStop(reason);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// A refusal that must stop playback, or null for a transient failure.
  static TicketStop? _reasonFor(ApiException error) => switch (error.code) {
    'ticket_superseded' => TicketStop.superseded,
    'ticket_expired' || 'ticket_ended' => TicketStop.expired,
    'ticket_revoked' => TicketStop.revoked,
    'ticket_exhausted' || 'video_time_exhausted' => TicketStop.exhausted,
    'ticket_invalid' || 'ticket_sequence_invalid' => TicketStop.invalid,
    _ when error is NotFoundException => TicketStop.invalid,
    _ when error is ForbiddenException => TicketStop.revoked,
    _ => null,
  };
}

final _random = Random.secure();

/// Random id for this app run's playback, sent with each ticket request.
String newDeviceSessionId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return 'd-${List.generate(24, (_) => chars[_random.nextInt(chars.length)]).join()}';
}
