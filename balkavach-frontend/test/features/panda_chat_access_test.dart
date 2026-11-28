import 'dart:convert';

import 'package:balkavach_app/features/companion/presentation/panda_chat_access_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _familyPath =
    '/api/v1/settings/families/${Fx.familyId}/panda-chat-access';
const _childPath =
    '/api/v1/settings/families/${Fx.familyId}/children/${Fx.childId}/panda-chat-access';

Map<String, Object?> _status(String status) => {
  'child_id': Fx.childId,
  'status': status,
  'requested_at': '2026-11-27T10:00:00Z',
  'decided_at': status == 'pending' ? null : '2026-11-27T11:00:00Z',
  'decided_by': status == 'pending' ? null : Fx.parentUserId,
};

Map<String, dynamic> _body(RequestOptions request) => request.data is String
    ? jsonDecode(request.data as String) as Map<String, dynamic>
    : (request.data as Map).cast<String, dynamic>();

Future<(Harness, String Function())> _pump(
  WidgetTester tester, {
  String initialStatus = 'pending',
  bool child = false,
}) async {
  final h = await Harness.create(
    session: child ? Fx.childSession() : Fx.parentSession(),
    prefs: onboardedPrefs,
  );
  var status = initialStatus;
  h.backend
    ..on('GET', _familyPath, (_) => FakeReply(200, [_status(status)]))
    ..on('PUT', _childPath, (request) {
      status = _body(request)['action'] == 'approve'
          ? 'approved'
          : _body(request)['action'] == 'reject'
          ? 'rejected'
          : 'revoked';
      return FakeReply(200, _status(status));
    });
  await pumpScreen(
    tester,
    const PandaChatAccessScreen(),
    overrides: h.overrides,
  );
  return (h, () => status);
}

void main() {
  testWidgets('a parent approves and can later revoke one child access', (
    tester,
  ) async {
    final (h, readStatus) = await _pump(tester);
    expect(find.byKey(const Key('pandaChatAccess.approve.${Fx.childId}')),
        findsOneWidget);

    await tester.tap(
      find.byKey(const Key('pandaChatAccess.approve.${Fx.childId}')),
    );
    await tester.pumpAndSettle();
    expect(readStatus(), 'approved');
    expect(_body(h.backend.requestsTo('PUT', _childPath).single), {
      'action': 'approve',
    });
    expect(find.byKey(const Key('pandaChatAccess.revoke.${Fx.childId}')),
        findsOneWidget);

    await tester.tap(
      find.byKey(const Key('pandaChatAccess.revoke.${Fx.childId}')),
    );
    await tester.pumpAndSettle();
    expect(readStatus(), 'revoked');
    expect(_body(h.backend.requestsTo('PUT', _childPath).last), {
      'action': 'revoke',
    });
  });

  testWidgets('a parent can reject a request', (tester) async {
    final (h, readStatus) = await _pump(tester);
    await tester.tap(
      find.byKey(const Key('pandaChatAccess.reject.${Fx.childId}')),
    );
    await tester.pumpAndSettle();
    expect(readStatus(), 'rejected');
    expect(_body(h.backend.requestsTo('PUT', _childPath).single), {
      'action': 'reject',
    });
  });

  testWidgets('a child cannot use the parent decision screen', (tester) async {
    final (h, _) = await _pump(tester, child: true);
    expect(find.byKey(const Key('pandaChatAccess.approve.${Fx.childId}')),
        findsNothing);
    expect(
      find.text(lookupAppLocalizations(const Locale('en')).pandaChatParentOnly),
      findsOneWidget,
    );
    expect(h.backend.requestsTo('GET', _familyPath), isEmpty);
  });
}
