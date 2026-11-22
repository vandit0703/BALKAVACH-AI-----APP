import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _reviewId = '11111111-1111-4111-8111-111111111111';
const _channelId = 'UC1234567890123456789012';

Map<String, Object?> _review({String status = 'pending_review'}) => {
  'id': _reviewId,
  'video_id': '22222222-2222-4222-8222-222222222222',
  'youtube_video_id': 'dQw4w9WgXcQ',
  'source_url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  'channel_id': _channelId,
  'channel_title': 'Science channel',
  'made_for_kids': true,
  'status': status,
  'screening_flags': <String>[],
  'rights_status': 'unreviewed',
  'discovered_at': '2026-10-26T10:00:00Z',
  'reviewed_by': null,
  'reviewed_at': null,
  'review_notes': null,
  'last_verified_at': '2026-10-26T10:00:00Z',
  'revoked_reason': null,
  'revoked_at': null,
  'title': 'A science lesson',
  'description': 'A lesson for children.',
  'thumbnail_url': null,
  'duration_seconds': 120,
  'video_format': 'regular',
  'language_code': 'en',
  'age_min': null,
  'age_max': null,
  'discovery_topic': 'science',
  'youtube_category_id': '27',
  'publication_source': 'manual',
  'publication_reason': null,
  'not_published_reason': 'Waiting for manual review',
};

Map<String, Object?> _trustedChannel({bool active = true}) => {
  'id': '33333333-3333-4333-8333-333333333333',
  'channel_id': _channelId,
  'channel_title': 'Science channel',
  'thumbnail_url': 'https://yt3.ggpht.com/channel.png',
  'age_min': null,
  'age_max': null,
  'language_code': null,
  'category_id': null,
  'rights_status': 'cleared',
  'is_active': active,
  'created_by': null,
  'created_at': '2026-10-26T10:00:00Z',
  'updated_at': '2026-10-26T10:00:00Z',
  'notes': null,
  'uploads_scan_complete': true,
};

