// D6 play-ticket client. MOCKED: a fake Dio backend stands in for the server
// (which refuses tickets until its deferred table exists). The players do not
// use this client yet; these tests pin its behaviour for when they do.

import 'package:balkavach_app/core/network/access_token_store.dart';
import 'package:balkavach_app/features/learning/data/play_ticket_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

const _create = '/api/v1/video-access/tickets';
const _beat = '/api/v1/video-access/tickets/t-1/heartbeat';
const _end = '/api/v1/video-access/tickets/t-1/end';

Map<String, Object?> ticketJson({int remaining = 900}) => {
  'ticket_id': 't-1',
  'ticket_token': 'tok_${'x' * 40}',
  'video_id': 'v-1',
  'youtube_video_id': 'abcdefghijk',
  'expires_at': '2026-11-19T12:01:00Z',
  'heartbeat_interval_seconds': 10,
  'remaining_seconds': remaining,
};

Map<String, Object?> status(String state, {int remaining = 800}) => {
  'ticket_id': 't-1',
  'state': state,
  'accepted_seconds': 10,
  'remaining_seconds': remaining,
  'is_exhausted': state == 'exhausted',
  'duplicate': false,
};

class Rig {
  Rig() {
    backend.reply('POST', _create, ticketJson(), status: 201);
    backend.on('POST', _beat, (_) => reply());
    backend.reply('POST', _end, status('ended'));
    final dio = createTestDio(backend, AccessTokenStore());
    session = PlayTicketSession(
      api: PlayTicketApi(dio),
      onStop: stops.add,
      onRemaining: remaining.add,
      deviceSessionId: 'device-test-0001',
    );
  }

  final backend = FakeBackend();
  final stops = <TicketStop>[];
  final remaining = <int>[];
  FakeReply Function() reply = () => FakeReply(200, status('playing'));
  late final PlayTicketSession session;

  List<Map<String, dynamic>> get beats => [
    for (final r in backend.requestsTo('POST', _beat))
      Map<String, dynamic>.from(r.data as Map),
  ];
}

void main() {
  test('playback may start only with a granted ticket', () async {
    final rig = Rig();
    final start = await rig.session.start('v-1');
    expect(start, isA<TicketGranted>());
    expect((start as TicketGranted).ticket.youtubeVideoId, 'abcdefghijk');
    final sent = rig.backend.requestsTo('POST', _create).single.data as Map;
    expect(sent['device_session_id'], 'device-test-0001');
    expect(start.ticket.toString(), isNot(contains('tok_')));
  });

  test(
    'a server without tickets means "use the existing path", not "free"',
    () async {
      final rig = Rig();
      rig.backend.reply('POST', _create, {
        'error': {'code': 'play_tickets_unavailable', 'message': 'off'},
      }, status: 503);
      expect(await rig.session.start('v-1'), isA<TicketsUnavailable>());
    },
  );

  test('no time left: the start is refused as exhausted', () async {
    final rig = Rig();
    rig.backend.reply('POST', _create, {
      'error': {'code': 'video_time_exhausted', 'message': 'none'},
    }, status: 403);
    final start = await rig.session.start('v-1');
    expect((start as TicketRefused).reason, TicketStop.exhausted);
  });

  testWidgets('heartbeats run only while playing, with rising sequences', (
    tester,
  ) async {
    final rig = Rig();
    await tester.runAsync(() => rig.session.start('v-1'));
    expect(rig.beats, isEmpty, reason: 'a ticket alone sends nothing');

    rig.session.onPlaying(0);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(seconds: 10));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    rig.session.onPaused(12);
    // Let the pause heartbeat (and any queued one) reach the fake server.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 60));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 60));
    // Play, one periodic beat, the pause; then nothing while paused.
    expect([for (final b in rig.beats) b['is_playing']], [true, true, false]);

    final sequences = [for (final b in rig.beats) b['sequence'] as int];
    expect(sequences, [for (var i = 0; i < sequences.length; i++) i]);
    expect(rig.beats.first['is_playing'], isTrue);
    expect(rig.beats.last['is_playing'], isFalse);
    expect(rig.beats.last['position_seconds'], 12);
    rig.session.dispose();
  });

  for (final (code, httpStatus, reason) in [
    ('ticket_superseded', 409, TicketStop.superseded),
    ('ticket_expired', 409, TicketStop.expired),
    ('ticket_revoked', 403, TicketStop.revoked),
    ('ticket_exhausted', 403, TicketStop.exhausted),
    ('ticket_invalid', 403, TicketStop.invalid),
    ('ticket_sequence_invalid', 409, TicketStop.invalid),
  ]) {
    test('a $code refusal stops playback', () async {
      final rig = Rig();
      await rig.session.start('v-1');
      rig.reply = () => FakeReply.error(httpStatus, code, 'refused');
      rig.session.onPlaying(0);
      // Real-time wait for the in-flight heartbeat: poll instead of a fixed
      // 10 ms, which lost the race when the full suite ran many isolates.
      for (var i = 0; i < 200 && rig.stops.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(rig.stops, [reason]);
      expect(rig.session.stopped, isTrue);
      rig.session.dispose();
    });
  }

  test(
    'a pause during an in-flight heartbeat is still sent, never lost',
    () async {
      final rig = Rig();
      await rig.session.start('v-1');
      rig.session.onPlaying(0); // heartbeat 0 is now in flight
      rig.session.onPaused(4); // must not be dropped
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect([for (final b in rig.beats) b['is_playing']], [true, false]);
      expect([for (final b in rig.beats) b['sequence']], [0, 1]);
      rig.session.dispose();
    },
  );

  test('an exhausted answer stops playback and reports zero', () async {
    final rig = Rig();
    await rig.session.start('v-1');
    rig.reply = () => FakeReply(200, status('exhausted', remaining: 0));
    rig.session.onPlaying(0);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(rig.stops, [TicketStop.exhausted]);
    expect(rig.remaining.last, 0);
  });

  testWidgets('network failures stop playback after two misses, never grant', (
    tester,
  ) async {
    final rig = Rig();
    await tester.runAsync(() => rig.session.start('v-1'));
    rig.reply = () => const FakeReply.fail(DioExceptionType.connectionError);
    rig.session.onPlaying(0);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(rig.stops, isEmpty, reason: 'one failure is tolerated');
    await tester.pump(const Duration(seconds: 10));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(rig.stops, [TicketStop.offline]);
    // Sequences kept rising across the failures.
    expect([for (final b in rig.beats) b['sequence']], [0, 1]);
    await tester.pump(const Duration(seconds: 30));
    expect(rig.beats.length, 2, reason: 'stopped means no more heartbeats');
  });

  test('ending sends a final report once, with the next sequence', () async {
    final rig = Rig();
    await rig.session.start('v-1');
    rig.session.onPlaying(0);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await rig.session.end(30);
    await rig.session.end(30);
    final ends = rig.backend.requestsTo('POST', _end);
    expect(ends, hasLength(1));
    expect((ends.single.data as Map)['sequence'], rig.session.lastSequence);
    expect((ends.single.data as Map)['position_seconds'], 30);
  });

  test('the feature is off unless the build turns it on', () {
    expect(kPlayTicketsEnabled, isFalse);
  });
}
