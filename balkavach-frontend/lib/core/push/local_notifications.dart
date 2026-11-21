import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_open_source.dart';

/// An Android notification channel the app creates. The ids must match the
/// ones the server puts in its push (`balkavach-backend/app/integrations/fcm.py`),
/// otherwise Android would file the push under a default channel.
@immutable
class PushChannel {
  const PushChannel(
    this.id,
    this.name,
    this.description, {
    this.importance = Importance.high,
  });

  final String id;
  final String name;
  final String description;
  final Importance importance;
}

/// The channels. A user can mute any one of them in Android's settings.
const pushChannels = <PushChannel>[
  PushChannel('balkavach_missions', 'Missions', 'New missions are ready'),
  PushChannel(
    'balkavach_approvals',
    'Approvals',
    'Missions waiting for review, and review results',
  ),
  PushChannel(
    'balkavach_rewards',
    'Rewards',
    'Stars, XP, badges and reward updates',
  ),
  PushChannel(
    'balkavach_reminders',
    'Reminders',
    'Streak and video-time reminders',
    importance: Importance.defaultImportance,
  ),
  PushChannel(
    'balkavach_safety',
    'Safety and account',
    'Important safety and account updates',
  ),
];

const _defaultChannelId = 'balkavach_missions';

/// Name of the drawable in `android/app/src/main/res/drawable`.
const notificationSmallIcon = 'ic_stat_balkavach';

/// Notifications that stack together in the shade.
const _groupKey = 'com.balkavach.notifications';

/// Shows notifications while the app is open (Android does not display an FCM
/// notification message in the foreground) and reports taps on them.
///
/// The payload carries only the server's `{type, notification_id}`; the screen
/// that opens is decided later, from the server's own record of the
/// notification, never from this payload.
class LocalNotifications {
  LocalNotifications([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<PushOpen>.broadcast();
  PushOpen? _launch;

  /// Taps on notifications this class showed.
  Stream<PushOpen> get taps => _taps.stream;

  /// The tapped notification that started the app, if any.
  PushOpen? get launchOpen => _launch;

  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(notificationSmallIcon),
      ),
      onDidReceiveNotificationResponse: (response) {
        final open = parsePayload(response.payload);
        if (open != null) _taps.add(open);
      },
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    for (final channel in pushChannels) {
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          channel.id,
          channel.name,
          description: channel.description,
          importance: channel.importance,
        ),
      );
    }
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      _launch = parsePayload(details?.notificationResponse?.payload);
    }
  }

  /// Shows [message] in the notification shade. Messages without a visible
  /// title or body (data only) are ignored.
  Future<void> showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final type = message.data['type'];
    final channel = pushChannels.firstWhere(
      (c) => c.id == message.notification?.android?.channelId,
      orElse: () => pushChannels.firstWhere((c) => c.id == _defaultChannelId),
    );
    final id = message.data['notification_id'];
    await _plugin.show(
      id: _idFor(id is String ? id : message.messageId ?? '$type'),
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          icon: notificationSmallIcon,
          importance: channel.importance,
          priority: Priority.high,
          groupKey: _groupKey,
          color: const Color(0xFF0051B6),
        ),
      ),
      payload: jsonEncode({
        for (final entry in message.data.entries)
          if (entry.key == 'type' || entry.key == 'notification_id')
            entry.key: entry.value,
      }),
    );
  }

  /// Removes everything this app has put in the shade (used on sign-out, so a
  /// shared phone never shows one person's notifications to the next).
  Future<void> clearAll() => _plugin.cancelAll();

  /// A stable positive 31-bit id per notification, so a repeated delivery of
  /// the same notification replaces itself instead of stacking.
  static int _idFor(String key) => key.hashCode & 0x7fffffff;

  /// Reads a payload written by [showForeground]; `null` for anything else.
  @visibleForTesting
  static PushOpen? parsePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      return PushOpen.fromData(Map<String, dynamic>.from(decoded));
    } on FormatException {
      return null;
    }
  }
}