void main() {
  channelTests();
  testWidgets(
    'admin discovers a channel and trusts it for automatic discovery',
    (tester) async {
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/videos/youtube/channels', <Object?>[])
        ..reply('GET', '/api/v1/admin/videos/youtube/reviews', <Object?>[])
        ..reply('GET', '/api/v1/admin/videos/youtube/channels/discover', [
          {
            'channel_id': _channelId,
            'channel_title': 'Science channel',
            'thumbnail_url': 'https://yt3.ggpht.com/channel.png',
            'is_trusted': false,
          },
        ])
        ..reply('GET', '/api/v1/admin/videos/categories', [
          {'id': 'cat-1', 'name': 'Education', 'is_active': true},
        ])
        ..reply('POST', '/api/v1/admin/videos/youtube/channels/trust', {
          'id': 1,
          'channel_id': _channelId,
          'channel_title': 'Science channel',
          'thumbnail_url': 'https://yt3.ggpht.com/channel.png',
          'rights_status': 'cleared',
          'age_min': 3,
          'age_max': 5,
          'language_code': 'en',
          'category': 'cat-1',
          'is_active': true,
          'discovered_at': '2026-04-12T10:00:00Z',
          'last_discovered_at': '2026-04-12T10:00:00Z',
          'initial_discovery': {
            'id': 1,
            'channel_id': _channelId,
            'triggered_by': null,
            'trigger': 'trust',
            'status': 'completed',
            'started_at': '2026-04-12T10:00:00Z',
            'completed_at': '2026-04-12T10:00:00Z',
            'scanned_videos': 0,
            'new_videos': 0,
            'duplicate_videos': 0,
            'shorts_count': 0,
            'long_videos_count': 0,
            'auto_approved_count': 0,
            'pending_review_count': 0,
            'quarantined_count': 0,
            'unavailable_count': 0,
            'error_count': 0,
            'error_message': null,
          },
        });
      await pumpAdmin(tester, server, size: const Size(1400, 1800));
      await openSection(tester, 'YouTube review');

      expect(find.text('Discover channels'), findsOneWidget);
      expect(find.text('Trusted channels'), findsOneWidget);
      expect(find.text('Videos for review'), findsOneWidget);
      expect(find.textContaining('All video records'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('youtube.channelSearch')),
        'science',
      );
      await tester.tap(find.byKey(const Key('youtube.searchChannels')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(Key('youtube.searchResult.$_channelId')),
          matching: find.text('Science channel'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(Key('youtube.searchResult.$_channelId')),
          matching: find.text(_channelId),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(Key('youtube.trust.$_channelId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('field.age_band')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3-5').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('field.rights_cleared')));
      await tester.tap(find.byKey(const Key('form.submit')));
      await tester.pumpAndSettle();

      final trustRequest = server
          .to('POST', '/api/v1/admin/videos/youtube/channels/trust')
          .single;
      expect(trustRequest.data, {
        'channel_id': _channelId,
        'channel_title': 'Science channel',
        'thumbnail_url': 'https://yt3.ggpht.com/channel.png',
        'age_min': 3,
        'age_max': 5,
        'language_code': 'en',
        'category': 'cat-1',
        'rights_status': 'cleared',
        'notes': null,
      });
      expect(
        server
            .to('GET', '/api/v1/admin/videos/youtube/channels/discover')
            .single
            .uri
            .queryParameters['query'],
        'science',
      );
      expect(find.textContaining('2 videos discovered'), findsOneWidget);
    },
  );

  testWidgets('trusted list shows channel identity and can stop trust', (
    tester,
  ) async {
    final server = baseServer()
      ..reply('GET', '/api/v1/admin/videos/youtube/channels', [
        _trustedChannel(),
      ])
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', <Object?>[])
      ..reply(
        'POST',
        '/api/v1/admin/videos/youtube/channels/$_channelId/untrust',
        _trustedChannel(active: false),
      );
    await pumpAdmin(tester, server, size: const Size(1400, 1200));
    await openSection(tester, 'YouTube review');

    expect(find.text('Science channel'), findsOneWidget);
    expect(find.textContaining(_channelId), findsWidgets);
    expect(find.text('Trusted'), findsOneWidget);
    await tester.tap(find.byKey(Key('youtube.untrust.$_channelId')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Stop discovering and publishing'),
      findsOneWidget,
    );
    await tester.tap(find.text('Remove channel trust').last);
    await tester.pumpAndSettle();

    expect(
      server.to(
        'POST',
        '/api/v1/admin/videos/youtube/channels/$_channelId/untrust',
      ),
      hasLength(1),
    );
  });

  testWidgets('admin can inspect and approve a video requiring review', (
    tester,
  ) async {
    final server = baseServer()
      ..reply('GET', '/api/v1/admin/videos/youtube/channels', <Object?>[])
      ..reply('GET', '/api/v1/admin/videos/categories', [
        {'id': 'science-id', 'name': 'Science', 'is_active': true},
      ])
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', [_review()])
      ..reply(
        'POST',
        '/api/v1/admin/videos/youtube/reviews/$_reviewId/approve',
        {..._review(status: 'approved'), 'age_min': 3, 'age_max': 5},
      );
    await pumpAdmin(tester, server, size: const Size(1400, 1600));
    await openSection(tester, 'YouTube review');

    expect(find.text('A science lesson'), findsOneWidget);
    await tester.tap(find.byKey(const Key('youtube.inspect.$_reviewId')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Channel: Science channel'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('field.rights_cleared')));
    await tester.tap(find.byKey(const Key('form.submit')));
    await tester.pumpAndSettle();

    expect(
      server
          .to('POST', '/api/v1/admin/videos/youtube/reviews/$_reviewId/approve')
          .single
          .data,
      {
        'language_code': 'en',
        'category_id': 'science-id',
        'age_min': 3,
        'age_max': 5,
        'rights_status': 'cleared',
      },
    );
  });

  testWidgets('read-only admins can search but cannot trust or untrust', (
    tester,
  ) async {
    final server = baseServer(permissions: ['video:read'])
      ..reply('GET', '/api/v1/admin/videos/youtube/channels', [
        _trustedChannel(),
      ])
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', [_review()])
      ..reply('GET', '/api/v1/admin/videos/youtube/channels/discover', [
        {
          'channel_id': 'UC9876543210123456789012',
          'channel_title': 'New channel',
          'thumbnail_url': null,
          'is_trusted': false,
        },
      ]);
    await pumpAdmin(tester, server, size: const Size(1400, 1600));
    await openSection(tester, 'YouTube review');

    await tester.enterText(
      find.byKey(const Key('youtube.channelSearch')),
      'new',
    );
    await tester.tap(find.byKey(const Key('youtube.searchChannels')));
    await tester.pumpAndSettle();
    expect(find.text('New channel'), findsOneWidget);
    expect(
      find.byKey(const Key('youtube.trust.UC9876543210123456789012')),
      findsNothing,
    );
    expect(find.byKey(Key('youtube.untrust.$_channelId')), findsNothing);
    await tester.tap(find.byKey(const Key('youtube.inspect.$_reviewId')));
    await tester.pumpAndSettle();
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });
}

Map<String, Object?> _detail({bool active = true}) => {
  'channel': _trustedChannel(active: active),
  'status': active ? 'approved' : 'revoked',
  'counts': {
    'discovered': 18,
    'approved': 12,
    'pending_review': 3,
    'quarantined': 2,
    'rejected': 1,
    'published': 11,
    'published_shorts': 4,
    'published_regular': 7,
  },
  'last_discovered_at': '2026-11-18T08:00:00Z',
  'last_verified_at': null,
};

const _detailPath = '/api/v1/admin/videos/youtube/channels/$_channelId';

void channelTests() {
  testWidgets('channel row opens the detail page with counts and discovery history', (
    tester,
  ) async {
    final server = baseServer()
      ..reply('GET', '/api/v1/admin/videos/youtube/channels', [
        {..._trustedChannel(), 'thumbnail_url': null},
      ])
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', <Object?>[])
      ..reply('GET', _detailPath, {..._trustedChannel(), 'thumbnail_url': null})
      ..reply('GET', '$_detailPath/videos', {
        'items': [
          {
            'id': _reviewId,
            'youtube_video_id': 'abc12345678',
            'title': 'How plants grow',
            'channel_id': _channelId,
            'channel_title': 'Science channel',
            'thumbnail_url': null,
            'duration_seconds': 420,
            'is_short': false,
            'view_count': 1200,
            'like_count': 45,
            'comment_count': 6,
            'age_min': 6,
            'age_max': 8,
            'language_code': 'en',
            'category': 'Science',
            'status': 'approved',
            'review_status': 'approved',
            'publication_status': 'published',
            'is_published': true,
            'rights_status': 'cleared',
            'screening_flags': <String>[],
            'rejection_reason': null,
            'notes': null,
            'not_published_reason': null,
            'discovered_at': '2026-04-12T10:00:00Z',
            'last_verified_at': '2026-04-12T10:00:00Z',
          },
        ],
        'total': 1,
        'limit': 20,
        'offset': 0,
      })
      ..reply('GET', '$_detailPath/discovery-history', [
        {
          'id': 42,
          'channel_id': _channelId,
          'triggered_by': null,
          'trigger': 'manual',
          'status': 'completed',
          'started_at': '2026-04-12T09:00:00Z',
          'completed_at': '2026-04-12T09:01:00Z',
          'scanned_videos': 10,
          'new_videos': 2,
          'duplicate_videos': 8,
          'shorts_count': 1,
          'long_videos_count': 1,
          'auto_approved_count': 1,
          'pending_review_count': 1,
          'quarantined_count': 0,
          'unavailable_count': 0,
          'error_count': 0,
          'error_message': null,
        },
      ]);
    await pumpAdmin(tester, server, size: const Size(1400, 1800));
    await openSection(tester, 'YouTube review');

    await tester.tap(find.byKey(const Key('youtube.channelRow.$_channelId')));
    await tester.pumpAndSettle();

    expect(find.text('Trusted channel details'), findsOneWidget);
    expect(find.text('How plants grow'), findsOneWidget);
    expect(find.textContaining('Run #42'), findsWidgets);
    expect(find.textContaining('manual'), findsWidgets);
    expect(find.textContaining('2 new'), findsWidgets);
    expect(find.textContaining('8 duplicates'), findsWidgets);
    expect(
      server.to('GET', '/api/v1/admin/videos/youtube/channels/$_channelId'),
      isNotEmpty,
    );
  });

  testWidgets('a failed channel details request shows an error state', (
    tester,
  ) async {
    final server = baseServer()
      ..reply('GET', '/api/v1/admin/videos/youtube/channels', [
        {..._trustedChannel(), 'thumbnail_url': null},
      ])
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', <Object?>[])
      ..reply('GET', _detailPath, {
        'error': {'code': 'x', 'message': 'boom'},
      }, status: 500)
      ..reply('GET', '$_detailPath/videos', {
        'items': <Object?>[],
        'total': 0,
        'limit': 20,
        'offset': 0,
      })
      ..reply('GET', '$_detailPath/discovery-history', <Object?>[]);
    await pumpAdmin(tester, server, size: const Size(1400, 1800));
    await openSection(tester, 'YouTube review');
    await tester.tap(find.byKey(const Key('youtube.channelRow.$_channelId')));
    await tester.pumpAndSettle();

    expect(find.text('Trusted channel details'), findsNothing);
    expect(find.byKey(const Key('error.retry')), findsWidgets);
  });

  testWidgets('Discover More shows loading and successful results for the selected channel', (
    tester,
  ) async {
    final discoverCompleter = Completer<Reply>();
    final server = baseServer()
      ..reply('GET', '/api/v1/admin/videos/youtube/channels', [
        {..._trustedChannel(), 'thumbnail_url': null},
      ])
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', <Object?>[])
      ..reply('GET', _detailPath, {..._trustedChannel(), 'thumbnail_url': null})
      ..reply('GET', '$_detailPath/videos', {
        'items': <Object?>[],
        'total': 0,
        'limit': 20,
        'offset': 0,
      })
      ..reply('GET', '$_detailPath/discovery-history', <Object?>[])
      ..on('POST', '$_detailPath/discover', (_) => discoverCompleter.future)
      // refresh after successful discovery
      ..reply('GET', _detailPath, {..._trustedChannel(), 'thumbnail_url': null})
      ..reply('GET', '$_detailPath/videos', {
        'items': <Object?>[],
        'total': 0,
        'limit': 20,
        'offset': 0,
      })
      ..reply('GET', '$_detailPath/discovery-history', [
        {
          'id': 43,
          'channel_id': _channelId,
          'channel_title': 'Science channel',
          'triggered_by': null,
          'trigger': 'manual',
          'status': 'completed',
          'started_at': '2026-04-12T11:00:00Z',
          'completed_at': '2026-04-12T11:01:00Z',
          'scanned_videos': 10,
          'new_videos': 2,
          'duplicate_videos': 8,
          'shorts_count': 1,
          'long_videos_count': 1,
          'auto_approved_count': 1,
          'pending_review_count': 1,
          'quarantined_count': 0,
          'unavailable_count': 0,
          'error_count': 0,
          'error_message': null,
        },
      ]);
    await pumpAdmin(tester, server, size: const Size(1400, 1800));
    await openSection(tester, 'YouTube review');
    await tester.tap(find.byKey(const Key('youtube.channelRow.$_channelId')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('youtube.channelDiscoverMore')));
    await tester.tap(find.byKey(const Key('youtube.channelDiscoverMore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('form.submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Discovering…'), findsWidgets);
    expect(find.textContaining('Fetching latest uploads'), findsOneWidget);
    expect(
      server.to('POST', '/api/v1/admin/videos/youtube/channels/$_channelId/discover'),
      hasLength(1),
    );

    discoverCompleter.complete(
      Reply(200, {
        'id': 43,
        'channel_id': _channelId,
        'channel_title': 'Science channel',
        'triggered_by': null,
        'trigger': 'manual',
        'status': 'completed',
        'started_at': '2026-04-12T11:00:00Z',
        'completed_at': '2026-04-12T11:01:00Z',
        'scanned_videos': 10,
        'new_videos': 2,
        'duplicate_videos': 8,
        'shorts_count': 1,
        'long_videos_count': 1,
        'auto_approved_count': 1,
        'pending_review_count': 1,
        'quarantined_count': 0,
        'unavailable_count': 0,
        'error_count': 0,
        'error_message': null,
      }),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Scanned: 10'), findsWidgets);
    expect(find.textContaining('New: 2'), findsWidgets);
    expect(
      server.to('GET', '/api/v1/admin/videos/youtube/channels/$_channelId').length,
      greaterThanOrEqualTo(2),
    );
  });

  testWidgets('Discover More shows an error message when channel discovery fails', (
    tester,
  ) async {
    final server = baseServer()
      ..reply('GET', '/api/v1/admin/videos/youtube/channels', [
        {..._trustedChannel(), 'thumbnail_url': null},
      ])
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', <Object?>[])
      ..reply('GET', _detailPath, {..._trustedChannel(), 'thumbnail_url': null})
      ..reply('GET', '$_detailPath/videos', {
        'items': <Object?>[],
        'total': 0,
        'limit': 20,
        'offset': 0,
      })
      ..reply('GET', '$_detailPath/discovery-history', <Object?>[])
      ..reply('POST', '$_detailPath/discover', {
        'error': {'code': 'x', 'message': 'boom'},
      }, status: 500);
    await pumpAdmin(tester, server, size: const Size(1400, 1800));
    await openSection(tester, 'YouTube review');
    await tester.tap(find.byKey(const Key('youtube.channelRow.$_channelId')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('youtube.channelDiscoverMore')));
    await tester.tap(find.byKey(const Key('youtube.channelDiscoverMore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('form.submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to discover more videos'), findsOneWidget);
  });
}
