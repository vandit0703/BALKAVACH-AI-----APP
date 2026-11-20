// Shorts and play tickets (D6). Verified against a FAKE BACKEND and PLAYER
// MOCKS (test/helpers/fake_video_players.dart): these tests prove how the
// Shorts pages drive the ticket lifecycle; they are not device verification,
// and the server's ticket table does not exist yet (tickets stay off in
// production builds: VIDEO_PLAY_TICKETS defaults to false).

import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/features/learning/data/playable_video.dart';
import 'package:balkavach_app/features/learning/data/playback_guard.dart';
import 'package:balkavach_app/features/learning/data/ticketed_playback.dart';
import 'package:balkavach_app/features/learning/data/video_playback_controller.dart';
import 'package:balkavach_app/features/learning/presentation/shorts_feed.dart';
import 'package:balkavach_app/features/learning/presentation/youtube_player_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_video_players.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _shortsPath = '/api/v1/videos/shorts';
const _ticketsPath = '/api/v1/video-access/tickets';
final _heartbeat = RegExp(r'/api/v1/video-access/tickets/[^/]+/heartbeat$');
final _end = RegExp(r'/api/v1/video-access/tickets/[^/]+/end$');
final _progress = RegExp(r'/api/v1/videos/watch-history/[^/]+/progress$');

String _ytId(int i) => 'abcdefghi${i.toString().padLeft(2, '0')}';

List<Map<String, Object?>> _shorts(int count) => [
  for (var i = 0; i < count; i++)
    {
      'id': 'short-$i',
      'title': 'Short $i',
      'description': null,
      'thumbnail_url': null,
      'duration_seconds': 45,
      'category_id': null,
      'language_code': 'en',
      'content_rating': 'educational',
      'video_source': 'youtube',
      'youtube_video_id': _ytId(i),
      'channel_name': 'Kids Science Club',
      'last_position_seconds': 0,
    },
];

class _Rig {
  _Rig(this.h, this.embeds);
  final Harness h;
  final EmbedRecorder embeds;

  List<RequestOptions> matching(String method, RegExp path) => h
      .backend
      .requests
      .where((r) => r.method == method && path.hasMatch(r.path))
      .toList();

  List<RequestOptions> get ticketStarts => h.backend.requestsTo('POST', _ticketsPath);
  List<RequestOptions> get heartbeats => matching('POST', _heartbeat);
  List<RequestOptions> get ends => matching('POST', _end);
  List<RequestOptions> get progressReports => matching('POST', _progress);
}

Future<_Rig> _pump(
  WidgetTester tester, {
  required bool tickets,
  FakeReply Function(RequestOptions)? start,
  FakeReply Function(RequestOptions)? heartbeat,
  FakeReply Function(RequestOptions)? progress,
  Locale locale = const Locale('en'),
}) async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  h.backend.reply('GET', _shortsPath, _shorts(3));
  h.backend.reply('GET', '/api/v1/video-access/allowance', {
    'child_id': 'child-1',
    'local_date': '2026-11-20',
    'timezone': 'UTC',
    'total_earned_today_seconds': 900,
    'consumed_today_seconds': 0,
    'remaining_seconds': 900,
    'daily_cap_seconds': 900,
    'is_exhausted': false,
    'active_entitlements_count': 0,
  });
  var issued = 0;
  h.backend.on(
    'POST',
    _ticketsPath,
    start ??
        (options) {
          final videoId = (options.data as Map)['video_id'] as String;
          issued++;
          return FakeReply(201, {
            'ticket_id': 'ticket-$issued',
            'ticket_token': 'token-$issued',
            'video_id': videoId,
            'youtube_video_id': null,
            'expires_at': '2026-11-20T10:01:00Z',
            'heartbeat_interval_seconds': 10,
            'remaining_seconds': 900,
          });
        },
  );
  h.backend.onPattern(
    'POST',
    _heartbeat,
    heartbeat ??
        (_) => const FakeReply(200, {
          'state': 'playing',
          'accepted_seconds': 10,
          'remaining_seconds': 890,
          'is_exhausted': false,
          'duplicate': false,
        }),
  );
  h.backend.onPattern(
    'POST',
    _end,
    (_) => const FakeReply(200, {
      'state': 'ended',
      'accepted_seconds': 0,
      'remaining_seconds': 890,
      'is_exhausted': false,
      'duplicate': false,
    }),
  );
  h.backend.onPattern(
    'POST',
    _progress,
    progress ??
        (_) => const FakeReply(200, {
          'remaining_allowance_seconds': 900,
          'is_exhausted': false,
        }),
  );
  final embeds = EmbedRecorder();
  await pumpScreen(
    tester,
    const ShortsFeedScreen(launch: ShortsLaunch()),
    overrides: [
      ...h.overrides,
      playTicketModeProvider.overrideWithValue(tickets),
      youtubeEmbedBuilderProvider.overrideWithValue(embeds.build),
      videoPlaybackControllerFactoryProvider.overrideWithValue(
        PlaybackRegistry().create,
      ),
    ],
    locale: locale,
  );
  return _Rig(h, embeds);
}

