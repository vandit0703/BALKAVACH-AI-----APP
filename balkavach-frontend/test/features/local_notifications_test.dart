import 'dart:convert';
import 'dart:io';

import 'package:balkavach_app/core/push/local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = '3f2b8c1e-5d6a-4c7b-9e0f-1a2b3c4d5e6f';

  test('a banner payload becomes a push open', () {
    final open = LocalNotifications.parsePayload(
      jsonEncode({'type': 'task_approved', 'notification_id': id}),
    );
    expect(open?.notificationId, id);
    expect(open?.type, 'task_approved');
  });

  test('missing, malformed or forged payloads open nothing', () {
    expect(LocalNotifications.parsePayload(null), isNull);
    expect(LocalNotifications.parsePayload(''), isNull);
    expect(LocalNotifications.parsePayload('not json'), isNull);
    expect(LocalNotifications.parsePayload('[1,2]'), isNull);
    expect(
      LocalNotifications.parsePayload(
        jsonEncode({'type': 'task_approved', 'notification_id': '../admin'}),
      ),
      isNull,
    );
  });

  test('a payload cannot smuggle a destination, only type and id', () {
    final open = LocalNotifications.parsePayload(
      jsonEncode({
        'type': 'task_approved',
        'notification_id': id,
        'route': '/parent/settings',
      }),
    );
    expect(open?.type, 'task_approved');
  });

  test('channel ids match the ones the server sends', () {
    final fcm = File(
      '../balkavach-backend/app/integrations/fcm.py',
    ).readAsStringSync();
    for (final channel in pushChannels) {
      expect(fcm, contains('"${channel.id}"'), reason: channel.id);
    }
    final used = RegExp(
      r'"(balkavach_[a-z]+)"',
    ).allMatches(fcm).map((m) => m.group(1));
    expect(pushChannels.map((c) => c.id), containsAll(used.toSet()));
  });
}
