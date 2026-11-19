import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/push/notification_open_source.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/routing/app_routes.dart';
import '../../approvals/presentation/approval_providers.dart';
import '../../authentication/domain/session.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../missions/data/missions_repository.dart';
import '../../missions/presentation/mission_providers.dart';
import '../domain/notification_category.dart';

/// Goes to a location. The app uses the router; tests record the call.
final notificationNavigatorProvider = Provider<void Function(String)>(
  (ref) =>
      (location) => ref.read(appRouterProvider).go(location),
);

/// A tapped push older than this is dropped instead of navigating (for
/// example when the user only signs in much later).
const pendingPushLifetime = Duration(minutes: 30);

/// Clock used for [pendingPushLifetime]; replaced in tests.
final pushClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Opens the right screen when a push is tapped.
///
/// * **Cold start:** the push that launched the app waits until the stored
///   session is restored, then navigates (never while the splash is deciding).
/// * **Running in the background:** navigates straight away.
/// * **Signed out / session expired:** the push waits; after sign-in it is
///   looked up on the server, which only returns the signed-in user's own
///   notifications, so another account's push never opens anything.
/// * **Deleted or unknown item:** the server answers 404 and the user lands on
///   their own home; offline, the push's type picks the category screen.
/// * **Opened twice** (Firebase can report the same tap as both the launch
///   message and an "opened" event): handled once.
///
/// The location comes from [locationFor], and the router's role guard still
/// applies, so a child is never shown a parent screen.
class NotificationOpenCoordinator extends Notifier<void> {
  final _handled = <String>{};
  PushOpen? _pending;
  DateTime? _pendingSince;
  bool _busy = false;

  @override
  void build() {
    final source = ref.watch(notificationOpenSourceProvider);
    final subscription = source.onOpened.listen(open);
    ref
      ..onDispose(subscription.cancel)
      ..listen(sessionControllerProvider, (_, _) => unawaited(_drain()));
    unawaited(_initial(source));
  }

  Future<void> _initial(NotificationOpenSource source) async {
    try {
      final first = await source.initial();
      if (first != null && ref.mounted) open(first);
    } on Object {
      // No launch message (or Firebase unavailable): nothing to open.
    }
  }

  /// Handles one tapped push (public for the notification sources and tests).
  void open(PushOpen push) {
    if (_handled.contains(push.notificationId)) return;
    if (_pending?.notificationId == push.notificationId) return;
    _pending = push;
    _pendingSince = ref.read(pushClockProvider)();
    unawaited(_drain());
  }

  Future<void> _drain() async {
    final push = _pending;
    if (push == null || _busy || !ref.mounted) return;
    final since = _pendingSince;
    if (since != null &&
        ref.read(pushClockProvider)().difference(since) > pendingPushLifetime) {
      _pending = null;
      return;
    }
    final state = ref.read(sessionControllerProvider);
    // Still restoring the stored session (cold start): wait for it.
    if (state.isLoading && !state.hasValue) return;
    final session = state.value;
    if (session == null || !(session.isChild || session.isParent)) return;

    _pending = null;
    _handled.add(push.notificationId);
    _busy = true;
    try {
      await _navigate(push, session);
    } finally {
      _busy = false;
    }
    if (_pending != null) unawaited(_drain());
  }

  Future<void> _navigate(PushOpen push, Session session) async {
    final audience = session.isChild
        ? NotificationAudience.child
        : NotificationAudience.parent;
    final home = session.isChild ? AppRoutes.childHome : AppRoutes.parentHome;
    final repository = ref.read(missionsRepositoryProvider);
    String location;
    try {
      final notification = await repository.getNotification(
        push.notificationId,
      );
      location = locationFor(
        type: notification.type,
        audience: audience,
        relatedTaskId: notification.relatedTaskId,
        childId: session.childId,
      );
      unawaited(_markRead(repository, push.notificationId));
    } on NotFoundException {
      // Deleted, or it belongs to another account on this phone.
      location = home;
    } on UnauthorizedException {
      // The session ended while looking it up; try again after sign-in.
      _handled.remove(push.notificationId);
      _pending ??= push;
      return;
    } on ApiException {
      // Offline or server trouble: the push's own type still picks a screen.
      final type = push.type;
      location = type == null
          ? home
          : locationFor(
              type: type,
              audience: audience,
              childId: session.childId,
            );
    }
    if (!ref.mounted) return;
    ref
      ..invalidate(childNotificationsProvider)
      ..invalidate(parentNotificationsProvider);
    ref.read(notificationNavigatorProvider)(location);
  }

  Future<void> _markRead(MissionsRepository repository, String id) async {
    try {
      await repository.markNotificationRead(id);
    } on ApiException {
      // Best effort; it stays unread in the centre.
    }
  }
}

final notificationOpenCoordinatorProvider =
    NotifierProvider<NotificationOpenCoordinator, void>(
      NotificationOpenCoordinator.new,
    );