/// Disposes the feed so held tickets end and heartbeat timers stop.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  // Let the best-effort ticket end and any request timeouts finish.
  await tester.pump(const Duration(minutes: 1));
}

Finder get _pager => find.byKey(const Key('videos.shorts.pager'));

void main() {
  group('ticket mode', () {
    testWidgets('a ticket comes before playback, only for the page on screen', (
      tester,
    ) async {
      final rig = await _pump(tester, tickets: true);

      expect(rig.ticketStarts, hasLength(1));
      expect((rig.ticketStarts.single.data as Map)['video_id'], 'short-0');
      // Granted: exactly one embed plays, and only for that page.
      expect(rig.embeds.activeCount, 1);
      expect(rig.embeds.only().videoId, _ytId(0));
      await _teardown(tester);
    });

    testWidgets('a ticket request that fails never plays and never falls back '
        'to record_progress', (
      tester,
    ) async {
      final rig = await _pump(
        tester,
        tickets: true,
        start: (_) => const FakeReply.fail(DioExceptionType.connectionTimeout),
      );

      expect(rig.embeds.activeCount, 0);
      expect(rig.progressReports, isEmpty);
      await _teardown(tester);
    });

    testWidgets('heartbeats run only while playing and never use '
        'record_progress', (tester) async {
      final rig = await _pump(tester, tickets: true);
      expect(rig.heartbeats, isEmpty, reason: 'not playing yet');

      rig.embeds.only().onPlayingChanged!(true);
      await tester.pumpAndSettle();
      final whilePlaying = rig.heartbeats.length;
      expect(whilePlaying, greaterThanOrEqualTo(1));

      await tester.pump(const Duration(seconds: 25));
      await tester.pumpAndSettle();
      expect(rig.heartbeats.length, greaterThan(whilePlaying));

      rig.embeds.only().onPlayingChanged!(false);
      await tester.pumpAndSettle();
      final afterPause = rig.heartbeats.length;
      expect((rig.heartbeats.last.data as Map)['is_playing'], isFalse);

      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(rig.heartbeats.length, afterPause, reason: 'paused: no beats');
      expect(rig.progressReports, isEmpty);
      await _teardown(tester);
    });

    testWidgets('another device taking over stops playback at once, with a '
        'localised notice and a retry for a fresh ticket', (tester) async {
      var superseded = true;
      final rig = await _pump(
        tester,
        tickets: true,
        heartbeat: (_) => superseded
            ? FakeReply.error(409, 'ticket_superseded', 'superseded')
            : const FakeReply(200, {
                'state': 'playing',
                'accepted_seconds': 10,
                'remaining_seconds': 880,
                'is_exhausted': false,
                'duplicate': false,
              }),
      );
      rig.embeds.only().onPlayingChanged!(true);
      await tester.pumpAndSettle();

      expect(rig.embeds.activeCount, 0, reason: 'the embed is removed');
      expect(find.byKey(const Key('videos.shorts.ticket')), findsOneWidget);
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.videoTicketSuperseded), findsOneWidget);
      expect(rig.progressReports, isEmpty, reason: 'never a legacy fallback');

      superseded = false;
      await tester.tap(find.text(l10n.videoRetry));
      await tester.pumpAndSettle();
      expect(rig.ticketStarts, hasLength(2), reason: 'a fresh ticket');
      expect(rig.embeds.activeCount, 1);
      expect(rig.progressReports, isEmpty);
      await _teardown(tester);
    });

    for (final (code, status) in [
      ('ticket_revoked', 403),
      ('ticket_expired', 409),
    ]) {
      testWidgets('$code stops playback and is not treated as a network blip', (
        tester,
      ) async {
        final rig = await _pump(
          tester,
          tickets: true,
          heartbeat: (_) => FakeReply.error(status, code, code),
        );
        rig.embeds.only().onPlayingChanged!(true);
        await tester.pumpAndSettle();

        expect(rig.embeds.activeCount, 0);
        expect(find.byKey(const Key('videos.shorts.ticket')), findsOneWidget);
        expect(find.byKey(const Key('videos.shorts.offline')), findsNothing);
        expect(rig.heartbeats, hasLength(1), reason: 'stopped on the refusal');
        expect(rig.progressReports, isEmpty);
        await _teardown(tester);
      });
    }

    testWidgets('exhaustion stops playback and opens the lock page', (
      tester,
    ) async {
      final rig = await _pump(
        tester,
        tickets: true,
        heartbeat: (_) => FakeReply.error(403, 'ticket_exhausted', 'used up'),
      );
      rig.embeds.only().onPlayingChanged!(true);
      await tester.pumpAndSettle();

      expect(rig.embeds.activeCount, 0);
      expect(find.byKey(const Key('video.lock.screen')), findsOneWidget);
      expect(rig.progressReports, isEmpty);
      await _teardown(tester);
    });

    testWidgets('swiping on ends this ticket and starts one for the next '
        'page', (tester) async {
      final rig = await _pump(tester, tickets: true);
      expect(rig.ticketStarts, hasLength(1));

      await tester.drag(_pager, const Offset(0, -700));
      await tester.pumpAndSettle();

      expect(rig.ends, hasLength(1));
      expect(rig.ticketStarts, hasLength(2));
      expect((rig.ticketStarts.last.data as Map)['video_id'], 'short-1');
      expect(rig.embeds.only().videoId, _ytId(1));
      expect(rig.progressReports, isEmpty);
      await _teardown(tester);
    });

    testWidgets('a server without tickets falls back to record_progress only '
        'before any ticket was issued', (tester) async {
      final rig = await _pump(
        tester,
        tickets: true,
        start: (_) => FakeReply.error(503, 'play_tickets_unavailable', 'off'),
      );
      expect(rig.embeds.activeCount, 1, reason: 'legacy metering takes over');

      rig.embeds.only().onPlayingChanged!(true);
      await tester.pumpAndSettle();
      expect(rig.progressReports, isNotEmpty);
      expect(rig.heartbeats, isEmpty);
      await _teardown(tester);
    });

    for (final locale in const [Locale('hi'), Locale('gu')]) {
      testWidgets('the takeover notice is localised (${locale.languageCode})', (
        tester,
      ) async {
        final rig = await _pump(
          tester,
          tickets: true,
          locale: locale,
          heartbeat: (_) => FakeReply.error(409, 'ticket_superseded', 'x'),
        );
        rig.embeds.only().onPlayingChanged!(true);
        await tester.pumpAndSettle();
        final l10n = lookupAppLocalizations(locale);
        expect(find.text(l10n.videoTicketSuperseded), findsOneWidget);
        await _teardown(tester);
      });
    }
  });

  group('tickets off (legacy)', () {
    testWidgets('no ticket is requested; record_progress meters playback', (
      tester,
    ) async {
      final rig = await _pump(tester, tickets: false);
      rig.embeds.only().onPlayingChanged!(true);
      await tester.pumpAndSettle();

      expect(rig.ticketStarts, isEmpty);
      expect(rig.heartbeats, isEmpty);
      expect(rig.progressReports, isNotEmpty);
      await _teardown(tester);
    });

    testWidgets('409 play_ticket_required stops at once: an update is needed, '
        'not a network problem', (tester) async {
      final rig = await _pump(
        tester,
        tickets: false,
        progress: (_) => FakeReply.error(
          409,
          'play_ticket_required',
          'This app version must use play tickets',
        ),
      );
      rig.embeds.only().onPlayingChanged!(true);
      await tester.pumpAndSettle();

      expect(rig.progressReports, hasLength(1), reason: 'stopped on the first');
      expect(rig.embeds.activeCount, 0);
      expect(
        find.byKey(const Key('videos.shorts.updateRequired')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('videos.shorts.offline')), findsNothing);
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.videoUpdateRequired), findsOneWidget);
      expect(find.text(l10n.videoRetry), findsNothing, reason: 'cannot help');
      await _teardown(tester);
    });
  });

  group('PlaybackGuard', () {
    test('play_ticket_required is a refusal, never counted as a failure', () async {
      final guard = PlaybackGuard();
      final refused = await guard.report(
        () async => throw const ConflictException(
          message: 'must use tickets',
          code: kPlayTicketRequiredCode,
        ),
      );
      expect(refused.verdict, PlaybackVerdict.updateRequired);
      expect(guard.consecutiveFailures, 0);

      // Any other conflict is still an unverified report (tolerated once).
      final other = await guard.report(
        () async => throw const ConflictException(message: 'x', code: 'other'),
      );
      expect(other.verdict, PlaybackVerdict.ok);
      expect(guard.consecutiveFailures, 1);
    });
  });
}
