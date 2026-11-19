import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/session_controller.dart';
import '../data/notification_preferences_repository.dart';
import '../domain/notification_preferences.dart';

/// One family's push preferences.
///
/// Every change shows at once; saves go to the server one at a time (so a
/// slow answer can never overwrite a newer change) and a rejected change is
/// rolled back and rethrown for the screen to report.
class NotificationPreferencesController
    extends AsyncNotifier<NotificationPreferences> {
  NotificationPreferencesController(this.familyId);

  final String familyId;

  Future<void> _queue = Future.value();
  int _pending = 0;

  @override
  Future<NotificationPreferences> build() {
    ref.watch(sessionUserIdProvider);
    return ref.read(notificationPreferencesRepositoryProvider).load(familyId);
  }

  Future<void> setCategory(PreferenceCategory category, bool on) {
    final current = state.value;
    if (current == null || current.isLocked(category)) return Future.value();
    final before = current.categories[category.key];
    state = AsyncData(
      current.copyWith(categories: {...current.categories, category.key: on}),
    );
    return _save(
      () => ref
          .read(notificationPreferencesRepositoryProvider)
          .save(familyId, categories: {category.key: on}),
      rollback: (latest) => latest.copyWith(
        categories: {...latest.categories, category.key: before ?? true},
      ),
    );
  }

  Future<void> setQuietHours(QuietHours quietHours) {
    final current = state.value;
    if (current == null) return Future.value();
    final before = current.quietHours;
    state = AsyncData(current.copyWith(quietHours: quietHours));
    return _save(
      () => ref
          .read(notificationPreferencesRepositoryProvider)
          .save(familyId, quietHours: quietHours),
      rollback: (latest) => latest.copyWith(quietHours: before),
    );
  }

  Future<void> _save(
    Future<NotificationPreferences> Function() send, {
    required NotificationPreferences Function(NotificationPreferences) rollback,
  }) {
    _pending++;
    final run = _queue.then((_) async {
      try {
        final saved = await send();
        // A newer change is still on its way: keep showing it.
        if (ref.mounted && _pending == 1) state = AsyncData(saved);
      } on Object {
        final latest = state.value;
        if (ref.mounted && latest != null) state = AsyncData(rollback(latest));
        rethrow;
      } finally {
        _pending--;
      }
    });
    // The chain itself never fails, so one error does not block later saves.
    _queue = run.then((_) {}, onError: (Object _) {});
    return run;
  }
}

final notificationPreferencesProvider =
    AsyncNotifierProvider.family<
      NotificationPreferencesController,
      NotificationPreferences,
      String
    >(NotificationPreferencesController.new);
