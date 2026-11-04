import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _reviewId = '11111111-1111-4111-8111-111111111111';

Map<String, Object?> _review({String status = 'pending_review'}) => {
  'id': _reviewId,
  'video_id': '22222222-2222-4222-8222-222222222222',
  'youtube_video_id': 'dQw4w9WgXcQ',
  'source_url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  'channel_id': 'UC1234567890123456789012',
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
};

void main() {
  testWidgets('admin can inspect and approve a reviewed YouTube candidate', (
    tester,
  ) async {
    final server = baseServer()
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', [_review()])
      ..reply(
        'POST',
        '/api/v1/admin/videos/youtube/reviews/$_reviewId/approve',
        {..._review(status: 'approved'), 'age_min': 3, 'age_max': 5},
      );
    await pumpAdmin(tester, server, size: const Size(1400, 2200));
    await openSection(tester, 'YouTube review');

    expect(find.text('A science lesson'), findsOneWidget);
    await tester.tap(find.byKey(const Key('youtube.inspect.$_reviewId')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Discovery topic: science'), findsOneWidget);
    // The backend's short/regular decision is shown, not recomputed.
    expect(find.textContaining('Child feed: Regular videos'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('field.rights_cleared')));
    await tester.tap(find.byKey(const Key('form.submit')));
    await tester.pumpAndSettle();

    final request = server
        .to('POST', '/api/v1/admin/videos/youtube/reviews/$_reviewId/approve')
        .single;
    expect(request.data, {
      'language_code': 'en',
      'age_min': 3,
      'age_max': 5,
      'rights_status': 'cleared',
    });
  });

  testWidgets('read-only admins cannot discover or approve videos', (
    tester,
  ) async {
    final server = baseServer(permissions: ['video:read'])
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', [_review()]);
    await pumpAdmin(tester, server, size: const Size(1400, 2200));
    await openSection(tester, 'YouTube review');

    expect(find.byKey(const Key('youtube.discover')), findsNothing);
    expect(find.byKey(const Key('youtube.recheck')), findsNothing);
    expect(find.byKey(const Key('youtube.autoReview')), findsNothing);
    await tester.tap(find.byKey(const Key('youtube.inspect.$_reviewId')));
    await tester.pumpAndSettle();
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(
      server.to(
        'POST',
        '/api/v1/admin/videos/youtube/reviews/$_reviewId/approve',
      ),
      isEmpty,
    );
    expect(find.byKey(const Key('youtube.publishApproved')), findsNothing);
  });

  testWidgets('admin can run approved-video publication batches', (
    tester,
  ) async {
    final server = baseServer()
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', [_review()])
      ..reply('POST', '/api/v1/admin/videos/youtube/publish-approved', {
        'checked': 0,
        'newly_published': 0,
        'blocked_by_reason': <String, int>{},
        'approved_unpublished_remaining': 0,
        'next_after_id': null,
        'complete': true,
      });
    await pumpAdmin(tester, server, size: const Size(1400, 2200));
    await openSection(tester, 'YouTube review');

    await tester.tap(find.byKey(const Key('youtube.publishApproved')));
    await tester.pumpAndSettle();

    expect(
      server
          .to('POST', '/api/v1/admin/videos/youtube/publish-approved')
          .single
          .data,
      {'limit': 50},
    );
  });

  Map<String, Object?> diagnostics() => {
    'approved': 63,
    'approved_automatic': 5,
    'approved_manual': 58,
    'pending_review': 2,
    'quarantined': 4,
    'rejected': 1,
    'published': 60,
    'oldest_approved_verification': '2026-11-02T07:23:33Z',
    'approved_stale': 0,
    'reverify_hours': 72,
    'quarantine_reasons': <String, int>{'keyword:fight': 3},
    'publication_failure_reasons': <String, int>{},
    'last_discovery_result': <String, int>{},
  };

  testWidgets('shows status counts, who approved and why a video waits', (
    tester,
  ) async {
    final automatic = {
      ..._review(status: 'approved'),
      'publication_source': 'automatic',
      'is_published': true,
    };
    final waiting = {
      ..._review(),
      'id': '33333333-3333-4333-8333-333333333333',
      'title': 'Long video',
      'not_published_reason':
          'Waiting for manual review: the video is longer than the automatic approval limit',
    };
    final server = baseServer()
      ..reply('GET', '/api/v1/admin/videos/youtube/diagnostics', diagnostics())
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', [
        automatic,
        waiting,
      ]);
    await pumpAdmin(tester, server, size: const Size(1400, 2200));
    await openSection(tester, 'YouTube review');
    await tester.pumpAndSettle();

    String count(String key) =>
        tester.widget<Text>(find.byKey(Key('youtube.count.$key'))).data!;
    expect(count('approved'), endsWith(': 63'));
    expect(count('pending_review'), endsWith(': 2'));
    expect(count('quarantined'), endsWith(': 4'));
    expect(count('rejected'), endsWith(': 1'));
    expect(count('published'), endsWith(': 60'));
    expect(
      find.textContaining(
        'Approved automatically: 5 · by an administrator: 58',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('past the 72-hour limit (hidden from children): 0'),
      findsOneWidget,
    );
    expect(find.text('Approved automatically'), findsOneWidget);
    expect(
      find.textContaining('longer than the automatic approval limit'),
      findsOneWidget,
    );
    expect(find.textContaining('keyword:fight'), findsOneWidget);
  });

  testWidgets(
    '"Process waiting videos" calls the backend and reports the result',
    (tester) async {
      final server = baseServer()
        ..reply('GET', '/api/v1/admin/videos/youtube/reviews', [_review()])
        ..reply(
          'GET',
          '/api/v1/admin/videos/youtube/diagnostics',
          diagnostics(),
        )
        ..reply('POST', '/api/v1/admin/videos/youtube/auto-review', {
          'checked': 7,
          'auto_approved': 3,
          'needs_manual_review': 2,
          'newly_quarantined': 1,
          'still_quarantined': 0,
          'returned_to_pending': 0,
          'unavailable': 1,
          'retry_later': 0,
          'error': null,
          'blocked_reasons': <String, int>{},
          'quarantine_reasons': <String, int>{},
        });
      await pumpAdmin(tester, server, size: const Size(1400, 2200));
      await openSection(tester, 'YouTube review');
      await tester.tap(find.byKey(const Key('youtube.autoReview')));
      await tester.pumpAndSettle();

      final request = server
          .to('POST', '/api/v1/admin/videos/youtube/auto-review')
          .single;
      expect(request.data, {'limit': 200, 'include_quarantined': true});
      expect(find.textContaining('3 approved automatically'), findsOneWidget);
    },
  );

  testWidgets('a YouTube outage is reported as nothing changed', (
    tester,
  ) async {
    final server = baseServer()
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', [_review()])
      ..reply('GET', '/api/v1/admin/videos/youtube/diagnostics', diagnostics())
      ..reply('POST', '/api/v1/admin/videos/youtube/auto-review', {
        'checked': 0,
        'auto_approved': 0,
        'needs_manual_review': 0,
        'newly_quarantined': 0,
        'still_quarantined': 0,
        'returned_to_pending': 0,
        'unavailable': 0,
        'retry_later': 4,
        'error': 'youtube_quota_exhausted',
        'blocked_reasons': <String, int>{},
        'quarantine_reasons': <String, int>{},
      });
    await pumpAdmin(tester, server, size: const Size(1400, 2200));
    await openSection(tester, 'YouTube review');
    await tester.tap(find.byKey(const Key('youtube.autoReview')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing was changed'), findsOneWidget);
  });

  testWidgets('the status counts refresh after discovery', (tester) async {
    var reads = 0;
    final server = baseServer()
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', [_review()])
      ..on('GET', '/api/v1/admin/videos/youtube/diagnostics', (_) {
        reads++;
        return Reply(200, {...diagnostics(), 'approved': reads == 1 ? 1 : 9});
      })
      ..reply('POST', '/api/v1/admin/videos/youtube/discover', {
        'created': <Object>[],
        'skipped_existing': 0,
        'skipped_unplayable': 0,
        'next_page_token': null,
        'automatically_published': 0,
        'quarantined': 0,
      });
    await pumpAdmin(tester, server, size: const Size(1400, 2200));
    await openSection(tester, 'YouTube review');
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('youtube.count.approved'))).data,
      endsWith(': 1'),
    );
    await tester.tap(find.byKey(const Key('youtube.discover')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('form.submit')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('youtube.count.approved'))).data,
      endsWith(': 9'),
    );
  });
}
