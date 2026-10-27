import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _reviewId = '11111111-1111-4111-8111-111111111111';

Map<String, Object?> _review({String status = 'pending_review'}) => {
  'id': _reviewId,
  'video_id': '22222222-2222-4222-8222-222222222222',
  'youtube_video_id': 'dQw4w9WgXcQ',
  'source_url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
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
  'language_code': 'en',
  'age_min': null,
  'age_max': null,
  'discovery_topic': 'science',
  'youtube_category_id': '27',
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
        {..._review(status: 'approved'), 'age_min': 4, 'age_max': 7},
      );
    await pumpAdmin(tester, server);
    await openSection(tester, 'YouTube review');

    expect(find.text('A science lesson'), findsOneWidget);
    await tester.tap(find.byKey(const Key('youtube.inspect.$_reviewId')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Discovery topic: science'), findsOneWidget);
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
      'age_min': 4,
      'age_max': 7,
      'rights_status': 'cleared',
    });
  });

  testWidgets('read-only admins cannot discover or approve videos', (
    tester,
  ) async {
    final server = baseServer(permissions: ['video:read'])
      ..reply('GET', '/api/v1/admin/videos/youtube/reviews', [_review()]);
    await pumpAdmin(tester, server);
    await openSection(tester, 'YouTube review');

    expect(find.byKey(const Key('youtube.discover')), findsNothing);
    expect(find.byKey(const Key('youtube.recheck')), findsNothing);
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
  });
}
