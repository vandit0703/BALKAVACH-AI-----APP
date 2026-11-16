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
  testWidgets('admin discovers a channel and trusts it for automatic discovery', (
    tester,
  ) async {
    final server = baseServer()
      ..reply('GET', '/api/v1/admin/videos/youtube/channels', <Object?>[])
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', [_review()])
      ..reply('GET', '/api/v1/admin/videos/youtube/channels/discover', [
        {
          'channel_id': _channelId,
          'channel_title': 'Science channel',
          'thumbnail_url': 'https://yt3.ggpht.com/channel.png',
          'is_trusted': false,
        },
      ])
      ..reply('POST', '/api/v1/admin/videos/youtube/channels/trust', {
        ..._trustedChannel(),
        'initial_discovery': {
          'created': 2,
          'automatically_published': 1,
          'pending_review': 1,
          'quarantined': 0,
          'unavailable': 0,
          'channels_pending_initial_scan': 1,
        },
      });
    await pumpAdmin(tester, server, size: const Size(1400, 1800));
    await openSection(tester, 'YouTube review');

    expect(find.text('Discover channels'), findsOneWidget);
    expect(find.text('Trusted channels'), findsOneWidget);
    expect(find.text('Videos for review'), findsOneWidget);
    expect(find.textContaining('All video records'), findsNothing);

    await tester.enterText(find.byKey(const Key('youtube.channelSearch')), 'science');
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
      'rights_status': 'cleared',
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
  });

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
    expect(find.text(_channelId), findsOneWidget);
    expect(find.text('Trusted'), findsOneWidget);
    await tester.tap(find.byKey(Key('youtube.untrust.$_channelId')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Stop discovering and publishing'), findsOneWidget);
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

    await tester.enterText(find.byKey(const Key('youtube.channelSearch')), 'new');
    await tester.tap(find.byKey(const Key('youtube.searchChannels')));
    await tester.pumpAndSettle();
    expect(find.text('New channel'), findsOneWidget);
    expect(find.byKey(const Key('youtube.trust.UC9876543210123456789012')), findsNothing);
    expect(find.byKey(Key('youtube.untrust.$_channelId')), findsNothing);
    await tester.tap(find.byKey(const Key('youtube.inspect.$_reviewId')));
    await tester.pumpAndSettle();
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });
}