import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A push the user tapped. The server's payload is only
/// `{type, notification_id}` (no names or titles), so this is all there is.
@immutable
class PushOpen {
  const PushOpen({required this.notificationId, this.type});

  final String notificationId;
  final String? type;

  /// `null` when the payload is missing or malformed: such a push opens the
  /// app normally and navigates nowhere.
  static PushOpen? fromData(Map<String, dynamic> data) {
    final id = data['notification_id'];
    final type = data['type'];
    if (id is! String || !_uuid.hasMatch(id)) return null;
    return PushOpen(
      notificationId: id.toLowerCase(),
      type: type is String && _type.hasMatch(type) ? type : null,
    );
  }

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _type = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
}

/// Where tapped pushes come from: the one that launched the app (cold start)
/// and the ones tapped while it was in the background.
abstract interface class NotificationOpenSource {
  /// The push that started the app from a terminated state, if any.
  Future<PushOpen?> initial();

  /// Pushes tapped while the app was running in the background.
  Stream<PushOpen> get onOpened;
}

class NoopNotificationOpenSource implements NotificationOpenSource {
  const NoopNotificationOpenSource();

  @override
  Future<PushOpen?> initial() async => null;

  @override
  Stream<PushOpen> get onOpened => const Stream.empty();
}

class FirebaseNotificationOpenSource implements NotificationOpenSource {
  const FirebaseNotificationOpenSource();

  @override
  Future<PushOpen?> initial() async {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    return message == null ? null : PushOpen.fromData(message.data);
  }

  @override
  Stream<PushOpen> get onOpened => FirebaseMessaging.onMessageOpenedApp
      .map((m) => PushOpen.fromData(m.data))
      .where((open) => open != null)
      .cast<PushOpen>();
}

/// Overridden in `bootstrap()` when Firebase is configured.
final notificationOpenSourceProvider = Provider<NotificationOpenSource>(
  (ref) => const NoopNotificationOpenSource(),
);
